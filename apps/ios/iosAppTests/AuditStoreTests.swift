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

// [01] Older records still need to tell the same story after category choices, routines or dates
// change

import XCTest
@testable import DFE

final class AuditStoreTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return value
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var inputs: FootprintInputs {
        FootprintInputs(usages: [
            CategoryUsage(category: .video, minutes: 60, gigabytesPerHour: 1, wifiShare: 0.8),
            CategoryUsage(category: .audio, minutes: 90, gigabytesPerHour: 0.05, wifiShare: 0.8)
        ], brightness: 0.4, gpsHours: 0.25, bluetoothHours: 2)
    }
    @MainActor private func makeStore() -> FootprintStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return FootprintStore(fileURL: directory.appendingPathComponent("history.json"),
                              calculator: SharedFootprintCalculator(), calendar: calendar)
    }

    // [02] Changing a category must update both its time and its source label, so the result still
    // tells the truth.
    @MainActor func testNewMappingRestoresOldUnmappedDurationAndKeepsAccurateSources() async throws {
        let store = makeStore()
        let first = date("2026-10-07T10:00:00Z")
        let importedDay = date("2026-10-08T10:00:00Z")
        let now = date("2026-10-09T10:00:00Z")
        try store.saveProfile(inputs, now: first)
        try store.importAutomaticUsage(day: importedDay, minutesByCategory: ["VIDEO_STREAMING": 30], now: now)
        XCTAssertEqual(store.records.last?.automaticCategories, [.video])

        // [03] Changing the mapping must not leave yesterday's measured video value
        // behind while claiming that only audio came from Screen Time.
        try store.importAutomaticUsage(day: importedDay, minutesByCategory: ["AUDIO_STREAMING": 15], now: now)
        let record = try XCTUnwrap(store.records.last)
        XCTAssertEqual(record.inputs.usages.first { $0.category == .video }?.minutes, 60)
        XCTAssertEqual(record.inputs.usages.first { $0.category == .audio }?.minutes, 15)
        XCTAssertEqual(record.automaticCategories, [.audio])
        XCTAssertEqual(record.inputs.brightness, 0.4)
        XCTAssertEqual(record.inputs.gpsHours, 0.25)
        XCTAssertEqual(record.inputs.bluetoothHours, 2)
        let expected = try SharedFootprintCalculator().calculate(record.inputs)
        XCTAssertEqual(record.result, expected)

        let reopened = FootprintStore(fileURL: store.fileURL, calculator: SharedFootprintCalculator(), calendar: calendar)
        XCTAssertNil(reopened.errorMessage)
        XCTAssertEqual(reopened.records.last, record)
    }

    // [04] Older records without clear source details need their original assumptions, rather than
    // a guessed mapping.
    @MainActor func testOlderAutomaticRecordWithoutSourceCategoriesReturnsToHistoricalRoutine() async throws {
        let store = makeStore()
        let day = date("2026-10-08T10:00:00Z")
        let now = date("2026-10-09T10:00:00Z")
        try store.saveProfile(inputs, now: date("2026-10-07T10:00:00Z"))
        try store.importAutomaticUsage(day: day, minutesByCategory: ["VIDEO_STREAMING": 30], now: now)
        var olderArchive = try XCTUnwrap(store.archive)
        olderArchive.records[olderArchive.records.count - 1].automaticCategories = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(olderArchive).write(to: store.fileURL, options: .atomic)
        try store.reload()
        try store.importAutomaticUsage(day: day, minutesByCategory: ["AUDIO_STREAMING": 0], now: now)
        XCTAssertEqual(store.records.last?.inputs.usages.first { $0.category == .video }?.minutes, 60)
        XCTAssertEqual(store.records.last?.inputs.usages.first { $0.category == .audio }?.minutes, 0)
        XCTAssertEqual(store.records.last?.automaticCategories, [.audio])
    }

    // [05] A person's earlier correction should keep its original scope when later category
    // choices change.
    @MainActor func testManualOverrideIgnoresLaterMappingOutsideItsOriginalCategories() async throws {
        let store = makeStore()
        var videoOnly = inputs
        videoOnly.usages.removeAll { $0.category == .audio }
        let day = date("2026-10-07T10:00:00Z")
        let now = date("2026-10-09T10:00:00Z")
        try store.saveProfile(videoOnly, now: day)
        let original = store.records.first
        try store.importAutomaticUsage(day: day, minutesByCategory: ["AUDIO_STREAMING": 20], now: now)
        XCTAssertEqual(store.records.first, original)
        XCTAssertEqual(store.records.first?.source, .manual)
    }

    // [06] Rejected setup must leave both the saved file and its completion status as they were.
    @MainActor func testRejectedPreSetupRoutineDoesNotChangeCompletionFlagsOrDisk() async throws {
        let store = makeStore()
        try store.saveProfile(inputs, now: date("2026-10-07T10:00:00Z"))
        let original = store.archive
        let file = try Data(contentsOf: store.fileURL)
        XCTAssertThrowsError(try store.saveProfile(inputs, now: date("2026-10-06T10:00:00Z")))
        XCTAssertEqual(store.archive, original)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), file)
    }

    // [07] If midnight passes during an edit, the change still belongs to the day the person
    // opened.
    @MainActor func testExplicitEditTargetRemainsPreviousDateAfterMidnight() async throws {
        let store = makeStore()
        let opened = date("2026-10-07T21:55:00Z") // [08] 23:55 in Zurich.
        let saved = date("2026-10-07T22:05:00Z")  // [09] 00:05 the next day.
        try store.saveProfile(inputs, now: opened)
        let target = store.dayKey(for: opened)
        var correction = inputs
        correction.usages[0].minutes = 15
        try store.saveDay(target, inputs: correction, now: saved)
        XCTAssertEqual(store.records.map(\.day), ["2026-10-07"])
        XCTAssertEqual(store.records.first?.inputs.usages[0].minutes, 15)
        XCTAssertEqual(store.records.first?.isCompleted, true)
    }
}
