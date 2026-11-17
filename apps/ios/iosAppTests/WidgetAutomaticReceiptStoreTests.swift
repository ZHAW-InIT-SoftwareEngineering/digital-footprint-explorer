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

// [01] The two workers share a technical receipt store, never real usage or history.
private final class ConcurrentAutomaticReceiptWrites: @unchecked Sendable {
    let store: WidgetAutomaticReceiptStore
    let success: WidgetAutomaticReceipt
    let failure: WidgetAutomaticReceipt
    private let lock = NSLock()
    private var errors = 0
    init(store: WidgetAutomaticReceiptStore, success: WidgetAutomaticReceipt, failure: WidgetAutomaticReceipt) {
        self.store = store; self.success = success; self.failure = failure
    }
    func write(_ receipt: WidgetAutomaticReceipt) {
        do { _ = try store.save(receipt) }
        catch { lock.lock(); errors += 1; lock.unlock() }
    }
    var errorCount: Int { lock.lock(); defer { lock.unlock() }; return errors }
}

final class WidgetAutomaticReceiptStoreTests: XCTestCase {
    private func folder() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func receipt(day: String = "2026-11-06", saved: Bool,
                         at time: String = "2026-11-07T19:29:38Z",
                         status: WidgetAutomaticReceipt.Status? = nil) -> WidgetAutomaticReceipt {
        let time = date(time)
        return WidgetAutomaticReceipt(day: day, queryStartedAt: time.addingTimeInterval(-1), finishedAt: time,
            savedAt: saved ? time : nil, status: status ?? (saved ? .pendingSaved : .queryFailed),
            calculationSucceeded: saved, pendingSaved: saved, elapsedMillis: 1_000, error: nil)
    }
    private func changed(_ receipt: WidgetAutomaticReceipt, fields: [String: Any]) throws -> WidgetAutomaticReceipt {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(receipt)) as? [String: Any])
        for (key, value) in fields { json[key] = value }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WidgetAutomaticReceipt.self, from: JSONSerialization.data(withJSONObject: json))
    }

    // [02] A second process can reject the same day after the first already saved it.
    func testStaleSameDayFailureDoesNotReplaceSuccessfulSaveTime() throws {
        let store = WidgetAutomaticReceiptStore(directory: folder())
        let success = receipt(saved: true)
        XCTAssertTrue(try store.save(success))
        XCTAssertFalse(try store.save(receipt(saved: false, at: "2026-11-07T19:30:00Z")))
        let latest = try XCTUnwrap(store.latest())
        XCTAssertEqual(latest.status, .pendingSaved)
        XCTAssertEqual(latest.savedAt, success.savedAt)
        XCTAssertTrue(latest.pendingSaved)
    }

    func testDurableHandoffWithPendingSnapshotIsAlsoPreserved() throws {
        let store = WidgetAutomaticReceiptStore(directory: folder())
        XCTAssertTrue(try store.save(receipt(saved: true, status: .pendingSavedSnapshotPending)))
        XCTAssertFalse(try store.save(receipt(saved: false, at: "2026-11-07T19:30:00Z")))
        XCTAssertEqual(try store.latest()?.status, .pendingSavedSnapshotPending)
    }

    // [03] Yesterday's success must not hide a real failure when the next day is requested.
    func testLaterDayFailureRemainsVisible() throws {
        let store = WidgetAutomaticReceiptStore(directory: folder())
        _ = try store.save(receipt(saved: true))
        XCTAssertTrue(try store.save(receipt(day: "2026-11-07", saved: false, at: "2026-11-08T07:00:00Z")))
        XCTAssertEqual(try store.latest()?.day, "2026-11-07")
        XCTAssertEqual(try store.latest()?.status, .queryFailed)
    }

    func testFresherSameDaySuccessReplacesEarlierSuccess() throws {
        let store = WidgetAutomaticReceiptStore(directory: folder())
        _ = try store.save(receipt(saved: true))
        let fresh = receipt(saved: true, at: "2026-11-07T19:31:00Z")
        XCTAssertTrue(try store.save(fresh))
        XCTAssertEqual(try store.latest()?.savedAt, fresh.savedAt)
        XCTAssertFalse(try store.save(receipt(saved: true)))
        XCTAssertEqual(try store.latest()?.savedAt, fresh.savedAt)
    }

    func testLateOlderDayCannotRollBackNewerSuccessfulDay() throws {
        let store = WidgetAutomaticReceiptStore(directory: folder())
        _ = try store.save(receipt(day: "2026-11-07", saved: true, at: "2026-11-08T07:00:00Z"))
        XCTAssertFalse(try store.save(receipt(saved: false, at: "2026-11-08T07:01:00Z")))
        XCTAssertEqual(try store.latest()?.day, "2026-11-07")
    }

    // [04] A different build needs its own evidence. It cannot borrow an earlier build's success.
    func testDifferentBuildFailureIsNotHiddenByPriorSuccess() throws {
        let store = WidgetAutomaticReceiptStore(directory: folder())
        _ = try store.save(receipt(saved: true))
        let newBuild = try changed(receipt(saved: false), fields: ["build": "synthetic-next-build"])
        XCTAssertTrue(try store.save(newBuild))
        XCTAssertEqual(try store.latest()?.build, "synthetic-next-build")
        XCTAssertEqual(try store.latest()?.status, .queryFailed)
    }

    func testDamagedTechnicalNoteDoesNotBlockFreshValidEvidence() throws {
        let directory = folder()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not JSON".utf8).write(to: directory.appendingPathComponent(WidgetAutomaticReceipt.fileName))
        let store = WidgetAutomaticReceiptStore(directory: directory)
        XCTAssertTrue(try store.save(receipt(saved: true)))
        XCTAssertTrue(try store.latest()?.pendingSaved == true)
    }

    func testInvalidSavedStatusCannotBecomeSuccessfulEvidence() throws {
        let store = WidgetAutomaticReceiptStore(directory: folder())
        let invalid = try changed(receipt(saved: false), fields: ["pendingSaved": true])
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertNil(try store.latest())
    }

    // [06] Withdrawing access must block a late note without reading or recreating the exchange state.
    func testWithdrawalMarkerBlocksLateReceiptWrites() throws {
        let directory = folder()
        let exchange = WidgetAutomaticExchange(directory: directory)
        let store = WidgetAutomaticReceiptStore(directory: directory)
        try exchange.blockNewQueries()
        XCTAssertFalse(try store.save(receipt(saved: true)))
        XCTAssertFalse(try store.save(receipt(saved: false)))
        XCTAssertNil(try store.latest())
    }

    func testExplicitValidSetupAllowsNewReceiptAfterWithdrawal() throws {
        let directory = folder()
        let exchange = WidgetAutomaticExchange(directory: directory)
        let store = WidgetAutomaticReceiptStore(directory: directory)
        try exchange.blockNewQueries()
        XCTAssertFalse(try store.save(receipt(saved: false)))
        let now = Date()
        let calendar = FootprintCalendar.localCalendar
        let begin = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: now))!
        let day = FootprintCalendar(calendar: calendar).key(begin)
        let inputs = FootprintInputs(usages: [CategoryUsage(category: .video)], brightness: 0.5,
            gpsHours: 0, bluetoothHours: 0)
        var archive = FootprintArchive(firstDay: day,
            revisions: [RoutineRevision(effectiveDay: day, savedAt: begin, inputs: inputs)], records: [])
        archive.inputPreference = .automatic
        archive.automaticStartDay = day
        _ = try exchange.publishContext(from: archive, enabled: true, calendar: calendar,
            classificationRevision: AutomaticActivityClassification.revision, now: now)
        XCTAssertFalse(try exchange.newQueriesAreBlocked())
        XCTAssertTrue(try store.save(receipt(saved: false)))
        XCTAssertEqual(try store.latest()?.status, .queryFailed)
    }

    // [05] These writes use the real shared-file lock. Either ordering must leave the success intact.
    func testConcurrentSuccessfulAndStaleWritesPreserveSuccess() throws {
        let store = WidgetAutomaticReceiptStore(directory: folder())
        let fixture = ConcurrentAutomaticReceiptWrites(store: store, success: receipt(saved: true),
            failure: receipt(saved: false, at: "2026-11-07T19:30:00Z"))
        DispatchQueue.concurrentPerform(iterations: 40) { index in
            fixture.write(index.isMultiple(of: 2) ? fixture.success : fixture.failure)
        }
        XCTAssertEqual(fixture.errorCount, 0)
        let latest = try XCTUnwrap(store.latest())
        XCTAssertTrue(latest.pendingSaved)
        XCTAssertEqual(latest.status, .pendingSaved)
        XCTAssertEqual(latest.savedAt, fixture.success.savedAt)
    }
}
