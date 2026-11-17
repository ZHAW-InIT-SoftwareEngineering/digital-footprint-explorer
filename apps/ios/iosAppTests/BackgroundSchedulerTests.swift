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

// [01] Ask iOS for useful refresh opportunities, while remembering that the system chooses when
// background work starts

import XCTest
import BackgroundTasks
@testable import DFE

private actor MemoryBackgroundRequestClient: BackgroundRequestClient {
    enum Failure: Error { case refused }
    private var dates: [Date?]
    private var failuresRemaining: Int
    private var pendingReadFailures: Int
    private var submissions = 0
    private var activeSubmissions = 0
    private var maximumActiveSubmissions = 0

    init(dates: [Date?] = [], failuresRemaining: Int = 0, pendingReadFailures: Int = 0) {
        self.dates = dates
        self.failuresRemaining = failuresRemaining
        self.pendingReadFailures = pendingReadFailures
    }
    func pendingDates() async throws -> [Date?] {
        // [02] Let requests overlap so the test can catch duplicate scheduling rather than
        // checking them one at a time.
        await Task.yield()
        if pendingReadFailures > 0 {
            pendingReadFailures -= 1
            throw Failure.refused
        }
        return dates
    }
    func submit(earliest: Date) async throws {
        activeSubmissions += 1
        maximumActiveSubmissions = max(maximumActiveSubmissions, activeSubmissions)
        defer { activeSubmissions -= 1 }
        await Task.yield()
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw Failure.refused
        }
        submissions += 1
        dates = [earliest]
    }
    func snapshot() -> (dates: [Date?], submissions: Int, maximumActive: Int) {
        (dates, submissions, maximumActiveSubmissions)
    }
}

final class BackgroundSchedulerTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return value
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    // [03] A missing completed day deserves a later retry, rather than waiting another full day.
    func testMissingLatestCompletedDayRequestsOneHourRetry() throws {
        let now = date("2026-10-20T10:00:00Z")
        let result = try XCTUnwrap(BackgroundSchedule.nextAttempt(after: now, importEligible: true,
            completedDates: [date("2026-10-18T12:00:00Z")], calendar: calendar, deliveryCalendar: calendar))
        XCTAssertEqual(result.timeIntervalSince(now), 3600)
    }

    // [04] Repeated attempts late in the day should stop before they delay the next morning's
    // opportunity.
    func testLateRetryIsBoundedByTheNextMorning() throws {
        let now = date("2026-10-20T21:40:00Z") // [05] 23:40 in Zurich.
        let result = try XCTUnwrap(BackgroundSchedule.nextAttempt(after: now, importEligible: true,
            completedDates: [], calendar: calendar, deliveryCalendar: calendar))
        XCTAssertEqual(result, date("2026-10-20T22:40:00Z"))
    }

    // [06] The first opt-in day and unavailable access need a later opportunity, not an immediate
    // retry loop.
    func testFirstOptInDayAndUnavailableAccessWaitUntilNextDay() throws {
        let now = date("2026-10-20T10:00:00Z")
        let result = try XCTUnwrap(BackgroundSchedule.nextAttempt(after: now, importEligible: false,
            completedDates: [], calendar: calendar, deliveryCalendar: calendar))
        XCTAssertEqual(result, date("2026-10-21T06:00:00Z"))
    }

    // [07] Once yesterday is saved, an older missing day should not keep waking the app.
    func testSavedYesterdayDoesNotKeepRetryingAnOlderUnavailableDay() throws {
        let now = date("2026-10-20T10:00:00Z")
        let result = try XCTUnwrap(BackgroundSchedule.nextAttempt(after: now, importEligible: true,
            completedDates: [date("2026-10-19T18:00:00Z")], calendar: calendar, deliveryCalendar: calendar))
        XCTAssertEqual(result, date("2026-10-21T06:00:00Z"))
    }

    // [08] Today's unfinished activity cannot stand in for yesterday's complete result.
    func testCurrentDayDoesNotStandInForMissingYesterday() throws {
        let now = date("2026-10-20T10:00:00Z")
        let result = try XCTUnwrap(BackgroundSchedule.nextAttempt(after: now, importEligible: true,
            completedDates: [now], calendar: calendar, deliveryCalendar: calendar))
        XCTAssertEqual(result, now.addingTimeInterval(3600))
    }

    // [09] The autumn clock change adds an hour, but the next request should still follow the
    // local morning.
    func testAutumnMorningFollowsTheTwentyFiveHourLocalDay() throws {
        let now = date("2026-10-25T12:00:00Z")
        let result = try XCTUnwrap(BackgroundSchedule.nextAttempt(after: now, importEligible: false,
            completedDates: [], calendar: calendar, deliveryCalendar: calendar))
        XCTAssertEqual(result.timeIntervalSince(calendar.startOfDay(for: now)), 33 * 3600)
        XCTAssertEqual(calendar.component(.hour, from: result), 8)
    }

    // [10] The spring clock change removes an hour; eight in the morning should still mean local
    // eight.
    func testSpringMorningWaitsUntilLocalEightAcrossClockChange() throws {
        let now = date("2026-03-29T00:30:00Z") // [11] Local clock jumps during this retry interval.
        let result = try XCTUnwrap(BackgroundSchedule.nextAttempt(after: now, importEligible: true,
            completedDates: [], calendar: calendar, deliveryCalendar: calendar))
        XCTAssertEqual(result, date("2026-03-29T06:00:00Z"))
        XCTAssertEqual(calendar.component(.hour, from: result), 8)
    }

    // [12] An earlier useful request should not be replaced just because another caller asks at
    // the same time.
    func testImmediateOverdueAndEqualRequestsArePreserved() {
        let desired = date("2026-10-20T10:00:00Z")
        XCTAssertFalse(BackgroundSchedule.shouldSubmit(earliest: desired, pending: [nil]))
        XCTAssertFalse(BackgroundSchedule.shouldSubmit(earliest: desired, pending: [desired.addingTimeInterval(-3600)]))
        XCTAssertFalse(BackgroundSchedule.shouldSubmit(earliest: desired, pending: [desired]))
        XCTAssertTrue(BackgroundSchedule.shouldSubmit(earliest: desired, pending: []))
        XCTAssertTrue(BackgroundSchedule.shouldSubmit(earliest: desired, pending: [desired.addingTimeInterval(3600)]))
    }

    // [13] Two screens asking together should create one system request, not compete for
    // background time.
    func testConcurrentIdenticalRequestsSubmitOnlyOnce() async throws {
        let desired = date("2026-10-20T10:00:00Z")
        let client = MemoryBackgroundRequestClient()
        let coordinator = BackgroundRequestCoordinator(client: client)
        let results = try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<20 { group.addTask { try await coordinator.submitIfNeeded(earliest: desired) } }
            var values: [Bool] = []
            for try await value in group { values.append(value) }
            return values
        }
        let state = await client.snapshot()
        XCTAssertEqual(results.filter { $0 }.count, 1)
        XCTAssertEqual(state.submissions, 1)
        XCTAssertEqual(state.maximumActive, 1)
        XCTAssertEqual(state.dates, [desired])
    }

    // [14] Overlapping requests must keep the earliest useful opportunity instead of pushing it
    // further away.
    func testConcurrentRequestsCannotPostponeTheEarliestOpportunity() async throws {
        let first = date("2026-10-20T10:00:00Z")
        let client = MemoryBackgroundRequestClient()
        let coordinator = BackgroundRequestCoordinator(client: client)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for offset in [7200.0, 0, 3600, 10800, 1800] {
                group.addTask { _ = try await coordinator.submitIfNeeded(earliest: first.addingTimeInterval(offset)) }
            }
            try await group.waitForAll()
        }
        let state = await client.snapshot()
        XCTAssertEqual(state.dates, [first])
        XCTAssertEqual(state.maximumActive, 1)
    }

    // [15] A retry that can help sooner should bring forward a request already waiting for
    // tomorrow.
    func testAnEarlierRetryAdvancesAQueuedNextDayRequest() async throws {
        let retry = date("2026-10-20T11:00:00Z")
        let client = MemoryBackgroundRequestClient(dates: [date("2026-10-20T22:00:00Z")])
        let coordinator = BackgroundRequestCoordinator(client: client)
        let submitted = try await coordinator.submitIfNeeded(earliest: retry)
        XCTAssertTrue(submitted)
        let state = await client.snapshot()
        XCTAssertEqual(state.dates, [retry])
        XCTAssertEqual(state.submissions, 1)
    }

    // [16] A failed request should not prevent a later attempt from asking iOS again.
    func testSubmissionFailureDoesNotPoisonLaterScheduling() async throws {
        let desired = date("2026-10-20T10:00:00Z")
        let client = MemoryBackgroundRequestClient(failuresRemaining: 1)
        let coordinator = BackgroundRequestCoordinator(client: client)
        do {
            _ = try await coordinator.submitIfNeeded(earliest: desired)
            XCTFail("Expected the first submission to fail")
        } catch MemoryBackgroundRequestClient.Failure.refused { }
        let submitted = try await coordinator.submitIfNeeded(earliest: desired)
        XCTAssertTrue(submitted)
        let state = await client.snapshot()
        XCTAssertEqual(state.submissions, 1)
        XCTAssertEqual(state.maximumActive, 1)
    }

    // [17] A result imported before eight still needs its morning opportunity so the optional
    // notice can follow.
    func testBeforeEightKeepsMorningOpportunityEvenWhenYesterdayWasAlreadyImported() throws {
        let now = date("2026-10-21T05:00:00Z") // [18] 07:00 local.
        let yesterday = date("2026-10-20T12:00:00Z")
        for savedDates in [[], [yesterday]] {
            let result = try XCTUnwrap(BackgroundSchedule.nextAttempt(after: now, importEligible: true,
                completedDates: savedDates, calendar: calendar, deliveryCalendar: calendar))
            XCTAssertEqual(result, date("2026-10-21T06:00:00Z"))
        }
    }

    // [19] After eight, missing data needs a retry; a completed day can wait until the next
    // morning.
    func testAtAndAfterEightSeparateMissingDayRetryFromNextDailyMorning() throws {
        for now in [date("2026-10-21T06:00:00Z"), date("2026-10-21T07:20:00Z")] {
            let missing = try XCTUnwrap(BackgroundSchedule.nextAttempt(after: now, importEligible: true,
                completedDates: [], calendar: calendar, deliveryCalendar: calendar))
            XCTAssertEqual(missing, now.addingTimeInterval(3600))
            let saved = try XCTUnwrap(BackgroundSchedule.nextAttempt(after: now, importEligible: true,
                completedDates: [date("2026-10-20T12:00:00Z")], calendar: calendar, deliveryCalendar: calendar))
            XCTAssertEqual(saved, date("2026-10-22T06:00:00Z"))
        }
    }

    // [29] A morning retry may use the last daytime hour, but it should not queue a notice check
    // for eight in the evening or later.
    func testNoticeRetryStopsBeforeEveningAndKeepsNextLocalMorning() throws {
        let savedDates = [date("2026-10-20T12:00:00Z")]
        let atEighteen = date("2026-10-21T16:00:00Z")
        XCTAssertEqual(BackgroundSchedule.nextAttempt(after: atEighteen, importEligible: true,
            completedDates: savedDates, notificationRetryNeeded: true,
            calendar: calendar, deliveryCalendar: calendar), date("2026-10-21T17:00:00Z"))
        for now in [date("2026-10-21T17:00:00Z"), date("2026-10-21T17:30:00Z"),
                    date("2026-10-21T18:00:00Z")] {
            XCTAssertEqual(BackgroundSchedule.nextAttempt(after: now, importEligible: true,
                completedDates: savedDates, notificationRetryNeeded: true,
                calendar: calendar, deliveryCalendar: calendar), date("2026-10-22T06:00:00Z"))
        }
        XCTAssertEqual(BackgroundSchedule.nextAttempt(after: date("2026-10-21T06:00:00Z"), importEligible: false,
            completedDates: savedDates, notificationRetryNeeded: true,
            calendar: calendar, deliveryCalendar: calendar), date("2026-10-22T06:00:00Z"))
    }

    // [30] Travel changes the quiet-hours boundary too. An archive's older time zone must not
    // stretch the person's local evening into another retry.
    func testNoticeRetryEveningBoundaryUsesTheDeliveryTimeZone() throws {
        var delivery = calendar
        delivery.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let now = date("2026-10-21T22:00:00Z") // [31] 19:00 local, already midnight in the archive.
        XCTAssertEqual(BackgroundSchedule.nextAttempt(after: now, importEligible: true,
            completedDates: [date("2026-10-21T12:00:00Z")], notificationRetryNeeded: true,
            calendar: calendar, deliveryCalendar: delivery), date("2026-10-22T11:00:00Z"))
    }

    // [20] The phone's notification clock and a saved history day may use different time zones
    // without mixing dates.
    func testLocalDeliveryClockAndArchiveDayEligibilityUseTheirOwnTimeZones() throws {
        var delivery = calendar
        delivery.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let beforeLocalEight = date("2026-10-21T10:30:00Z") // [21] 07:30 local, 12:30 archive time.
        let result = try XCTUnwrap(BackgroundSchedule.nextAttempt(after: beforeLocalEight, importEligible: true,
            completedDates: [date("2026-10-20T12:00:00Z")], calendar: calendar, deliveryCalendar: delivery))
        XCTAssertEqual(result, date("2026-10-21T11:00:00Z"))
        let afterLocalEight = date("2026-10-21T11:30:00Z")
        let next = try XCTUnwrap(BackgroundSchedule.nextAttempt(after: afterLocalEight, importEligible: true,
            completedDates: [date("2026-10-20T12:00:00Z")], calendar: calendar, deliveryCalendar: delivery))
        XCTAssertEqual(next, date("2026-10-22T11:00:00Z"))
    }

    // [22] The two kinds of background request need separate identities so one cannot replace the
    // other.
    func testRefreshAndProcessingRequestsKeepTheirOwnKindsIdentifiersAndDates() throws {
        let earliest = date("2026-10-23T06:00:00Z")
        let refresh = BackgroundTaskKind.refresh.makeRequest(earliest: earliest)
        let processing = BackgroundTaskKind.processing.makeRequest(earliest: earliest)
        XCTAssertTrue(refresh is BGAppRefreshTaskRequest)
        XCTAssertFalse(refresh is BGProcessingTaskRequest)
        let fallback = try XCTUnwrap(processing as? BGProcessingTaskRequest)
        XCTAssertFalse(fallback.requiresExternalPower)
        XCTAssertFalse(fallback.requiresNetworkConnectivity)
        XCTAssertEqual(refresh.identifier, BackgroundScheduler.refreshIdentifier)
        XCTAssertEqual(processing.identifier, BackgroundScheduler.identifier)
        XCTAssertNotEqual(refresh.identifier, processing.identifier)
        XCTAssertEqual(refresh.earliestBeginDate, earliest)
        XCTAssertEqual(processing.earliestBeginDate, earliest)
    }

    // [23] iOS needs both background tasks declared in the app before it can launch either one.
    func testBothRequestKindsAreDeclaredInTheAppBundle() throws {
        let identifiers = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String])
        let modes = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])
        for kind in BackgroundTaskKind.allCases {
            XCTAssertTrue(identifiers.contains(kind.identifier))
            XCTAssertTrue(modes.contains(kind.requiredBackgroundMode))
        }
    }

    // [24] If iOS refuses one background route, the app should still try to register the other.
    func testRegistrationAttemptsBothKindsEvenWhenOneIsRefused() {
        for refused in BackgroundTaskKind.allCases {
            var attempted: [BackgroundTaskKind] = []
            let registered = BackgroundTaskRegistration.registerAll { kind in
                attempted.append(kind)
                return kind != refused
            }
            XCTAssertEqual(attempted, BackgroundTaskKind.allCases)
            XCTAssertEqual(registered, Set(BackgroundTaskKind.allCases.filter { $0 != refused }))
        }
    }

    // [25] A problem with one scheduling route must not stop the independent route from being
    // requested.
    func testOneLaneReadOrSubmitFailureDoesNotBlockTheOtherLane() async {
        for failedKind in BackgroundTaskKind.allCases {
            for failureAtRead in [true, false] {
                let failing = MemoryBackgroundRequestClient(failuresRemaining: failureAtRead ? 0 : 1,
                    pendingReadFailures: failureAtRead ? 1 : 0)
                let healthy = MemoryBackgroundRequestClient()
                let refresh = failedKind == .refresh ? failing : healthy
                let processing = failedKind == .processing ? failing : healthy
                let lanes = BackgroundRequestLanes(refresh: BackgroundRequestCoordinator(client: refresh),
                    processing: BackgroundRequestCoordinator(client: processing))
                let result = await lanes.submit(earliest: date("2026-10-23T06:00:00Z"),
                    enabled: Set(BackgroundTaskKind.allCases))
                XCTAssertEqual(result[failedKind], .failed)
                let healthyKind: BackgroundTaskKind = failedKind == .refresh ? .processing : .refresh
                XCTAssertEqual(result[healthyKind], .submitted)
                let state = await healthy.snapshot()
                XCTAssertEqual(state.submissions, 1)
            }
        }
    }

    // [26] Adding the newer route should preserve an older request that already offers an earlier
    // chance.
    func testNewRefreshLanePreservesAnEarlierLegacyProcessingRequest() async {
        let earlier = date("2026-10-23T05:00:00Z")
        let desired = date("2026-10-23T06:00:00Z")
        let refresh = MemoryBackgroundRequestClient()
        let processing = MemoryBackgroundRequestClient(dates: [earlier])
        let lanes = BackgroundRequestLanes(refresh: BackgroundRequestCoordinator(client: refresh),
            processing: BackgroundRequestCoordinator(client: processing))
        let result = await lanes.submit(earliest: desired, enabled: Set(BackgroundTaskKind.allCases))
        XCTAssertEqual(result[.refresh], .submitted)
        XCTAssertEqual(result[.processing], .earlierRequestKept)
        let state = await processing.snapshot()
        XCTAssertEqual(state.dates, [earlier])
        XCTAssertEqual(state.submissions, 0)
    }

}
