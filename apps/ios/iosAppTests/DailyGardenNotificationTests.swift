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

// [01] A morning notice needs a relevant result, private wording and a reliable one-per-day limit

import XCTest
import UserNotifications
@testable import DFE

private final class MemoryGardenNotificationLedger: GardenNotificationLedgerStore, @unchecked Sendable {
    enum Failure: Error { case damaged }
    private let lock = NSLock()
    private var value = DailyGardenNotificationLedger()
    var refusesReads = false
    var refusesWrites = false
    func load() throws -> DailyGardenNotificationLedger {
        lock.lock(); defer { lock.unlock() }
        if refusesReads { throw Failure.damaged }
        return value
    }
    func save(_ ledger: DailyGardenNotificationLedger) throws {
        lock.lock(); defer { lock.unlock() }
        if refusesWrites { throw Failure.damaged }
        value = ledger
    }
}

private actor MemoryGardenNotificationClient: GardenNotificationClient {
    enum Failure: Error { case uncertainAdd }
    var authorized = true
    var refuseAdd = false
    var refusedIdentifiers: Set<String> = []
    var identifiers: [String] = []
    var pendingPlans: [DailyGardenNotificationPlan] = []
    var scheduled: [DailyGardenNotificationPlan] = []
    var removed: [String] = []
    func isAuthorized() async -> Bool { await Task.yield(); return authorized }
    func requestState() async -> GardenNotificationRequestState {
        GardenNotificationRequestState(pendingIdentifiers: pendingPlans.map(\.identifier), deliveredIdentifiers: identifiers)
    }
    func add(_ plan: DailyGardenNotificationPlan) async throws {
        await Task.yield()
        if refuseAdd || refusedIdentifiers.contains(plan.identifier) { throw Failure.uncertainAdd }
        scheduled.append(plan)
        pendingPlans.removeAll { $0.identifier == plan.identifier }
        if plan.deliverAt > Date.distantPast { pendingPlans.append(plan) }
    }
    func remove(identifiers values: [String]) async {
        removed += values
        pendingPlans.removeAll { values.contains($0.identifier) }
    }
    func configure(authorized: Bool = true, refuseAdd: Bool = false, identifiers: [String] = [],
                   refusedIdentifiers: Set<String> = []) {
        self.authorized = authorized
        self.refuseAdd = refuseAdd
        self.identifiers = identifiers
        self.refusedIdentifiers = refusedIdentifiers
    }
    func setPending(_ plans: [DailyGardenNotificationPlan]) { pendingPlans = plans }
    func snapshot() -> (scheduled: [DailyGardenNotificationPlan], removed: [String], identifiers: [String],
                        pending: [DailyGardenNotificationPlan]) {
        (scheduled, removed, identifiers, pendingPlans)
    }
}

final class DailyGardenNotificationTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func calendar(_ zone: String = "Europe/Zurich") -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone)!
        return value
    }
    private func record(day: String = "2026-10-20", garden: FootprintGarden = .growing,
                        minutes: Double = 20, total: Double = 0.08, baseline: Double? = 0.1) -> FootprintRecord {
        FootprintRecord(day: day,
            inputs: FootprintInputs(usages: [CategoryUsage(category: .video, minutes: minutes)],
                brightness: 0.5, gpsHours: 0, bluetoothHours: 0),
            result: FootprintResult(totalKg: total, appUsageKg: total, displayKg: 0, backgroundKg: 0, categories: []),
            source: .screenTimeWithEstimates, calculatedAt: date("2026-10-21T06:00:00Z"),
            isCompleted: true, garden: garden, baselineKg: baseline, automaticCategories: [.video])
    }
    private func plan(now: Date? = nil) throws -> DailyGardenNotificationPlan {
        try XCTUnwrap(DailyGardenNotificationPlan.make(records: [record()], automaticAccessReady: true,
            now: now ?? date("2026-10-21T07:00:00Z"), recordCalendar: calendar(), deliveryCalendar: calendar()))
    }

    // [02] Morning follows the person's local clock, even on the days when the clocks move forward
    // or back.
    func testMorningUsesLocalEightAcrossBothDaylightSavingChanges() throws {
        for (day, beforeEight, atEight) in [
            ("2026-03-28", "2026-03-29T05:59:00Z", "2026-03-29T06:00:00Z"),
            ("2026-10-24", "2026-10-25T06:59:00Z", "2026-10-25T07:00:00Z")
        ] {
            let early = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [record(day: day)],
                automaticAccessReady: true, now: date(beforeEight), recordCalendar: calendar(), deliveryCalendar: calendar()))
            XCTAssertEqual(early.deliverAt, date(atEight))
            XCTAssertTrue(early.scheduledForMorning)
            let result = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [record(day: day)],
                automaticAccessReady: true, now: date(atEight), recordCalendar: calendar(), deliveryCalendar: calendar()))
            XCTAssertEqual(result.deliverAt, date(atEight))
            XCTAssertEqual(result.recordDay, day)
        }
    }

    // [03] A notice needs a complete, usable automatic day. Missing or invalid activity is not a
    // reason to announce a result.
    func testOnlyACompleteValidYesterdayWithActualAutomaticUseCanProduceNotice() {
        let now = date("2026-10-21T07:00:00Z")
        var incomplete = record(); incomplete.isCompleted = false
        var manual = record(); manual.source = .manual
        var noProvenCategories = record(); noProvenCategories.automaticCategories = nil
        let candidates: [[FootprintRecord]] = [[], [incomplete], [manual], [noProvenCategories],
            [record(day: "2026-10-19")], [record(day: "2026-10-21")],
            [record(minutes: 0)], [record(total: 0)], [record(total: .nan)], [record(minutes: -1)]]
        for records in candidates {
            XCTAssertNil(DailyGardenNotificationPlan.make(records: records,
                automaticAccessReady: true, now: now, recordCalendar: calendar(), deliveryCalendar: calendar()))
        }
        XCTAssertNil(DailyGardenNotificationPlan.make(records: [record()],
            automaticAccessReady: false, now: now, recordCalendar: calendar(), deliveryCalendar: calendar()))
    }

    // [04] A late import should not interrupt someone at night just to catch up on a morning
    // message.
    func testLateImportStaysQuietInsteadOfSendingAtNight() throws {
        XCTAssertNil(DailyGardenNotificationPlan.make(records: [record()], automaticAccessReady: true,
            now: date("2026-10-21T18:00:00Z"), recordCalendar: calendar(), deliveryCalendar: calendar()))
        let lateMorning = try plan(now: date("2026-10-21T09:00:00Z"))
        XCTAssertEqual(lateMorning.deliverAt, date("2026-10-21T09:00:00Z"))
    }

    // [25] A fresh result before breakfast can wait with iOS until eight. A later failed
    // query must not send another message for a morning that already has one planned.
    func testFreshResultBeforeEightSchedulesForMorningAndPreventsLaterNotice() async throws {
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        let days = calendar()
        let beforeEight = date("2026-10-21T05:00:00Z")
        let atEight = date("2026-10-21T06:00:00Z")
        let atNine = date("2026-10-21T07:00:00Z")
        try await coordinator.setEnabled(true, now: beforeEight, calendar: days)
        var saved = record()
        saved.calculatedAt = beforeEight
        let earlyPlan = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [saved], automaticAccessReady: true,
            now: beforeEight, recordCalendar: days, deliveryCalendar: days))
        XCTAssertEqual(earlyPlan.deliverAt, atEight)
        XCTAssertTrue(earlyPlan.scheduledForMorning)
        let first = try await coordinator.submit(earlyPlan, now: beforeEight, calendar: days)
        XCTAssertEqual(first, .scheduled)

        let pending = ScreenTimeRefreshResult(attemptedDays: 1, pendingDays: 1)
        XCTAssertFalse(pending.canNotifyLatestCompletedDay)
        let laterPlan = DailyGardenNotificationPlan.make(records: [saved], automaticAccessReady: true,
            now: atNine, recordCalendar: days, deliveryCalendar: days)
        let retryNeeded = try await coordinator.needsRetry(for: laterPlan, now: atNine, calendar: days)
        XCTAssertFalse(retryNeeded)
        let duplicate = try await coordinator.submit(laterPlan, now: atNine, calendar: days)
        XCTAssertEqual(duplicate, .alreadyReserved)
        let state = await client.snapshot()
        XCTAssertEqual(state.scheduled.count, 1)
        XCTAssertEqual(state.scheduled.first?.deliverAt, atEight)
    }

    // [26] Another data check is useful only while the person wants notices and iOS permits them.
    // A reserved morning must not start a fresh round of retries.
    func testMorningRetryStopsWhenDisabledDeniedOrAlreadyReserved() async throws {
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        let candidate = try plan()
        let disabled = try await coordinator.needsRetry(for: candidate)
        XCTAssertFalse(disabled)
        try await coordinator.setEnabled(true)
        await client.configure(authorized: false)
        let denied = try await coordinator.needsRetry(for: candidate)
        XCTAssertFalse(denied)
        await client.configure()
        let eligible = try await coordinator.needsRetry(for: candidate)
        XCTAssertTrue(eligible)
        let sent = try await coordinator.submit(candidate)
        XCTAssertEqual(sent, .scheduled)
        let reserved = try await coordinator.needsRetry(for: candidate)
        XCTAssertFalse(reserved)
        for retryNeeded in [disabled, denied, reserved] {
            XCTAssertEqual(BackgroundSchedule.nextAttempt(after: candidate.deliverAt, importEligible: true,
                completedDates: [date("2026-10-20T12:00:00Z")], notificationRetryNeeded: retryNeeded,
                calendar: calendar(), deliveryCalendar: calendar()), date("2026-10-22T06:00:00Z"))
        }
        let state = await client.snapshot()
        XCTAssertEqual(state.scheduled.count, 1)
    }

    // [27] A notice already held by iOS needs no retry, even if this local record has no date stamp.
    func testKnownSystemNoticeAndIneligibleDayDoNotRequestMorningRetry() async throws {
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true)
        let noDay = try await coordinator.needsRetry(for: nil)
        XCTAssertFalse(noDay)
        let candidate = try plan()
        await client.configure(identifiers: [candidate.identifier])
        let alreadyKnown = try await coordinator.needsRetry(for: candidate)
        XCTAssertFalse(alreadyKnown)
        XCTAssertTrue(try ledger.load().reservations.isEmpty, "This read must not reserve or send a notice")
        let state = await client.snapshot()
        XCTAssertTrue(state.scheduled.isEmpty)
    }

    // [05] The message should describe the saved garden, without inventing new flowers or a
    // streak.
    func testCopyUsesTheSavedGardenWithoutInventingGrowthOrStreaks() throws {
        let now = date("2026-10-21T07:00:00Z")
        for (state, total) in [(FootprintGarden.flourishing, 0.05), (.growing, 0.08),
                               (.stable, 0.1), (.wilting, 0.12), (.withered, 0.15)] {
            let result = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [record(garden: state, total: total)],
                automaticAccessReady: true, now: now, recordCalendar: calendar(), deliveryCalendar: calendar()))
            XCTAssertTrue(result.body.lowercased().contains("yesterday"))
            XCTAssertFalse(result.body.contains("streak"))
            XCTAssertFalse(result.body.contains("CO"))
            XCTAssertLessThanOrEqual(result.body.count, 80)
        }
        let first = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [record(baseline: nil)],
            automaticAccessReady: true, now: now, recordCalendar: calendar(), deliveryCalendar: calendar()))
        XCTAssertTrue(first.body.contains("daily estimate"))
        XCTAssertFalse(first.body.contains("first"))
        XCTAssertEqual(DailyGardenNotificationPlan.gardenURL, "digitalfootprint://today")
        let transition = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [
            record(), record(day: "2026-10-18", garden: .withered), record(day: "2026-10-19", garden: .stable)
        ], automaticAccessReady: true, now: now, recordCalendar: calendar(), deliveryCalendar: calendar()))
        let unchangedContext = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [record()],
            automaticAccessReady: true, now: now, recordCalendar: calendar(), deliveryCalendar: calendar()))
        XCTAssertTrue(transition.title.contains("Garden"))
        XCTAssertNotEqual(transition.title, unchangedContext.title)
        XCTAssertEqual(transition.body, unchangedContext.body)
        XCTAssertTrue(transition.body.contains("lower than usual"))
    }

    // [06] A gap in history means we cannot honestly call a different-looking garden a change from
    // yesterday.
    func testGapsInHistoryDoNotInventAYesterdayGardenChange() throws {
        let candidate = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [
            record(day: "2026-10-18", garden: .stable), record()
        ], automaticAccessReady: true, now: date("2026-10-21T07:00:00Z"),
            recordCalendar: calendar(), deliveryCalendar: calendar()))
        let withoutGap = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [record()],
            automaticAccessReady: true, now: date("2026-10-21T07:00:00Z"),
            recordCalendar: calendar(), deliveryCalendar: calendar()))
        XCTAssertEqual(candidate.title, withoutGap.title)
        XCTAssertEqual(candidate.body, withoutGap.body)
        XCTAssertFalse(candidate.body.contains("moved"))
    }

    // [07] An earlier manual or incomplete day cannot support a claim about consecutive automatic
    // results.
    func testUnprovenPreviousDaysDoNotInventAnAutomaticGardenChange() throws {
        var manual = record(day: "2026-10-19", garden: .stable); manual.source = .manual
        var incomplete = record(day: "2026-10-19", garden: .stable); incomplete.isCompleted = false
        var unproven = record(day: "2026-10-19", garden: .stable); unproven.automaticCategories = nil
        var invalid = record(day: "2026-10-19", garden: .stable); invalid.inputs.brightness = .nan
        let withoutPrevious = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [record()],
            automaticAccessReady: true, now: date("2026-10-21T07:00:00Z"),
            recordCalendar: calendar(), deliveryCalendar: calendar()))
        for previous in [manual, incomplete, unproven, invalid] {
            let candidate = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [previous, record()],
                automaticAccessReady: true, now: date("2026-10-21T07:00:00Z"),
                recordCalendar: calendar(), deliveryCalendar: calendar()))
            XCTAssertEqual(candidate.title, withoutPrevious.title)
            XCTAssertEqual(candidate.body, withoutPrevious.body)
        }
    }

    // [08] A Lock Screen can be seen by other people, so the message avoids app names and private
    // usage details.
    func testNotificationCopyKeepsUsageDetailsOffTheLockScreen() throws {
        let cases: [(state: String, garden: FootprintGarden, total: Double, baseline: Double?, phrase: String)] = [
            ("baseline-absent", .stable, 0.08, nil, "daily estimate"),
            ("flourishing", .flourishing, 0.05, 0.1, "much lower than usual"),
            ("growing", .growing, 0.08, 0.1, "lower than usual"),
            ("stable", .stable, 0.1, 0.1, "close to usual"),
            ("wilting", .wilting, 0.12, 0.1, "higher than usual"),
            ("withered", .withered, 0.15, 0.1, "much higher than usual"),
            ("adjacent-transition", .growing, 0.08, 0.1, "lower than usual")
        ]
        var previews: [[String: String]] = []
        for item in cases {
            let current = record(garden: item.garden, total: item.total, baseline: item.baseline)
            let records = item.state == "adjacent-transition"
                ? [record(day: "2026-10-19", garden: .stable, total: 0.1), current] : [current]
            let candidate = try XCTUnwrap(DailyGardenNotificationPlan.make(records: records,
                automaticAccessReady: true, now: date("2026-10-21T07:00:00Z"),
                recordCalendar: calendar(), deliveryCalendar: calendar()))
            XCTAssertTrue(candidate.body.contains("Yesterday"))
            XCTAssertTrue(candidate.body.contains(item.phrase))
            if item.state == "adjacent-transition" {
                let withoutChange = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [current],
                    automaticAccessReady: true, now: date("2026-10-21T07:00:00Z"),
                    recordCalendar: calendar(), deliveryCalendar: calendar()))
                XCTAssertTrue(candidate.title.contains("Garden"))
                XCTAssertNotEqual(candidate.title, withoutChange.title)
                XCTAssertEqual(candidate.body, withoutChange.body)
            }
            let text = candidate.title + " " + candidate.body
            XCTAssertTrue(text.rangeOfCharacter(from: .decimalDigits) == nil)
            XCTAssertFalse(text.contains(FootprintCategory.video.title))
            XCTAssertFalse(text.contains("kg"))
            XCTAssertLessThanOrEqual(candidate.title.count, 32)
            XCTAssertLessThanOrEqual(candidate.body.count, 80)
            previews.append(["state": item.state, "title": candidate.title, "body": candidate.body,
                             "recordDay": candidate.recordDay, "deliveryDay": candidate.deliveryDay])
        }
        // [09] Preview content comes from the real planner and isolated synthetic records.
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: previews, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "dfe-daily-notification-preview-content"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // [10] When the app is open, the same daily update can appear as a banner and remain in
    // Notification Center.
    func testDailyForegroundNoticeRequestsBannerAndNotificationCenter() {
        let options = GardenNotificationDelegate.foregroundPresentationOptions(
            identifier: DailyGardenNotificationPlan.prefix + "2026-10-21",
            gardenURL: DailyGardenNotificationPlan.gardenURL)
        XCTAssertEqual(options, [.banner, .list])
        XCTAssertFalse(options.contains(.sound))
    }

    // [11] The garden's presentation choice should not make an unrelated notification interrupt
    // the person.
    func testOtherForegroundNotificationsStaySilent() {
        for (identifier, route) in [
            ("another-feature.2026-10-21", DailyGardenNotificationPlan.gardenURL as String?),
            (DailyGardenNotificationPlan.prefix + "2026-10-21", "digitalfootprint://history"),
            (DailyGardenNotificationPlan.prefix + "2026-10-21", nil)
        ] {
            XCTAssertTrue(GardenNotificationDelegate.foregroundPresentationOptions(
                identifier: identifier, gardenURL: route).isEmpty)
        }
    }

    // [12] Opening the app during a background refresh must not cause two notices for the same
    // morning.
    func testConcurrentForegroundAndBackgroundRefreshesScheduleOnlyOneNotice() async throws {
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true)
        let candidate = try plan()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask { _ = try? await coordinator.submit(candidate) }
            }
        }
        let state = await client.snapshot()
        XCTAssertEqual(state.scheduled.count, 1)
        XCTAssertEqual(try ledger.load().reservations.count, 1)
    }

    // [13] Reopening or retrying later should remember that today's notification opportunity was
    // already reserved.
    func testRelaunchAndSameDayRetryKeepTheDurableReservation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("notice-ledger.json")
        let client = MemoryGardenNotificationClient()
        let firstLedger = FileGardenNotificationLedgerStore(url: file)
        let first = DailyGardenNotificationCoordinator(client: client, ledgerStore: firstLedger)
        try await first.setEnabled(true)
        let candidate = try plan()
        let firstResult = try await first.submit(candidate)
        XCTAssertEqual(firstResult, .scheduled)
        let reopened = DailyGardenNotificationCoordinator(client: client,
            ledgerStore: FileGardenNotificationLedgerStore(url: file))
        let nextResult = try await reopened.submit(candidate)
        XCTAssertEqual(nextResult, .alreadyReserved)
        let state = await client.snapshot()
        XCTAssertEqual(state.scheduled.count, 1)
        XCTAssertTrue(try firstLedger.load().contains(candidate))
    }

    // [14] If scheduling has an uncertain outcome, staying quiet is safer than risking a duplicate
    // notice.
    func testUncertainSchedulingErrorConsumesItsDayRatherThanRiskingDuplicate() async throws {
        let client = MemoryGardenNotificationClient()
        await client.configure(refuseAdd: true)
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true)
        let candidate = try plan()
        let first = try await coordinator.submit(candidate)
        XCTAssertEqual(first, .schedulingFailed)
        await client.configure()
        let retry = try await coordinator.submit(candidate)
        XCTAssertEqual(retry, .alreadyReserved)
        let state = await client.snapshot()
        XCTAssertTrue(state.scheduled.isEmpty)
    }

    // [15] Turning notices off should remove this feature's requests without disturbing unrelated
    // notifications.
    func testPermissionDeniedAndOptOutRemoveOnlyDailyGardenRequests() async throws {
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        let own = DailyGardenNotificationPlan.prefix + "2026-10-21"
        let unrelated = "unrelated-local-feature"
        await client.configure(authorized: false, identifiers: [unrelated])
        await client.setPending([try plan()])
        try await coordinator.setEnabled(true)
        let result = try await coordinator.submit(try plan())
        XCTAssertEqual(result, .denied)
        var state = await client.snapshot()
        XCTAssertEqual(state.removed, [own])
        XCTAssertEqual(state.identifiers, [unrelated])
        await client.configure(identifiers: [unrelated])
        await client.setPending([try plan()])
        try await coordinator.setEnabled(false)
        state = await client.snapshot()
        XCTAssertEqual(state.identifiers, [unrelated])
        let enabled = try await coordinator.isEnabled()
        XCTAssertFalse(enabled)
    }

    // [16] A damaged or disabled notice record is a reason to stop, rather than send without
    // reliable daily limits.
    func testDisabledOrDamagedLedgerNeverPublishesNotification() async throws {
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        let result = try await coordinator.submit(try plan())
        XCTAssertEqual(result, .disabled)
        ledger.refusesReads = true
        do {
            _ = try await coordinator.needsRetry(for: try plan())
            XCTFail("A damaged ledger must stop morning retries too.")
        } catch { }
        do {
            _ = try await coordinator.submit(try plan())
            XCTFail("A damaged ledger must stop scheduling.")
        } catch { }
        await client.setPending([try plan()])
        do { try await coordinator.setEnabled(false) } catch { }
        let state = await client.snapshot()
        XCTAssertTrue(state.scheduled.isEmpty)
        XCTAssertEqual(state.removed, [try plan().identifier])
    }

    // [17] Travel or a clock change must not turn one result into two daily notifications.
    func testTimeZoneOrClockChangeCannotReuseAReservedDayOrRecord() async throws {
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true)
        let original = try plan()
        _ = try await coordinator.submit(original)
        let sameDayInAnotherZone = DailyGardenNotificationPlan(deliveryDay: original.deliveryDay,
            recordDay: "2026-10-19", title: original.title, body: original.body,
            deliverAt: original.deliverAt, timeZoneIdentifier: "America/New_York")
        let shiftedDaySameRecord = DailyGardenNotificationPlan(deliveryDay: "2026-10-22",
            recordDay: original.recordDay, title: original.title, body: original.body,
            deliverAt: original.deliverAt, timeZoneIdentifier: "Pacific/Auckland")
        for candidate in [sameDayInAnotherZone, shiftedDaySameRecord] {
            let outcome = try await coordinator.submit(candidate)
            XCTAssertEqual(outcome, .alreadyReserved)
        }
        let state = await client.snapshot()
        XCTAssertEqual(state.scheduled.count, 1)
    }

    // [18] A request already known to iOS should be recognized, rather than sent a second time.
    func testExistingPendingOrDeliveredRequestIsAdoptedWithoutRepublishing() async throws {
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true)
        let candidate = try plan()
        await client.configure(identifiers: [candidate.identifier])
        let result = try await coordinator.submit(candidate)
        XCTAssertEqual(result, .alreadyReserved)
        XCTAssertTrue(try ledger.load().contains(candidate))
        let state = await client.snapshot()
        XCTAssertTrue(state.scheduled.isEmpty)
    }

    // [19] A saved history date should not force the morning notice to use a time zone the person
    // has left.
    func testDeliveryClockIsLocalEvenWhenTheArchiveUsesAnotherTimeZone() throws {
        let beforeEight = date("2026-10-21T10:59:00Z") // [20] 07:59 in Sao Paulo, 12:59 in Zurich.
        let early = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [record()], automaticAccessReady: true,
            now: beforeEight, recordCalendar: calendar(), deliveryCalendar: calendar("America/Sao_Paulo")))
        XCTAssertEqual(early.deliverAt, date("2026-10-21T11:00:00Z"))
        XCTAssertTrue(early.scheduledForMorning)
        let localEight = date("2026-10-21T11:00:00Z")
        let candidate = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [record()],
            automaticAccessReady: true, now: localEight, recordCalendar: calendar(),
            deliveryCalendar: calendar("America/Sao_Paulo")))
        XCTAssertEqual(candidate.deliverAt, localEight)
        XCTAssertEqual(candidate.timeZoneIdentifier, "America/Sao_Paulo")
        XCTAssertNil(DailyGardenNotificationPlan.make(records: [record()], automaticAccessReady: true,
            now: date("2026-10-21T06:00:00Z"), recordCalendar: calendar(),
            deliveryCalendar: calendar("Pacific/Honolulu")))
    }

    // [21] A valid fresh result for yesterday remains useful even if a separate older-day catch-up
    // fails.
    @MainActor
    func testFreshYesterdayCanNotifyEvenWhenAnOlderBackfillFails() async throws {
        let now = date("2026-10-21T07:00:00Z")
        let days = calendar()
        let today = days.startOfDay(for: now)
        let latest = try XCTUnwrap(days.date(byAdding: .day, value: -1, to: today))
        let importPlan = ScreenTimeImportPlan.make(start: date("2026-10-19T00:00:00Z"),
            today: today, calendar: days, cursor: nil,
            shouldRefreshLatest: { _ in true }, shouldBackfill: { _ in true })
        var saved: [FootprintRecord] = []
        let refresh = try await ScreenTimeCompletedDayImporter.run(dates: importPlan.dates,
            today: today, calendar: days, shouldImport: { _ in true }, importDay: { day in
                if !days.isDate(day, inSameDayAs: latest) { throw CocoaError(.fileReadCorruptFile) }
                saved.append(self.record())
                return ScreenTimeDayImportReceipt(day: day, created: true)
            }, onError: { _ in .error })
        XCTAssertEqual(refresh.attemptedDays, 2)
        XCTAssertEqual(refresh.importedDays, 1)
        XCTAssertFalse(refresh.completedWithoutFatalError)
        XCTAssertTrue(refresh.canNotifyLatestCompletedDay)

        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true)
        if refresh.canNotifyLatestCompletedDay {
            let candidate = DailyGardenNotificationPlan.make(records: saved,
                automaticAccessReady: true, now: now, recordCalendar: days, deliveryCalendar: days)
            let result = try await coordinator.submit(candidate)
            XCTAssertEqual(result, .scheduled)
        }
        let state = await client.snapshot()
        XCTAssertEqual(state.scheduled.count, 1,
                       "A separate older error must not silence yesterday's committed garden")
        XCTAssertEqual(state.scheduled.first?.recordDay, "2026-10-20")
    }

    // [22] Without current access and a fresh import result, an old saved day must not trigger a
    // new notice.
    @MainActor
    func testLostAccessOrUnrefreshedYesterdayCannotNotifyAnOldSavedResult() async throws {
        let days = calendar()
        let today = days.startOfDay(for: date("2026-10-21T07:00:00Z"))
        let latest = try XCTUnwrap(days.date(byAdding: .day, value: -1, to: today))
        let importPlan = ScreenTimeImportPlan.make(start: date("2026-10-19T00:00:00Z"),
            today: today, calendar: days, cursor: nil,
            shouldRefreshLatest: { _ in true }, shouldBackfill: { _ in true })
        let accessLost = try await ScreenTimeCompletedDayImporter.run(dates: importPlan.dates,
            today: today, calendar: days, shouldImport: { _ in true }, importDay: { day in
                if !days.isDate(day, inSameDayAs: latest) { throw ScreenTimeImportError.permissionRequired }
                return ScreenTimeDayImportReceipt(day: day, created: true)
            }, onError: { _ in .noAccess })
        XCTAssertTrue(accessLost.latestCompletedDayRefreshed)
        XCTAssertTrue(accessLost.stoppedForAccess)
        XCTAssertFalse(accessLost.canNotifyLatestCompletedDay)
        let olderOnly = ScreenTimeRefreshResult(attemptedDays: 2, importedDays: 1,
            pendingDays: 1, newRecords: 1)
        XCTAssertFalse(olderOnly.canNotifyLatestCompletedDay)
        XCTAssertFalse(ScreenTimeRefreshResult().canNotifyLatestCompletedDay)
    }

    // [23] Troubleshooting only needs our own valid delivery dates, not other notifications or
    // their contents.
    func testTechnicalNotificationProjectionKeepsOnlyValidOwnDeliveryDates() {
        let prefix = DailyGardenNotificationPlan.prefix
        let projected = GardenNotificationTechnicalSnapshot.deliveryDays(from: [
            prefix + "2026-10-23", "unrelated-2026-10-22", prefix + "2026-02-30",
            prefix + "2026-10-22.private-content", prefix + "2026-10-22"
        ])
        XCTAssertEqual(projected, ["2026-10-22", "2026-10-23"])
        XCTAssertEqual(GardenNotificationTechnicalSnapshot.relativePath,
                       "DFENotificationDiagnostics/state-v1.json")
    }

    // [24] Deleting history resets future notice choices without pretending to erase notifications
    // already delivered.
    func testDeletingHistoryResetsOptInAndReservationsButKeepsDeliveredHistory() async throws {
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true)
        let candidate = try plan()
        _ = try await coordinator.submit(candidate)
        await client.configure(identifiers: ["delivered-garden-receipt"])
        try await coordinator.reset()
        let saved = try ledger.load()
        let state = await client.snapshot()
        XCTAssertFalse(saved.enabled)
        XCTAssertTrue(saved.reservations.isEmpty)
        XCTAssertEqual(state.removed, [candidate.identifier])
        XCTAssertEqual(state.identifiers, ["delivered-garden-receipt"])
    }

    // [28] Planning ahead leaves the morning invitation with iOS, even if DFE cannot run.
    // Thirty separate local dates keep a quiet app from requesting an unlimited number of alerts.
    func testMorningReminderHorizonHasThirtyLocalDatesAtEight() throws {
        let now = date("2026-10-31T06:59:00Z")
        let plans = DailyGardenNotificationPlan.morningReminders(after: now, calendar: calendar())
        XCTAssertEqual(plans.count, 30)
        XCTAssertEqual(DailyGardenNotificationPlan.morningReminders(after: now, calendar: calendar(), count: 100).count, 30)
        XCTAssertTrue(DailyGardenNotificationPlan.morningReminders(after: now, calendar: calendar(), count: 0).isEmpty)
        XCTAssertTrue(DailyGardenNotificationPlan.morningReminders(after: now, calendar: calendar(), count: -1).isEmpty)
        XCTAssertEqual(plans.first?.deliveryDay, "2026-10-31")
        XCTAssertEqual(plans.last?.deliveryDay, "2026-11-29")
        XCTAssertEqual(plans.first?.deliverAt, date("2026-10-31T07:00:00Z"))
        XCTAssertEqual(Set(plans.map(\.identifier)).count, 30)
        for item in plans {
            XCTAssertEqual(calendar().component(.hour, from: item.deliverAt), 8)
            XCTAssertEqual(calendar().component(.minute, from: item.deliverAt), 0)
            XCTAssertEqual(item.kind, .reminder)
            XCTAssertTrue(item.scheduledForMorning)
            XCTAssertTrue(item.recordDay.isEmpty)
        }
    }

    // [29] Eight has already passed at the boundary. Start tomorrow instead of sending a
    // surprise catch-up reminder as soon as someone turns the feature on.
    func testReminderPlanningAtOrAfterEightStartsTomorrow() {
        for now in [date("2026-10-31T07:00:00Z"), date("2026-10-31T20:00:00Z")] {
            let plans = DailyGardenNotificationPlan.morningReminders(after: now, calendar: calendar(), count: 2)
            XCTAssertEqual(plans.map(\.deliveryDay), ["2026-11-01", "2026-11-02"])
            XCTAssertEqual(plans.first?.deliverAt, date("2026-11-01T07:00:00Z"))
        }
    }

    // [30] Calendar days are not always twenty-four hours long. Keep breakfast at eight
    // when the local clocks change in either direction.
    func testPlannedRemindersKeepLocalEightAcrossShortAndLongDays() {
        for (start, expected, gap) in [
            ("2026-03-28T05:00:00Z", ["2026-03-28T07:00:00Z", "2026-03-29T06:00:00Z"], 23.0),
            ("2026-10-24T05:00:00Z", ["2026-10-24T06:00:00Z", "2026-10-25T07:00:00Z"], 25.0)
        ] {
            let plans = DailyGardenNotificationPlan.morningReminders(after: date(start), calendar: calendar(), count: 2)
            XCTAssertEqual(plans.map(\.deliverAt), expected.map(date))
            XCTAssertEqual(plans[1].deliverAt.timeIntervalSince(plans[0].deliverAt), gap * 3_600)
        }
    }

    // [31] An invitation does not know yesterday's activity. Its wording must never pretend
    // that a new estimate, a greener garden or a streak has been calculated.
    func testGenericReminderInvitesWithoutClaimingFreshActivityOrGrowth() throws {
        let candidate = try XCTUnwrap(DailyGardenNotificationPlan.morningReminders(
            after: date("2026-10-31T06:00:00Z"), calendar: calendar(), count: 1).first)
        let text = (candidate.title + " " + candidate.body).lowercased()
        XCTAssertFalse(text.contains("yesterday"))
        XCTAssertFalse(text.contains("ready"))
        XCTAssertFalse(text.contains("lower"))
        XCTAssertFalse(text.contains("higher"))
        XCTAssertFalse(text.contains("streak"))
        XCTAssertFalse(text.contains("bloom"))
        XCTAssertTrue(candidate.recordDay.isEmpty)
        XCTAssertLessThanOrEqual(candidate.title.count, 32)
        XCTAssertLessThanOrEqual(candidate.body.count, 100)
    }

    // [32] People who already enabled daily updates should keep their choice after upgrading.
    // Their old saved file has no reminder list yet.
    func testOldNotificationLedgerLoadsWithAnEmptyReminderList() throws {
        let old = Data(#"{"enabled":true,"reservations":[]}"#.utf8)
        let saved = try JSONDecoder().decode(DailyGardenNotificationLedger.self, from: old)
        XCTAssertTrue(saved.enabled)
        XCTAssertTrue(saved.reservations.isEmpty)
        XCTAssertTrue(saved.reminders.isEmpty)
    }

    // [33] The switch remains optional. Preparing future days must not turn it on for someone.
    func testDisabledPreferenceNeverSchedulesGenericReminders() async throws {
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        let result = try await coordinator.prepareMorningReminders(now: date("2026-10-21T05:00:00Z"),
            calendar: calendar(), days: 3)
        XCTAssertEqual(result, .disabled)
        XCTAssertTrue(try ledger.load().reminders.isEmpty)
        let state = await client.snapshot()
        XCTAssertTrue(state.scheduled.isEmpty)
    }

    // [34] Reopening DFE should top up the coming mornings without replacing the same
    // pending invitation every time Settings reads the saved switch.
    func testRepeatedPreparationKeepsOnePendingReminderPerDay() async throws {
        let now = date("2026-10-21T05:00:00Z")
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true, now: now, calendar: calendar())
        let first = try await coordinator.prepareMorningReminders(now: now, calendar: calendar(), days: 3)
        let repeated = try await coordinator.prepareMorningReminders(now: now, calendar: calendar(), days: 3)
        XCTAssertEqual(first, .scheduled)
        XCTAssertEqual(repeated, .alreadyReserved)
        let state = await client.snapshot()
        XCTAssertEqual(state.scheduled.count, 3)
        XCTAssertEqual(state.pending.count, 3)
        XCTAssertEqual(Set(state.pending.map(\.identifier)).count, 3)
        XCTAssertEqual(try ledger.load().reminders.count, 3)
        XCTAssertTrue(try ledger.load().reservations.isEmpty)
    }

    // [35] When a fresh result is available early, replace the invitation for that same
    // morning. A second notification would turn one useful nudge into two interruptions.
    func testFreshPreEightResultReplacesGenericWithSameIdentifierAndDeliveryTime() async throws {
        let now = date("2026-10-21T05:30:00Z")
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true, now: now, calendar: calendar())
        _ = try await coordinator.prepareMorningReminders(now: now, calendar: calendar(), days: 3)
        let before = await client.snapshot()
        let original = try XCTUnwrap(before.pending.first { $0.deliveryDay == "2026-10-21" })
        let fresh = try plan(now: now)
        let result = try await coordinator.submit(fresh, now: now, calendar: calendar())
        XCTAssertEqual(result, .scheduled)
        _ = try await coordinator.prepareMorningReminders(now: now, calendar: calendar(), days: 3)
        let after = await client.snapshot()
        let revised = try XCTUnwrap(after.pending.first { $0.deliveryDay == "2026-10-21" })
        XCTAssertEqual(after.pending.count, 3)
        XCTAssertEqual(revised.kind, .estimate)
        XCTAssertEqual(revised.identifier, original.identifier)
        XCTAssertEqual(revised.deliverAt, original.deliverAt)
        XCTAssertEqual(revised.recordDay, "2026-10-20")
        XCTAssertEqual(try ledger.load().reservations.count, 1)
    }

    // [36] Dismissing a banner removes it from Notification Center, but does not give us
    // permission to send the same morning's invitation again.
    func testDueGenericReminderBlocksSummaryEvenAfterSystemRequestWasDismissed() async throws {
        let beforeEight = date("2026-10-21T05:30:00Z")
        let afterEight = date("2026-10-21T06:05:00Z")
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true, now: beforeEight, calendar: calendar())
        _ = try await coordinator.prepareMorningReminders(now: beforeEight, calendar: calendar(), days: 1)
        await client.setPending([])
        let fresh = try plan(now: afterEight)
        let result = try await coordinator.submit(fresh, now: afterEight, calendar: calendar())
        let retry = try await coordinator.needsRetry(for: fresh, now: afterEight, calendar: calendar())
        XCTAssertEqual(result, .alreadyReserved)
        XCTAssertFalse(retry)
        let state = await client.snapshot()
        XCTAssertEqual(state.scheduled.count, 1)
    }

    // [37] The one-per-day record must survive an app restart. Keeping only a value in
    // memory would lose the guard precisely when someone has closed DFE.
    func testReminderDueGuardSurvivesRelaunchWithFileBackedLedger() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("notice-ledger.json")
        let client = MemoryGardenNotificationClient()
        let beforeEight = date("2026-10-21T05:30:00Z")
        let first = DailyGardenNotificationCoordinator(client: client, ledgerStore: FileGardenNotificationLedgerStore(url: file))
        try await first.setEnabled(true, now: beforeEight, calendar: calendar())
        _ = try await first.prepareMorningReminders(now: beforeEight, calendar: calendar(), days: 1)
        await client.setPending([])
        let reopened = DailyGardenNotificationCoordinator(client: client,
            ledgerStore: FileGardenNotificationLedgerStore(url: file))
        let afterEight = date("2026-10-21T06:10:00Z")
        let result = try await reopened.submit(try plan(now: afterEight), now: afterEight, calendar: calendar())
        XCTAssertEqual(result, .alreadyReserved)
        let state = await client.snapshot()
        XCTAssertEqual(state.scheduled.count, 1)
    }

    // [38] A temporary refusal for one date should not erase the other planned mornings.
    // Retrying that future date replaces the same request instead of creating another one.
    func testPartialReminderFailureKeepsOtherDatesAndRepairsOnlyMissingFutureRequest() async throws {
        let now = date("2026-10-21T05:30:00Z")
        let plans = DailyGardenNotificationPlan.morningReminders(after: now, calendar: calendar(), count: 3)
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true, now: now, calendar: calendar())
        await client.configure(refusedIdentifiers: [plans[1].identifier])
        let first = try await coordinator.prepareMorningReminders(now: now, calendar: calendar(), days: 3)
        XCTAssertEqual(first, .schedulingFailed)
        var state = await client.snapshot()
        XCTAssertEqual(state.pending.count, 2)
        XCTAssertEqual(try ledger.load().reminders.count, 3)
        await client.configure()
        let repaired = try await coordinator.prepareMorningReminders(now: now, calendar: calendar(), days: 3)
        XCTAssertEqual(repaired, .scheduled)
        state = await client.snapshot()
        XCTAssertEqual(state.pending.count, 3)
        XCTAssertEqual(state.scheduled.count, 3)
        XCTAssertEqual(Set(state.pending.map(\.identifier)).count, 3)
    }

    // [39] If the date stamp cannot be saved, stop before asking iOS to deliver anything.
    // Otherwise a crash could leave a notification with no duplicate protection.
    func testLedgerWriteFailureStopsReminderSubmission() async throws {
        let now = date("2026-10-21T05:30:00Z")
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true, now: now, calendar: calendar())
        ledger.refusesWrites = true
        do {
            _ = try await coordinator.prepareMorningReminders(now: now, calendar: calendar(), days: 3)
            XCTFail("A reminder needs its saved date guard before it is submitted.")
        } catch { }
        let state = await client.snapshot()
        XCTAssertTrue(state.scheduled.isEmpty)
    }

    // [40] Turning the switch off cancels our future invitations while leaving other
    // features and already delivered notifications alone.
    func testOptOutAndDeniedPermissionRemoveFutureRemindersWithoutTouchingOtherNotices() async throws {
        let now = date("2026-10-21T05:30:00Z")
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true, now: now, calendar: calendar())
        _ = try await coordinator.prepareMorningReminders(now: now, calendar: calendar(), days: 3)
        await client.configure(authorized: false, identifiers: ["another-feature"])
        let denied = try await coordinator.prepareMorningReminders(now: now, calendar: calendar(), days: 3)
        XCTAssertEqual(denied, .denied)
        var state = await client.snapshot()
        XCTAssertTrue(state.pending.isEmpty)
        XCTAssertEqual(state.removed.count, 3)
        XCTAssertEqual(state.identifiers, ["another-feature"])
        await client.configure(identifiers: ["another-feature"])
        _ = try await coordinator.prepareMorningReminders(now: now, calendar: calendar(), days: 3)
        try await coordinator.setEnabled(false, now: now, calendar: calendar())
        state = await client.snapshot()
        XCTAssertTrue(state.pending.isEmpty)
        XCTAssertEqual(state.identifiers, ["another-feature"])
        let enabled = try await coordinator.isEnabled()
        XCTAssertFalse(enabled)
    }

    // [41] Switching notices off and on after breakfast must not forget an invitation that
    // may already have appeared, even when its banner has since been dismissed.
    func testOptOutAndBackOnKeepsDueMorningGuard() async throws {
        let beforeEight = date("2026-10-21T05:30:00Z")
        let afterEight = date("2026-10-21T06:10:00Z")
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true, now: beforeEight, calendar: calendar())
        _ = try await coordinator.prepareMorningReminders(now: beforeEight, calendar: calendar(), days: 1)
        await client.setPending([])
        try await coordinator.setEnabled(false, now: afterEight, calendar: calendar())
        try await coordinator.setEnabled(true, now: afterEight, calendar: calendar())
        let result = try await coordinator.submit(try plan(now: afterEight), now: afterEight, calendar: calendar())
        XCTAssertEqual(result, .alreadyReserved)
        let state = await client.snapshot()
        XCTAssertEqual(state.scheduled.count, 1)
    }

    // [42] Deleting history also turns this feature off and clears future invitations.
    // Notifications already delivered are part of iOS history, not the app's saved entries.
    func testResetCancelsGenericRequestsAndClearsTheirLedger() async throws {
        let now = date("2026-10-21T05:30:00Z")
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true, now: now, calendar: calendar())
        _ = try await coordinator.prepareMorningReminders(now: now, calendar: calendar(), days: 3)
        await client.configure(identifiers: ["already-delivered"])
        try await coordinator.reset()
        let saved = try ledger.load()
        let state = await client.snapshot()
        XCTAssertFalse(saved.enabled)
        XCTAssertTrue(saved.reminders.isEmpty)
        XCTAssertTrue(saved.reservations.isEmpty)
        XCTAssertTrue(state.pending.isEmpty)
        XCTAssertEqual(state.identifiers, ["already-delivered"])
    }

    // [43] The open app and a background refresh can arrive together. Whichever gets here
    // first, the final request for today must be one fresh summary with the same identifier.
    func testConcurrentReminderPreparationAndFreshEarlySummaryKeepOnePendingRequestPerDay() async throws {
        let now = date("2026-10-21T05:30:00Z")
        let days = calendar()
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true, now: now, calendar: calendar())
        let fresh = try plan(now: now)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask { _ = try await coordinator.prepareMorningReminders(now: now, calendar: days, days: 3) }
                group.addTask { _ = try await coordinator.submit(fresh, now: now, calendar: days) }
            }
            try await group.waitForAll()
        }
        let state = await client.snapshot()
        XCTAssertEqual(state.pending.count, 3)
        XCTAssertEqual(Set(state.pending.map(\.identifier)).count, 3)
        XCTAssertEqual(state.pending.first { $0.deliveryDay == "2026-10-21" }?.kind, .estimate)
        XCTAssertEqual(try ledger.load().reservations.count, 1)
    }

    // [44] Moving east can make local eight pass before the old saved deadline. Moving west
    // can do the reverse. In either case, a possibly delivered invitation gets no second summary.
    func testTravelUsesBothSavedAndCurrentLocalDeadlineToPreventDuplicateSummary() async throws {
        for (zone, later) in [
            ("Asia/Tokyo", "2026-10-21T05:45:00Z"),
            ("America/New_York", "2026-10-21T06:10:00Z")
        ] {
            let beforeEight = date("2026-10-21T05:30:00Z")
            let client = MemoryGardenNotificationClient()
            let ledger = MemoryGardenNotificationLedger()
            let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
            try await coordinator.setEnabled(true, now: beforeEight, calendar: calendar())
            _ = try await coordinator.prepareMorningReminders(now: beforeEight, calendar: calendar(), days: 1)
            await client.setPending([])
            let local = calendar(zone)
            let candidate = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [record()],
                automaticAccessReady: true, now: date(later), recordCalendar: calendar(), deliveryCalendar: local))
            let result = try await coordinator.submit(candidate, now: date(later), calendar: local)
            XCTAssertEqual(result, .alreadyReserved)
            let state = await client.snapshot()
            XCTAssertEqual(state.scheduled.count, 1)
        }
    }

    // [45] iOS needs a real calendar request to show an invitation while DFE is closed.
    // A floating local clock keeps eight as eight after the person changes time zones.
    func testNativeMorningRequestsUseOneShotLocalCalendarAndTodayRoute() throws {
        let now = date("2026-10-21T05:30:00Z")
        let reminder = try XCTUnwrap(DailyGardenNotificationPlan.morningReminders(
            after: now, calendar: calendar(), count: 1).first)
        let fresh = try plan(now: now)
        for candidate in [reminder, fresh] {
            let request = GardenNotificationRequestBuilder.make(candidate)
            let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
            XCTAssertFalse(trigger.repeats)
            XCTAssertEqual(request.identifier, candidate.identifier)
            XCTAssertEqual(trigger.dateComponents.year, 2026)
            XCTAssertEqual(trigger.dateComponents.month, 10)
            XCTAssertEqual(trigger.dateComponents.day, 21)
            XCTAssertEqual(trigger.dateComponents.hour, 8)
            XCTAssertEqual(trigger.dateComponents.minute, 0)
            XCTAssertEqual(trigger.dateComponents.second, 0)
            XCTAssertNil(trigger.dateComponents.timeZone)
            XCTAssertEqual(request.content.userInfo["gardenURL"] as? String, DailyGardenNotificationPlan.gardenURL)
        }
        let request = GardenNotificationRequestBuilder.make(reminder)
        XCTAssertTrue((request.content.userInfo["recordDay"] as? String ?? "").isEmpty)
    }

    // [46] A newly calculated result later in the day can still be shown immediately when
    // no morning invitation or earlier result has taken that day's single opportunity.
    func testNativeLaterEstimateKeepsImmediateDelivery() throws {
        let candidate = try plan(now: date("2026-10-21T07:00:00Z"))
        XCTAssertEqual(candidate.kind, .estimate)
        XCTAssertFalse(candidate.scheduledForMorning)
        let request = GardenNotificationRequestBuilder.make(candidate)
        XCTAssertNil(request.trigger)
        XCTAssertEqual(request.content.userInfo["recordDay"] as? String, "2026-10-20")
        XCTAssertEqual(request.identifier, candidate.identifier)
    }

    // [47] Cancelling just before eight can finish after iOS has already shown the card.
    // Keep its date guard when the person turns updates on again a few seconds later.
    func testOptOutStartedBeforeEightKeepsPossibleDeliveryGuardAcrossCancellation() async throws {
        let preparedAt = date("2026-10-21T05:59:58Z")
        let optOutStartedAt = date("2026-10-21T05:59:59Z")
        let optInAgainAt = date("2026-10-21T06:00:01Z")
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true, now: preparedAt, calendar: calendar())
        _ = try await coordinator.prepareMorningReminders(now: preparedAt, calendar: calendar(), days: 1)
        try await coordinator.setEnabled(false, now: optOutStartedAt, calendar: calendar())
        // [48] The pending request and dismissed banner are both gone. Neither proves
        // that iOS managed to cancel the notification before its delivery time.
        await client.setPending([])
        await client.configure()
        try await coordinator.setEnabled(true, now: optInAgainAt, calendar: calendar())
        let result = try await coordinator.submit(try plan(now: optInAgainAt),
            now: optInAgainAt, calendar: calendar())
        XCTAssertEqual(result, .alreadyReserved)
        let state = await client.snapshot()
        XCTAssertEqual(state.scheduled.count, 1,
                       "An uncertain cancellation must not create a second alert after eight.")
    }

    // [49] A replan can cancel unused dates near the same morning boundary. Cancellation
    // removes the pending request, while its saved date still protects against an uncertain delivery.
    func testReplanCancellationBeforeEightKeepsPossibleDeliveryGuard() async throws {
        let preparedAt = date("2026-10-21T05:59:58Z")
        let replanStartedAt = date("2026-10-21T05:59:59Z")
        let afterEight = date("2026-10-21T06:00:01Z")
        let client = MemoryGardenNotificationClient()
        let ledger = MemoryGardenNotificationLedger()
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        try await coordinator.setEnabled(true, now: preparedAt, calendar: calendar())
        _ = try await coordinator.prepareMorningReminders(now: preparedAt, calendar: calendar(), days: 1)
        _ = try await coordinator.prepareMorningReminders(now: replanStartedAt, calendar: calendar(), days: 0)
        await client.setPending([])
        await client.configure()
        let result = try await coordinator.submit(try plan(now: afterEight),
            now: afterEight, calendar: calendar())
        XCTAssertEqual(result, .alreadyReserved)
        let state = await client.snapshot()
        XCTAssertTrue(state.pending.isEmpty)
        XCTAssertEqual(state.scheduled.count, 1,
                       "Replanning cannot turn a possibly displayed reminder into another alert.")
    }

    // [50] A month of invitations should feel varied without changing after every reopen.
    // Date-based choices give tomorrow a different nudge without storing a personal profile.
    func testThirtyDayGenericInvitationsAreVariedDeterministicAndNeverRepeatOnAdjacentDays() {
        let now = date("2026-10-21T05:30:00Z")
        let planned = DailyGardenNotificationPlan.morningReminders(after: now, calendar: calendar())
        let repeated = DailyGardenNotificationPlan.morningReminders(after: now, calendar: calendar())
        XCTAssertEqual(planned, repeated)
        XCTAssertEqual(planned.count, 30)
        XCTAssertGreaterThanOrEqual(Set(planned.map(\.title)).count, 8)
        XCTAssertGreaterThanOrEqual(Set(planned.map(\.body)).count, 8)
        for (previous, next) in zip(planned, planned.dropFirst()) {
            XCTAssertNotEqual(previous.title, next.title)
            XCTAssertNotEqual(previous.body, next.body)
        }
        for candidate in planned {
            let text = (candidate.title + " " + candidate.body).lowercased()
            for unprovenClaim in ["yesterday", "ready", "lower", "higher", "streak", "bloom"] {
                XCTAssertFalse(text.contains(unprovenClaim), candidate.deliveryDay)
            }
            XCTAssertLessThanOrEqual(candidate.title.count, 32)
            XCTAssertLessThanOrEqual(candidate.body.count, 100)
            XCTAssertTrue(candidate.recordDay.isEmpty)
        }
    }

    // [51] Different wording must still describe the same saved comparison. Only a valid
    // neighbouring automatic day can turn that message into a claim that the garden changed.
    func testFreshMessagesVaryAcrossLocalDaysWithoutInventingComparisonsOrChanges() throws {
        let days = calendar()
        let cases: [(FootprintGarden, Double, Double?, String)] = [
            (.flourishing, 0.05, 0.1, "much lower than usual"),
            (.growing, 0.08, 0.1, "lower than usual"),
            (.stable, 0.1, 0.1, "close to usual"),
            (.wilting, 0.12, 0.1, "higher than usual"),
            (.withered, 0.15, 0.1, "much higher than usual"),
            (.stable, 0.08, nil, "daily estimate")
        ]
        for (state, total, baseline, phrase) in cases {
            var messages = Set<String>()
            for offset in 0..<8 {
                let now = try XCTUnwrap(days.date(byAdding: .day, value: offset,
                    to: date("2026-10-21T10:00:00Z")))
                let yesterday = try XCTUnwrap(days.date(byAdding: .day, value: -1, to: days.startOfDay(for: now)))
                let previousDay = try XCTUnwrap(days.date(byAdding: .day, value: -1, to: yesterday))
                let keys = FootprintCalendar(calendar: days)
                var current = record(day: keys.key(yesterday), garden: state, total: total, baseline: baseline)
                current.calculatedAt = now
                let candidate = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [current],
                    automaticAccessReady: true, now: now, recordCalendar: days, deliveryCalendar: days))
                let reopened = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [current],
                    automaticAccessReady: true, now: now, recordCalendar: days, deliveryCalendar: days))
                XCTAssertEqual(candidate, reopened)
                XCTAssertTrue(candidate.body.contains("Yesterday"))
                XCTAssertTrue(candidate.body.contains(phrase))
                XCTAssertFalse(candidate.body.lowercased().contains("first"))
                let text = candidate.title + " " + candidate.body
                XCTAssertFalse(text.lowercased().contains("streak"))
                XCTAssertTrue(text.rangeOfCharacter(from: .decimalDigits) == nil)
                XCTAssertFalse(text.contains(FootprintCategory.video.title))
                XCTAssertLessThanOrEqual(candidate.title.count, 32)
                XCTAssertLessThanOrEqual(candidate.body.count, 80)
                messages.insert(text)

                let sameState = record(day: keys.key(previousDay), garden: state, total: total)
                let unchanged = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [sameState, current],
                    automaticAccessReady: true, now: now, recordCalendar: days, deliveryCalendar: days))
                XCTAssertEqual(unchanged.title, candidate.title)
                XCTAssertEqual(unchanged.body, candidate.body)
                let otherState: FootprintGarden = state == .stable ? .growing : .stable
                let otherTotal = otherState == .stable ? 0.1 : 0.08
                let changedBefore = record(day: keys.key(previousDay), garden: otherState, total: otherTotal)
                let changed = try XCTUnwrap(DailyGardenNotificationPlan.make(records: [changedBefore, current],
                    automaticAccessReady: true, now: now, recordCalendar: days, deliveryCalendar: days))
                if baseline != nil {
                    XCTAssertTrue(changed.title.contains("Garden"))
                    XCTAssertNotEqual(changed.title, candidate.title)
                } else {
                    XCTAssertEqual(changed.title, candidate.title)
                }
                XCTAssertEqual(changed.body, candidate.body)
            }
            XCTAssertGreaterThanOrEqual(messages.count, 3)
        }
    }

    // [52] The earlier app saved just these three reminder fields. Keeping that shape here
    // checks a real upgrade instead of creating an already-updated test record.
    private func oldReminderLedger(_ plans: [DailyGardenNotificationPlan]) throws -> DailyGardenNotificationLedger {
        let rows: [[String: Any]] = plans.map { candidate in
            ["deliveryDay": candidate.deliveryDay,
             "deliverAt": candidate.deliverAt.timeIntervalSinceReferenceDate,
             "timeZoneIdentifier": candidate.timeZoneIdentifier]
        }
        let saved: [String: Any] = ["enabled": true, "reservations": [] as [Any], "reminders": rows]
        let bytes = try JSONSerialization.data(withJSONObject: saved)
        return try JSONDecoder().decode(DailyGardenNotificationLedger.self, from: bytes)
    }

    // [53] Updating the app should refresh its known future invitations once. An older
    // pending estimate with no reminder date record is left alone rather than guessed about.
    func testOldQueuedReminderCopyIsUpdatedOnceWithoutReplacingUnknownPendingEstimate() async throws {
        let now = date("2026-10-21T05:30:00Z")
        let plans = DailyGardenNotificationPlan.morningReminders(after: now, calendar: calendar(), count: 4)
        let oldPending = plans.prefix(3).map { candidate in
            DailyGardenNotificationPlan(kind: .reminder, scheduledForMorning: true,
                deliveryDay: candidate.deliveryDay, recordDay: "", title: "A Moment for Your Garden",
                body: "What will your digital day look like? Open your garden to explore your latest estimate.",
                deliverAt: candidate.deliverAt, timeZoneIdentifier: candidate.timeZoneIdentifier)
        }
        let unknown = DailyGardenNotificationPlan(kind: .estimate, scheduledForMorning: true,
            deliveryDay: plans[3].deliveryDay, recordDay: "2026-10-23",
            title: "An Existing Garden Update", body: "An earlier saved estimate.",
            deliverAt: plans[3].deliverAt, timeZoneIdentifier: plans[3].timeZoneIdentifier)
        let previous = try oldReminderLedger(oldPending)
        XCTAssertEqual(previous.reminders.map(\.contentRevision), [0, 0, 0])
        let ledger = MemoryGardenNotificationLedger()
        try ledger.save(previous)
        let client = MemoryGardenNotificationClient()
        await client.setPending(oldPending + [unknown])
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        let updated = try await coordinator.prepareMorningReminders(now: now, calendar: calendar(), days: 4)
        XCTAssertEqual(updated, .scheduled)
        var state = await client.snapshot()
        XCTAssertEqual(state.scheduled.count, 3)
        XCTAssertEqual(state.pending.count, 4)
        XCTAssertEqual(Set(state.scheduled.map(\.identifier)), Set(oldPending.map(\.identifier)))
        for expected in plans.prefix(3) {
            let actual = try XCTUnwrap(state.pending.first { $0.identifier == expected.identifier })
            XCTAssertEqual(actual.title, expected.title)
            XCTAssertEqual(actual.body, expected.body)
        }
        XCTAssertEqual(state.pending.first { $0.identifier == unknown.identifier }, unknown)
        XCTAssertTrue(try ledger.load().reminders.allSatisfy {
            $0.contentRevision == DailyGardenNotificationPlan.reminderCopyRevision
        })
        let repeated = try await coordinator.prepareMorningReminders(now: now, calendar: calendar(), days: 4)
        XCTAssertEqual(repeated, .alreadyReserved)
        state = await client.snapshot()
        XCTAssertEqual(state.scheduled.count, 3)
        XCTAssertEqual(state.pending.first { $0.identifier == unknown.identifier }, unknown)
    }

    // [54] A refused future wording update can be repaired under the same identifier.
    // Once that morning may have appeared, old wording is no reason to send another alert.
    func testFailedReminderCopyUpdateRetriesBeforeDeadlineButNeverRepublishesADueDay() async throws {
        let beforeEight = date("2026-10-21T05:30:00Z")
        let retryBeforeEight = date("2026-10-21T05:45:00Z")
        let afterEight = date("2026-10-21T06:05:00Z")
        let original = try XCTUnwrap(DailyGardenNotificationPlan.morningReminders(
            after: beforeEight, calendar: calendar(), count: 1).first)
        let oldPending = DailyGardenNotificationPlan(kind: .reminder, scheduledForMorning: true,
            deliveryDay: original.deliveryDay, recordDay: "", title: "An Earlier Garden Invitation",
            body: "Open your garden to explore your latest estimate.",
            deliverAt: original.deliverAt, timeZoneIdentifier: original.timeZoneIdentifier)
        let ledger = MemoryGardenNotificationLedger()
        try ledger.save(oldReminderLedger([oldPending]))
        let client = MemoryGardenNotificationClient()
        await client.setPending([oldPending])
        await client.configure(refuseAdd: true)
        let coordinator = DailyGardenNotificationCoordinator(client: client, ledgerStore: ledger)
        let failed = try await coordinator.prepareMorningReminders(now: beforeEight, calendar: calendar(), days: 1)
        XCTAssertEqual(failed, .schedulingFailed)
        XCTAssertEqual(try ledger.load().reminders.first?.contentRevision, 0)
        var state = await client.snapshot()
        XCTAssertEqual(state.pending, [oldPending])
        await client.configure()
        let repaired = try await coordinator.prepareMorningReminders(now: retryBeforeEight, calendar: calendar(), days: 1)
        XCTAssertEqual(repaired, .scheduled)
        XCTAssertEqual(try ledger.load().reminders.first?.contentRevision,
                       DailyGardenNotificationPlan.reminderCopyRevision)
        state = await client.snapshot()
        XCTAssertEqual(state.pending.count, 1)
        XCTAssertEqual(state.scheduled.count, 1)
        XCTAssertEqual(state.pending.first?.identifier, original.identifier)

        let dueLedger = MemoryGardenNotificationLedger()
        try dueLedger.save(oldReminderLedger([oldPending]))
        let dueClient = MemoryGardenNotificationClient()
        await dueClient.setPending([oldPending])
        await dueClient.configure(refuseAdd: true)
        let dueCoordinator = DailyGardenNotificationCoordinator(client: dueClient, ledgerStore: dueLedger)
        let failedAgain = try await dueCoordinator.prepareMorningReminders(now: beforeEight, calendar: calendar(), days: 1)
        XCTAssertEqual(failedAgain, .schedulingFailed)
        await dueClient.setPending([])
        await dueClient.configure()
        _ = try await dueCoordinator.prepareMorningReminders(now: afterEight, calendar: calendar(), days: 1)
        let dueSlot = try XCTUnwrap(try dueLedger.load().reminders.first { $0.deliveryDay == original.deliveryDay })
        XCTAssertEqual(dueSlot.contentRevision, 0)
        let lateSummary = try await dueCoordinator.submit(try plan(now: afterEight),
            now: afterEight, calendar: calendar())
        XCTAssertEqual(lateSummary, .alreadyReserved)
        let dueState = await dueClient.snapshot()
        XCTAssertFalse(dueState.scheduled.contains { $0.identifier == original.identifier })
        XCTAssertFalse(dueState.pending.contains { $0.identifier == original.identifier })
    }
}
