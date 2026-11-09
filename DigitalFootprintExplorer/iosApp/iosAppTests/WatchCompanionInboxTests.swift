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

private enum CompanionInboxTestError: Error { case unavailable }

final class WatchCompanionInboxTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-08T08:00:00Z")!
    private let oldPhone = UUID(uuidString: "BC8D0441-E9CF-41C0-9453-857405EC2F4B")!
    private let newPhone = UUID(uuidString: "45917C57-D921-4F40-B8E3-C54F7229D2FC")!

    private func message(_ producer: UUID, _ sequence: UInt64,
                         _ status: CompanionGardenAvailability = .available) -> CompanionGardenEnvelope {
        let snapshot = CompanionGardenSnapshot(day: "2026-11-07", totalKg: 0.06, garden: .growing,
                                               source: .screenTimeWithEstimates, calculatedAt: now, isCompleted: true)
        return CompanionGardenEnvelope(producer: producer, sequence: sequence, sentAt: now,
                                        availability: status, snapshot: status == .available ? snapshot : nil)
    }

    private func directory() -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: path) }
        return path
    }

    // [01] This is the reported A/B/A replay: an old clear must not make an old result valid again, even after restarting the Watch.
    func testOldClearBetweenNewWithdrawalAndOldEstimateCannotRestoreResultAfterRelaunch() throws {
        let store = CompanionGardenStorage(directory: directory())
        var inbox = CompanionGardenInbox(envelope: message(oldPhone, 50))
        XCTAssertTrue(try inbox.receive(message(newPhone, 1, .sharingOff), trustedReply: false,
                                       persist: { try store.saveInbox($0, now: now) }, invalidateSavedResult: {}))
        inbox = try store.loadInbox(now: now)
        XCTAssertTrue(try inbox.receive(message(oldPhone, 49, .empty), trustedReply: false,
                                       persist: { try store.saveInbox($0, now: now) }, invalidateSavedResult: {}))
        inbox = try store.loadInbox(now: now)
        XCTAssertTrue(inbox.requiresInteractiveResume)
        XCTAssertFalse(try inbox.receive(message(oldPhone, 50), trustedReply: false,
                                        persist: { _ in XCTFail("A blocked result must not be saved") }, invalidateSavedResult: {}))
        XCTAssertNil(inbox.envelope?.snapshot)
    }

    func testCurrentDirectReplyResumesNewPhoneThenNormalUpdatesContinue() throws {
        var inbox = CompanionGardenInbox(envelope: message(oldPhone, 50))
        _ = try inbox.receive(message(newPhone, 1, .sharingOff), trustedReply: false,
                              persist: { _ in }, invalidateSavedResult: {})
        XCTAssertFalse(try inbox.receive(message(newPhone, 2), trustedReply: false,
                                        persist: { _ in }, invalidateSavedResult: {}))
        XCTAssertTrue(try inbox.receive(message(newPhone, 2), trustedReply: true,
                                       persist: { _ in }, invalidateSavedResult: {}))
        XCTAssertFalse(inbox.requiresInteractiveResume)
        XCTAssertTrue(try inbox.receive(message(newPhone, 3), trustedReply: false,
                                       persist: { _ in }, invalidateSavedResult: {}))
        XCTAssertFalse(try inbox.receive(message(oldPhone, 51), trustedReply: false,
                                        persist: { _ in }, invalidateSavedResult: {}))
    }

    func testSamePhoneUpdateDoesNotRequireAnotherInteraction() throws {
        var inbox = CompanionGardenInbox(envelope: message(oldPhone, 50))
        XCTAssertTrue(try inbox.receive(message(oldPhone, 51), trustedReply: false,
                                       persist: { _ in }, invalidateSavedResult: {}))
        XCTAssertEqual(inbox.envelope?.sequence, 51)
        XCTAssertFalse(inbox.requiresInteractiveResume)
    }

    // [02] If storage fails completely, the app still hides the amount it has just been asked to clear.
    func testFailedClearMasksInMemoryEvenIfInvalidationAlsoFails() {
        var inbox = CompanionGardenInbox(envelope: message(oldPhone, 50))
        var attemptedInvalidation = false
        XCTAssertThrowsError(try inbox.receive(message(oldPhone, 51, .sharingOff), trustedReply: false,
            persist: { _ in throw CompanionInboxTestError.unavailable },
            invalidateSavedResult: {
                attemptedInvalidation = true
                throw CompanionInboxTestError.unavailable
            }))
        XCTAssertTrue(attemptedInvalidation)
        XCTAssertEqual(inbox.envelope?.availability, .sharingOff)
        XCTAssertNil(inbox.envelope?.snapshot)
        XCTAssertTrue(inbox.requiresInteractiveResume)
        XCTAssertFalse((try? inbox.receive(message(oldPhone, 52), trustedReply: false,
                                           persist: { _ in }, invalidateSavedResult: {})) ?? true)
    }

    func testFailedResultSaveKeepsThePreviousAcceptedResult() {
        let before = message(oldPhone, 50)
        var inbox = CompanionGardenInbox(envelope: before)
        XCTAssertThrowsError(try inbox.receive(message(oldPhone, 51), trustedReply: false,
            persist: { _ in throw CompanionInboxTestError.unavailable },
            invalidateSavedResult: { XCTFail("A failed ordinary update is not a clear") }))
        XCTAssertEqual(inbox.envelope, before)
    }

    func testInPlaceBlockedRecordRemovesReadableAmountAndSurvivesReload() throws {
        let store = CompanionGardenStorage(directory: directory())
        try store.saveInbox(CompanionGardenInbox(envelope: message(oldPhone, 50)), now: now)
        XCTAssertNotNil(try store.load(now: now)?.snapshot)
        try store.invalidateSavedResult()
        let restored = try store.loadInbox(now: now)
        XCTAssertTrue(restored.requiresInteractiveResume)
        XCTAssertNil(restored.envelope)
        XCTAssertNil(try store.load(now: now))
        let data = try Data(contentsOf: store.directory.appendingPathComponent(CompanionGardenStorage.fileName))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["cacheVersion", "requiresInteractiveResume"])
    }

    func testLegacySavedResultLoadsWithoutChangingTransportFormat() throws {
        let store = CompanionGardenStorage(directory: directory())
        let result = message(oldPhone, 50)
        try store.save(result, now: now)
        let restored = try store.loadInbox(now: now)
        XCTAssertEqual(restored.envelope, result)
        XCTAssertFalse(restored.requiresInteractiveResume)
    }

    func testBlockedCacheCannotExposeAnAmountThroughTheComplicationReader() throws {
        let store = CompanionGardenStorage(directory: directory())
        let invalid = CompanionGardenInbox(envelope: message(oldPhone, 50), requiresInteractiveResume: true)
        XCTAssertThrowsError(try store.saveInbox(invalid, now: now))
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(invalid).write(to: store.directory.appendingPathComponent(CompanionGardenStorage.fileName))
        XCTAssertThrowsError(try store.load(now: now))
    }
}
