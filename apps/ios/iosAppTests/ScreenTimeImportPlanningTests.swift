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

// [01] Yesterday comes first. Older gaps take small turns, always within the person's saved
// consent dates

import XCTest
@testable import DFE

@MainActor
final class ScreenTimeImportPlanningTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return value
    }
    private func date(_ day: Int, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }
    private func plan(start: Date, today: Date, cursor: Date? = nil, limit: Int = 6,
                      latest: (Date) -> Bool = { _ in true },
                      older: (Date) -> Bool = { _ in true }) -> ScreenTimeImportPlan {
        ScreenTimeImportPlan.make(start: start, today: today, calendar: calendar,
            cursor: cursor, backfillLimit: limit, shouldRefreshLatest: latest, shouldBackfill: older)
    }

    // [02] Saving yesterday first gives the person a fresh garden even if iOS stops the older
    // catch-up work.
    func testLatestDayCommitsBeforeAnOldQueryCanBeCancelled() async throws {
        let current = date(23)
        let yesterday = date(22)
        let jobs = plan(start: date(1), today: current)
        var committed: [Date] = []
        do {
            _ = try await ScreenTimeCompletedDayImporter.run(dates: jobs.dates, today: current,
                calendar: calendar, shouldImport: { _ in true }, importDay: { day in
                    guard day == yesterday else { throw CancellationError() }
                    committed.append(day)
                    return ScreenTimeDayImportReceipt(day: day, created: true)
                }, onError: { _ in .pending })
            XCTFail("The interrupted historical query must cancel its run.")
        } catch is CancellationError { }
        XCTAssertEqual(committed, [yesterday])
    }

    // [03] Saved older days should avoid extra queries, while yesterday can still receive Apple's
    // latest response.
    func testPreviouslyCommittedHistoryIsNotQueriedAgainButYesterdayIsFresh() async throws {
        let current = date(23)
        let jobs = plan(start: date(1), today: current, older: { _ in false })
        var queried: [Date] = []
        let result = try await ScreenTimeCompletedDayImporter.run(dates: jobs.dates,
            today: current, calendar: calendar, shouldImport: { _ in true }, importDay: { day in
                queried.append(day)
                return ScreenTimeDayImportReceipt(day: day, created: false)
            }, onError: { _ in .error })
        XCTAssertEqual(queried, [date(22)])
        XCTAssertEqual(result.attemptedDays, 1)
        XCTAssertEqual(result.newRecords, 0)
        XCTAssertTrue(result.latestCompletedDayRefreshed)
    }

    // [04] A large backlog should not turn one visit into an unlimited wait for historical
    // activity.
    func testForegroundBackfillCannotExceedSixOlderDays() {
        let jobs = plan(start: date(1), today: date(23), limit: 1000)
        XCTAssertEqual(jobs.dates.count, 7)
        XCTAssertEqual(jobs.dates.first, date(22))
        XCTAssertEqual(jobs.nextBackfillDay.count, 6)
        XCTAssertEqual(Set(jobs.dates).count, jobs.dates.count)
        XCTAssertTrue(jobs.dates.allSatisfy { $0 < date(23) && $0 >= date(1) })
    }

    // [05] Unavailable older days should take turns, so one gap cannot block every day behind it.
    func testPendingDaysRotateInsteadOfBlockingTheSameOlderGaps() {
        let first = plan(start: date(18), today: date(23), limit: 2)
        XCTAssertEqual(first.dates, [date(22), date(18), date(19)])
        let second = plan(start: date(18), today: date(23), cursor: first.nextBackfillDay[date(19)], limit: 2)
        XCTAssertEqual(second.dates, [date(22), date(20), date(21)])
        let third = plan(start: date(18), today: date(23), cursor: second.nextBackfillDay[date(21)], limit: 2)
        XCTAssertEqual(third.dates, first.dates)
    }

    // [06] An outdated catch-up position must never take a request outside the person's saved
    // consent dates.
    func testCursorOutsideSavedConsentResetsToItsFirstAllowedDay() {
        for stale in [date(1), date(23), date(30)] {
            let jobs = plan(start: date(18), today: date(23), cursor: stale, limit: 1)
            XCTAssertEqual(jobs.dates, [date(22), date(18)])
        }
        XCTAssertTrue(plan(start: date(23), today: date(23)).dates.isEmpty)
        XCTAssertTrue(plan(start: date(24), today: date(23)).dates.isEmpty)
    }

    // [07] Deliberate manual days and completed older imports need protection from unnecessary
    // replacement.
    func testManualDatesAndSavedOlderImportsStayProtected() {
        let protected: Set<Date> = [date(18), date(20), date(22)]
        let jobs = plan(start: date(18), today: date(23), latest: { !protected.contains($0) },
                        older: { !protected.contains($0) })
        XCTAssertEqual(jobs.dates, [date(19), date(21)])
        XCTAssertTrue(Set(jobs.dates).isDisjoint(with: protected))
    }

    // [08] Background time is short, so that pass focuses on yesterday rather than searching
    // through history.
    func testBackgroundBudgetQueriesYesterdayWithoutHistoricalWork() {
        for limit in [0, -1] {
            let jobs = plan(start: date(1), today: date(23), limit: limit)
            XCTAssertEqual(jobs.dates, [date(22)])
            XCTAssertTrue(jobs.nextBackfillDay.isEmpty)
        }
    }

    // [09] Catch-up should visit each local date once, including dates with shorter or longer
    // clock-change days.
    func testCalendarPlanningKeepsDatesAcrossBothDaylightSavingChanges() {
        for (month, start, current, transition, expectedHours) in [(3, 27, 31, 29, 23.0), (10, 23, 28, 25, 25.0)] {
            let first = date(start, month: month)
            let today = date(current, month: month)
            let jobs = plan(start: first, today: today)
            XCTAssertEqual(jobs.dates.count, current - start)
            XCTAssertEqual(Set(jobs.dates).count, current - start)
            XCTAssertEqual(jobs.dates.first, date(current - 1, month: month))
            XCTAssertTrue(jobs.dates.contains(date(transition, month: month)))
            XCTAssertEqual(calendar.dateInterval(of: .day, for: date(transition, month: month))!.duration / 3600,
                           expectedHours)
        }
    }

    // [10] A later pass should move on only after an older query was actually tried, not merely
    // placed in a plan.
    func testRetryCursorAdvancesOnlyWhenTheOldQueryIsActuallyAttempted() async throws {
        let current = date(23)
        let jobs = plan(start: date(18), today: current, limit: 2)
        var cursor: Date?
        XCTAssertNil(cursor)
        var attempts = 0
        let result = try await ScreenTimeCompletedDayImporter.run(dates: jobs.dates, today: current,
            calendar: calendar, shouldImport: { _ in true }, onAttempt: { day in
                attempts += 1
                if let next = jobs.nextBackfillDay[day] { cursor = next }
            }, importDay: { day in
                if day == self.date(22) { return ScreenTimeDayImportReceipt(day: day, created: false) }
                throw ScreenTimeImportError.noData
            }, onError: { _ in .pending })
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(cursor, date(20))
        XCTAssertEqual(result.pendingDays, 2)
        XCTAssertTrue(result.latestCompletedDayRefreshed)
    }
}
