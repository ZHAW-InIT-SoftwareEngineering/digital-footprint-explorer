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

#if os(iOS)
import XCTest
@testable import DFE

private enum WatchSaveTestError: Error { case full, unreadable }

private final class WatchTestPersistence: CompanionGardenPersistence {
    var saved: CompanionGardenEnvelope?
    var failSaves = false
    var failReads = false
    private(set) var saveCount = 0
    func load(now: Date) throws -> CompanionGardenEnvelope? {
        if failReads { throw WatchSaveTestError.unreadable }
        try saved?.validate(now: now)
        return saved
    }
    func save(_ envelope: CompanionGardenEnvelope, now: Date) throws {
        if failSaves { throw WatchSaveTestError.full }
        try envelope.validate(now: now)
        saved = envelope
        saveCount += 1
    }
}

@MainActor
final class WatchCompanionServiceTests: XCTestCase {
    private func phoneSnapshot(source: WidgetEstimateSource = .screenTimeWithEstimates) -> GardenWidgetSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        return GardenWidgetSnapshot(day: CompanionGardenSnapshot.dayKey(yesterday, calendar: calendar),
                                    totalKg: 0.06, garden: .growing, source: source,
                                    calculatedAt: Date(), isCompleted: true)
    }

    // [01] A full disk must not leave yesterday's estimate waiting in Apple's transfer queue after the user stops sharing.
    func testWithdrawalStillQueuesAnAggregateFreeClearWhenSaveFails() throws {
        let storage = WatchTestPersistence()
        var sent: [CompanionGardenEnvelope] = []
        let service = WatchCompanionService(storage: storage) { sent.append($0) }
        service.setSharingEnabled(true)
        service.publish(snapshot: phoneSnapshot())
        service.start()
        XCTAssertNotNil(sent.last?.snapshot)
        storage.failSaves = true
        let previousSequence = try XCTUnwrap(sent.last?.sequence)
        service.setSharingEnabled(false)
        let withdrawal = try XCTUnwrap(sent.last)
        XCTAssertEqual(withdrawal.availability, .sharingOff)
        XCTAssertNil(withdrawal.snapshot)
        XCTAssertGreaterThan(withdrawal.sequence, previousSequence)
        let count = sent.count
        service.publish(snapshot: phoneSnapshot())
        XCTAssertEqual(sent.count, count)
    }

    func testFailedResultSaveDoesNotTransmitAnUntrackedEstimate() {
        let storage = WatchTestPersistence()
        var sent: [CompanionGardenEnvelope] = []
        let service = WatchCompanionService(storage: storage) { sent.append($0) }
        service.setSharingEnabled(true)
        service.start()
        let count = sent.count
        storage.failSaves = true
        service.publish(snapshot: phoneSnapshot())
        XCTAssertEqual(sent.count, count)
        XCTAssertNil(storage.saved?.snapshot)
    }

    func testColdStartWhileOffReplacesOldQueuedEstimateEvenWhenSaveFails() throws {
        let storage = WatchTestPersistence()
        var sent: [CompanionGardenEnvelope] = []
        let previous = WatchCompanionService(storage: storage) { _ in }
        previous.setSharingEnabled(true)
        previous.publish(snapshot: phoneSnapshot())
        XCTAssertNotNil(storage.saved?.snapshot)
        storage.failSaves = true
        let restored = WatchCompanionService(storage: storage) { sent.append($0) }
        restored.start()
        XCTAssertFalse(restored.sharingEnabled)
        XCTAssertFalse(sent.isEmpty)
        XCTAssertTrue(sent.allSatisfy { $0.snapshot == nil && $0.availability == .sharingOff })
    }

    func testIsolatedLaunchCannotStartSharing() {
        let service = WatchCompanionService(isolated: true)
        service.setSharingEnabled(true)
        service.start()
        service.publish(snapshot: phoneSnapshot())
        service.clear()
        service.disconnect()
        XCTAssertFalse(service.sharingEnabled)
        XCTAssertEqual(service.transferStatus, "Watch sharing is off")
    }

    func testColdLaunchRestoresSharingWithoutSavingAnEmptyResult() throws {
        let storage = WatchTestPersistence()
        let snapshot = phoneSnapshot()
        let previous = WatchCompanionService(storage: storage) { _ in }
        previous.setSharingEnabled(true)
        previous.publish(snapshot: snapshot)
        let saved = try XCTUnwrap(storage.saved)
        let saveCount = storage.saveCount

        var sent: [CompanionGardenEnvelope] = []
        let restored = WatchCompanionService(storage: storage) { sent.append($0) }
        restored.restoreSharingPreference(true)
        let reread = GardenWidgetSnapshot(day: snapshot.day, totalKg: snapshot.totalKg,
                                        garden: snapshot.garden, source: snapshot.source,
                                        calculatedAt: Date(timeIntervalSince1970:
                                            snapshot.calculatedAt.timeIntervalSince1970.rounded(.down)),
                                        isCompleted: snapshot.isCompleted)
        restored.publish(snapshot: reread, screenTimeAccess: nil)
        restored.publish(snapshot: reread, screenTimeAccess: true)
        restored.start()
        XCTAssertEqual(storage.saveCount, saveCount)
        XCTAssertEqual(sent, [saved])
    }

    func testManualAndRoutineResultsDoNotRequireScreenTime() {
        let service = WatchCompanionService(storage: WatchTestPersistence()) { _ in }
        service.restoreSharingPreference(true)
        service.publish(snapshot: phoneSnapshot(source: .manual), screenTimeAccess: false)
        XCTAssertEqual(service.resultForWatchRefresh()?.snapshot?.source, .manual)
        service.publish(snapshot: phoneSnapshot(source: .routineEstimate), screenTimeAccess: nil)
        XCTAssertEqual(service.resultForWatchRefresh()?.snapshot?.source, .routineEstimate)
        service.publish(snapshot: phoneSnapshot(), screenTimeAccess: false)
        XCTAssertEqual(service.resultForWatchRefresh()?.availability, .disconnected)
        XCTAssertNil(service.resultForWatchRefresh()?.snapshot)
    }

    // [02] Turning the clock back can hide the previous result without resetting its sender or order.
    func testClockCorrectionKeepsTheSavedProducerAndSequence() throws {
        let storage = WatchTestPersistence()
        let snapshot = phoneSnapshot()
        let producer = UUID()
        let future = Date().addingTimeInterval(3_600)
        let cached = CompanionGardenSnapshot(day: snapshot.day, totalKg: 0.04, garden: .stable,
                                             source: .manual, calculatedAt: future, isCompleted: true)
        try storage.save(CompanionGardenEnvelope(producer: producer, sequence: 20, sentAt: future,
                                                 availability: .available, snapshot: cached), now: future)
        var sent: [CompanionGardenEnvelope] = []
        let service = WatchCompanionService(storage: storage) { sent.append($0) }
        service.restoreSharingPreference(true)
        service.start()
        XCTAssertTrue(sent.isEmpty)
        service.publish(snapshot: snapshot)
        XCTAssertEqual(sent.last?.producer, producer)
        XCTAssertEqual(sent.last?.sequence, 21)
    }

    func testAnUnreadableSenderWaitsForRecoveryBeforePublishing() throws {
        let storage = WatchTestPersistence()
        let producer = UUID()
        try storage.save(CompanionGardenEnvelope(producer: producer, sequence: 5, sentAt: Date(),
                                                 availability: .empty, snapshot: nil), now: Date())
        storage.failReads = true
        var sent: [CompanionGardenEnvelope] = []
        let service = WatchCompanionService(storage: storage) { sent.append($0) }
        service.restoreSharingPreference(true)
        service.start()
        service.publish(snapshot: phoneSnapshot())
        XCTAssertTrue(sent.isEmpty)

        storage.failReads = false
        let reply = try XCTUnwrap(service.resultForWatchRefresh())
        XCTAssertEqual(reply.producer, producer)
        XCTAssertEqual(reply.sequence, 6)
        XCTAssertNotNil(reply.snapshot)
    }

    func testDirectRefreshRepairsCorruptSenderWhenNeitherCopyCanBeRead() throws {
        let storage = WatchTestPersistence()
        storage.failReads = true
        var sent: [CompanionGardenEnvelope] = []
        let service = WatchCompanionService(storage: storage) { sent.append($0) }
        service.restoreSharingPreference(true)
        service.start()
        service.publish(snapshot: phoneSnapshot())
        XCTAssertTrue(sent.isEmpty)

        let reply = try XCTUnwrap(service.resultForWatchRefresh())
        XCTAssertEqual(reply.sequence, 1)
        XCTAssertNotNil(reply.snapshot)
        XCTAssertEqual(storage.saved, reply)
    }
}
#endif
