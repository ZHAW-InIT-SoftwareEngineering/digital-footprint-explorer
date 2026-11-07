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

import XCTest
@testable import DFE

private final class VerificationCalculator: FootprintCalculating {
    var shouldFail = false
    func calculate(_ inputs: FootprintInputs) throws -> FootprintResult {
        if shouldFail { throw FootprintError.invalidResult }
        return FootprintResult(totalKg: 0.01, appUsageKg: 0.01, displayKg: 0, backgroundKg: 0, categories: [])
    }
}

@MainActor private final class ImportVerificationGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }
}

final class ImportVerificationIntegrationTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return calendar
    }
    private var minutes: [String: Double] {
        Dictionary(uniqueKeysWithValues: FootprintCategory.allCases.map { ($0.rawValue, $0 == .video ? 30 : 0) })
    }
    @MainActor private func makeStore(calculator: VerificationCalculator = VerificationCalculator(),
                                      completedAt: Date, completedState: AutomaticUpdateCompletionState = .background) throws -> FootprintStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = FootprintStore(fileURL: directory.appendingPathComponent("history.json"),
            calculator: calculator, calendar: calendar, verificationClock: { completedAt },
            verificationCompletionState: { completedState })
        try store.saveAutomaticProfile(AutomaticActivityClassification.assumptions(preserving: nil),
                                       now: date("2026-10-30T12:00:00Z"))
        return store
    }

    // [01] A slow query must report when the saved result became available, not when it started.
    @MainActor func testActualCompletionClockFollowsSuccessfulCommit() async throws {
        let completion = date("2026-11-01T07:12:46Z")
        let store = try makeStore(completedAt: completion)
        try store.importAutomaticUsage(day: date("2026-10-31T12:00:00Z"), minutesByCategory: minutes,
            now: date("2026-11-01T07:00:00Z"), origin: .backgroundRefresh)
        let check = try XCTUnwrap(store.importVerification.record(for: "2026-10-31"))
        XCTAssertEqual(check.firstObservedAt, completion)
        XCTAssertEqual(check.lastObservedAt, completion)
        XCTAssertEqual(check.firstOrigin, .backgroundRefresh)
        XCTAssertEqual(check.lastCompletionState, .background)
        XCTAssertTrue(check.initialSaveObserved)
        XCTAssertEqual(store.records.last?.source, .screenTimeWithEstimates)
    }

    // [02] A failed calculation has no saved result, so it must leave no successful-import note.
    @MainActor func testFailedImportDoesNotCreateSuccessReceipt() async throws {
        let calculator = VerificationCalculator()
        let store = try makeStore(calculator: calculator, completedAt: date("2026-11-01T07:12:46Z"))
        calculator.shouldFail = true
        XCTAssertThrowsError(try store.importAutomaticUsage(day: date("2026-10-31T12:00:00Z"),
            minutesByCategory: minutes, now: date("2026-11-01T07:00:00Z"), origin: .backgroundProcessing))
        XCTAssertTrue(store.importVerification.records.isEmpty)
        XCTAssertTrue(store.records.isEmpty)
    }

    // [03] Saving a technical check is useful, but its failure must not lose the person's real result.
    @MainActor func testReceiptWriteFailureKeepsSuccessfulHistory() async throws {
        let store = try makeStore(completedAt: date("2026-11-01T07:12:46Z"))
        let blocked = store.fileURL.deletingPathExtension().appendingPathExtension("import-verification.json")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        try store.importAutomaticUsage(day: date("2026-10-31T12:00:00Z"), minutesByCategory: minutes,
            now: date("2026-11-01T07:00:00Z"), origin: .backgroundRefresh)
        XCTAssertEqual(store.records.last?.day, "2026-10-31")
        XCTAssertTrue(store.importVerification.persistenceFailed)
        XCTAssertTrue(store.importVerification.records.isEmpty)
    }

    // [04] An older imported day has an unknown first time. A new check cannot rewrite that history.
    @MainActor func testOlderAutomaticRecordDoesNotAcquireInventedFirstImport() async throws {
        let store = try makeStore(completedAt: date("2026-11-01T07:12:46Z"))
        try store.saveDay("2026-10-31", inputs: AutomaticActivityClassification.assumptions(preserving: nil),
                          source: .screenTimeWithEstimates, now: date("2026-11-01T06:00:00Z"))
        try store.importAutomaticUsage(day: date("2026-10-31T12:00:00Z"), minutesByCategory: minutes,
            now: date("2026-11-01T07:00:00Z"), origin: .foreground)
        XCTAssertFalse(try XCTUnwrap(store.importVerification.record(for: "2026-10-31")).initialSaveObserved)
    }

    // [05] An explicit manual entry wins, and cannot be reported as an automatic import.
    @MainActor func testPreservedManualDayCreatesNoAutomaticCheck() async throws {
        let store = try makeStore(completedAt: date("2026-11-01T07:12:46Z"))
        try store.saveDay("2026-10-31", inputs: AutomaticActivityClassification.assumptions(preserving: nil),
                          source: .manual, now: date("2026-11-01T06:00:00Z"))
        try store.importAutomaticUsage(day: date("2026-10-31T12:00:00Z"), minutesByCategory: minutes,
            now: date("2026-11-01T07:00:00Z"), origin: .foreground)
        XCTAssertTrue(store.importVerification.records.isEmpty)
        XCTAssertEqual(store.records.last?.source, .manual)
    }

    // [06] Delete all means the saved technical dates go too, including after the store is reopened.
    @MainActor func testDeleteAllClearsPersistedImportChecks() async throws {
        let store = try makeStore(completedAt: date("2026-11-01T07:12:46Z"))
        try store.importAutomaticUsage(day: date("2026-10-31T12:00:00Z"), minutesByCategory: minutes,
            now: date("2026-11-01T07:00:00Z"), origin: .backgroundRefresh)
        try store.deleteAll()
        let reopened = FootprintStore(fileURL: store.fileURL, calculator: VerificationCalculator(), calendar: calendar)
        XCTAssertTrue(reopened.importVerification.records.isEmpty)
        XCTAssertFalse(reopened.isConfigured)
    }

    // [07] An open screen may wait for background work. The single real save keeps its background origin.
    @MainActor func testCoalescedForegroundWaiterCannotRelabelBackgroundSave() async throws {
        let store = try makeStore(completedAt: date("2026-11-01T07:12:46Z"), completedState: .active)
        let coordinator = RefreshCoordinator<Bool>()
        let key = UUID()
        let entered = ImportVerificationGate()
        let finish = ImportVerificationGate()
        let background = Task { @MainActor in
            try await coordinator.perform(key: key, context: "2026-11-01|Europe/Zurich") {
                entered.open()
                await finish.wait()
                try store.importAutomaticUsage(day: self.date("2026-10-31T12:00:00Z"), minutesByCategory: self.minutes,
                    now: self.date("2026-11-01T07:00:00Z"), origin: .backgroundRefresh)
                return true
            }
        }
        await entered.wait()
        let foreground = Task { @MainActor in
            try await coordinator.perform(key: key, context: "2026-11-01|Europe/Zurich") {
                try store.importAutomaticUsage(day: self.date("2026-10-31T12:00:00Z"), minutesByCategory: self.minutes,
                    now: self.date("2026-11-01T07:00:00Z"), origin: .foreground)
                return true
            }
        }
        for _ in 0..<1_000 {
            if coordinator.waitingRequests > 0 { break }
            await Task.yield()
        }
        XCTAssertEqual(coordinator.waitingRequests, 1)
        finish.open()
        let backgroundResult = try await background.value
        let foregroundResult = try await foreground.value
        XCTAssertTrue(backgroundResult && foregroundResult)
        let check = try XCTUnwrap(store.importVerification.record(for: "2026-10-31"))
        XCTAssertEqual(check.firstOrigin, .backgroundRefresh)
        XCTAssertEqual(check.lastOrigin, .backgroundRefresh)
        XCTAssertEqual(check.lastCompletionState, .active, "Started in background does not mean it finished there")
    }
    // [08] A copied support check must contain dates and status, never the underlying estimate or activity.
    @MainActor func testSupportReportContainsOnlyVerificationFields() async throws {
        let store = try makeStore(completedAt: date("2026-11-01T07:12:46Z"))
        try store.importAutomaticUsage(day: date("2026-10-31T12:00:00Z"), minutesByCategory: minutes,
            now: date("2026-11-01T07:00:00Z"), origin: .backgroundRefresh)
        let report = AutomaticUpdateSupportReport(capturedAt: date("2026-11-01T07:13:00Z"),
            producer: .current, latestSavedDay: store.latest?.day, verifiedSave: store.latestVerifiedAutomaticSave,
            importCheckSaveFailed: false, publication: store.widgetVerification, widgetReads: [], widgetCheckSaveFailed: false)
        let data = try JSONEncoder().encode(report)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(root.keys), ["schemaVersion", "capturedAt", "producer", "latestSavedDay", "verifiedSave",
                                        "importCheckSaveFailed", "publication", "widgetReads", "widgetCheckSaveFailed"])
        let text = String(decoding: data, as: UTF8.self)
        for forbidden in ["totalKg", "minutes", "usages", "tokens", "bundleIdentifier", "inputs", "snapshot"] {
            XCTAssertFalse(text.contains("\"" + forbidden + "\""))
        }
    }

    // [09] Even an unfinished older automatic day has a past save whose exact time we did not observe.
    @MainActor func testOlderIncompleteAutomaticRecordKeepsUnknownFirstImport() async throws {
        let store = try makeStore(completedAt: date("2026-11-01T07:12:46Z"))
        try store.saveDay("2026-10-31", inputs: AutomaticActivityClassification.assumptions(preserving: nil),
                          source: .screenTimeWithEstimates, now: date("2026-10-31T12:00:00Z"))
        XCTAssertFalse(try XCTUnwrap(store.latest).isCompleted)
        try store.importAutomaticUsage(day: date("2026-10-31T12:00:00Z"), minutesByCategory: minutes,
            now: date("2026-11-01T07:00:00Z"), origin: .foreground)
        let check = try XCTUnwrap(store.latestVerifiedAutomaticSave)
        XCTAssertFalse(check.initialSaveObserved)
        XCTAssertEqual(check.lastObservedAt, date("2026-11-01T07:12:46Z"))
    }

    // [10] A later manual edit keeps its day, but must not carry an old import's success label.
    @MainActor func testManualReplacementIsNotReportedAsVerifiedImport() async throws {
        let store = try makeStore(completedAt: date("2026-11-01T07:12:46Z"))
        try store.importAutomaticUsage(day: date("2026-10-31T12:00:00Z"), minutesByCategory: minutes,
            now: date("2026-11-01T07:00:00Z"), origin: .backgroundRefresh)
        XCTAssertNotNil(store.latestVerifiedAutomaticSave)
        try store.saveDay("2026-10-31", inputs: AutomaticActivityClassification.assumptions(preserving: nil),
                          source: .manual, now: date("2026-11-01T07:15:00Z"))
        XCTAssertNotNil(store.importVerification.record(for: "2026-10-31"))
        XCTAssertNil(store.latestVerifiedAutomaticSave)
        let report = AutomaticUpdateSupportReport(capturedAt: date("2026-11-01T07:16:00Z"),
            producer: .current, latestSavedDay: store.latest?.day, verifiedSave: store.latestVerifiedAutomaticSave,
            importCheckSaveFailed: false, publication: nil, widgetReads: [], widgetCheckSaveFailed: false)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
        XCTAssertEqual(root["latestSavedDay"] as? String, "2026-10-31")
        XCTAssertNil(root["verifiedSave"])
        XCTAssertNil(root["importedDay"])
    }

    // [11] A receipt for an earlier save does not turn an unfinished current result into a completed import.
    @MainActor func testIncompleteCurrentAutomaticResultDoesNotShowEarlierReceipt() async throws {
        let store = try makeStore(completedAt: date("2026-11-01T07:12:46Z"))
        try store.importAutomaticUsage(day: date("2026-10-31T12:00:00Z"), minutesByCategory: minutes,
            now: date("2026-11-01T07:00:00Z"), origin: .backgroundRefresh)
        try store.saveDay("2026-10-31", inputs: AutomaticActivityClassification.assumptions(preserving: nil),
                          source: .screenTimeWithEstimates, now: date("2026-10-31T12:00:00Z"))
        XCTAssertFalse(try XCTUnwrap(store.latest).isCompleted)
        XCTAssertNotNil(store.importVerification.record(for: "2026-10-31"))
        XCTAssertNil(store.latestVerifiedAutomaticSave)
    }

}
