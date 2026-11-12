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

// [01] Saved history needs protection when a file is damaged, unfamiliar or impossible to save

import XCTest
@testable import DFE

private struct ExtraTestCalculator: FootprintCalculating {
    func calculate(_ inputs: FootprintInputs) throws -> FootprintResult {
        let total = inputs.totalMinutes / 1000
        return FootprintResult(totalKg: total, appUsageKg: total, displayKg: 0, backgroundKg: 0, categories: [])
    }
}

final class AdditionalStoreTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return value
    }
    private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }
    private var inputs: FootprintInputs {
        FootprintInputs(usages: [CategoryUsage(category: .video, minutes: 60, gigabytesPerHour: 1, wifiShare: 0.8)], brightness: 0.5, gpsHours: 0, bluetoothHours: 0)
    }
    @MainActor private func store() -> FootprintStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return FootprintStore(fileURL: directory.appendingPathComponent("history.json"), calculator: ExtraTestCalculator(), calendar: calendar)
    }

    // [02] Keeping an old result in memory must not give the app permission to replace a damaged
    // file.
    @MainActor func testLiveReloadFailureBlocksEveryMutationAndKeepsDamagedFile() async throws {
        let store = store()
        let now = date("2026-10-07T10:00:00Z")
        try store.saveProfile(inputs, now: now)
        let existing = store.archive
        let damaged = Data("unreadable replacement".utf8)
        try damaged.write(to: store.fileURL)
        XCTAssertThrowsError(try store.refresh(now: now))
        // [03] The screen may still remember a valid result. That is not permission to replace the
        // damaged file.
        XCTAssertThrowsError(try store.saveDay("2026-10-07", inputs: inputs, now: now))
        XCTAssertThrowsError(try store.saveProfile(inputs, now: now))
        XCTAssertThrowsError(try store.catchUp(now: date("2026-10-10T10:00:00Z")))
        XCTAssertThrowsError(try store.importAutomaticUsage(day: now, minutesByCategory: ["VIDEO_STREAMING": 20], now: date("2026-10-10T10:00:00Z")))
        XCTAssertEqual(store.archive, existing)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), damaged)
        try store.deleteAll()
        try store.saveProfile(inputs, now: now)
        XCTAssertTrue(store.isConfigured)
    }

    // [04] A newer app may understand this file later, so an older version must leave it alone.
    @MainActor func testUnsupportedFutureVersionRemainsUntouched() async throws {
        let store = store()
        let now = date("2026-10-07T10:00:00Z")
        try store.saveProfile(inputs, now: now)
        var next = try XCTUnwrap(store.archive)
        next.version = 999
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let future = try encoder.encode(next)
        try future.write(to: store.fileURL)
        XCTAssertThrowsError(try store.refresh(now: now))
        XCTAssertThrowsError(try store.catchUp(now: date("2026-10-10T10:00:00Z")))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), future)
    }

    // [05] An unexpected order can change a day's meaning. Rejecting the file protects the
    // original history.
    @MainActor func testOutOfOrderArchiveIsRejectedAndPreserved() async throws {
        let store = store()
        let now = date("2026-10-07T10:00:00Z")
        try store.saveProfile(inputs, now: now)
        try store.catchUp(now: date("2026-10-10T10:00:00Z"))
        var next = try XCTUnwrap(store.archive)
        next.records.reverse()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let unordered = try encoder.encode(next)
        try unordered.write(to: store.fileURL)
        XCTAssertThrowsError(try store.refresh(now: now))
        XCTAssertThrowsError(try store.saveProfile(inputs, now: now))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), unordered)
    }

    // [06] Missing or invalid app categories must not turn into a believable automatic estimate.
    @MainActor func testAutomaticImportRejectsEmptyInvalidAndUnconfiguredCategories() async throws {
        let store = store()
        let first = date("2026-10-07T10:00:00Z")
        let day = date("2026-10-08T10:00:00Z")
        let now = date("2026-10-09T10:00:00Z")
        try store.saveProfile(inputs, now: first)
        let original = store.archive
        for values in [[:], ["VIDEO_STREAMING": Double.nan], ["VIDEO_STREAMING": -1], ["AUDIO_STREAMING": 0], ["AUDIO_STREAMING": -1]] {
            XCTAssertThrowsError(try store.importAutomaticUsage(day: day, minutesByCategory: values, now: now))
            XCTAssertEqual(store.archive, original)
        }
        try store.importAutomaticUsage(day: day, minutesByCategory: ["VIDEO_STREAMING": 0], now: now)
        XCTAssertEqual(store.records.last?.inputs.totalMinutes, 0)
    }

    // [07] The screen must not promise a saved setup when the phone could not keep it.
    @MainActor func testFileWriteFailureDoesNotPublishAnUnsavedProfile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blockingFile = directory.appendingPathComponent("not-a-directory")
        try Data("keep this file".utf8).write(to: blockingFile)
        let store = FootprintStore(fileURL: blockingFile.appendingPathComponent("history.json"), calculator: ExtraTestCalculator(), calendar: calendar)
        XCTAssertThrowsError(try store.saveProfile(inputs))
        XCTAssertFalse(store.isConfigured)
        XCTAssertEqual(try String(contentsOf: blockingFile, encoding: .utf8), "keep this file")
    }

    // [08] The same saved date needs the same meaning even if the person uses another calendar.
    func testDefaultCalendarAlwaysUsesGregorianDayIDs() {
        let days = FootprintCalendar()
        XCTAssertEqual(days.calendar.identifier, .gregorian)
        let date = days.calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 12))!
        XCTAssertEqual(days.key(date), "2026-10-07")
        XCTAssertEqual(days.key(try! XCTUnwrap(days.date("2026-10-07"))), "2026-10-07")
    }
}
