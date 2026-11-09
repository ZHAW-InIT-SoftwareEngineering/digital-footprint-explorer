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

final class WatchRefreshAttemptTests: XCTestCase {
    // [01] This is the stalled-activation case: no phone reply has even been sent, but the attempt still expires and can be retried.
    func testActivationWaitHasADeadlineAndAllowsAnotherAttempt() throws {
        var state = CompanionRefreshAttempt()
        let first = try XCTUnwrap(state.begin(now: 100))
        XCTAssertEqual(state.phase, .activation)
        XCTAssertFalse(state.accepts(first, now: 108))
        XCTAssertFalse(state.beginReply(for: first, now: 108))
        XCTAssertTrue(state.finish(first))
        let retry = try XCTUnwrap(state.begin(now: 109))
        XCTAssertNotEqual(first, retry)
        XCTAssertTrue(state.beginReply(for: retry, now: 110))
    }

    func testActivationDoesNotRestartTheOriginalDeadline() throws {
        var state = CompanionRefreshAttempt()
        let id = try XCTUnwrap(state.begin(now: 10))
        XCTAssertTrue(state.beginReply(for: id, now: 17.5))
        XCTAssertEqual(state.deadline, 18)
        XCTAssertFalse(state.accepts(id, now: 18))
    }

    func testLateReplyCannotFinishOrOverwriteANewerAttempt() throws {
        var state = CompanionRefreshAttempt()
        let old = try XCTUnwrap(state.begin(now: 100))
        XCTAssertTrue(state.beginReply(for: old, now: 101))
        XCTAssertTrue(state.finish(old))
        let current = try XCTUnwrap(state.begin(now: 109))
        XCTAssertFalse(state.accepts(old, now: 110))
        XCTAssertFalse(state.finish(old))
        XCTAssertEqual(state.id, current)
        XCTAssertTrue(state.accepts(current, now: 110))
    }

    func testRepeatedActivationAndReachabilitySendOnlyOnce() throws {
        var state = CompanionRefreshAttempt()
        let id = try XCTUnwrap(state.begin(now: 10))
        XCTAssertTrue(state.beginReply(for: id, now: 11))
        XCTAssertFalse(state.beginReply(for: id, now: 11.1))
        XCTAssertFalse(state.beginReply(for: id, now: 11.2))
        XCTAssertEqual(state.phase, .reply)
    }

    func testLateActivationAfterOfflineFinishDoesNotSendARequest() throws {
        var state = CompanionRefreshAttempt()
        let id = try XCTUnwrap(state.begin(now: 10))
        XCTAssertTrue(state.finish(id))
        XCTAssertFalse(state.beginReply(for: id, now: 11))
        XCTAssertNil(state.id)
    }

    func testOverlappingRefreshDoesNotReplaceTheActiveDeadline() throws {
        var state = CompanionRefreshAttempt()
        let id = try XCTUnwrap(state.begin(now: 10))
        XCTAssertNil(state.begin(now: 15))
        XCTAssertEqual(state.id, id)
        XCTAssertEqual(state.deadline, 18)
    }
}
