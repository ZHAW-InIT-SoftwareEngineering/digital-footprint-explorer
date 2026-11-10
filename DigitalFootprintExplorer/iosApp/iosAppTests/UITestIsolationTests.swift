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

// [01] Interface previews need their own history and settings so they cannot affect the owner's
// real activity or access

#if DEBUG
import XCTest
@testable import DFE

private final class PreviewIsolationCalculator: FootprintCalculating {
    func calculate(_ inputs: FootprintInputs) throws -> FootprintResult {
        let total = inputs.totalMinutes / 1_000
        return FootprintResult(totalKg: total, appUsageKg: total, displayKg: 0,
                               backgroundKg: 0, categories: [])
    }
}

@MainActor
final class UITestIsolationTests: XCTestCase {
    private let arguments = ["-ui-testing", "-ui-automatic-preview"]
    private let scopeKey = "dfe.screenTime.activityScope.v1"
    private let startKey = "dfe.screenTime.allActivityStartDay.v1"
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return value
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var first: Date { date("2026-10-19T10:00:00Z") }
    private var next: Date { date("2026-10-20T10:00:00Z") }
    private var later: Date { date("2026-10-22T10:00:00Z") }

    private func defaults() throws -> UserDefaults {
        let suite = "dfe.preview-boundary-tests.\(UUID().uuidString)"
        let value = try XCTUnwrap(UserDefaults(suiteName: suite))
        value.removePersistentDomain(forName: suite)
        addTeardownBlock { value.removePersistentDomain(forName: suite) }
        return value
    }
    private func store() -> FootprintStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return FootprintStore(fileURL: directory.appendingPathComponent("history.json"),
                              calculator: PreviewIsolationCalculator(), calendar: calendar)
    }
    private func saveSetup(_ service: ScreenTimeService, history: FootprintStore) throws {
        try service.saveControlledAllActivitySetup(
            inputs: AutomaticActivityClassification.assumptions(preserving: nil), store: history, now: first)
    }

    // [02] Only a deliberate interface-test launch should select disposable test storage.
    func testOnlyExplicitUITestFlagEnablesIsolation() {
        for flags in [[], ["-ui-automatic-preview"], ["-ui-testing-disabled"], ["-ui-revoked-preview"]] {
            XCTAssertFalse(UITestIsolation(arguments: flags).isActive)
            XCTAssertFalse(UITestIsolation(arguments: flags).permitsAutomaticPreview)
        }
        XCTAssertTrue(UITestIsolation(arguments: ["-ui-testing"]).isActive)
        XCTAssertFalse(UITestIsolation(arguments: ["-ui-testing"]).permitsAutomaticPreview)
        XCTAssertTrue(UITestIsolation(arguments: arguments).permitsAutomaticPreview)
    }

    // [03] Preview connection status should come from saved test choices, not the owner's real
    // Apple permission.
    func testPreviewAuthorizationDependsOnSavedScopeRatherThanThePhonesPermission() {
        let ordinary = UITestIsolation(arguments: arguments)
        XCTAssertEqual(ordinary.authorizationState(hasSavedSetup: false, previouslyAuthorized: false), .notRequested)
        XCTAssertEqual(ordinary.authorizationState(hasSavedSetup: false, previouslyAuthorized: true), .revoked)
        XCTAssertEqual(ordinary.authorizationState(hasSavedSetup: true, previouslyAuthorized: false), .dataAccess)
        let revoked = UITestIsolation(arguments: arguments + ["-ui-revoked-preview"])
        XCTAssertEqual(revoked.authorizationState(hasSavedSetup: false, previouslyAuthorized: false), .revoked)
        XCTAssertEqual(revoked.authorizationState(hasSavedSetup: true, previouslyAuthorized: true), .dataAccess)
    }

    // [04] Tapping a preview permission action must not silently finish a setup the test has not
    // saved.
    func testIsolatedPermissionActionsLeaveAnUnconfiguredPreviewUnchanged() async throws {
        let preferences = try defaults()
        let service = ScreenTimeService(isolatedUIArguments: arguments, defaults: preferences)
        XCTAssertEqual(service.state, .notRequested)
        XCTAssertTrue(service.supportsAutomaticSetup)
        let saved = preferences.dictionaryRepresentation()
        await service.requestAuthorization()
        await service.disconnect()
        service.refreshAuthorization()
        XCTAssertEqual(service.state, .notRequested)
        XCTAssertFalse(service.isRequesting)
        XCTAssertEqual(preferences.dictionaryRepresentation() as NSDictionary, saved as NSDictionary)
        XCTAssertNil(service.diagnosticScopeMutation)
    }

    // [05] A completed preview setup should remain connected when its local service is created
    // again.
    func testCompletedPreviewSetupStaysConnectedAfterAColdServiceReload() throws {
        let preferences = try defaults()
        let history = store()
        let service = ScreenTimeService(isolatedUIArguments: arguments, defaults: preferences)
        try saveSetup(service, history: history)
        XCTAssertTrue(service.hasSavedAutomaticSetup(store: history))
        XCTAssertEqual(service.state, .dataAccess)
        XCTAssertTrue(history.records.isEmpty, "Preview consent must not invent a daily result")
        let bytes = try Data(contentsOf: history.fileURL)
        let reopened = ScreenTimeService(isolatedUIArguments: arguments, defaults: preferences)
        reopened.refreshAuthorization()
        XCTAssertEqual(reopened.state, .dataAccess)
        XCTAssertTrue(reopened.hasSavedAutomaticSetup(store: history))
        XCTAssertEqual(try Data(contentsOf: history.fileURL), bytes)
    }

    // [06] A preview that represents revoked access should stay disconnected until its own setup
    // is saved again.
    func testRevokedPreviewStaysRevokedUntilControlledSetupIsSaved() async throws {
        let preferences = try defaults()
        let history = store()
        let flags = arguments + ["-ui-revoked-preview"]
        let service = ScreenTimeService(isolatedUIArguments: flags, defaults: preferences)
        XCTAssertEqual(service.state, .revoked)
        await service.requestAuthorization()
        XCTAssertEqual(service.state, .revoked, "A preview must not ask Apple to repair access")
        try saveSetup(service, history: history)
        XCTAssertEqual(service.state, .dataAccess)
        XCTAssertEqual(ScreenTimeService(isolatedUIArguments: flags, defaults: preferences).state, .dataAccess)
    }

    // [07] Crossing midnight in a layout test must not request private activity or rewrite saved
    // test days.
    func testIsolatedRefreshAcrossMidnightCannotImportActivityOrRewriteSavedDays() async throws {
        let preferences = try defaults()
        let history = store()
        let service = ScreenTimeService(isolatedUIArguments: arguments, defaults: preferences)
        try saveSetup(service, history: history)
        var minutes = Dictionary(uniqueKeysWithValues: FootprintCategory.allCases.map { ($0.rawValue, 0.0) })
        minutes[FootprintCategory.video.rawValue] = 20
        try history.importAutomaticUsage(day: first, minutesByCategory: minutes, now: next)
        let bytes = try Data(contentsOf: history.fileURL)
        let archive = history.archive
        XCTAssertTrue(service.hasEligibleCompletedDay(store: history, now: later))
        let result = try await service.refreshAutomaticDays(store: history, now: later)
        XCTAssertEqual(result, ScreenTimeRefreshResult())
        XCTAssertFalse(result.latestCompletedDayRefreshed)
        XCTAssertEqual(history.archive, archive)
        XCTAssertEqual(try Data(contentsOf: history.fileURL), bytes)
        XCTAssertNil(service.lastImportDate)
        XCTAssertFalse(service.isImporting)
    }

    // [08] A preview disconnect should change only its displayed state, leaving real permission
    // and saved setup alone.
    func testIsolatedDisconnectCannotRevokeOrClearTheSavedPreviewSetup() async throws {
        let preferences = try defaults()
        let history = store()
        let service = ScreenTimeService(isolatedUIArguments: arguments, defaults: preferences)
        try saveSetup(service, history: history)
        let bytes = try Data(contentsOf: history.fileURL)
        let saved = preferences.dictionaryRepresentation()
        await service.disconnect()
        XCTAssertEqual(service.state, .dataAccess)
        XCTAssertTrue(service.hasSavedAutomaticSetup(store: history))
        XCTAssertEqual(try Data(contentsOf: history.fileURL), bytes)
        XCTAssertEqual(preferences.dictionaryRepresentation() as NSDictionary, saved as NSDictionary)
        XCTAssertNil(service.diagnosticScopeMutation)
    }

    // [09] Delete uses a fresh routine and a later start date, while the saved connection stays usable.
    func testDeleteKeepsConnectedSetupAfterReopeningWithoutRestoringErasedDays() throws {
        let preferences = try defaults()
        let history = store()
        let service = ScreenTimeService(isolatedUIArguments: arguments, defaults: preferences)
        var earlierInputs = AutomaticActivityClassification.assumptions(preserving: nil)
        earlierInputs.brightness = 0.9
        try service.saveControlledAllActivitySetup(inputs: earlierInputs, store: history, now: first)
        var minutes = Dictionary(uniqueKeysWithValues: FootprintCategory.allCases.map { ($0.rawValue, 0.0) })
        minutes[FootprintCategory.video.rawValue] = 20
        try history.importAutomaticUsage(day: first, minutesByCategory: minutes, now: next)
        XCTAssertEqual(history.records.count, 1)
        preferences.set(Data("{}".utf8), forKey: "dfe.screenTime.categorySelections.v1")
        preferences.set(history.dayKey(for: next), forKey: "dfe.screenTime.backfillCursorDay.v1")
        preferences.set("keep", forKey: "unrelated")
        service.beforeWidgetAccessEnds = { XCTFail("Deletion is not a request to disconnect") }
        let previousContext = service.refreshContext(store: history, now: later)
        try service.deleteSavedEntries(in: history, now: later)

        XCTAssertEqual(service.state, .dataAccess)
        XCTAssertTrue(service.hasSavedAutomaticSetup(store: history))
        XCTAssertNotEqual(service.refreshContext(store: history, now: later), previousContext)
        XCTAssertEqual(preferences.string(forKey: scopeKey), ScreenTimeActivityScope.allAuthorizedApps.rawValue)
        XCTAssertEqual(preferences.string(forKey: startKey), history.dayKey(for: first))
        XCTAssertNil(preferences.object(forKey: "dfe.screenTime.categorySelections.v1"))
        XCTAssertNil(preferences.object(forKey: "dfe.screenTime.backfillCursorDay.v1"))
        XCTAssertEqual(preferences.string(forKey: "unrelated"), "keep")
        XCTAssertEqual(service.diagnosticScopeMutation?.reason, .localReset)
        XCTAssertNil(history.importVerification.record(for: history.dayKey(for: first)))

        let reopened = FootprintStore(fileURL: history.fileURL,
            calculator: PreviewIsolationCalculator(), calendar: calendar)
        let reopenedService = ScreenTimeService(isolatedUIArguments: arguments, defaults: preferences)
        XCTAssertEqual(reopenedService.state, .dataAccess)
        XCTAssertTrue(reopenedService.hasSavedAutomaticSetup(store: reopened))
        XCTAssertTrue(reopened.records.isEmpty)
        XCTAssertFalse(reopened.archive?.containsScreenTimeDerivedData ?? true)
        XCTAssertEqual(reopened.archive?.revisions.map(\.inputs),
            [AutomaticActivityClassification.assumptions(preserving: nil)])
        XCTAssertEqual(reopened.firstDay, reopened.dayKey(for: later))
        XCTAssertFalse(reopenedService.hasEligibleCompletedDay(store: reopened, now: later))
        XCTAssertThrowsError(try reopened.importAutomaticUsage(day: first, minutesByCategory: minutes, now: later))
        XCTAssertThrowsError(try reopened.importAutomaticUsage(day: later, minutesByCategory: minutes, now: later))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: later))
        try reopened.importAutomaticUsage(day: later, minutesByCategory: minutes, now: tomorrow)
        XCTAssertEqual(reopened.records.map(\.day), [reopened.dayKey(for: later)])
    }
}
#endif
