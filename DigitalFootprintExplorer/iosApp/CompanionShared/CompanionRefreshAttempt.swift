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

import Foundation

// [01] One deadline covers connecting and asking the phone. A failed connection must not leave the refresh button waiting forever.
struct CompanionRefreshAttempt: Sendable {
    enum Phase: Sendable { case activation, reply }
    private(set) var id: UUID?
    private(set) var deadline: TimeInterval?
    private(set) var phase: Phase?

    mutating func begin(now: TimeInterval) -> UUID? {
        guard id == nil, now.isFinite, now >= 0 else { return nil }
        let next = UUID()
        id = next
        deadline = now + 8
        phase = .activation
        return next
    }

    func accepts(_ candidate: UUID, now: TimeInterval) -> Bool {
        guard id == candidate, let deadline, now.isFinite, now >= 0 else { return false }
        return now < deadline
    }

    // [02] Repeated activation or reachability calls may arrive together. Only the first one may send this request.
    mutating func beginReply(for candidate: UUID, now: TimeInterval) -> Bool {
        guard phase == .activation, accepts(candidate, now: now) else { return false }
        phase = .reply
        return true
    }

    // [03] A reply from an old attempt cannot stop the spinner or overwrite the result of a newer attempt.
    @discardableResult
    mutating func finish(_ candidate: UUID) -> Bool {
        guard id == candidate else { return false }
        id = nil
        deadline = nil
        phase = nil
        return true
    }
}
