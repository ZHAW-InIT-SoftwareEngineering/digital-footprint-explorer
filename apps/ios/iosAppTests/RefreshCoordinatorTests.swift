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

// [01] Refresh callers can share useful work, but never the wrong day or a result from another
// history file

import XCTest
@testable import DFE

@MainActor
private final class RefreshTestGate {
    private var continuation: CheckedContinuation<Void, Error>?
    private(set) var entered = false
    func suspend() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                entered = true
            }
        } onCancel: {
            Task { @MainActor in self.release(cancelled: true) }
        }
        try Task.checkCancellation()
    }
    func release(cancelled: Bool = false) {
        let pending = continuation
        continuation = nil
        if cancelled { pending?.resume(throwing: CancellationError()) }
        else { pending?.resume() }
    }
}

@MainActor
private final class RefreshTestCounter {
    var calls = 0
    var active = 0
    var maximumActive = 0
    func begin() { calls += 1; active += 1; maximumActive = max(maximumActive, active) }
    func end() { active -= 1 }
}

final class RefreshCoordinatorTests: XCTestCase {
    @MainActor private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<2_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("The controlled refresh did not reach its expected suspension point.")
    }

    // [02] Two waiting screens should share one recovery attempt after iOS cancels the background
    // work.
    @MainActor func testTwoForegroundWaitersShareOneRetryAfterBackgroundCancellation() async throws {
        let coordinator = RefreshCoordinator<Int>(), key = UUID()
        let gate = RefreshTestGate(), counter = RefreshTestCounter()
        let operation: @MainActor @Sendable () async throws -> Int = {
            counter.begin(); defer { counter.end() }
            if counter.calls == 1 { try await gate.suspend() }
            return counter.calls
        }
        let background = Task { try await coordinator.perform(key: key, operation) }
        await waitUntil { gate.entered }
        let first = Task { try await coordinator.perform(key: key, operation) }
        let second = Task { try await coordinator.perform(key: key, operation) }
        await waitUntil { coordinator.waitingRequests == 2 }
        background.cancel()
        let firstValue = try await first.value, secondValue = try await second.value
        XCTAssertEqual(firstValue, 2)
        XCTAssertEqual(secondValue, 2)
        do { _ = try await background.value; XCTFail("The cancelled owner should not succeed.") }
        catch is CancellationError { }
        XCTAssertEqual(counter.calls, 2)
        XCTAssertEqual(counter.maximumActive, 1)
        XCTAssertEqual(coordinator.waitingRequests, 0)
    }

    // [03] Leaving one screen should not cancel background work that another caller still needs.
    @MainActor func testCancellingAWaiterDoesNotCancelTheBackgroundOwner() async throws {
        let coordinator = RefreshCoordinator<Int>(), key = UUID(), gate = RefreshTestGate()
        let counter = RefreshTestCounter()
        let background = Task { try await coordinator.perform(key: key) {
            counter.begin(); defer { counter.end() }
            try await gate.suspend()
            return 11
        } }
        await waitUntil { gate.entered }
        let foreground = Task { try await coordinator.perform(key: key) { counter.begin(); counter.end(); return 99 } }
        await waitUntil { coordinator.waitingRequests == 1 }
        foreground.cancel()
        gate.release()
        let value = try await background.value
        XCTAssertEqual(value, 11)
        do { _ = try await foreground.value; XCTFail("A cancelled waiter must not succeed or retry.") }
        catch is CancellationError { }
        XCTAssertEqual(counter.calls, 1)
    }

    // [04] When every caller has cancelled, there is no reason to start another recovery request.
    @MainActor func testCancelledOwnerAndWaiterDoNotStartRecovery() async throws {
        let coordinator = RefreshCoordinator<Int>(), key = UUID(), gate = RefreshTestGate()
        let counter = RefreshTestCounter()
        let operation: @MainActor @Sendable () async throws -> Int = {
            counter.begin(); defer { counter.end() }
            try await gate.suspend()
            return counter.calls
        }
        let owner = Task { try await coordinator.perform(key: key, operation) }
        await waitUntil { gate.entered }
        let waiter = Task { try await coordinator.perform(key: key, operation) }
        await waitUntil { coordinator.waitingRequests == 1 }
        waiter.cancel(); owner.cancel()
        for task in [owner, waiter] {
            do { _ = try await task.value; XCTFail("Cancelled work must remain cancelled.") }
            catch is CancellationError { }
        }
        XCTAssertEqual(counter.calls, 1)
        XCTAssertEqual(counter.active, 0)
    }

    // [05] Separate histories may wait their turn, but one must never receive the other history's
    // result.
    @MainActor func testDifferentInstancesWaitButNeverShareTheOtherArchivesResult() async throws {
        let coordinator = RefreshCoordinator<Int>(), gate = RefreshTestGate(), counter = RefreshTestCounter()
        let first = Task { try await coordinator.perform(key: UUID()) {
            counter.begin(); defer { counter.end() }
            try await gate.suspend()
            return 11
        } }
        await waitUntil { gate.entered }
        let second = Task { try await coordinator.perform(key: UUID()) {
            counter.begin(); defer { counter.end() }
            return 22
        } }
        let cancelled = Task { try await coordinator.perform(key: UUID()) {
            counter.begin(); defer { counter.end() }
            return 99
        } }
        await waitUntil { coordinator.waitingRequests == 2 }
        XCTAssertEqual(counter.calls, 1)
        cancelled.cancel()
        gate.release()
        let firstValue = try await first.value, secondValue = try await second.value
        do { _ = try await cancelled.value; XCTFail("A cancelled isolated waiter must not start.") }
        catch is CancellationError { }
        XCTAssertEqual(firstValue, 11)
        XCTAssertEqual(secondValue, 22)
        XCTAssertEqual(counter.maximumActive, 1)
    }

    // [06] A failed recovery should stop cleanly, leaving the next independent refresh free to try
    // again.
    @MainActor func testFatalRecoveryDoesNotLoopAndNextIndependentRefreshCanRun() async throws {
        enum Failure: Error { case expected }
        let coordinator = RefreshCoordinator<Int>(), key = UUID(), gate = RefreshTestGate()
        let counter = RefreshTestCounter()
        let operation: @MainActor @Sendable () async throws -> Int = {
            counter.begin(); defer { counter.end() }
            if counter.calls == 1 { try await gate.suspend() }
            throw Failure.expected
        }
        let owner = Task { try await coordinator.perform(key: key, operation) }
        await waitUntil { gate.entered }
        let waiter = Task { try await coordinator.perform(key: key, operation) }
        await waitUntil { coordinator.waitingRequests == 1 }
        owner.cancel()
        do { _ = try await waiter.value; XCTFail("The recovery error must reach its caller.") }
        catch Failure.expected { }
        do { _ = try await owner.value; XCTFail("The first owner was cancelled.") }
        catch is CancellationError { }
        XCTAssertEqual(counter.calls, 2)
        let value = try await coordinator.perform(key: key) { 33 }
        XCTAssertEqual(value, 33)
    }

    // [07] After midnight, a waiting refresh needs the new day's result rather than yesterday's
    // completed work.
    @MainActor func testNewDayWaiterRunsItsOwnRefreshWithTheSameArchiveKey() async throws {
        let coordinator = RefreshCoordinator<String>(), key = UUID(), gate = RefreshTestGate()
        let counter = RefreshTestCounter()
        let beforeMidnight = Task { try await coordinator.perform(key: key, context: "2026-10-22|Europe/Zurich|0") {
            counter.begin(); defer { counter.end() }
            try await gate.suspend()
            return "2026-10-21"
        } }
        await waitUntil { gate.entered }
        let afterMidnight = Task { try await coordinator.perform(key: key, context: "2026-10-23|Europe/Zurich|0") {
            counter.begin(); defer { counter.end() }
            return "2026-10-22"
        } }
        await waitUntil { coordinator.waitingRequests == 1 }
        XCTAssertEqual(counter.calls, 1)
        gate.release()
        let old = try await beforeMidnight.value, current = try await afterMidnight.value
        XCTAssertEqual(old, "2026-10-21")
        XCTAssertEqual(current, "2026-10-22")
        XCTAssertEqual(counter.calls, 2)
        XCTAssertEqual(counter.maximumActive, 1)
    }

    // [08] Travel or a setup change can alter what activity is allowed, so an older request cannot
    // answer for it.
    @MainActor func testTimeZoneAndSetupChangesCannotReuseTheSameDayFlight() async throws {
        for context in ["2026-10-23|America/New_York|0", "2026-10-23|Europe/Zurich|1"] {
            let coordinator = RefreshCoordinator<Int>(), key = UUID(), gate = RefreshTestGate()
            let counter = RefreshTestCounter()
            let earlier = Task { try await coordinator.perform(key: key, context: "2026-10-23|Europe/Zurich|0") {
                counter.begin(); defer { counter.end() }
                try await gate.suspend()
                return 11
            } }
            await waitUntil { gate.entered }
            let changed = Task { try await coordinator.perform(key: key, context: context) {
                counter.begin(); defer { counter.end() }
                return 22
            } }
            await waitUntil { coordinator.waitingRequests == 1 }
            gate.release()
            let earlierValue = try await earlier.value, changedValue = try await changed.value
            XCTAssertEqual(earlierValue, 11)
            XCTAssertEqual(changedValue, 22)
            XCTAssertEqual(counter.calls, 2)
            XCTAssertEqual(counter.maximumActive, 1)
        }
    }

    // [09] Recovering cancelled work must not borrow a newer day's result just because both use
    // the same history file.
    @MainActor func testCancelledRecoveryNeverJoinsAnotherDayWithTheSameArchiveKey() async throws {
        let coordinator = RefreshCoordinator<Int>(), key = UUID()
        let cancelledGate = RefreshTestGate(), newerGate = RefreshTestGate(), counter = RefreshTestCounter()
        let earlierContext = "2026-10-22|Europe/Zurich|0"
        let newerContext = "2026-10-23|Europe/Zurich|0"
        let earlierOperation: @MainActor @Sendable () async throws -> Int = {
            counter.begin(); defer { counter.end() }
            if counter.calls == 1 { try await cancelledGate.suspend() }
            return 11
        }
        let owner = Task { try await coordinator.perform(key: key, context: earlierContext, earlierOperation) }
        await waitUntil { cancelledGate.entered }
        let newer = Task { try await coordinator.perform(key: key, context: newerContext) {
            counter.begin(); defer { counter.end() }
            try await newerGate.suspend()
            return 22
        } }
        await waitUntil { coordinator.waitingRequests == 1 }
        let earlierWaiter = Task { try await coordinator.perform(key: key, context: earlierContext, earlierOperation) }
        await waitUntil { coordinator.waitingRequests == 2 }
        owner.cancel()
        await waitUntil { newerGate.entered }
        newerGate.release()
        let newerValue = try await newer.value, recoveredEarlierValue = try await earlierWaiter.value
        XCTAssertEqual(newerValue, 22)
        XCTAssertEqual(recoveredEarlierValue, 11)
        do { _ = try await owner.value; XCTFail("The original cancelled owner must stay cancelled.") }
        catch is CancellationError { }
        XCTAssertEqual(counter.calls, 3)
        XCTAssertEqual(counter.maximumActive, 1)
        XCTAssertEqual(coordinator.waitingRequests, 0)
    }

    // [10] The caller needs to distinguish new records, missing data and lost access to show the
    // right outcome.
    func testCompletionOutcomeSeparatesPendingAccessErrorsAndNewRecords() {
        var result = ScreenTimeRefreshResult()
        XCTAssertEqual(result.outcome, .noNewRecord)
        result.attemptedDays = 2; result.pendingDays = 2
        XCTAssertEqual(result.outcome, .pending)
        XCTAssertTrue(result.completedWithoutFatalError)
        result.importedDays = 1
        XCTAssertEqual(result.outcome, .imported)
        XCTAssertEqual(result.newRecords, 0)
        result.stoppedForError = true
        XCTAssertEqual(result.outcome, .error)
        XCTAssertFalse(result.completedWithoutFatalError)
        result.stoppedForAccess = true
        XCTAssertEqual(result.outcome, .noAccess)
        XCTAssertEqual(result.importedDays, 1)
    }
}
