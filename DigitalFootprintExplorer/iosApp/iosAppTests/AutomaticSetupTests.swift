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

// [01] Automatic input needs a clear choice, a saved start date and usable activity before it can
// create a day

import XCTest
@testable import DFE

private final class AutomaticSetupCalculator: FootprintCalculating {
    var calls = 0
    func calculate(_ inputs: FootprintInputs) throws -> FootprintResult {
        calls += 1
        let total = inputs.totalMinutes / 1000
        return FootprintResult(totalKg: total, appUsageKg: total, displayKg: 0,
                               backgroundKg: 0, categories: [])
    }
}

final class AutomaticSetupTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return value
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var first: Date { date("2026-10-07T10:00:00Z") }
    private var nextDay: Date { date("2026-10-08T10:00:00Z") }
    private var later: Date { date("2026-10-10T10:00:00Z") }
    private func inputs(_ minutes: Double = 60) -> FootprintInputs {
        FootprintInputs(usages: [CategoryUsage(category: .video, minutes: minutes,
                                              gigabytesPerHour: 1, wifiShare: 0.8)],
                        brightness: 0.5, gpsHours: 0.25, bluetoothHours: 2)
    }
    @MainActor private func store(_ calculator: AutomaticSetupCalculator = AutomaticSetupCalculator()) -> FootprintStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return FootprintStore(fileURL: directory.appendingPathComponent("history.json"),
                              calculator: calculator, calendar: calendar)
    }
    @MainActor private func reopen(_ store: FootprintStore) -> FootprintStore {
        FootprintStore(fileURL: store.fileURL, calculator: AutomaticSetupCalculator(), calendar: calendar)
    }

    @MainActor private func isolatedScreenTimeDefaults() throws -> UserDefaults {
        let name = "dfe-test-activity-scope-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    // [02] Choosing a few apps in an older version is not permission to include every authorized
    // app later.
    @MainActor func testLegacyScreenTimeChoicesDoNotOptIntoAllAppActivity() async throws {
        let defaults = try isolatedScreenTimeDefaults()
        let legacyChoices = Data("{}".utf8)
        defaults.set(legacyChoices, forKey: "dfe.screenTime.categorySelections.v1")
        let service = ScreenTimeService(defaults: defaults)
        XCTAssertEqual(service.activityScope, .selectedApps)
        XCTAssertNil(defaults.object(forKey: "dfe.screenTime.activityScope.v1"))
        XCTAssertEqual(defaults.data(forKey: "dfe.screenTime.categorySelections.v1"), legacyChoices)
        XCTAssertEqual(ScreenTimeService(defaults: defaults).activityScope, .selectedApps)
    }

    // [03] An unfamiliar saved choice should not quietly give the app a wider view of activity.
    @MainActor func testUnknownSavedScopeKeepsTheNarrowerModeWithoutRewritingIt() async throws {
        let defaults = try isolatedScreenTimeDefaults()
        defaults.set("unknown-future-scope", forKey: "dfe.screenTime.activityScope.v1")
        defaults.set("2026-10-01", forKey: "dfe.screenTime.allActivityStartDay.v1")
        let service = ScreenTimeService(defaults: defaults)
        XCTAssertEqual(service.activityScope, .selectedApps)
        XCTAssertEqual(defaults.string(forKey: "dfe.screenTime.activityScope.v1"), "unknown-future-scope")
        XCTAssertEqual(defaults.string(forKey: "dfe.screenTime.allActivityStartDay.v1"), "2026-10-01")
    }

    // [04] After reopening, the app should remember the wider access the person explicitly chose.
    @MainActor func testAnExplicitSavedAllActivityScopeSurvivesServiceReload() async throws {
        let defaults = try isolatedScreenTimeDefaults()
        defaults.set(ScreenTimeActivityScope.allAuthorizedApps.rawValue, forKey: "dfe.screenTime.activityScope.v1")
        defaults.set("2026-10-08", forKey: "dfe.screenTime.allActivityStartDay.v1")
        let firstService = ScreenTimeService(defaults: defaults)
        let reopenedService = ScreenTimeService(defaults: defaults)
        XCTAssertEqual(firstService.activityScope, .allAuthorizedApps)
        XCTAssertEqual(reopenedService.activityScope, .allAuthorizedApps)
        XCTAssertEqual(defaults.string(forKey: "dfe.screenTime.allActivityStartDay.v1"), "2026-10-08")
    }

    // [05] Older automatic history is not proof that the person agreed to the newer all-app setup.
    @MainActor func testLegacyAutomaticArchiveDoesNotCountAsAllActivitySetup() async throws {
        let store = store()
        try store.saveAutomaticProfile(inputs(), now: first)
        let defaults = try isolatedScreenTimeDefaults()
        defaults.set("2026-10-07", forKey: "dfe.screenTime.allActivityStartDay.v1")
        let service = ScreenTimeService(defaults: defaults)
        let saved = store.archive

        XCTAssertFalse(service.hasSavedAutomaticSetup(store: store))
        XCTAssertEqual(service.activityScope, .selectedApps)
        XCTAssertNil(defaults.object(forKey: "dfe.screenTime.activityScope.v1"))
        XCTAssertEqual(store.archive, saved)
    }

    // [06] The saved start date prevents automatic input from reaching back before the person's
    // choice.
    @MainActor func testAllActivitySetupNeedsAValidSavedScopeBoundary() async throws {
        let store = store()
        try store.saveAutomaticProfile(inputs(), now: first)
        for key in [nil, "", "not a date", "2026-02-30", "2026-10-7"] {
            let defaults = try isolatedScreenTimeDefaults()
            defaults.set(ScreenTimeActivityScope.allAuthorizedApps.rawValue,
                         forKey: "dfe.screenTime.activityScope.v1")
            if let key { defaults.set(key, forKey: "dfe.screenTime.allActivityStartDay.v1") }
            let service = ScreenTimeService(defaults: defaults)

            XCTAssertFalse(service.hasSavedAutomaticSetup(store: store))
            XCTAssertEqual(defaults.string(forKey: "dfe.screenTime.allActivityStartDay.v1"), key)
            XCTAssertTrue(store.records.isEmpty)
        }
    }

    // [07] Setup can be complete before the first full day is ready; the app should wait without
    // asking again.
    @MainActor func testSavedAllActivitySetupDoesNotWaitForACompletedDay() async throws {
        let store = store()
        try store.saveAutomaticProfile(inputs(), now: first)
        let defaults = try isolatedScreenTimeDefaults()
        defaults.set(ScreenTimeActivityScope.allAuthorizedApps.rawValue,
                     forKey: "dfe.screenTime.activityScope.v1")
        defaults.set("2026-10-07", forKey: "dfe.screenTime.allActivityStartDay.v1")
        let service = ScreenTimeService(defaults: defaults)

        XCTAssertTrue(service.hasSavedAutomaticSetup(store: store))
        XCTAssertFalse(service.hasEligibleCompletedDay(store: store, now: first))
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertTrue(ScreenTimeService(defaults: defaults).hasSavedAutomaticSetup(store: reopen(store)))
    }

    // [08] Losing Apple's permission changes the connection, but it should not erase the person's
    // setup history.
    @MainActor func testRevokedPermissionDoesNotEraseSavedAllActivitySetup() async throws {
        let store = store()
        try store.saveAutomaticProfile(inputs(), now: first)
        let defaults = try isolatedScreenTimeDefaults()
        defaults.set(ScreenTimeActivityScope.allAuthorizedApps.rawValue,
                     forKey: "dfe.screenTime.activityScope.v1")
        defaults.set("2026-10-07", forKey: "dfe.screenTime.allActivityStartDay.v1")
        let service = ScreenTimeService(defaults: defaults)
        let saved = store.archive
        let revoked = ScreenTimeAuthorizationDecision.state(permission: .notDetermined,
            previouslyAuthorized: true, supportsDataAccess: true, enabled: true)

        // [09] Permission loss changes connection status, without silently clearing consent history.
        XCTAssertEqual(revoked, .revoked)
        XCTAssertFalse(service.hasSavedAutomaticSetup(store: store) && revoked.canImport)
        XCTAssertTrue(service.hasSavedAutomaticSetup(store: store))
        XCTAssertEqual(store.archive, saved)
        XCTAssertEqual(defaults.string(forKey: "dfe.screenTime.allActivityStartDay.v1"), "2026-10-07")
        XCTAssertEqual(defaults.string(forKey: "dfe.screenTime.activityScope.v1"),
                       ScreenTimeActivityScope.allAuthorizedApps.rawValue)
    }

    #if DEBUG
    // [10] Test shortcuts belong only to a clearly isolated run, never to a normal launch on
    // someone's phone.
    @MainActor func testControlledAllActivitySetupRefusesANormalTestLaunch() async throws {
        let defaults = try isolatedScreenTimeDefaults()
        let service = ScreenTimeService(defaults: defaults)
        let store = store()

        XCTAssertThrowsError(try service.saveControlledAllActivitySetup(inputs: inputs(), store: store, now: first))
        XCTAssertFalse(store.isConfigured)
        XCTAssertEqual(service.activityScope, .selectedApps)
        XCTAssertNil(defaults.object(forKey: "dfe.screenTime.activityScope.v1"))
        XCTAssertNil(defaults.object(forKey: "dfe.screenTime.allActivityStartDay.v1"))
    }
    #endif

    // [11] A leftover preference without a saved setup must not authorize a new import.
    @MainActor func testDeleteRemovesIncompleteSetupInsteadOfGrantingAccess() async throws {
        let defaults = try isolatedScreenTimeDefaults()
        defaults.set(ScreenTimeActivityScope.allAuthorizedApps.rawValue, forKey: "dfe.screenTime.activityScope.v1")
        defaults.set("2026-10-08", forKey: "dfe.screenTime.allActivityStartDay.v1")
        defaults.set(Data("{}".utf8), forKey: "dfe.screenTime.categorySelections.v1")
        defaults.set("keep this setting", forKey: "unrelated-test-setting")
        let service = ScreenTimeService(defaults: defaults)
        // [12] Local reset does not call Apple's disconnect or request usage data.
        #if DEBUG
        XCTAssertNil(service.diagnosticScopeMutation)
        let resetBegan = Date()
        #endif
        let history = store()
        try service.deleteSavedEntries(in: history, now: later)
        XCTAssertFalse(history.isConfigured)
        #if DEBUG
        let receipt = try XCTUnwrap(service.diagnosticScopeMutation)
        XCTAssertEqual(receipt.reason, .localReset)
        XCTAssertGreaterThanOrEqual(receipt.timestamp, resetBegan)
        XCTAssertLessThanOrEqual(receipt.timestamp, Date())
        XCTAssertEqual(ScreenTimeService(defaults: defaults).diagnosticScopeMutation?.reason, .localReset)
        #endif
        XCTAssertEqual(service.activityScope, .selectedApps)
        XCTAssertNil(defaults.object(forKey: "dfe.screenTime.activityScope.v1"))
        XCTAssertNil(defaults.object(forKey: "dfe.screenTime.allActivityStartDay.v1"))
        XCTAssertNil(defaults.object(forKey: "dfe.screenTime.categorySelections.v1"))
        XCTAssertEqual(defaults.string(forKey: "unrelated-test-setting"), "keep this setting")
        XCTAssertEqual(ScreenTimeService(defaults: defaults).activityScope, .selectedApps)
    }

    // [13] A date from another input mode should not change which days a selected-app setup may
    // read.
    func testSelectedAppScopeIgnoresAnUnrelatedAllActivityStartDate() {
        let result = ScreenTimeScopeStart.importStart(scope: .selectedApps, archiveStart: first,
            allActivityStartDay: "2026-10-10", calendar: calendar)
        XCTAssertEqual(result, calendar.startOfDay(for: first))
    }

    // [14] Both the person's opt-in date and the archive's start date limit the first allowed
    // automatic day.
    func testAllActivityCannotImportBeforeEitherItsOptInOrTheArchiveBoundary() {
        XCTAssertEqual(ScreenTimeScopeStart.importStart(scope: .allAuthorizedApps, archiveStart: first,
            allActivityStartDay: "2026-10-08", calendar: calendar), calendar.startOfDay(for: nextDay))
        XCTAssertEqual(ScreenTimeScopeStart.importStart(scope: .allAuthorizedApps, archiveStart: nextDay,
            allActivityStartDay: "2026-10-07", calendar: calendar), calendar.startOfDay(for: nextDay))
    }

    // [15] An absent or broken start date is a reason to stop, rather than guess when consent
    // began.
    func testMissingOrMalformedAllActivityStartKeepsImportBlocked() {
        for key in [nil, "", "not a date", "2026-02-30", "2026-10-8", "2026-13-01"] {
            XCTAssertNil(ScreenTimeScopeStart.importStart(scope: .allAuthorizedApps,
                archiveStart: first, allActivityStartDay: key, calendar: calendar))
        }
    }

    // [16] Saving the setup records assumptions, not a day of activity that Apple has not
    // supplied.
    @MainActor func testAutomaticSetupSavesAssumptionsWithoutInventingADailyResult() async throws {
        let calculator = AutomaticSetupCalculator()
        let store = store(calculator)
        try store.saveAutomaticProfile(inputs(), now: first)
        XCTAssertTrue(store.isConfigured)
        XCTAssertTrue(store.usesAutomaticInput)
        XCTAssertEqual(store.firstDay, "2026-10-07")
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertNil(store.latest)
        XCTAssertEqual(calculator.calls, 0)
        let assumptions = try XCTUnwrap(store.archive?.revisions.first?.inputs)
        XCTAssertEqual(assumptions.totalMinutes, 0)
        XCTAssertEqual(assumptions.usages.first?.gigabytesPerHour, 1)
        XCTAssertEqual(assumptions.usages.first?.wifiShare, 0.8)
        XCTAssertEqual(assumptions.brightness, 0.5)
        XCTAssertEqual(assumptions.gpsHours, 0.25)
        XCTAssertEqual(assumptions.bluetoothHours, 2)
        XCTAssertEqual(reopen(store).archive, store.archive)
    }

    // [17] Older manual routines still need to open correctly after automatic setup becomes
    // available.
    @MainActor func testLegacyArchiveKeepsItsManualRoutineAndCatchUp() async throws {
        let store = store()
        try store.saveProfile(inputs(45), now: first)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any])
        json.removeValue(forKey: "inputPreference")
        try JSONSerialization.data(withJSONObject: json).write(to: store.fileURL, options: .atomic)
        let reopened = reopen(store)
        XCTAssertNil(reopened.archive?.inputPreference)
        XCTAssertFalse(reopened.usesAutomaticInput)
        try reopened.catchUp(now: nextDay)
        XCTAssertEqual(reopened.records.first?.source, .manual)
        XCTAssertEqual(reopened.records.first?.inputs.totalMinutes, 45)
        try reopened.catchUp(now: later)
        XCTAssertEqual(reopened.records.count, 3)
        XCTAssertEqual(reopened.records.last?.source, .routineEstimate)
    }

    // [18] Invalid assumptions should stop setup before a misleading history file is created.
    @MainActor func testInvalidAutomaticSetupCannotCreateAnArchive() async throws {
        let store = store()
        XCTAssertThrowsError(try store.saveAutomaticProfile(.empty, now: first))
        var invalid = inputs()
        invalid.usages[0].gigabytesPerHour = .nan
        XCTAssertThrowsError(try store.saveAutomaticProfile(invalid, now: first))
        XCTAssertFalse(store.isConfigured)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    // [19] If the first save fails, the app must still show that setup needs to be completed.
    @MainActor func testFailedFirstSaveKeepsSetupUnconfigured() async throws {
        let store = store()
        let parent = store.fileURL.deletingLastPathComponent()
        try Data("file occupying the history directory".utf8).write(to: parent)
        XCTAssertThrowsError(try store.saveAutomaticProfile(inputs(), now: first))
        XCTAssertNil(store.archive)
        XCTAssertFalse(store.usesAutomaticInput)
        XCTAssertEqual(try Data(contentsOf: parent), Data("file occupying the history directory".utf8))
    }

    // [20] A failed settings change should leave the last successfully saved assumptions in place.
    @MainActor func testFailedAssumptionRevisionKeepsTheCommittedArchive() async throws {
        let store = store()
        try store.saveAutomaticProfile(inputs(), now: first)
        let original = try Data(contentsOf: store.fileURL)
        let archive = store.archive
        // [21] A directory at the file path causes a genuine storage failure.
        try FileManager.default.removeItem(at: store.fileURL)
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.saveProfile(inputs(120), now: nextDay))
        XCTAssertEqual(store.archive, archive)
        XCTAssertTrue(store.usesAutomaticInput)
        try FileManager.default.removeItem(at: store.fileURL)
        try original.write(to: store.fileURL, options: .atomic)
        XCTAssertEqual(reopen(store).archive, archive)
    }

    // [22] Unavailable days must stay empty, and later setup cannot make earlier collection look
    // authorized.
    @MainActor func testMissingAutomaticDaysStayMissingAndCannotBeBackdated() async throws {
        let store = store()
        try store.saveAutomaticProfile(inputs(), now: first)
        try store.catchUp(now: later)
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertThrowsError(try store.importAutomaticUsage(day: date("2026-10-06T10:00:00Z"),
            minutesByCategory: ["VIDEO_STREAMING": 15], now: later))
        XCTAssertThrowsError(try store.importAutomaticUsage(day: later,
            minutesByCategory: ["VIDEO_STREAMING": 15], now: later))
        XCTAssertTrue(store.records.isEmpty)
        let original = store.archive
        XCTAssertThrowsError(try store.catchUp(now: later, shouldCancel: { true }))
        XCTAssertEqual(store.archive, original)
    }

    // [23] A measured zero is useful data. It should be saved when Apple supplied a complete day.
    @MainActor func testFirstCompletedDayAcceptsMeasuredTimeIncludingARealZero() async throws {
        let store = store()
        try store.saveAutomaticProfile(inputs(), now: first)
        try store.importAutomaticUsage(day: first, minutesByCategory: ["VIDEO_STREAMING": 20], now: nextDay)
        let record = try XCTUnwrap(store.records.first)
        XCTAssertEqual(record.day, "2026-10-07")
        XCTAssertEqual(record.inputs.totalMinutes, 20)
        XCTAssertEqual(record.inputs.usages.first?.gigabytesPerHour, 1)
        XCTAssertEqual(record.inputs.brightness, 0.5)
        XCTAssertEqual(record.source, .screenTimeWithEstimates)
        XCTAssertEqual(record.automaticCategories, [.video])
        XCTAssertTrue(record.isCompleted)
        try store.importAutomaticUsage(day: first, minutesByCategory: ["VIDEO_STREAMING": 0], now: nextDay)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.inputs.totalMinutes, 0)
        XCTAssertFalse(reopen(store).canExportHistory)
    }

    // [24] One missing category is not proof of no use; an incomplete response must stay pending.
    @MainActor func testPartialCategoryDataCannotBecomeAZeroUseDay() async throws {
        let store = store()
        var assumptions = inputs()
        assumptions.usages.append(CategoryUsage(category: .audio, gigabytesPerHour: 0.1))
        try store.saveAutomaticProfile(assumptions, now: first)
        let original = try Data(contentsOf: store.fileURL)
        XCTAssertThrowsError(try store.importAutomaticUsage(day: first,
            minutesByCategory: ["VIDEO_STREAMING": 30], now: nextDay))
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
        try store.importAutomaticUsage(day: first,
            minutesByCategory: ["VIDEO_STREAMING": 30, "AUDIO_STREAMING": 10], now: nextDay)
        XCTAssertEqual(store.records.first?.inputs.totalMinutes, 40)
    }

    // [25] An explicit correction in older history keeps priority over a later automatic import.
    @MainActor func testManualCorrectionKeepsPriorityWithinAnAutomaticRoutine() async throws {
        let store = store()
        try store.saveAutomaticProfile(inputs(), now: first)
        try store.importAutomaticUsage(day: first, minutesByCategory: ["VIDEO_STREAMING": 20], now: nextDay)
        try store.saveDay("2026-10-07", inputs: inputs(35), now: nextDay)
        let corrected = store.archive
        try store.importAutomaticUsage(day: first, minutesByCategory: ["VIDEO_STREAMING": 10], now: nextDay)
        XCTAssertEqual(store.archive, corrected)
        XCTAssertEqual(store.records.first?.source, .manual)
        XCTAssertEqual(store.records.first?.inputs.totalMinutes, 35)
        XCTAssertTrue(reopen(store).usesAutomaticInput)
        XCTAssertFalse(reopen(store).canExportHistory)
    }

    // [26] Revising future assumptions should not remove automatic mode or rewrite earlier
    // measured activity.
    @MainActor func testAssumptionEditsKeepAutomaticModeAndEarlierMeasuredRecords() async throws {
        let store = store()
        try store.saveAutomaticProfile(inputs(), now: first)
        try store.importAutomaticUsage(day: first, minutesByCategory: ["VIDEO_STREAMING": 20], now: nextDay)
        let oldRecord = store.records.first
        var changed = inputs(120)
        changed.usages[0].gigabytesPerHour = 2
        changed.brightness = 0.75
        try store.saveProfile(changed, now: nextDay)
        XCTAssertTrue(store.usesAutomaticInput)
        XCTAssertEqual(store.firstDay, "2026-10-07")
        XCTAssertEqual(store.records.first, oldRecord)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.archive?.revisions.last?.inputs.totalMinutes, 0)
        try store.importAutomaticUsage(day: nextDay, minutesByCategory: ["VIDEO_STREAMING": 40], now: later)
        XCTAssertEqual(store.records.last?.inputs.usages.first?.gigabytesPerHour, 2)
        XCTAssertEqual(store.records.last?.inputs.brightness, 0.75)
        XCTAssertEqual(store.records.last?.inputs.totalMinutes, 40)
        XCTAssertEqual(store.records.first?.inputs.usages.first?.gigabytesPerHour, 1)
        XCTAssertFalse(reopen(store).canExportHistory)
    }

    // [27] After deleting history, an older manual setup can start cleanly without hidden
    // automatic settings.
    @MainActor func testDeletingAutomaticHistoryAllowsAFreshManualStart() async throws {
        let store = store()
        try store.saveAutomaticProfile(inputs(), now: first)
        try store.importAutomaticUsage(day: first, minutesByCategory: ["VIDEO_STREAMING": 20], now: nextDay)
        try store.deleteAll()
        XCTAssertFalse(store.isConfigured)
        XCTAssertFalse(store.usesAutomaticInput)
        try store.saveProfile(inputs(45), now: later)
        XCTAssertFalse(store.usesAutomaticInput)
        XCTAssertEqual(store.firstDay, "2026-10-10")
        XCTAssertEqual(store.records.first?.source, .manual)
        XCTAssertEqual(store.records.first?.inputs.totalMinutes, 45)
        XCTAssertTrue(reopen(store).canExportHistory)
    }

    // [28] Switching to automatic input starts at the new choice and leaves earlier history where
    // it belongs.
    @MainActor func testSwitchingFromManualStartsAutomaticInputAtOptInWithoutMovingHistory() async throws {
        let store = store()
        try store.saveProfile(inputs(45), now: first)
        try store.saveAutomaticProfile(inputs(), now: nextDay)
        XCTAssertEqual(store.firstDay, "2026-10-07")
        XCTAssertEqual(store.archive?.automaticStartDay, "2026-10-08")
        XCTAssertEqual(store.records.first?.source, .manual)
        XCTAssertEqual(store.records.first?.inputs.totalMinutes, 45)
        let reopened = reopen(store)
        XCTAssertEqual(reopened.automaticStartDate, calendar.startOfDay(for: nextDay))
        let original = try Data(contentsOf: reopened.fileURL)
        XCTAssertThrowsError(try reopened.importAutomaticUsage(day: first,
            minutesByCategory: ["VIDEO_STREAMING": 20], now: later))
        XCTAssertEqual(try Data(contentsOf: reopened.fileURL), original)
        try reopened.importAutomaticUsage(day: nextDay,
            minutesByCategory: ["VIDEO_STREAMING": 20], now: later)
        try reopened.saveProfile(inputs(90), now: later)
        XCTAssertEqual(reopen(reopened).archive?.automaticStartDay, "2026-10-08")
        XCTAssertEqual(reopened.records.map(\.day), ["2026-10-07", "2026-10-08"])
        XCTAssertEqual(reopened.records.first?.inputs.totalMinutes, 45)
        XCTAssertEqual(reopened.records.last?.source, .screenTimeWithEstimates)
    }

    // [29] An old automatic file without a start date needs a new review, rather than an invented
    // consent date.
    @MainActor func testAutomaticArchiveWithoutOptInDateNeedsAnExplicitSetupReview() async throws {
        let store = store()
        try store.saveAutomaticProfile(inputs(), now: first)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any])
        json.removeValue(forKey: "automaticStartDay")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        try legacy.write(to: store.fileURL, options: .atomic)
        let reopened = reopen(store)
        XCTAssertTrue(reopened.isConfigured)
        XCTAssertTrue(reopened.usesAutomaticInput)
        XCTAssertNil(reopened.automaticStartDate)
        XCTAssertThrowsError(try reopened.importAutomaticUsage(day: first,
            minutesByCategory: ["VIDEO_STREAMING": 20], now: nextDay))
        XCTAssertThrowsError(try reopened.saveProfile(inputs(), now: later))
        XCTAssertTrue(reopened.records.isEmpty)
        XCTAssertEqual(try Data(contentsOf: reopened.fileURL), legacy)
        // [30] Reviewing setup establishes a new date instead of guessing an older one.
        try reopened.saveAutomaticProfile(inputs(), now: later)
        XCTAssertEqual(reopened.firstDay, "2026-10-07")
        XCTAssertEqual(reopen(reopened).archive?.automaticStartDay, "2026-10-10")
        XCTAssertThrowsError(try reopened.importAutomaticUsage(day: first,
            minutesByCategory: ["VIDEO_STREAMING": 20], now: date("2026-10-11T10:00:00Z")))
        try reopened.importAutomaticUsage(day: later, minutesByCategory: ["VIDEO_STREAMING": 20],
            now: date("2026-10-11T10:00:00Z"))
        XCTAssertEqual(reopened.records.map(\.day), ["2026-10-10"])
    }

    // [31] Broken consent details must remain available for recovery instead of being overwritten
    // by setup.
    @MainActor func testInvalidAutomaticStartMetadataIsPreservedAndCannotBeOverwritten() async throws {
        let store = store()
        try store.saveAutomaticProfile(inputs(), now: first)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any])
        for invalidDay in ["not a date", "2026-02-30", "2026-10-06", "2026-10-09"] {
            var invalid = original
            invalid["automaticStartDay"] = invalidDay
            let data = try JSONSerialization.data(withJSONObject: invalid)
            try data.write(to: store.fileURL, options: .atomic)
            let reopened = reopen(store)
            XCTAssertFalse(reopened.isConfigured)
            XCTAssertNotNil(reopened.errorMessage)
            XCTAssertThrowsError(try reopened.saveAutomaticProfile(inputs(), now: later))
            XCTAssertEqual(try Data(contentsOf: reopened.fileURL), data)
        }
    }
}
