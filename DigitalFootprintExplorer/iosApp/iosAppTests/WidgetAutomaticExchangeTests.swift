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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import XCTest
@testable import DFE

@MainActor
final class WidgetAutomaticExchangeTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-07T09:00:00Z")!
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return value
    }
    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func clear(_ exchange: WidgetAutomaticExchange) throws {
        let deletion = try exchange.beginDeletion(archiveReplacementID: nil, widgetAccess: false)
        try exchange.finishDeletion(deletion, archive: nil, calendar: calendar,
            classificationRevision: "fixture-classification", now: now)
    }
    private func inputs() -> FootprintInputs {
        FootprintInputs(usages: [CategoryUsage(category: .video, gigabytesPerHour: 0.5, wifiShare: 0.8)],
            brightness: 0.5, gpsHours: 0, bluetoothHours: 0)
    }
    private func archive(at date: Date? = nil) -> FootprintArchive {
        let date = date ?? now.addingTimeInterval(-3 * 86_400)
        let day = FootprintCalendar(calendar: calendar).key(date)
        var archive = FootprintArchive(firstDay: day,
            revisions: [RoutineRevision(effectiveDay: day, savedAt: date.addingTimeInterval(0.375), inputs: inputs())], records: [])
        archive.inputPreference = .automatic
        archive.automaticStartDay = day
        return archive
    }
    @discardableResult
    private func prepare(_ exchange: WidgetAutomaticExchange, archive: FootprintArchive? = nil,
                         now date: Date? = nil) throws -> WidgetAutomaticContext {
        try exchange.publishContext(from: archive ?? self.archive(), enabled: true,
            calendar: calendar, classificationRevision: "fixture-classification", modelRevision: "fixture-model",
            now: date ?? now)
    }
    private func record(_ request: WidgetAutomaticRequest, at date: Date? = nil) -> FootprintRecord {
        var values = request.inputs
        values.usages[0].minutes = 30
        values.calendarDayMinutes = request.interval.duration / 60
        let result = FootprintResult(totalKg: 0.012, appUsageKg: 0.012, displayKg: 0, backgroundKg: 0,
            categories: [CategoryFootprint(category: .video, totalKg: 0.012,
                deviceKg: 0.004, networkKg: 0.004, backendKg: 0.004)])
        return FootprintRecord(day: request.day, inputs: values, result: result, source: .screenTimeWithEstimates,
            calculatedAt: date ?? now, isCompleted: true,
            garden: .state(total: result.totalKg, baseline: request.baselineKg),
            baselineKg: request.baselineKg, automaticCategories: [.video])
    }

    // [01] Reading the saved setup again must not create a new consent ticket because a date had fractions.
    func testUnchangedContextKeepsItsEpochAfterDiskRoundTrip() throws {
        let exchange = WidgetAutomaticExchange(directory: folder())
        let first = try prepare(exchange)
        let repeated = try prepare(exchange)
        XCTAssertEqual(first, repeated)
        XCTAssertEqual(try exchange.currentContext(), first)
        XCTAssertEqual(first.fingerprint.count, 64)
    }

    // [02] Deletion wins even if Apple's old query answers afterwards.
    func testDisabledTombstoneRejectsLateCommitAndClearsSavedGarden() throws {
        let exchange = WidgetAutomaticExchange(directory: folder())
        try prepare(exchange)
        let request = try XCTUnwrap(exchange.contextForYesterday(now: now, calendar: calendar))
        try clear(exchange)
        XCTAssertFalse(try exchange.currentContext()?.enabled ?? true)
        let file = exchange.directory!.appendingPathComponent(WidgetAutomaticExchange.fileName)
        #if os(iOS)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #if targetEnvironment(simulator)
        // [07] The simulator may omit protection metadata. Only the phone can establish its actual protection.
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            XCTAssertEqual(protection, .completeUntilFirstUserAuthentication)
        }
        #else
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .completeUntilFirstUserAuthentication)
        #endif
        #endif
        try Data(repeating: 0x20, count: 524_289).write(to: file)
        XCTAssertThrowsError(try exchange.currentContext())
        try clear(exchange)
        XCTAssertFalse(try exchange.currentContext()?.enabled ?? true)
        XCTAssertFalse(try exchange.validateRequest(request, now: now, calendar: calendar))
        XCTAssertThrowsError(try exchange.commit(record(request), expected: request, at: now, calendar: calendar))
        XCTAssertTrue(try exchange.pendingRecords().isEmpty)
        XCTAssertNil(WidgetSnapshotStorage(directory: exchange.directory).read().snapshot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exchange.directory!.appendingPathComponent(WidgetAutomaticExchange.fileName).path))
    }

    // [03] Two widget sizes can ask together, but the same date must be saved only once.
    func testCompetingSameDayCommitsKeepOneDurableRecord() throws {
        let exchange = WidgetAutomaticExchange(directory: folder())
        try prepare(exchange)
        let request = try XCTUnwrap(exchange.contextForYesterday(now: now, calendar: calendar))
        XCTAssertTrue(try exchange.commit(record(request), expected: request, at: now, calendar: calendar))
        XCTAssertFalse(try exchange.commit(record(request), expected: request, at: now, calendar: calendar))
        XCTAssertEqual(try exchange.pendingRecords().count, 1)
        XCTAssertEqual(WidgetSnapshotStorage(directory: exchange.directory).read().snapshot?.day, request.day)
        XCTAssertNil(try exchange.contextForYesterday(now: now, calendar: calendar))
    }

    func testTravelAndDayChangeRejectTheOldRequest() throws {
        let exchange = WidgetAutomaticExchange(directory: folder())
        try prepare(exchange)
        let request = try XCTUnwrap(exchange.contextForYesterday(now: now, calendar: calendar))
        var otherZone = calendar
        otherZone.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertFalse(try exchange.validateRequest(request, now: now, calendar: otherZone))
        XCTAssertThrowsError(try exchange.commit(record(request), expected: request, at: now, calendar: otherZone))
        XCTAssertFalse(try exchange.validateRequest(request, now: now.addingTimeInterval(86_400), calendar: calendar))
        var future = record(request)
        future.calculatedAt = now.addingTimeInterval(60)
        XCTAssertThrowsError(try exchange.commit(future, expected: request, at: now, calendar: calendar))
        XCTAssertTrue(try exchange.pendingRecords().isEmpty)
    }

    func testNewAssumptionsInvalidateAnInFlightRequest() throws {
        let exchange = WidgetAutomaticExchange(directory: folder())
        var saved = archive()
        let first = try prepare(exchange, archive: saved)
        let request = try XCTUnwrap(exchange.contextForYesterday(now: now, calendar: calendar))
        var changed = inputs()
        changed.brightness = 0.7
        saved.revisions[0] = RoutineRevision(effectiveDay: saved.firstDay, savedAt: now, inputs: changed)
        let second = try prepare(exchange, archive: saved)
        XCTAssertNotEqual(first.epoch, second.epoch)
        XCTAssertThrowsError(try exchange.commit(record(request), expected: request, at: now, calendar: calendar))
    }

    // [04] A stopped app can replay a pending day; acknowledgement must wait for its own successful save.
    func testReplayRemainsAvailableUntilIdempotentAcknowledgement() throws {
        let directory = folder()
        let exchange = WidgetAutomaticExchange(directory: directory)
        try prepare(exchange)
        let request = try XCTUnwrap(exchange.contextForYesterday(now: now, calendar: calendar))
        XCTAssertTrue(try exchange.commit(record(request, at: now.addingTimeInterval(0.375)),
            expected: request, at: now.addingTimeInterval(0.375), calendar: calendar))
        let reloaded = WidgetAutomaticExchange(directory: directory)
        let first = try XCTUnwrap(reloaded.pendingRecords().first)
        XCTAssertEqual(try reloaded.pendingRecords().first, first)
        try reloaded.acknowledge(ids: [first.id])
        try reloaded.acknowledge(ids: [first.id])
        XCTAssertTrue(try reloaded.pendingRecords().isEmpty)
    }

    func testSnapshotCanBeRepairedFromTheDurablePendingDay() throws {
        let exchange = WidgetAutomaticExchange(directory: folder())
        try prepare(exchange)
        let request = try XCTUnwrap(exchange.contextForYesterday(now: now, calendar: calendar))
        XCTAssertTrue(try exchange.commit(record(request), expected: request, at: now, calendar: calendar))
        _ = try WidgetSnapshotStorage(directory: exchange.directory).write(nil)
        XCTAssertNil(WidgetSnapshotStorage(directory: exchange.directory).read().snapshot)
        XCTAssertNil(try exchange.recoverPendingSnapshot(now: now.addingTimeInterval(-60), calendar: calendar))
        XCTAssertNil(WidgetSnapshotStorage(directory: exchange.directory).read().snapshot)
        XCTAssertEqual(try exchange.pendingRecords().count, 1)
        XCTAssertEqual(try exchange.recoverPendingSnapshot(now: now, calendar: calendar)?.day, request.day)
        XCTAssertEqual(WidgetSnapshotStorage(directory: exchange.directory).read().snapshot?.day, request.day)
    }

    // [05] A damaged handoff must not be silently replaced by a fresh setup or invented zero.
    func testInvalidJSONBlocksNormalReadsAndWritesButExplicitClearCanRecover() throws {
        let directory = folder()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(WidgetAutomaticExchange.fileName)
        let damaged = Data("{broken".utf8)
        try damaged.write(to: file)
        let exchange = WidgetAutomaticExchange(directory: directory)
        XCTAssertThrowsError(try exchange.currentContext())
        XCTAssertThrowsError(try prepare(exchange))
        XCTAssertEqual(try Data(contentsOf: file), damaged)
        try clear(exchange)
        XCTAssertFalse(try exchange.currentContext()?.enabled ?? true)
    }

    func testChangedAssumptionsAndWrongSourceCannotBecomePendingDays() throws {
        let exchange = WidgetAutomaticExchange(directory: folder())
        try prepare(exchange)
        let request = try XCTUnwrap(exchange.contextForYesterday(now: now, calendar: calendar))
        var changed = record(request)
        changed.inputs.brightness = 0.1
        XCTAssertThrowsError(try exchange.commit(changed, expected: request, at: now, calendar: calendar))
        changed = record(request)
        changed.source = .manual
        XCTAssertThrowsError(try exchange.commit(changed, expected: request, at: now, calendar: calendar))
        changed = record(request)
        changed.inputs.calendarDayMinutes = 25 * 60
        XCTAssertThrowsError(try exchange.commit(changed, expected: request, at: now, calendar: calendar))
        XCTAssertTrue(try exchange.pendingRecords().isEmpty)
    }

    func testKnownManualDayAndFutureOptInDoNotStartAWidgetImport() throws {
        let exchange = WidgetAutomaticExchange(directory: folder())
        try prepare(exchange)
        let request = try XCTUnwrap(exchange.contextForYesterday(now: now, calendar: calendar))
        var saved = archive()
        var manual = record(request)
        manual.source = .manual
        saved.records = [manual]
        try prepare(exchange, archive: saved)
        XCTAssertNil(try exchange.contextForYesterday(now: now, calendar: calendar))
        XCTAssertNil(try exchange.contextForYesterday(now: now, calendar: calendar, allowExistingAutomaticDay: true))
        saved.records = []
        saved.automaticStartDay = FootprintCalendar(calendar: calendar).key(now)
        try prepare(exchange, archive: saved)
        XCTAssertNil(try exchange.contextForYesterday(now: now, calendar: calendar))
    }

    // [06] The probe can recheck a real automatic day, but ordinary widget work still skips saved dates.
    func testControlledAutomaticReimportIsExplicitAndPreservesPendingUntilAcknowledged() throws {
        let exchange = WidgetAutomaticExchange(directory: folder())
        try prepare(exchange)
        let first = try XCTUnwrap(exchange.contextForYesterday(now: now, calendar: calendar))
        var saved = archive()
        saved.records = [record(first)]
        try prepare(exchange, archive: saved)
        XCTAssertNil(try exchange.contextForYesterday(now: now, calendar: calendar))
        let recheck = try XCTUnwrap(exchange.contextForYesterday(now: now, calendar: calendar, allowExistingAutomaticDay: true))
        XCTAssertTrue(recheck.allowsExistingAutomaticDay)
        XCTAssertTrue(try exchange.commit(record(recheck), expected: recheck, at: now, calendar: calendar))
        let pending = try XCTUnwrap(exchange.pendingRecords().first)
        var changed = inputs()
        changed.brightness = 0.6
        saved.revisions.append(RoutineRevision(effectiveDay: FootprintCalendar(calendar: calendar).key(now), savedAt: now, inputs: changed))
        try prepare(exchange, archive: saved)
        XCTAssertEqual(try exchange.pendingRecords().first?.id, pending.id)
        try exchange.acknowledge(ids: [pending.id])
        XCTAssertTrue(try exchange.pendingRecords().isEmpty)
    }

    func testMailboxStopsAtItsLimitWithoutDroppingUnacknowledgedDays() throws {
        let exchange = WidgetAutomaticExchange(directory: folder())
        let start = now.addingTimeInterval(-40 * 86_400)
        let saved = archive(at: start.addingTimeInterval(-86_400))
        for index in 0..<WidgetAutomaticExchange.maximumPendingRecords {
            let date = calendar.date(byAdding: .day, value: index, to: start)!
            try prepare(exchange, archive: saved, now: date)
            let request = try XCTUnwrap(exchange.contextForYesterday(now: date, calendar: calendar))
            XCTAssertTrue(try exchange.commit(record(request, at: date), expected: request, at: date, calendar: calendar))
        }
        let fullDate = calendar.date(byAdding: .day, value: WidgetAutomaticExchange.maximumPendingRecords, to: start)!
        try prepare(exchange, archive: saved, now: fullDate)
        XCTAssertNil(try exchange.contextForYesterday(now: fullDate, calendar: calendar))
        XCTAssertEqual(try exchange.pendingRecords().count, WidgetAutomaticExchange.maximumPendingRecords)
    }

    // [08] A broken record is never a reason to prevent someone withdrawing automatic access.
    func testSeparateBlockMarkerStopsQueriesWhenTheHandoffIsUnreadable() throws {
        let directory = folder()
        let exchange = WidgetAutomaticExchange(directory: directory)
        try prepare(exchange)
        let request = try XCTUnwrap(exchange.contextForYesterday(now: now, calendar: calendar))
        let file = directory.appendingPathComponent(WidgetAutomaticExchange.fileName)
        let damaged = Data("{broken".utf8)
        try damaged.write(to: file)
        XCTAssertNoThrow(try exchange.blockNewQueries())
        XCTAssertTrue(try exchange.newQueriesAreBlocked())
        XCTAssertNil(try exchange.contextForYesterday(now: now, calendar: calendar))
        XCTAssertFalse(try exchange.validateRequest(request, now: now, calendar: calendar))
        XCTAssertThrowsError(try exchange.commit(record(request), expected: request, at: now, calendar: calendar))
        XCTAssertThrowsError(try exchange.publishContext(from: archive(), enabled: false, calendar: calendar,
            classificationRevision: "fixture-classification", now: now))
        XCTAssertTrue(try exchange.newQueriesAreBlocked())
        XCTAssertThrowsError(try prepare(exchange))
        XCTAssertTrue(try exchange.newQueriesAreBlocked())
        XCTAssertEqual(try Data(contentsOf: file), damaged)
    }

    func testExplicitValidSetupRemovesTheBlockWithANewConsentEpoch() throws {
        let exchange = WidgetAutomaticExchange(directory: folder())
        let before = try prepare(exchange)
        let oldRequest = try XCTUnwrap(exchange.contextForYesterday(now: now, calendar: calendar))
        try exchange.blockNewQueries()
        XCTAssertTrue(try exchange.newQueriesAreBlocked())
        let after = try prepare(exchange)
        XCTAssertNotEqual(before.epoch, after.epoch)
        XCTAssertFalse(try exchange.newQueriesAreBlocked())
        XCTAssertFalse(try exchange.validateRequest(oldRequest, now: now, calendar: calendar))
        XCTAssertNotNil(try exchange.contextForYesterday(now: now, calendar: calendar))
    }
}
