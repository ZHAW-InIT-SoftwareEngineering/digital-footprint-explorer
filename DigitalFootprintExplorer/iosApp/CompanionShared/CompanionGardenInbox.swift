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

// [01] This extra state stays on the Watch. It stops an old phone's delayed messages from undoing a clear from a new installation.
struct CompanionGardenInbox: Codable, Equatable, Sendable {
    let cacheVersion: Int
    private(set) var envelope: CompanionGardenEnvelope?
    private(set) var requiresInteractiveResume: Bool

    init(envelope: CompanionGardenEnvelope? = nil, requiresInteractiveResume: Bool = false) {
        cacheVersion = 1
        self.envelope = envelope
        self.requiresInteractiveResume = requiresInteractiveResume
    }

    static var blocked: Self { Self(requiresInteractiveResume: true) }

    private mutating func accept(_ next: CompanionGardenEnvelope, trustedReply: Bool) -> Bool {
        if next.snapshot != nil, requiresInteractiveResume, !trustedReply { return false }
        guard next.canReplace(envelope, allowProducerChange: trustedReply) else { return false }
        if trustedReply {
            requiresInteractiveResume = false
        } else if let envelope, envelope.producer != next.producer {
            // [02] A second old clear must not remove this protection. Only a reply to our current request may resume results.
            requiresInteractiveResume = true
        }
        envelope = next
        return true
    }

    // [03] New results wait for a successful save. A privacy clear takes effect in memory even when the disk is full.
    @discardableResult
    mutating func receive(_ next: CompanionGardenEnvelope, trustedReply: Bool,
                          persist: (Self) throws -> Void, invalidateSavedResult: () throws -> Void) throws -> Bool {
        var updated = self
        guard updated.accept(next, trustedReply: trustedReply) else { return false }
        guard updated != self else { return true }
        do {
            try persist(updated)
            self = updated
            return true
        } catch {
            if next.snapshot == nil {
                // If saving the full clear fails, block passive results until a direct refresh and remove the readable old amount.
                updated.requiresInteractiveResume = true
                self = updated
                try? invalidateSavedResult()
                try? persist(updated)
            }
            throw error
        }
    }
}
