/*
 * Copyright (C) 2026 Zurich University of Applied Sciences, Switzerland
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

// [01] This optional phone check uses the owner's existing app choices and keeps its test history
// separate

import XCTest
#if SCREEN_TIME_ENABLED
import DeviceActivity
import FamilyControls
import ManagedSettings
#endif
@testable import DFE

/// [02] Run separately on a phone after its owner has approved Screen Time and saved choices.
/// No permission prompt, real history write or widget publication belongs in this test.
final class LiveScreenTimeImportTests: XCTestCase {
    // [03] This checks the real permission-to-saved-result path, without asking again or
    // publishing a test garden to widgets.
    @MainActor func testApprovedYesterdayUsageReachesAnIsolatedArchive() async throws {
        guard ProcessInfo.processInfo.environment["DFE_RUN_LIVE_SCREEN_TIME_TEST"] == "1" else {
            throw XCTSkip("Live Screen Time validation was not requested for this run.")
        }
        #if targetEnvironment(simulator)
        throw XCTSkip("This optional check requires a physical iPhone.")
        #elseif SCREEN_TIME_ENABLED
        guard #available(iOS 26.4, *) else {
            throw XCTSkip("The phone does not support expanded Screen Time data access.")
        }

        // [04] Read the saved choices, but keep every test update in separate settings so the
        // original setup stays intact.
        let selectionKey = "dfe.screenTime.categorySelections.v1"
        guard let savedChoices = UserDefaults.standard.data(forKey: selectionKey) else {
            throw XCTSkip("Approve Screen Time and save app choices in the app first.")
        }
        let suiteName = "dfe-live-screen-time-test-\(UUID().uuidString)"
        let isolatedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        isolatedDefaults.set(savedChoices, forKey: selectionKey)
        defer { isolatedDefaults.removePersistentDomain(forName: suiteName) }
        let service = ScreenTimeService(defaults: isolatedDefaults)
        service.refreshAuthorization()
        // [05] Wait briefly for Apple's existing permission status; do not open another permission
        // prompt.
        let authorizationDeadline = Date().addingTimeInterval(5)
        while !service.state.canImport,
              service.state == .notRequested || service.state == .revoked,
              Date() < authorizationDeadline {
            try await Task.sleep(for: .milliseconds(50))
            service.refreshAuthorization()
        }
        guard service.state.canImport else {
            throw XCTSkip("The existing permission does not allow live usage import [\(service.state)].")
        }
        let mappedCategories = Set(service.selections.compactMap { id, choice in
            choice.applicationTokens.isEmpty && choice.categoryTokens.isEmpty
                ? nil : FootprintCategory(rawValue: id)
        })
        guard !mappedCategories.isEmpty else {
            throw XCTSkip("Save at least one app or group choice before this live check.")
        }

        // [06] Permission renewal can invalidate a saved app choice. Check that link without
        // recording private identities or counts.
        let selectedApps = Set(service.selections.values.flatMap { $0.applicationTokens })
        let selectedGroups = Set(service.selections.values.flatMap { $0.categoryTokens })
        do {
            if !selectedApps.isEmpty {
                var resolved = selectedApps
                for app in try await FamilyActivityData.shared.installedApplications {
                    guard let token = app.token, selectedApps.contains(token) else { continue }
                    resolved.remove(token)
                }
                guard resolved.isEmpty else {
                    XCTFail("Selected app tokens could not be resolved [selected-app-token-unresolved].")
                    return
                }
            }
            if !selectedGroups.isEmpty {
                var resolved = selectedGroups
                for group in try await FamilyActivityData.shared.activityCategories {
                    guard let token = group.token, selectedGroups.contains(token) else { continue }
                    resolved.remove(token)
                }
                guard resolved.isEmpty else {
                    XCTFail("Selected category tokens could not be resolved [selected-category-token-unresolved].")
                    return
                }
            }
        } catch {
            let reason: String
            switch error {
            case DeviceActivityData.Error.unavailable: reason = "apple-unavailable"
            case DeviceActivityData.Error.unauthorized: reason = "apple-unauthorized"
            case DeviceActivityData.Error.missingData: reason = "apple-missing-data"
            default: reason = "system-error"
            }
            XCTFail("The identity check did not complete [identity-check-\(reason)]. Private API details were omitted.")
            return
        }

        let now = Date()
        var calendar = FootprintCalendar.localCalendar
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: now)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let days = FootprintCalendar(calendar: calendar)
        if let reason = await returnedIdentityIssue(selections: service.selections,
            interval: DateInterval(start: yesterday, end: today)) {
            XCTFail("The selected-scope identity probe stopped [\(reason)]. No private values were recorded.")
            return
        }

        // [07] These assumptions belong only to yesterday's disposable test, not to the person's
        // saved routine.
        let inputs = FootprintInputs(usages: FootprintCategory.allCases.filter {
            mappedCategories.contains($0)
        }.map {
            CategoryUsage(category: $0, minutes: 0, gigabytesPerHour: 1, wifiShare: 0.8)
        }, brightness: 0.5, gpsHours: 0, bluetoothHours: 0)
        try inputs.validate()
        let archive = FootprintArchive(firstDay: days.key(yesterday), revisions: [
            RoutineRevision(effectiveDay: days.key(yesterday), savedAt: now, inputs: inputs)
        ], records: [], inputPreference: .automatic, automaticStartDay: days.key(yesterday))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dfe-live-screen-time-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("isolated-history.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(archive).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let calculator = SharedFootprintCalculator()
        let store = FootprintStore(fileURL: fileURL, calculator: calculator,
                                   calendar: calendar, widgetPublisher: nil)
        XCTAssertTrue(store.isConfigured && store.usesAutomaticInput,
                      "The isolated automatic test archive must be readable.")
        XCTAssertTrue(store.automaticStartDate == yesterday,
                      "The isolated scenario must start on its requested completed day.")

        // [08] Use the same activity request as the real app, so made-up minutes cannot make this
        // check pass.
        let importStartedAt = Date()
        do { try await service.refreshCompletedDays(store: store, now: now) }
        catch {
            XCTFail("The live import ended with an error. No private API details were recorded.")
            return
        }
        let importFinishedAt = Date()
        guard let record = store.records.first else {
            // [09] Keep the failure reason useful without copying Apple's text, which may include
            // private details.
            let knownReasons: [(ScreenTimeImportError, String)] = [
                (.permissionRequired, "permission-required"), (.noSelection, "no-selection"),
                (.invalidDuration, "invalid-duration"), (.noData, "no-data"),
                (.multipleDevices, "multiple-devices"), (.incompleteData, "incomplete-data"),
                (.unmappedSelection, "unmapped-selection"), (.conflictingSelection, "conflicting-selection"),
                (.selectionChanged, "selection-changed")
            ]
            let systemReasons: [(DeviceActivityData.Error, String)] = [
                (.unavailable, "apple-unavailable"), (.unauthorized, "apple-unauthorized"),
                (.missingData, "apple-missing-data")
            ]
            let reason = knownReasons.first { $0.0.errorDescription == service.lastError }?.1
                ?? systemReasons.first { $0.0.localizedDescription == service.lastError }?.1
                ?? (service.lastError == nil ? "no-service-notice" : "system-error")
            XCTFail("No complete live day was imported [\(reason)]. Missing data is not zero usage.")
            return
        }
        XCTAssertTrue(calendar.startOfDay(for: Date()) == today,
                      "The local day changed during the test; repeat the check.")
        XCTAssertTrue(store.records.count == 1 && record.day == days.key(yesterday),
                      "The import must save only the requested completed day.")
        XCTAssertTrue(record.source == .screenTimeWithEstimates && record.isCompleted,
                      "A routine estimate cannot count as a successful live import.")
        // [15] The saved time belongs to the completed work, rather than the earlier calculation date.
        let completedAt = try XCTUnwrap(service.lastImportDate)
        XCTAssertTrue(completedAt >= importStartedAt && completedAt <= importFinishedAt && service.lastError == nil,
                      "The live import must record its completion within this request and finish without a notice.")
        XCTAssertTrue(Set(record.automaticCategories ?? []) == mappedCategories,
                      "Only the person's mapped categories may supply measured time.")
        XCTAssertTrue(record.inputs.usages.allSatisfy {
            $0.minutes.isFinite && (0...(today.timeIntervalSince(yesterday) / 60)).contains($0.minutes)
        } && record.inputs.totalMinutes <= today.timeIntervalSince(yesterday) / 60,
                      "Imported durations must remain within the completed day's bounds.")
        XCTAssertTrue(record.inputs.brightness == inputs.brightness
                      && record.inputs.gpsHours == inputs.gpsHours
                      && record.inputs.bluetoothHours == inputs.bluetoothHours
                      && record.inputs.usages.allSatisfy { $0.gigabytesPerHour == 1 && $0.wifiShare == 0.8 },
                      "Importing usage must keep the isolated scenario's other assumptions.")
        if ProcessInfo.processInfo.environment["DFE_LIVE_EXPECT_NONZERO"] == "1" {
            XCTAssertTrue(record.inputs.totalMinutes > 0,
                          "The owner expected selected app use yesterday, but no positive duration was imported.")
        }
        let recalculated = try calculator.calculate(record.inputs)
        XCTAssertTrue(record.result == recalculated,
                      "The saved result must match the shared model for its imported inputs.")
        let reopened = FootprintStore(fileURL: fileURL, calculator: calculator,
                                      calendar: calendar, widgetPublisher: nil)
        guard reopened.errorMessage == nil, reopened.records.count == store.records.count else {
            XCTFail("The saved archive could not be reopened [reload-archive-structure-mismatch].")
            return
        }
        // [10] Saved times keep whole seconds. Allow only that known loss of detail, while
        // checking every other saved value exactly.
        let dateDecoder = JSONDecoder()
        dateDecoder.dateDecodingStrategy = .iso8601
        var expectedRecords = store.records
        var timestampPrecisionChanged = false
        for index in expectedRecords.indices {
            let original = expectedRecords[index].calculatedAt
            let savedDate = try dateDecoder.decode(Date.self, from: encoder.encode(original))
            timestampPrecisionChanged = timestampPrecisionChanged || original != savedDate
            expectedRecords[index].calculatedAt = savedDate
        }
        guard reopened.records == expectedRecords else {
            var withoutDateDifferences = store.records
            for index in withoutDateDifferences.indices {
                withoutDateDifferences[index].calculatedAt = reopened.records[index].calculatedAt
            }
            let reason = withoutDateDifferences == reopened.records
                ? "reload-timestamp-mismatch" : "reload-non-date-field-mismatch"
            XCTFail("The imported day changed after reload [\(reason)]. No private values were recorded.")
            return
        }
        if timestampPrecisionChanged {
            XCTContext.runActivity(named: "Reload: only expected subsecond timestamp precision changed; other fields exact") { _ in }
        }

        // [11] Apple may update its answer on a second request, but the same day must not become
        // two history entries.
        do { try await service.refreshCompletedDays(store: reopened, now: now) }
        catch {
            XCTFail("The repeated live import did not complete. Private API details were omitted.")
            return
        }
        XCTAssertTrue(reopened.records.count == 1
                      && reopened.records.first?.day == days.key(yesterday)
                      && reopened.records.first?.source == .screenTimeWithEstimates
                      && service.lastError == nil,
                      "Repeating the import must not create duplicate or fallback days.")
        // [12] no activity attachments here: app names, private identities, minutes and totals
        // stay on the phone
        #else
        throw XCTSkip("Use the optional ScreenTimeDebug configuration for this check.")
        #endif
    }

    #if SCREEN_TIME_ENABLED
    @available(iOS 26.4, *)
    @MainActor private func returnedIdentityIssue(selections: [String: FamilyActivitySelection],
                                                interval: DateInterval) async -> String? {
        // [13] Check why the chosen apps do not match without reading their minutes or saving
        // their private identities.
        var apps: [ApplicationToken: String] = [:]
        var groups: [ActivityCategoryToken: String] = [:]
        var bundles: [String: String] = [:]
        var resolvedApps: [Application: String] = [:]
        var resolvedGroups: [ActivityCategory: String] = [:]
        var bundleTokens: [String: Set<ApplicationToken>] = [:]
        var appTokens: [Application: Set<ApplicationToken>] = [:]
        var groupTokens: [ActivityCategory: Set<ActivityCategoryToken>] = [:]
        do {
            for (id, choice) in selections {
                for token in choice.applicationTokens { try ScreenTimeIdentityMapping.assign(token, to: id, in: &apps) }
                for token in choice.categoryTokens { try ScreenTimeIdentityMapping.assign(token, to: id, in: &groups) }
            }
            if !apps.isEmpty {
                var unresolved = Set(apps.keys)
                for app in try await FamilyActivityData.shared.installedApplications {
                    guard let token = app.token, apps[token] != nil else { continue }
                    try ScreenTimeIdentityMapping.resolveSelectedApplication(app, token: token,
                        bundleIdentifier: app.bundleIdentifier, tokenAssignments: apps,
                        resolvedApplications: &resolvedApps, bundleAssignments: &bundles)
                    appTokens[app, default: []].insert(token)
                    if let bundle = app.bundleIdentifier, !bundle.isEmpty { bundleTokens[bundle, default: []].insert(token) }
                    unresolved.remove(token)
                }
                guard unresolved.isEmpty else { return "second-app-token-unresolved" }
                guard resolvedApps.keys.allSatisfy({ $0.bundleIdentifier?.isEmpty == false }) else {
                    return "selected-app-bundle-missing"
                }
            }
            if !groups.isEmpty {
                var unresolved = Set(groups.keys)
                for group in try await FamilyActivityData.shared.activityCategories {
                    guard let token = group.token, let id = groups[token] else { continue }
                    try ScreenTimeIdentityMapping.assign(group, to: id, in: &resolvedGroups)
                    groupTokens[group, default: []].insert(token)
                    unresolved.remove(token)
                }
                guard unresolved.isEmpty else { return "second-category-token-unresolved" }
            }
            let filter = ScreenTimeQueryScope.filter(interval: interval,
                applications: Set(apps.keys), categories: Set(groups.keys))
            var selectedIdentitySeen = false
            var foreignIdentitySeen = false
            var missingIdentitySeen = false
            var coveredApps = Set<ApplicationToken>()
            var coveredGroups = Set<ActivityCategoryToken>()
            for try await data in DeviceActivityData.activityData(filteredBy: filter, using: .live) {
                for await segment in data.activitySegments {
                    guard FootprintCalendar.localCalendar.isDate(segment.dateInterval.start,
                        inSameDayAs: interval.start) else { continue }
                    for await group in segment.categories {
                        let groupID = group.category.token.flatMap { groups[$0] } ?? resolvedGroups[group.category]
                        if let token = group.category.token, groups[token] != nil { coveredGroups.insert(token) }
                        else { coveredGroups.formUnion(groupTokens[group.category] ?? []) }
                        for await item in group.applications {
                            let app = item.application
                            let id = ScreenTimeIdentityMapping.categoryID(token: app.token,
                                bundleIdentifier: app.bundleIdentifier, tokenAssignments: apps,
                                bundleAssignments: bundles) ?? resolvedApps[app]
                            coveredApps.formUnion(try ScreenTimeImportScope.recognizedTokens(token: app.token,
                                bundleIdentifier: app.bundleIdentifier, selected: Set(apps.keys), bundleAliases: bundleTokens))
                            coveredApps.formUnion(appTokens[app] ?? [])
                            // [14] Keep reading: an unrelated app early in the response must not
                            // hide a selected app that appears later.
                            if id != nil || groupID != nil { selectedIdentitySeen = true }
                            else if app.token != nil || app.bundleIdentifier?.isEmpty == false { foreignIdentitySeen = true }
                            else { missingIdentitySeen = true }
                        }
                    }
                }
            }
            if foreignIdentitySeen || missingIdentitySeen {
                let selected = selectedIdentitySeen ? "seen" : "absent"
                let foreign = foreignIdentitySeen ? "seen" : "absent"
                let missing = missingIdentitySeen ? "seen" : "absent"
                let label = "identity-summary-selected-\(selected)-foreign-\(foreign)-missing-\(missing)"
                guard !missingIdentitySeen else { return label }
                do {
                    try ScreenTimeImportScope.validateCoverage(selectedApps: Set(apps.keys), coveredApps: coveredApps,
                        selectedGroups: Set(groups.keys), coveredGroups: coveredGroups, foreignRowsSeen: foreignIdentitySeen)
                } catch { return label }
                XCTContext.runActivity(named: "Identity scope: selected and foreign rows; all choices covered; no missing identity") { _ in }
            }
            return nil
        } catch {
            switch error {
            case DeviceActivityData.Error.unavailable: return "identity-probe-apple-unavailable"
            case DeviceActivityData.Error.unauthorized: return "identity-probe-apple-unauthorized"
            case DeviceActivityData.Error.missingData: return "identity-probe-apple-missing-data"
            case ScreenTimeImportError.conflictingSelection: return "identity-probe-selection-conflict"
            default: return "identity-probe-system-error"
            }
        }
    }
    #endif
}
