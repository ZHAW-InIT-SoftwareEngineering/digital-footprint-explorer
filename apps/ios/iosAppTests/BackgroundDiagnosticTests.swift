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

// [01] Troubleshooting should explain what happened without copying a person's private activity

#if DEBUG
import XCTest
@testable import DFE

final class BackgroundDiagnosticTests: XCTestCase {
    // [02] A one-off background test must expire and run only once, so it cannot remain active by
    // accident.
    func testSimulationArmExpiresAndIsConsumedOnlyOnce() {
        let now = Date(timeIntervalSince1970: 1_000)
        var arm = BackgroundDiagnosticArm()
        arm.mark(probe: true, now: now)
        let first = arm.consume(now: now.addingTimeInterval(59))
        XCTAssertEqual(first.trigger, "simulated_debugger")
        XCTAssertTrue(first.probe)
        XCTAssertFalse(arm.consume(now: now.addingTimeInterval(59)).probe)
        arm.mark(probe: true, now: now)
        let expired = arm.consume(now: now.addingTimeInterval(61))
        XCTAssertEqual(expired.trigger, "system_callback_observed")
        XCTAssertFalse(expired.probe)
        arm.mark(probe: true, now: now)
        XCTAssertFalse(arm.consume(now: now.addingTimeInterval(-1)).probe)
    }

    // [03] Equivalent saved times should match, while an unknown widget state must not look like a
    // confirmed one.
    func testWidgetComparisonNormalizesISOSecondsAndKeepsUnknownDistinct() {
        let expected = GardenWidgetSnapshot(day: "2026-10-17", totalKg: 0.06, garden: .growing,
            source: .screenTimeWithEstimates, calculatedAt: Date(timeIntervalSince1970: 1_000.75), isCompleted: true)
        let saved = GardenWidgetSnapshot(day: expected.day, totalKg: expected.totalKg, garden: expected.garden,
            source: expected.source, calculatedAt: Date(timeIntervalSince1970: 1_000), isCompleted: true)
        XCTAssertEqual(BackgroundWidgetComparison.matches(expected: expected, actual: .saved(saved)), true)
        let changed = GardenWidgetSnapshot(day: saved.day, totalKg: 0.07, garden: saved.garden,
            source: saved.source, calculatedAt: saved.calculatedAt, isCompleted: true)
        XCTAssertEqual(BackgroundWidgetComparison.matches(expected: expected, actual: .saved(changed)), false)
        XCTAssertNil(BackgroundWidgetComparison.matches(expected: expected, actual: .unavailable))
        XCTAssertNil(BackgroundWidgetComparison.matches(expected: expected, actual: .unreadable))
        XCTAssertEqual(BackgroundWidgetComparison.matches(expected: nil, actual: .empty), true)
        XCTAssertEqual(BackgroundWidgetComparison.matches(expected: expected, actual: .empty), false)
    }

    // [04] A file fingerprint lets us check whether history changed without publishing its
    // contents.
    func testArchiveFingerprintTracksSyntheticBytesWithoutIncludingTheirContents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("synthetic-archive.json")
        try Data("abc".utf8).write(to: file)
        let first = try XCTUnwrap(BackgroundArchiveFingerprint.read(fileURL: file))
        // [05] A published fingerprint example checks the actual result, rather than only noticing
        // that a file changed.
        XCTAssertEqual(first, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(BackgroundArchiveFingerprint.read(fileURL: file), first)
        try Data("changed synthetic archive with no personal data".utf8).write(to: file)
        let changed = try XCTUnwrap(BackgroundArchiveFingerprint.read(fileURL: file))
        XCTAssertNotEqual(changed, first)
        XCTAssertEqual(changed.count, 64)
        XCTAssertTrue(changed.allSatisfy { "0123456789abcdef".contains($0) })
        let state = BackgroundDiagnosticState(authorization: "data_access", allScopeSaved: true,
            automaticEnabled: true, eligibleCompletedDay: false, normalOptInStartDay: nil,
            completedDatesEligible: nil, applicationState: "background", widgetMatchesLatest: nil,
            archiveFingerprint: changed)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let receipt = try encoder.encode(state)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: receipt) as? [String: Any])
        XCTAssertEqual(fields["archive_fingerprint"] as? String, changed)
        XCTAssertFalse(String(decoding: receipt, as: UTF8.self).contains("changed synthetic archive"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        XCTAssertEqual(try decoder.decode(BackgroundDiagnosticState.self, from: receipt).archiveFingerprint, changed)
    }

    // [06] An unreadable file should remain unknown, and older technical records should still be
    // readable.
    func testMissingOrUnreadableArchiveFingerprintStaysUnknownAndLegacyReceiptsStillDecode() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let missing = directory.appendingPathComponent("missing.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertNil(BackgroundArchiveFingerprint.read(fileURL: missing))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        XCTAssertNil(BackgroundArchiveFingerprint.read(fileURL: directory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        // [07] Older troubleshooting records still need to open even though they did not save this
        // extra detail.
        let legacy = Data("""
        {"schema_version":1,"debug_only":true,"updated_at":"2026-10-21T08:00:00Z","events":[
          {"timestamp":"2026-10-21T08:00:00Z","event":"finish","source":"foreground",
           "trigger":"application_refresh","state":{"authorization":"data_access",
            "all_scope_saved":true,"automatic_enabled":true,"eligible_completed_day":false,
            "application_state":"active"}}
        ]}
        """.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackgroundDiagnosticLog.self, from: legacy)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertNil(try XCTUnwrap(decoded.events.first).state.archiveFingerprint)
    }

    // [08] Keeping only a small list of declared status fields avoids growing logs or collecting
    // extra details.
    func testDiagnosticRingIsBoundedAndContainsOnlyDeclaredStatusFields() throws {
        let state = BackgroundDiagnosticState(authorization: "data_access", allScopeSaved: true,
            automaticEnabled: true, eligibleCompletedDay: false, normalOptInStartDay: nil, completedDatesEligible: nil, applicationState: "background", widgetMatchesLatest: nil)
        var log = BackgroundDiagnosticLog(updatedAt: Date(timeIntervalSince1970: 0))
        for index in 0..<80 {
            log.append(BackgroundDiagnosticEvent(timestamp: Date(timeIntervalSince1970: Double(index)),
                event: "finish", source: "background", trigger: "simulated_debugger",
                taskCompleted: true, taskSuccess: true, outcome: "no_new_record", attemptedDays: 0,
                importedDays: 0, pendingDays: 0, newRecords: 0, state: state, probe: nil))
        }
        XCTAssertEqual(log.events.count, 60)
        XCTAssertEqual(log.events.first?.timestamp, Date(timeIntervalSince1970: 20))
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(log)
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(Set(decoded.keys), ["schema_version", "debug_only", "updated_at", "events"])
        let events = try XCTUnwrap(decoded["events"] as? [[String: Any]])
        let allowed: Set<String> = ["timestamp", "event", "source", "trigger", "task_completed", "task_success",
            "outcome", "attempted_days", "imported_days", "pending_days", "new_records", "state"]
        XCTAssertTrue(events.allSatisfy { Set($0.keys) == allowed })
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(BackgroundDiagnosticLog.self, from: bytes).events.count, 60)
    }
}
#endif
