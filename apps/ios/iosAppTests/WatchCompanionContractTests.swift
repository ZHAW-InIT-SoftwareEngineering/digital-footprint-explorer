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

final class WatchCompanionContractTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-07T22:00:00Z")!
    private let producer = UUID(uuidString: "CA2B8805-B90A-499D-A0AB-DBD74693DBE1")!

    private func snapshot(day: String = "2026-11-06", total: Double = 0.06,
                          calculatedAt: Date? = nil) -> CompanionGardenSnapshot {
        CompanionGardenSnapshot(day: day, totalKg: total, garden: .growing,
                                source: .screenTimeWithEstimates, calculatedAt: calculatedAt ?? now,
                                isCompleted: true)
    }

    private func envelope(sequence: UInt64 = 1, availability: CompanionGardenAvailability = .available,
                          origin: UUID? = nil) -> CompanionGardenEnvelope {
        CompanionGardenEnvelope(producer: origin ?? producer, sequence: sequence, sentAt: now,
                                availability: availability, snapshot: availability == .available ? snapshot() : nil)
    }

    // [01] A useful Watch card needs only the total and its context. An accidental detailed export should fail this test.
    func testEncodedResultContainsOnlyOneAggregateAndOrderingMetadata() throws {
        let data = try envelope().encoded(now: now)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["version", "producer", "sequence", "sentAt", "availability", "snapshot"])
        let result = try XCTUnwrap(json["snapshot"] as? [String: Any])
        XCTAssertEqual(Set(result.keys), ["day", "totalKg", "garden", "source", "calculatedAt", "isCompleted"])
        XCTAssertEqual(try CompanionGardenEnvelope.decode(data, now: now), envelope())
    }

    func testSharingIsOffUntilExplicitlyEnabled() {
        var policy = CompanionSharingPolicy()
        XCTAssertFalse(policy.isEnabled)
        XCTAssertNil(policy.allowedSnapshot(snapshot()))
        XCTAssertEqual(policy.responseAvailability(for: .available), .sharingOff)
        policy.setEnabled(true)
        XCTAssertEqual(policy.allowedSnapshot(snapshot()), snapshot())
        policy.setEnabled(false)
        XCTAssertNil(policy.allowedSnapshot(snapshot()))
        XCTAssertEqual(policy.responseAvailability(for: .disconnected), .sharingOff)
    }

    func testInvalidAmountsNeverBecomeAWatchGarden() {
        for value in [Double.nan, .infinity, -.infinity, -0.1, Double.greatestFiniteMagnitude] {
            XCTAssertThrowsError(try snapshot(total: value).validate(now: now))
        }
        XCTAssertNoThrow(try snapshot(total: 0).validate(now: now))
    }

    func testRejectsImpossibleAndFutureDayLabels() {
        for day in ["2026-02-30", "2026-2-03", "2026-13-01", "2026-11-10", "not-a-date"] {
            XCTAssertThrowsError(try snapshot(day: day).validate(now: now), day)
        }
        // [02] A phone in UTC+14 can already name tomorrow. That real time-zone boundary must remain valid.
        XCTAssertNoThrow(try snapshot(day: "2026-11-08").validate(now: now))
    }

    func testRejectsFutureSaveTimeBeyondClockSkew() {
        XCTAssertThrowsError(try snapshot(calculatedAt: now.addingTimeInterval(301)).validate(now: now))
        XCTAssertNoThrow(try snapshot(calculatedAt: now.addingTimeInterval(120)).validate(now: now))
    }

    func testTombstonesCannotCarryAnEstimate() {
        let invalid = CompanionGardenEnvelope(producer: producer, sequence: 2, sentAt: now,
                                              availability: .sharingOff, snapshot: snapshot())
        XCTAssertThrowsError(try invalid.encoded(now: now))
        let invalidAvailable = CompanionGardenEnvelope(producer: producer, sequence: 2, sentAt: now,
                                                       availability: .available, snapshot: nil)
        XCTAssertThrowsError(try invalidAvailable.encoded(now: now))
    }

    func testDelayedEstimateCannotReplaceWithdrawal() {
        let before = envelope(sequence: 7)
        let withdrawal = envelope(sequence: 8, availability: .sharingOff)
        XCTAssertTrue(withdrawal.canReplace(before))
        XCTAssertFalse(before.canReplace(withdrawal))
        XCTAssertFalse(envelope(sequence: 8).canReplace(withdrawal))
        XCTAssertTrue(withdrawal.canReplace(withdrawal))
        XCTAssertTrue(envelope(sequence: 9).canReplace(withdrawal))
    }

    func testNewPhoneInstallationNeedsCurrentInteractiveReply() {
        let before = envelope(sequence: 50, availability: .sharingOff)
        let replacement = envelope(origin: UUID())
        XCTAssertFalse(replacement.canReplace(before))
        XCTAssertTrue(replacement.canReplace(before, allowProducerChange: true))
        XCTAssertTrue(replacement.canReplace(nil))
    }

    func testNewPhoneInstallationCanClearBeforeInteractiveRefresh() {
        let before = envelope(sequence: 50)
        let withdrawal = envelope(availability: .sharingOff, origin: UUID())
        XCTAssertTrue(withdrawal.canReplace(before))
        XCTAssertNil(withdrawal.snapshot)
        XCTAssertFalse(before.canReplace(withdrawal))
        XCTAssertFalse(envelope(sequence: 51).canReplace(withdrawal))
    }

    func testOversizedOrUnsupportedMessageIsRejected() throws {
        XCTAssertThrowsError(try CompanionGardenEnvelope.decode(Data(repeating: 0, count: 16_385), now: now))
        let data = try envelope().encoded(now: now)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["version"] = 2
        XCTAssertThrowsError(try CompanionGardenEnvelope.decode(JSONSerialization.data(withJSONObject: json), now: now))
        json["version"] = 1
        json["sequence"] = 0
        XCTAssertThrowsError(try CompanionGardenEnvelope.decode(JSONSerialization.data(withJSONObject: json), now: now))
    }

    func testProtectedStoreRetainsClearAfterRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CompanionGardenStorage(directory: directory)
        try store.save(envelope(sequence: 4), now: now)
        try store.save(envelope(sequence: 5, availability: .empty), now: now)
        let restored = try XCTUnwrap(CompanionGardenStorage(directory: directory).load(now: now))
        XCTAssertEqual(restored.availability, .empty)
        XCTAssertNil(restored.snapshot)
        XCTAssertFalse(envelope(sequence: 4).canReplace(restored))
    }

    func testBadIncomingResultDoesNotOverwriteSavedFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CompanionGardenStorage(directory: directory)
        let before = envelope(sequence: 4)
        try store.save(before, now: now)
        let invalid = CompanionGardenEnvelope(producer: producer, sequence: 5, sentAt: now,
                                              availability: .available, snapshot: snapshot(total: -.infinity))
        XCTAssertThrowsError(try store.save(invalid, now: now))
        XCTAssertEqual(try store.load(now: now), before)
    }

    func testFreshnessUsesCalendarDayAcrossZurichClockChange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let morning = ISO8601DateFormatter().date(from: "2026-10-25T07:00:00Z")!
        XCTAssertFalse(snapshot(day: "2026-10-24").isOlderThanLatestCompletedDay(now: morning, calendar: calendar))
        XCTAssertTrue(snapshot(day: "2026-10-23").isOlderThanLatestCompletedDay(now: morning, calendar: calendar))
        XCTAssertEqual(CompanionGardenSnapshot.dayKey(snapshot(day: "2026-10-24").dayDate!, calendar: calendar), "2026-10-24")
    }

    func testSmallPositiveFootprintDoesNotRoundToZero() {
        let label = snapshot(total: 0.000000001).amountLabel(locale: Locale(identifier: "en_US_POSIX"))
        XCTAssertNotEqual(label, "0")
        XCTAssertFalse(label.isEmpty)
    }

    func testFreshnessUsesGregorianSavedDayWithAnotherPreferredCalendar() {
        var calendar = Calendar(identifier: .buddhist)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        XCTAssertFalse(snapshot(day: "2026-11-06").isOlderThanLatestCompletedDay(now: now, calendar: calendar))
        XCTAssertTrue(snapshot(day: "2026-11-05").isOlderThanLatestCompletedDay(now: now, calendar: calendar))
    }
}
