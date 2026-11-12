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

// [01] Screen Time-derived history stays inside the app; older manual records keep their separate
// export rules

import XCTest
@testable import DFE

private struct ExportPolicyCalculator: FootprintCalculating {
    func calculate(_ inputs: FootprintInputs) throws -> FootprintResult {
        let total = inputs.totalMinutes / 1000
        return FootprintResult(totalKg: total, appUsageKg: total, displayKg: 0,
                               backgroundKg: 0, categories: [])
    }
}

final class HistoryExportPolicyTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return value
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var first: Date { date("2026-10-07T10:00:00Z") }
    private var importedDay: Date { date("2026-10-08T10:00:00Z") }
    private var now: Date { date("2026-10-10T10:00:00Z") }
    private func inputs(_ minutes: Double = 60) -> FootprintInputs {
        FootprintInputs(usages: [CategoryUsage(category: .video, minutes: minutes,
                                              gigabytesPerHour: 1, wifiShare: 0.8)],
                        brightness: 0.5, gpsHours: 0, bluetoothHours: 0)
    }
    @MainActor private func store() -> FootprintStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return FootprintStore(fileURL: directory.appendingPathComponent("history.json"),
                              calculator: ExportPolicyCalculator(), calendar: calendar)
    }
    @MainActor private func reopen(_ store: FootprintStore) -> FootprintStore {
        FootprintStore(fileURL: store.fileURL, calculator: ExportPolicyCalculator(), calendar: calendar)
    }
    @MainActor private func removeProvenanceField(from store: FootprintStore) throws {
        // [02] Older history did not record its import origin this way. It still needs the right
        // export protection.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL))
                                 as? [String: Any])
        json.removeValue(forKey: "screenTimeDataImported")
        try JSONSerialization.data(withJSONObject: json).write(to: store.fileURL, options: .atomic)
    }

    // [03] Older manual records should stay exportable after reopening, even before the source
    // flag existed.
    @MainActor func testManualAndRoutineHistoryRemainsExportableAcrossRelaunch() async throws {
        let store = store()
        XCTAssertFalse(store.canExportHistory)
        try store.saveProfile(inputs(), now: first)
        try store.catchUp(now: now)
        XCTAssertTrue(store.canExportHistory)
        try removeProvenanceField(from: store)
        let reopened = reopen(store)
        XCTAssertNil(reopened.errorMessage)
        XCTAssertTrue(reopened.canExportHistory)
        try reopened.saveDay("2026-10-08", inputs: inputs(30), now: now)
        XCTAssertTrue(reopen(reopened).canExportHistory)
    }

    // [04] Editing a result does not erase its imported origin, so protected history must still
    // stay inside the app.
    @MainActor func testImportOriginSurvivesManualCorrectionAndRelaunch() async throws {
        let store = store()
        try store.saveProfile(inputs(), now: first)
        try store.importAutomaticUsage(day: importedDay, minutesByCategory: ["VIDEO_STREAMING": 20], now: now)
        XCTAssertFalse(store.canExportHistory)
        let reopened = reopen(store)
        XCTAssertFalse(reopened.canExportHistory)
        try reopened.saveDay("2026-10-08", inputs: inputs(35), now: now)
        XCTAssertTrue(reopened.records.allSatisfy { $0.source != .screenTimeWithEstimates })
        XCTAssertFalse(reopened.canExportHistory)
        XCTAssertEqual(reopened.archive?.screenTimeDataImported, true)
        XCTAssertFalse(reopen(reopened).canExportHistory)
    }

    // [05] Older imports need the same protection even after their last visible record has been
    // corrected.
    @MainActor func testLegacyImportRemainsBlockedAfterItsLastRecordIsCorrected() async throws {
        let store = store()
        try store.saveProfile(inputs(), now: first)
        try store.importAutomaticUsage(day: importedDay, minutesByCategory: ["VIDEO_STREAMING": 20], now: now)
        try removeProvenanceField(from: store)
        let reopened = reopen(store)
        XCTAssertNil(reopened.archive?.screenTimeDataImported)
        XCTAssertFalse(reopened.canExportHistory)
        try reopened.saveDay("2026-10-08", inputs: inputs(35), now: now)
        XCTAssertFalse(reopen(reopened).canExportHistory)
    }

    // [06] A measured zero still came from Screen Time and needs the same export restriction as
    // other activity.
    @MainActor func testImportedZeroStillBlocksExport() async throws {
        let store = store()
        try store.saveProfile(inputs(), now: first)
        try store.importAutomaticUsage(day: importedDay, minutesByCategory: ["VIDEO_STREAMING": 0], now: now)
        XCTAssertEqual(store.records.last?.inputs.totalMinutes, 0)
        XCTAssertFalse(reopen(store).canExportHistory)
    }

    // [07] An import that is ignored should not change the export rights of an explicitly manual
    // day.
    @MainActor func testIgnoredImportDoesNotRestrictAnExplicitManualDay() async throws {
        let store = store()
        try store.saveProfile(inputs(), now: first)
        try store.saveDay("2026-10-08", inputs: inputs(45), now: now)
        try store.importAutomaticUsage(day: importedDay, minutesByCategory: ["VIDEO_STREAMING": 20], now: now)
        XCTAssertEqual(store.records.last?.inputs.totalMinutes, 45)
        XCTAssertTrue(reopen(store).canExportHistory)
    }

    // [08] A rejected import should leave both the saved history and its export status unchanged.
    @MainActor func testRejectedImportKeepsManualArchiveAndExportPolicy() async throws {
        let store = store()
        try store.saveProfile(inputs(), now: first)
        let original = try Data(contentsOf: store.fileURL)
        XCTAssertThrowsError(try store.importAutomaticUsage(day: importedDay,
            minutesByCategory: ["VIDEO_STREAMING": .nan], now: now))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
        XCTAssertTrue(reopen(store).canExportHistory)
    }

    // [09] Deleting the old history allows a genuinely new manual archive without carrying over
    // its source flag.
    @MainActor func testDeletingHistoryAllowsANewManualArchiveToBeExported() async throws {
        let store = store()
        try store.saveProfile(inputs(), now: first)
        try store.importAutomaticUsage(day: importedDay, minutesByCategory: ["VIDEO_STREAMING": 20], now: now)
        try store.deleteAll()
        XCTAssertNil(store.archive)
        XCTAssertFalse(store.canExportHistory)
        try store.saveProfile(inputs(), now: now)
        XCTAssertEqual(store.archive?.screenTimeDataImported, false)
        XCTAssertTrue(reopen(store).canExportHistory)
    }

    // [10] Unreadable history must not be guessed to be manual just to make an export possible.
    @MainActor func testUnreadableHistoryCannotBeExportedAsManualData() async throws {
        let store = store()
        try store.saveProfile(inputs(), now: first)
        let damaged = Data("unreadable history".utf8)
        try damaged.write(to: store.fileURL)
        XCTAssertThrowsError(try store.reload())
        XCTAssertFalse(store.canExportHistory)
        XCTAssertFalse(reopen(store).canExportHistory)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), damaged)
    }
}
