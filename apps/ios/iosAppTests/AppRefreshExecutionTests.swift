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

// [01] Background time is short. Longer catch-up work belongs to a separate pass while the app is
// open

import XCTest
@testable import DFE

@MainActor
private final class BackgroundLaunchGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var entered = false
    func suspend() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered = true
        }
    }
    func release() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}

@MainActor
final class AppRefreshExecutionTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return value
    }
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 23))! }
    private var start: Date { calendar.date(byAdding: .day, value: -365, to: today)! }
    private func plan(isActive: Bool) -> ScreenTimeImportPlan {
        ScreenTimeImportPlan.make(start: start, today: today, calendar: calendar, cursor: nil,
            backfillLimit: AppRefreshBackfillPolicy.limit(isApplicationActive: isActive),
            shouldRefreshLatest: { _ in true }, shouldBackfill: { _ in true })
    }
    private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<2_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("The controlled refresh did not reach its suspension point.")
    }

    // [02] Opening the hidden screen during a background launch must not add more work to iOS's
    // short time slot.
    func testColdBackgroundViewTaskCannotExpandTheSharedBackgroundFlight() async throws {
        let coordinator = RefreshCoordinator<ScreenTimeRefreshResult>(), key = UUID()
        let gate = BackgroundLaunchGate()
        let context = "2026-10-23|Europe/Zurich|0"
        let jobs = plan(isActive: false)
        var queried: [Date] = []
        var backgroundStartedAnotherQuery = false
        // [03] The hidden screen can start before iOS hands over its background task; that order
        // must stay safe.
        let viewTask = Task { try await coordinator.perform(key: key, context: context) {
            try await ScreenTimeCompletedDayImporter.run(dates: jobs.dates, today: self.today,
                calendar: self.calendar, shouldImport: { _ in true }, importDay: { day in
                    queried.append(day)
                    if queried.count == 1 { await gate.suspend() }
                    return ScreenTimeDayImportReceipt(day: day, created: true)
                }, onError: { _ in .error })
        } }
        await waitUntil { gate.entered }
        let background = Task { try await coordinator.perform(key: key, context: context) {
            backgroundStartedAnotherQuery = true
            return ScreenTimeRefreshResult()
        } }
        await waitUntil { coordinator.waitingRequests == 1 }
        gate.release()
        let viewResult = try await viewTask.value, backgroundResult = try await background.value
        XCTAssertEqual(queried, [calendar.date(byAdding: .day, value: -1, to: today)!])
        XCTAssertEqual(viewResult.attemptedDays, 1)
        XCTAssertEqual(backgroundResult, viewResult)
        XCTAssertTrue(viewResult.latestCompletedDayRefreshed)
        XCTAssertFalse(backgroundStartedAnotherQuery)
    }

    // [04] While the person is using the app, a small catch-up pass can fill older gaps without a
    // long wait.
    func testAnActiveForegroundRefreshStillProcessesBoundedOlderGaps() async throws {
        let jobs = plan(isActive: true)
        var queried: [Date] = []
        let result = try await ScreenTimeCompletedDayImporter.run(dates: jobs.dates, today: today,
            calendar: calendar, shouldImport: { _ in true }, importDay: { day in
                queried.append(day)
                return ScreenTimeDayImportReceipt(day: day, created: true)
            }, onError: { _ in .error })
        XCTAssertEqual(queried.count, 7)
        XCTAssertEqual(queried.first, calendar.date(byAdding: .day, value: -1, to: today))
        XCTAssertEqual(result.attemptedDays, 7)
        XCTAssertTrue(result.latestCompletedDayRefreshed)
    }

    // [05] Coming back to the app should allow a fresh catch-up, even if a background pass just
    // finished.
    func testActivationAfterBackgroundCompletionCanStartForegroundCatchUp() async throws {
        let coordinator = RefreshCoordinator<ScreenTimeRefreshResult>(), key = UUID()
        let context = "2026-10-23|Europe/Zurich|0"
        var counts: [Int] = []
        for isActive in [false, true] {
            let jobs = plan(isActive: isActive)
            let result = try await coordinator.perform(key: key, context: context) {
                try await ScreenTimeCompletedDayImporter.run(dates: jobs.dates, today: self.today,
                    calendar: self.calendar, shouldImport: { _ in true }, importDay: { day in
                        ScreenTimeDayImportReceipt(day: day, created: true)
                    }, onError: { _ in .error })
            }
            counts.append(result.attemptedDays)
        }
        XCTAssertEqual(counts, [1, 7])
    }
}
