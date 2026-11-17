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

// [01] Not every local day has twenty-four hours. Activity limits need to follow the actual date
// and time zone

import XCTest
@testable import DFE

final class CalendarDayCapacityTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return value
    }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func inputs(_ minutes: Double = 0) -> FootprintInputs {
        FootprintInputs(usages: [CategoryUsage(category: .video, minutes: minutes,
            gigabytesPerHour: 1, wifiShare: 0.8)], brightness: 0, gpsHours: 0, bluetoothHours: 0)
    }
    @MainActor private func store() -> FootprintStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return FootprintStore(fileURL: folder.appendingPathComponent("history.json"),
            calculator: SharedFootprintCalculator(), calendar: calendar)
    }

    // [02] A long day should keep its original time limit after travel or reopening the saved
    // history.
    @MainActor func testLongCalendarDayUsesSharedCalculationAndSurvivesTravelAndCopying() async throws {
        let store = store()
        let day = date("2026-10-25T11:00:00Z")
        let now = date("2026-10-26T11:00:00Z")
        try store.saveAutomaticProfile(inputs(), now: day)
        try store.importAutomaticUsage(day: day, minutesByCategory: ["VIDEO_STREAMING": 1450], now: now)
        let record = try XCTUnwrap(store.latest)
        XCTAssertEqual(record.inputs.calendarDayMinutes, 1500)
        XCTAssertEqual(record.inputs.totalMinutes, 1450)
        let reference = try SharedFootprintCalculator().calculate(inputs(60))
        XCTAssertEqual(record.result.totalKg, reference.totalKg * 1450 / 60, accuracy: 1e-10)
        XCTAssertEqual(record.source, .screenTimeWithEstimates)
        XCTAssertEqual(HistoryTipSelector.tip(records: [record], calendar: calendar).category, .video)

        var travelled = Calendar(identifier: .gregorian)
        travelled.timeZone = TimeZone(identifier: "Pacific/Honolulu")!
        let reopened = FootprintStore(fileURL: store.fileURL,
            calculator: SharedFootprintCalculator(), calendar: travelled)
        XCTAssertNil(reopened.errorMessage)
        XCTAssertEqual(reopened.latest, record)
        let copy = try JSONDecoder().decode(FootprintRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(copy.inputs.calendarDayMinutes, 1500)
        XCTAssertEqual(try SharedFootprintCalculator().calculate(copy.inputs).totalKg,
                       record.result.totalKg, accuracy: 1e-12)
        var missingCapacity = copy.inputs
        missingCapacity.calendarDayMinutes = nil
        XCTAssertThrowsError(try missingCapacity.validate())
    }

    // [03] Valid activity must fit the actual day, rather than being cut to a fixed
    // twenty-four-hour limit.
    @MainActor func testImportsUseActualShortOrdinaryAndLongDayLimitsWithoutClipping() async throws {
        for (dayText, nowText, capacity) in [
            ("2026-03-29T10:00:00Z", "2026-03-30T10:00:00Z", 1380.0),
            ("2026-10-24T10:00:00Z", "2026-10-25T11:00:00Z", 1440.0),
            ("2026-10-25T11:00:00Z", "2026-10-26T11:00:00Z", 1500.0)
        ] {
            let store = store()
            let day = date(dayText)
            let now = date(nowText)
            try store.saveAutomaticProfile(inputs(), now: day)
            let before = store.archive
            XCTAssertThrowsError(try store.importAutomaticUsage(day: day,
                minutesByCategory: ["VIDEO_STREAMING": capacity + 1], now: now))
            XCTAssertEqual(store.archive, before)
            try store.importAutomaticUsage(day: day,
                minutesByCategory: ["VIDEO_STREAMING": capacity], now: now)
            XCTAssertEqual(store.latest?.inputs.totalMinutes, capacity)
            XCTAssertEqual(store.latest?.inputs.calendarDayMinutes, capacity)
        }
    }

    // [04] Older records still need their original default, and fractions of a minute should not
    // disappear.
    func testLegacyInputsKeepTheOriginalDefaultAndFractionalUsageStillWorks() throws {
        let original = inputs(60.125)
        let encoded = try JSONEncoder().encode(original)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["calendarDayMinutes"])
        let decoded = try JSONDecoder().decode(FootprintInputs.self, from: encoded)
        XCTAssertNil(decoded.calendarDayMinutes)
        XCTAssertEqual(decoded.usageCapacityMinutes, 1440)
        XCTAssertEqual(decoded, original)
        XCTAssertNoThrow(try decoded.validate())
        XCTAssertThrowsError(try inputs(1441).validate())
    }

    // [05] A broken day limit must not make impossible activity look acceptable to the calculation
    // model.
    func testInvalidCalendarCapacityCannotBroadenTheModelContract() throws {
        for invalid in [Double.nan, .infinity, -.infinity, 0, -1, 1500.5, 2881] {
            var value = inputs()
            value.calendarDayMinutes = invalid
            XCTAssertThrowsError(try value.validate())
            XCTAssertThrowsError(try SharedFootprintCalculator().calculate(value))
        }
        var value = inputs(1450)
        value.calendarDayMinutes = 1380
        XCTAssertThrowsError(try value.validate())
        value.calendarDayMinutes = 1500
        XCTAssertNoThrow(try value.validate())
    }

    // [06] Damaged day-length details should not cause the app to replace the original saved file.
    @MainActor func testCorruptCapacityMetadataDoesNotOverwriteTheSavedArchive() async throws {
        let store = store()
        let day = date("2026-10-25T11:00:00Z")
        try store.saveAutomaticProfile(inputs(), now: day)
        try store.importAutomaticUsage(day: day, minutesByCategory: ["VIDEO_STREAMING": 1450],
                                       now: date("2026-10-26T11:00:00Z"))
        let original = try XCTUnwrap(store.archive)
        for invalid in [0.0, 1500.5, 2881.0, 1380.0] {
            var corrupted = original
            corrupted.records[0].inputs.calendarDayMinutes = invalid
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(corrupted)
            try data.write(to: store.fileURL)
            let reopened = FootprintStore(fileURL: store.fileURL,
                calculator: SharedFootprintCalculator(), calendar: calendar)
            XCTAssertNotNil(reopened.errorMessage)
            XCTAssertThrowsError(try reopened.saveAutomaticProfile(inputs(), now: day))
            XCTAssertEqual(try Data(contentsOf: store.fileURL), data)
        }
    }

    // [07] General estimate settings should not carry a special limit that belonged to one
    // particular date.
    @MainActor func testReviewingAutomaticAssumptionsDoesNotReuseADatedCapacity() async throws {
        let store = store()
        var previousDay = inputs()
        previousDay.calendarDayMinutes = 1500
        try store.saveAutomaticProfile(previousDay, now: date("2026-10-26T11:00:00Z"))
        XCTAssertNil(store.archive?.revisions.last?.inputs.calendarDayMinutes)
    }
}
