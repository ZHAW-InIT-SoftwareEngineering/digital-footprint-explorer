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

// [01] Only these fake counters cross queues. The tests never open a person's saved activity.
private final class DeadlineTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var counts = (saves: 0, completions: 0, timeouts: 0, calculatedAtTimeout: false)
    func save() { lock.lock(); counts.saves += 1; lock.unlock() }
    func complete() { lock.lock(); counts.completions += 1; lock.unlock() }
    func timeout(_ calculated: Bool) {
        lock.lock(); counts.timeouts += 1; counts.calculatedAtTimeout = calculated; lock.unlock()
    }
    func snapshot() -> (saves: Int, completions: Int, timeouts: Int, calculatedAtTimeout: Bool) {
        lock.lock(); defer { lock.unlock() }; return counts
    }
}

final class WidgetAutomaticDeadlineTests: XCTestCase {
    // [02] A late query is not allowed to save after WidgetKit has already received the old garden.
    func testTimeoutBlocksLateSaveAndSecondCompletion() {
        let state = DeadlineTestState()
        let returned = expectation(description: "timeout returned")
        let terminal = WidgetAutomaticTerminal(deadlineUptime: ProcessInfo.processInfo.systemUptime + 0.03,
            timeout: { state.timeout($0) }, completion: { state.complete(); returned.fulfill() })
        terminal.arm()
        wait(for: [returned], timeout: 1)
        terminal.noteCalculationSucceeded()
        terminal.finishQuery { state.save() }
        let result = state.snapshot()
        XCTAssertEqual(result.saves, 0)
        XCTAssertEqual(result.completions, 1)
        XCTAssertEqual(result.timeouts, 1)
        XCTAssertFalse(result.calculatedAtTimeout)
    }

    // [03] If the query wins, its save finishes before the timeline callback reads shared storage.
    func testQuerySavesBeforeCompletionAndOnlyOnce() {
        let state = DeadlineTestState()
        var observedSaves = -1
        let terminal = WidgetAutomaticTerminal(deadlineUptime: ProcessInfo.processInfo.systemUptime + 1,
            timeout: { state.timeout($0) }, completion: {
                state.complete(); observedSaves = state.snapshot().saves
            })
        terminal.arm()
        terminal.finishQuery { state.save() }
        terminal.finishQuery { state.save() }
        XCTAssertEqual(observedSaves, 1)
        XCTAssertEqual(state.snapshot().saves, 1)
        XCTAssertEqual(state.snapshot().completions, 1)
        XCTAssertEqual(state.snapshot().timeouts, 0)
    }

    func testExpiredDeadlineRejectsSaveEvenBeforeTimerRuns() {
        let state = DeadlineTestState()
        let terminal = WidgetAutomaticTerminal(deadlineUptime: ProcessInfo.processInfo.systemUptime - 1,
            timeout: { state.timeout($0) }, completion: { state.complete() })
        terminal.noteCalculationSucceeded()
        terminal.finishQuery { state.save() }
        XCTAssertEqual(state.snapshot().saves, 0)
        XCTAssertEqual(state.snapshot().completions, 1)
        XCTAssertEqual(state.snapshot().timeouts, 1)
        XCTAssertTrue(state.snapshot().calculatedAtTimeout)
    }

    // [04] These requests finish on different queues, like a real deadline racing the API response.
    func testQueryAndTimeoutRaceCompleteOnce() {
        let state = DeadlineTestState()
        let returned = expectation(description: "all requests returned")
        returned.expectedFulfillmentCount = 100
        for _ in 0..<100 {
            let terminal = WidgetAutomaticTerminal(deadlineUptime: ProcessInfo.processInfo.systemUptime + 0.001,
                timeout: { state.timeout($0) }, completion: { state.complete(); returned.fulfill() })
            terminal.arm()
            DispatchQueue.global().async { terminal.finishQuery { state.save() } }
        }
        wait(for: [returned], timeout: 3)
        XCTAssertEqual(state.snapshot().completions, 100)
        XCTAssertEqual(state.snapshot().saves + state.snapshot().timeouts, 100)
    }
}
