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

// [01] An activity request needs stable day boundaries from the calendar it started with

import XCTest
@testable import DFE

final class ScreenTimeCalendarSnapshotTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    // [02] A request needs stable day boundaries even if the phone changes time zone while it is
    // running.
    func testFrozenCalendarKeepsItsZoneAndDaylightSavingRules() throws {
        var source = calendar("Europe/Zurich")
        let snapshot = ScreenTimeCalendarSnapshot(source)
        source.timeZone = TimeZone(identifier: "America/New_York")!
        XCTAssertEqual(snapshot.calendar.timeZone.identifier, "Europe/Zurich")
        for (instant, hours) in [("2026-03-29T12:00:00Z", 23.0), ("2026-10-25T12:00:00Z", 25.0)] {
            XCTAssertEqual(snapshot.calendar.dateInterval(of: .day, for: date(instant))!.duration / 3600, hours)
        }
        XCTAssertThrowsError(try snapshot.requireCurrent(source)) { error in
            guard case ScreenTimeRefreshContextError.timeZoneChanged = error else {
                return XCTFail("A changed time zone must reject the old query context.")
            }
        }
    }

    // [03] Midnight alone does not change a completed older day's boundaries, so that response can
    // remain valid.
    func testSameZoneAcrossMidnightDoesNotRejectAValidOlderDay() throws {
        let source = calendar("Europe/Zurich")
        let snapshot = ScreenTimeCalendarSnapshot(source)
        let before = date("2026-10-22T21:59:00Z")
        let after = date("2026-10-22T22:01:00Z")
        XCTAssertEqual(snapshot.calendar.component(.day, from: before), 22)
        XCTAssertEqual(source.component(.day, from: after), 23)
        try snapshot.requireCurrent(source)
        // [04] A midnight change alone does not change the boundary of an older query.
        let requested = snapshot.calendar.dateInterval(of: .day, for: date("2026-10-21T12:00:00Z"))!
        XCTAssertEqual(requested, source.dateInterval(of: .day, for: date("2026-10-21T12:00:00Z")))
    }

    // [05] If travel changes the time zone mid-request, its old day boundaries must not reach
    // saved history.
    @MainActor func testZoneChangeDuringAQueryCannotCommitItsResponse() async throws {
        let snapshot = ScreenTimeCalendarSnapshot(calendar("Europe/Zurich"))
        var current = calendar("Europe/Zurich")
        let today = snapshot.calendar.startOfDay(for: date("2026-10-23T10:00:00Z"))
        let yesterday = snapshot.calendar.date(byAdding: .day, value: -1, to: today)!
        var committed = false
        var regularFailureHandlerCalled = false
        do {
            _ = try await ScreenTimeCompletedDayImporter.run(dates: [yesterday], today: today,
                calendar: snapshot.calendar, shouldImport: { _ in true }, importDay: { day in
                    await Task.yield()
                    current.timeZone = TimeZone(identifier: "America/New_York")!
                    try snapshot.requireCurrent(current)
                    committed = true
                    return ScreenTimeDayImportReceipt(day: day, created: true)
                }, onError: { _ in regularFailureHandlerCalled = true; return .pending })
            XCTFail("A stale-zone query must throw before its response is saved.")
        } catch ScreenTimeRefreshContextError.timeZoneChanged { }
        XCTAssertFalse(committed)
        XCTAssertFalse(regularFailureHandlerCalled)
    }

    // [06] An earlier successful save does not make a later stale-calendar response safe to
    // announce.
    @MainActor func testZoneChangeAfterAnEarlierCommitCannotReturnANotificationReceipt() async throws {
        let snapshot = ScreenTimeCalendarSnapshot(calendar("Europe/Zurich"))
        var current = calendar("Europe/Zurich")
        let today = snapshot.calendar.startOfDay(for: date("2026-10-23T10:00:00Z"))
        let yesterday = snapshot.calendar.date(byAdding: .day, value: -1, to: today)!
        let older = snapshot.calendar.date(byAdding: .day, value: -2, to: today)!
        var committed: [Date] = []
        var returnedReceipt = false
        do {
            _ = try await ScreenTimeCompletedDayImporter.run(dates: [yesterday, older], today: today,
                calendar: snapshot.calendar, shouldImport: { _ in true }, importDay: { day in
                    if day == older { current.timeZone = TimeZone(identifier: "America/New_York")! }
                    try snapshot.requireCurrent(current)
                    committed.append(day)
                    return ScreenTimeDayImportReceipt(day: day, created: true)
                }, onError: { _ in .error })
            returnedReceipt = true
        } catch ScreenTimeRefreshContextError.timeZoneChanged { }
        XCTAssertEqual(committed, [yesterday])
        XCTAssertFalse(returnedReceipt)
    }
}
