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

// [01] This optional phone check uses existing permission and disposable storage to verify the
// real all-app import

import XCTest
#if SCREEN_TIME_ENABLED
import DeviceActivity
import FamilyControls
import ManagedSettings
#endif
@testable import DFE

/// [02] Run separately after the owner has approved all-app access on the test phone.
/// No permission prompt, real history write or widget publication belongs in this test.
final class LiveAllActivityImportTests: XCTestCase {
    // [03] The real Apple response must reach the shared calculation and survive a save without
    // changing the person's history.
    @MainActor func testAllAuthorizedAppsReachAnIsolatedArchive() async throws {
        guard ProcessInfo.processInfo.environment["DFE_RUN_LIVE_SCREEN_TIME_TEST"] == "1" else {
            throw XCTSkip("Live Screen Time validation was not requested for this run.")
        }
        guard ProcessInfo.processInfo.environment["DFE_RUN_ALL_ACTIVITY_TEST"] == "1" else {
            throw XCTSkip("The all-authorized-app scenario was not requested for this run.")
        }
        #if targetEnvironment(simulator)
        throw XCTSkip("This optional check requires a physical iPhone.")
        #elseif SCREEN_TIME_ENABLED
        guard #available(iOS 26.4, *) else {
            throw XCTSkip("The phone does not support expanded Screen Time data access.")
        }

        let now = Date()
        var calendar = FootprintCalendar.localCalendar
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: now)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let days = FootprintCalendar(calendar: calendar)
        let interval = DateInterval(start: yesterday, end: today)

        // [04] Try all-app access in separate test settings, leaving the person's saved choices
        // untouched.
        let suiteName = "dfe-live-all-apps-test-\(UUID().uuidString)"
        let isolatedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { isolatedDefaults.removePersistentDomain(forName: suiteName) }
        isolatedDefaults.set(ScreenTimeActivityScope.allAuthorizedApps.rawValue,
                             forKey: "dfe.screenTime.activityScope.v1")
        isolatedDefaults.set(days.key(yesterday), forKey: "dfe.screenTime.allActivityStartDay.v1")
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
        XCTAssertTrue(service.activityScope == .allAuthorizedApps,
                      "The isolated import must use all authorized apps, without a picker.")
        let mappedCategories = Set(FootprintCategory.allCases)
        let probe: AllActivityProbe
        do { probe = try await independentlyReadAllApps(during: interval) }
        catch {
            let reason: String
            switch error {
            case AllActivityProbeIssue.noData: reason = "all-apps-no-data"
            case AllActivityProbeIssue.missingIdentity: reason = "all-apps-identity-missing"
            case AllActivityProbeIssue.contradictoryIdentity: reason = "all-apps-identity-conflict"
            case AllActivityProbeIssue.invalidDuration: reason = "all-apps-duration-invalid"
            case AllActivityProbeIssue.incompleteDay: reason = "all-apps-day-incomplete"
            case AllActivityProbeIssue.multipleDevices: reason = "all-apps-multiple-devices"
            case DeviceActivityData.Error.unavailable: reason = "all-apps-apple-unavailable"
            case DeviceActivityData.Error.unauthorized: reason = "all-apps-apple-unauthorized"
            case DeviceActivityData.Error.missingData: reason = "all-apps-apple-missing-data"
            default: reason = "all-apps-system-error"
            }
            XCTFail("The independent all-app check stopped [\(reason)]. Private values were omitted.")
            return
        }
        guard probe.hasMultiplePositiveApps && probe.hasMultipleCategoryRows else {
            XCTFail("The previous day did not prove multiple apps and distinct groups [all-apps-insufficient-variety].")
            return
        }
        // [06] These assumptions belong only to yesterday's disposable test, not to the person's
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

        // [07] Use the same activity request as the real app, so made-up minutes cannot make this
        // check pass.
        let importStartedAt = Date()
        do { try await service.refreshCompletedDays(store: store, now: now) }
        catch {
            XCTFail("The live import ended with an error. No private API details were recorded.")
            return
        }
        let importFinishedAt = Date()
        guard let record = store.records.first else {
            // [08] Keep the failure reason useful without copying Apple's text, which may include
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
                      "All model categories must receive measured time or a genuine measured zero.")
        let actualMinutes = Dictionary(uniqueKeysWithValues: record.inputs.usages.map {
            ($0.category, $0.minutes)
        })
        guard FootprintCategory.allCases.allSatisfy({
            abs((actualMinutes[$0] ?? -1) - (probe.minutesByCategory[$0] ?? 0)) <= 0.001
        }) else {
            XCTFail("The imported time differs from the independent app rows [all-apps-time-not-conserved].")
            return
        }
        XCTContext.runActivity(named: "All-app scope: multiple positive apps and multiple distinct category objects; per-category time conserved") { _ in }
        XCTContext.runActivity(named: "All-app scope: no saved app or group selection was required") { _ in }
        XCTAssertTrue(record.inputs.usages.allSatisfy {
            $0.minutes.isFinite && (0...(today.timeIntervalSince(yesterday) / 60)).contains($0.minutes)
        } && record.inputs.totalMinutes <= today.timeIntervalSince(yesterday) / 60,
                      "Imported durations must remain within the completed day's bounds.")
        XCTAssertTrue(record.inputs.brightness == inputs.brightness
                      && record.inputs.gpsHours == inputs.gpsHours
                      && record.inputs.bluetoothHours == inputs.bluetoothHours
                      && record.inputs.usages.allSatisfy { $0.gigabytesPerHour == 1 && $0.wifiShare == 0.8 },
                      "Importing usage must keep the isolated scenario's other assumptions.")
        XCTAssertTrue(record.inputs.totalMinutes > 0,
                      "The varied-use scenario must import positive activity.")
        let recalculated = try calculator.calculate(record.inputs)
        XCTAssertTrue(record.result == recalculated,
                      "The saved result must match the shared model for its imported inputs.")
        let reopened = FootprintStore(fileURL: fileURL, calculator: calculator,
                                      calendar: calendar, widgetPublisher: nil)
        guard reopened.errorMessage == nil, reopened.records.count == store.records.count else {
            XCTFail("The saved archive could not be reopened [reload-archive-structure-mismatch].")
            return
        }
        // [09] Saved times keep whole seconds. Allow only that known loss of detail, while
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

        // [10] Apple may update its answer on a second request, but the same day must not become
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
        // [11] no activity attachments here: app names, private identities, minutes and totals
        // stay on the phone
        #else
        throw XCTSkip("Use the optional ScreenTimeDebug configuration for this check.")
        #endif
    }

    #if SCREEN_TIME_ENABLED
    private enum AllActivityProbeIssue: Error {
        case noData, missingIdentity, contradictoryIdentity, invalidDuration, incompleteDay, multipleDevices
    }
    @available(iOS 26.4, *)
    private enum AllActivityIdentity: Hashable {
        case bundle(String)
        case token(ApplicationToken)
    }
    private struct AllActivityProbe {
        var minutesByCategory: [FootprintCategory: Double]
        var hasMultiplePositiveApps: Bool
        var hasMultipleCategoryRows: Bool
    }

    @available(iOS 26.4, *)
    @MainActor private func independentlyReadAllApps(during interval: DateInterval) async throws -> AllActivityProbe {
        // [12] Keep this private app list in memory only; it must not be copied into the test
        // report.
        var tokenBundles: [ApplicationToken: String] = [:]
        var bundleTokens: [String: Set<ApplicationToken>] = [:]
        for app in try await FamilyActivityData.shared.installedApplications {
            guard let token = app.token, let bundle = app.bundleIdentifier, !bundle.isEmpty else { continue }
            guard tokenBundles[token] == nil || tokenBundles[token] == bundle else {
                throw AllActivityProbeIssue.contradictoryIdentity
            }
            tokenBundles[token] = bundle
            bundleTokens[bundle, default: []].insert(token)
        }
        // [13] No app filter is used here because this check covers all authorized activity on
        // this phone.
        let filter = DeviceActivityFilter(segment: .daily(during: interval))
        var devices = Set<DeviceActivityData.Device>()
        var seen = [AllActivityIdentity: Double]()
        var totals = Dictionary(uniqueKeysWithValues: FootprintCategory.allCases.map { ($0, 0.0) })
        var positiveGroups = Set<ActivityCategory>()
        var sawCompleteSegment = false
        for try await data in DeviceActivityData.activityData(filteredBy: filter, using: .live) {
            devices.insert(data.device)
            guard devices.count == 1 else { throw AllActivityProbeIssue.multipleDevices }
            for await segment in data.activitySegments {
                guard abs(segment.dateInterval.start.timeIntervalSince(interval.start)) <= 0.001,
                      abs(segment.dateInterval.end.timeIntervalSince(interval.end)) <= 0.001 else {
                    throw AllActivityProbeIssue.incompleteDay
                }
                sawCompleteSegment = true
                for await group in segment.categories {
                    var rowHasPositiveApp = false
                    // [14] Group and website totals can overlap app time. Adding them would count
                    // the same use again.
                    for await row in group.applications {
                        let app = row.application
                        let suppliedBundle = app.bundleIdentifier.flatMap { $0.isEmpty ? nil : $0 }
                        let resolvedBundle = app.token.flatMap { tokenBundles[$0] }
                        if let suppliedBundle, let resolvedBundle, suppliedBundle != resolvedBundle {
                            throw AllActivityProbeIssue.contradictoryIdentity
                        }
                        if let token = app.token, let suppliedBundle,
                           let aliases = bundleTokens[suppliedBundle], !aliases.contains(token) {
                            throw AllActivityProbeIssue.contradictoryIdentity
                        }
                        let bundle = suppliedBundle ?? resolvedBundle
                        let identity: AllActivityIdentity
                        if let bundle { identity = .bundle(bundle) }
                        else if let token = app.token { identity = .token(token) }
                        else { throw AllActivityProbeIssue.missingIdentity }
                        let seconds = row.totalActivityDuration
                        guard seconds.isFinite && seconds >= 0 else {
                            throw AllActivityProbeIssue.invalidDuration
                        }
                        rowHasPositiveApp = rowHasPositiveApp || seconds > 0
                        if let previous = seen[identity] {
                            guard abs(previous - seconds) <= 0.001 else {
                                throw AllActivityProbeIssue.invalidDuration
                            }
                            continue
                        }
                        seen[identity] = seconds
                        let category = AutomaticActivityClassification.category(bundleIdentifier: bundle)
                        totals[category, default: 0] += seconds / 60
                    }
                    if rowHasPositiveApp { positiveGroups.insert(group.category) }
                }
            }
        }
        guard sawCompleteSegment else { throw AllActivityProbeIssue.noData }
        guard totals.values.reduce(0, +) <= interval.duration / 60 else {
            throw AllActivityProbeIssue.invalidDuration
        }
        return AllActivityProbe(minutesByCategory: totals,
            hasMultiplePositiveApps: seen.values.filter { $0 > 0 }.count >= 2,
            hasMultipleCategoryRows: positiveGroups.count >= 2)
    }
    #endif
}
