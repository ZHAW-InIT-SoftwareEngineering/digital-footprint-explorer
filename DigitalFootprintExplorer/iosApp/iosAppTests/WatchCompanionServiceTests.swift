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

private enum WatchSaveTestError: Error { case full }

private final class WatchTestPersistence: CompanionGardenPersistence {
    var saved: CompanionGardenEnvelope?
    var failSaves = false
    func load(now: Date) throws -> CompanionGardenEnvelope? { saved }
    func save(_ envelope: CompanionGardenEnvelope, now: Date) throws {
        if failSaves { throw WatchSaveTestError.full }
        saved = envelope
    }
}

@MainActor
final class WatchCompanionServiceTests: XCTestCase {
    private func phoneSnapshot() -> GardenWidgetSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        return GardenWidgetSnapshot(day: CompanionGardenSnapshot.dayKey(yesterday, calendar: calendar),
                                    totalKg: 0.06, garden: .growing, source: .screenTimeWithEstimates,
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
}
#endif
