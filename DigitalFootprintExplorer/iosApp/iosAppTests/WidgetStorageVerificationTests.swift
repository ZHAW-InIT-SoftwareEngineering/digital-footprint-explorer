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

import XCTest
@testable import DFE

// [13] Two test workers share only their result list; production ordering comes from FileCoordinator.
private final class ConcurrentWidgetVerification: @unchecked Sendable {
    let checks: WidgetStorageVerificationStore
    let observed: WidgetSnapshotReadResult
    let publisher: FootprintWidgetPublisher
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let writeFinished = DispatchSemaphore(value: 0)
    let deleteAttempted = DispatchSemaphore(value: 0)
    let deleteFinished = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var errors: [String] = []

    init(storage: WidgetSnapshotStorage, producer: WidgetVerificationProducer) {
        observed = storage.read()
        publisher = FootprintWidgetPublisher(storage: storage, producer: producer, reload: {})
        checks = WidgetStorageVerificationStore(directory: storage.directory, producer: producer)
    }
    func writeReceipt() {
        var paused = checks
        paused.beforeTimelineReceiptWrite = { [self] in
            entered.signal()
            if release.wait(timeout: .now() + 5) != .success { note("Timed out releasing the receipt writer") }
        }
        do {
            if try !paused.recordTimelineRead(family: "small", result: observed, at: Date(), isPreview: false) {
                note("The original read was not saved")
            }
        } catch { note("Receipt writer failed") }
        writeFinished.signal()
    }
    func deleteSnapshot() {
        deleteAttempted.signal()
        do { try publisher.publish(nil) }
        catch { note("Deletion failed") }
        deleteFinished.signal()
    }
    private func note(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        errors.append(message)
    }
    func recordedErrors() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return errors
    }
}

@MainActor
final class WidgetStorageVerificationTests: XCTestCase {
    private let producer = WidgetVerificationProducer(build: "2", configuration: "release", isSimulator: false)
    private func folder() -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: value) }
        return value
    }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func snapshot(day: String = "2026-10-31", amount: Double = 0.01234) -> GardenWidgetSnapshot {
        GardenWidgetSnapshot(day: day, totalKg: amount, garden: .growing, source: .screenTimeWithEstimates,
                             calculatedAt: date("2026-11-01T07:10:00Z"), isCompleted: true)
    }

    // [01] The check time follows the real read, while the write time names the earlier completed write.
    func testActualReadBackTimeFollowsWriteAndSurvivesReload() throws {
        let storage = WidgetSnapshotStorage(directory: folder())
        var now = date("2026-11-01T07:10:00Z")
        let writtenAt = now
        let checkedAt = date("2026-11-01T07:10:03Z")
        let publisher = FootprintWidgetPublisher(storage: storage, clock: { now }, readBack: {
            now = checkedAt
            return storage.read()
        }, producer: producer, reload: {})
        try publisher.publish(snapshot())
        let value = try XCTUnwrap(publisher.verification)
        XCTAssertEqual(value.status, .verified)
        XCTAssertEqual(value.publishedAt, writtenAt)
        XCTAssertEqual(value.checkedAt, checkedAt)
        XCTAssertTrue(value.receiptStored)
        XCTAssertEqual(WidgetStorageVerificationStore(directory: storage.directory, producer: producer).publication(), value)
    }

    // [10] A real clock includes fractions that the saved ISO date does not keep.
    func testFractionalSavedTimeDoesNotCauseAFalseReadBackFailure() throws {
        let storage = WidgetSnapshotStorage(directory: folder())
        let plain = snapshot()
        let value = GardenWidgetSnapshot(day: plain.day, totalKg: plain.totalKg, garden: plain.garden,
            source: plain.source, calculatedAt: plain.calculatedAt.addingTimeInterval(0.375), isCompleted: true)
        let publisher = FootprintWidgetPublisher(storage: storage, producer: producer, reload: {})
        XCTAssertNoThrow(try publisher.publish(value))
        XCTAssertEqual(publisher.verification?.status, .verified)
        XCTAssertEqual(storage.read().snapshot?.day, value.day)
    }

    // [02] A no-change update still checks the file, but does not invent another write or redraw.
    func testUnchangedSummaryGetsNewReadCheckWithoutAnotherPublication() throws {
        let storage = WidgetSnapshotStorage(directory: folder())
        var now = date("2026-11-01T07:10:00Z")
        var reads = 0
        var reloads = 0
        let publisher = FootprintWidgetPublisher(storage: storage, clock: { now }, readBack: {
            reads += 1
            return storage.read()
        }, producer: producer, reload: { reloads += 1 })
        try publisher.publish(snapshot())
        let first = try XCTUnwrap(publisher.verification)
        let bytes = try Data(contentsOf: XCTUnwrap(storage.fileURL))
        now = date("2026-11-01T09:00:00Z")
        try publisher.publish(snapshot())
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(publisher.verification?.checkedAt, now)
        XCTAssertEqual(publisher.verification?.publishedAt, first.publishedAt)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(storage.fileURL)), bytes)
    }

    // [03] Upgrading from a saved garden without proof gives each installed size one new chance to read.
    func testLegacySummaryRequestsOneProofReloadWithoutWaitingForUninstalledFamilies() throws {
        let storage = WidgetSnapshotStorage(directory: folder())
        try storage.write(snapshot())
        var reloads = 0
        let publisher = FootprintWidgetPublisher(storage: storage, producer: producer, reload: { reloads += 1 })
        try publisher.publish(snapshot())
        XCTAssertEqual(reloads, 1)
        XCTAssertNil(publisher.verification?.publishedAt, "An old file's original write time is unknown")
        XCTAssertEqual(publisher.verification?.status, .verified)
        for _ in 0..<3 { try publisher.publish(snapshot()) }
        XCTAssertEqual(reloads, 1)
        XCTAssertTrue(publisher.timelineReadChecks.isEmpty, "No installed size is assumed from a host check")
    }

    // [04] Another writer can change the file before the read. A plausible garden must not hide that mismatch.
    func testChangedReadBackIsRecordedAsMismatchAndDoesNotClaimPublicationSuccess() throws {
        let storage = WidgetSnapshotStorage(directory: folder())
        var reloads = 0
        let publisher = FootprintWidgetPublisher(storage: storage, readBack: {
            _ = try? storage.write(self.snapshot(amount: 0.08))
            return storage.read()
        }, producer: producer, reload: { reloads += 1 })
        XCTAssertThrowsError(try publisher.publish(snapshot()))
        XCTAssertEqual(publisher.verification?.status, .mismatch)
        XCTAssertEqual(reloads, 0)
        XCTAssertEqual(WidgetStorageVerificationStore(directory: storage.directory, producer: producer).publication()?.status, .mismatch)
    }

    // [05] Missing, unreadable and unavailable storage remain separate from a confirmed saved garden.
    func testReadFailuresNeverBecomeVerified() throws {
        let examples: [(WidgetSnapshotReadResult, WidgetVerificationStatus)] = [
            (.empty, .mismatch), (.unreadable, .unreadable), (.unavailable, .unavailable)
        ]
        for (read, expected) in examples {
            let publisher = FootprintWidgetPublisher(storage: WidgetSnapshotStorage(directory: folder()),
                readBack: { read }, producer: producer, reload: {})
            XCTAssertThrowsError(try publisher.publish(snapshot()))
            XCTAssertEqual(publisher.verification?.status, expected)
        }
    }

    func testUnavailableAndFailedWritesHaveNoFalseHealthyCheck() throws {
        let unavailable = FootprintWidgetPublisher(storage: WidgetSnapshotStorage(directory: nil),
                                                   producer: producer, reload: {})
        XCTAssertThrowsError(try unavailable.publish(snapshot()))
        XCTAssertEqual(unavailable.verification?.status, .unavailable)
        XCTAssertFalse(try XCTUnwrap(unavailable.verification).receiptStored)
        let obstruction = folder()
        try Data("not a directory".utf8).write(to: obstruction)
        let failed = FootprintWidgetPublisher(storage: WidgetSnapshotStorage(directory: obstruction),
                                              producer: producer, reload: {})
        XCTAssertThrowsError(try failed.publish(snapshot()))
        XCTAssertEqual(failed.verification?.status, .writeFailed)
        XCTAssertFalse(try XCTUnwrap(failed.verification).receiptStored)
    }

    // [06] A failed technical receipt must leave a successfully written garden available to both widgets.
    func testReceiptWriteFailureDoesNotUndoSavedSummary() throws {
        let directory = folder()
        try FileManager.default.createDirectory(at: directory.appendingPathComponent(WidgetStorageVerificationStore.publicationFile),
                                                withIntermediateDirectories: true)
        let storage = WidgetSnapshotStorage(directory: directory)
        let publisher = FootprintWidgetPublisher(storage: storage, producer: producer, reload: {})
        XCTAssertNoThrow(try publisher.publish(snapshot()))
        XCTAssertEqual(storage.read().snapshot, snapshot())
        XCTAssertEqual(publisher.verification?.status, .verified)
        XCTAssertFalse(try XCTUnwrap(publisher.verification).receiptStored)
    }

    // [07] Each size reports its own timeline read. A read confirms access, not display time.
    func testFamilyReadsPersistIndependentlyWithNoUsageValues() throws {
        let directory = folder()
        let store = WidgetStorageVerificationStore(directory: directory, producer: producer)
        try WidgetSnapshotStorage(directory: directory).write(snapshot())
        let first = date("2026-11-01T07:11:00Z")
        let second = date("2026-11-01T07:12:00Z")
        XCTAssertTrue(try store.recordTimelineRead(family: "small", result: .saved(snapshot()), at: first, isPreview: false))
        XCTAssertTrue(try store.recordTimelineRead(family: "medium", result: .saved(snapshot()), at: second, isPreview: false))
        let reads = store.timelineReads()
        XCTAssertEqual(reads.map(\.family), ["small", "medium"])
        XCTAssertEqual(reads.map(\.day), ["2026-10-31", "2026-10-31"])
        XCTAssertEqual(reads.map(\.readAt), [first, second])
        let file = directory.appendingPathComponent("garden-widget-read-small-v1.json")
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let check = try XCTUnwrap(envelope["check"] as? [String: Any])
        XCTAssertEqual(Set(envelope.keys), ["version", "check"])
        XCTAssertEqual(Set(check.keys), ["family", "status", "day", "readAt", "producer"])
        XCTAssertEqual(Set(try XCTUnwrap(check["producer"] as? [String: Any]).keys), ["build", "configuration", "isSimulator"])
    }

    func testPreviewAndUnsupportedSizeNeverCreateTimelineEvidence() throws {
        let directory = folder()
        let store = WidgetStorageVerificationStore(directory: directory, producer: producer)
        XCTAssertFalse(try store.recordTimelineRead(family: "small", result: .saved(snapshot()), at: Date(), isPreview: true))
        XCTAssertFalse(try store.recordTimelineRead(family: "large", result: .saved(snapshot()), at: Date(), isPreview: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(store.timelineReads().isEmpty)
    }

    // [08] A previous build or development check is retained as old evidence, never read as today's release check.
    func testDifferentProducerCannotSupplyCurrentProof() throws {
        let directory = folder()
        let old = WidgetStorageVerificationStore(directory: directory, producer: producer)
        try WidgetSnapshotStorage(directory: directory).write(snapshot())
        try old.recordTimelineRead(family: "small", result: .saved(snapshot()), at: Date(), isPreview: false)
        try old.recordPublication(WidgetPublicationVerification(status: .verified, day: "2026-10-31", checkedAt: Date(),
            publishedAt: nil, producer: producer))
        for changed in [WidgetVerificationProducer(build: "3", configuration: "release", isSimulator: false),
                        WidgetVerificationProducer(build: "2", configuration: "debug", isSimulator: false),
                        WidgetVerificationProducer(build: "2", configuration: "release", isSimulator: true)] {
            let current = WidgetStorageVerificationStore(directory: directory, producer: changed)
            XCTAssertNil(current.publication())
            XCTAssertTrue(current.timelineReads().isEmpty)
        }
    }

    // [09] A deleted history must not leave either size's old day in a technical proof file.
    func testDeletionClearsOnlyTheKnownEvidenceAndSummary() throws {
        let directory = folder()
        let storage = WidgetSnapshotStorage(directory: directory)
        let store = WidgetStorageVerificationStore(directory: directory, producer: producer)
        let publisher = FootprintWidgetPublisher(storage: storage, producer: producer, reload: {})
        try publisher.publish(snapshot())
        try store.recordTimelineRead(family: "small", result: .saved(snapshot()), at: Date(), isPreview: false)
        try store.recordTimelineRead(family: "medium", result: .saved(snapshot()), at: Date(), isPreview: false)
        let unrelated = directory.appendingPathComponent("unrelated.txt")
        try Data("keep".utf8).write(to: unrelated)
        try publisher.publish(nil)
        XCTAssertNil(storage.read().snapshot)
        XCTAssertNil(store.publication())
        XCTAssertTrue(store.timelineReads().isEmpty)
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("keep".utf8))
        XCTAssertEqual(publisher.verification?.status, .empty)
    }

    func testPublicationPrivacyKeysAndInvalidReceiptRejection() throws {
        let directory = folder()
        let store = WidgetStorageVerificationStore(directory: directory, producer: producer)
        let now = date("2026-11-01T07:11:00Z")
        let check = WidgetPublicationVerification(status: .verified, day: "2026-10-31", checkedAt: now,
            publishedAt: now, producer: producer)
        try store.recordPublication(check)
        let file = directory.appendingPathComponent(WidgetStorageVerificationStore.publicationFile)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let value = try XCTUnwrap(envelope["check"] as? [String: Any])
        XCTAssertEqual(Set(value.keys), ["status", "day", "checkedAt", "publishedAt", "producer", "receiptStored"])
        XCTAssertThrowsError(try store.recordPublication(.init(status: .verified, day: "2026-02-30", checkedAt: now,
            publishedAt: nil, producer: producer)))
        XCTAssertThrowsError(try store.recordPublication(.init(status: .verified, day: nil, checkedAt: now,
            publishedAt: nil, producer: producer)))
        var newer = envelope
        newer["version"] = 2
        try JSONSerialization.data(withJSONObject: newer).write(to: file)
        XCTAssertNil(store.publication())
        try Data("broken".utf8).write(to: file)
        XCTAssertNil(store.publication())
    }

    func testEmptyAndUnreadableTimelineStatesDoNotInventADay() throws {
        let directory = folder()
        let store = WidgetStorageVerificationStore(directory: directory, producer: producer)
        try store.recordTimelineRead(family: "small", result: .empty, at: Date(), isPreview: false)
        try Data("broken".utf8).write(to: directory.appendingPathComponent("garden-widget-v1.json"))
        try store.recordTimelineRead(family: "medium", result: .unreadable, at: Date(), isPreview: false)
        XCTAssertEqual(store.timelineReads().map(\.status), [.empty, .unreadable])
        XCTAssertTrue(store.timelineReads().allSatisfy { $0.day == nil })
    }

    // [11] The app can expose a check without exporting the garden amount or its original payload.
    func testAppDataMirrorKeepsOnlyApprovedChecksAndCanClearThem() throws {
        let directory = folder()
        let file = directory.appendingPathComponent("checks.json")
        let now = date("2026-11-01T07:20:00Z")
        let publication = WidgetPublicationVerification(status: .verified, day: "2026-10-31", checkedAt: now,
            publishedAt: nil, producer: producer)
        let read = WidgetTimelineReadCheck(family: "small", status: .verified, day: "2026-10-31",
            readAt: now, producer: producer)
        try WidgetVerificationMirror.write(to: file, publication: publication, timelineReads: [read], at: now)
        let data = try Data(contentsOf: file)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["version", "capturedAt", "publication", "timelineReads"])
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertEqual(json["capturedAt"] as? String, "2026-11-01T07:20:00Z")
        let saved = try XCTUnwrap(json["publication"] as? [String: Any])
        XCTAssertEqual(Set(saved.keys), ["status", "day", "checkedAt", "producer", "receiptStored"])
        let reads = try XCTUnwrap(json["timelineReads"] as? [[String: Any]])
        XCTAssertEqual(Set(try XCTUnwrap(reads.first).keys), ["family", "status", "day", "readAt", "producer"])
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        for excluded in ["totalKg", "minutes", "applicationTokens", "snapshot", "fileURL", "hash"] {
            XCTAssertFalse(encoded.contains(excluded))
        }
        let other = directory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: other)
        try WidgetVerificationMirror.clear(at: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
        XCTAssertNoThrow(try WidgetVerificationMirror.clear(at: file))
    }

    func testUnknownMirrorDoesNotBecomeHealthyAndBadWritesRemainFailures() throws {
        let file = folder().appendingPathComponent("checks.json")
        try WidgetVerificationMirror.write(to: file, publication: nil, timelineReads: [])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertTrue(json["publication"] is NSNull)
        XCTAssertTrue(try XCTUnwrap(json["timelineReads"] as? [Any]).isEmpty)
        let obstruction = folder()
        try Data("not a directory".utf8).write(to: obstruction)
        XCTAssertThrowsError(try WidgetVerificationMirror.write(to: obstruction.appendingPathComponent("checks.json"),
            publication: nil, timelineReads: []))
        let invalid = WidgetTimelineReadCheck(family: "unsupported", status: .verified, day: "2026-10-31",
            readAt: Date(), producer: producer)
        XCTAssertThrowsError(try WidgetVerificationMirror.write(to: file, publication: nil, timelineReads: [invalid]))
    }


    // [12] A timeline that read just before deletion must not recreate a successful old-day check.
    func testDeletedOrReplacedSnapshotDoesNotCreateStaleTimelineProof() throws {
        let directory = folder()
        let storage = WidgetSnapshotStorage(directory: directory)
        let store = WidgetStorageVerificationStore(directory: directory, producer: producer)
        try storage.write(snapshot())
        let observed = storage.read()
        try storage.write(nil)
        XCTAssertFalse(try store.recordTimelineRead(family: "small", result: observed, at: Date(), isPreview: false))
        XCTAssertTrue(store.timelineReads().isEmpty)
        try storage.write(snapshot(day: "2026-11-01"))
        XCTAssertFalse(try store.recordTimelineRead(family: "medium", result: observed, at: Date(), isPreview: false))
        XCTAssertTrue(store.timelineReads().isEmpty)
    }


    // [14] Pause between rechecking and writing. Deletion must wait, then remove the finished old receipt.
    func testIndependentCoordinatorsPreventReceiptReappearingAfterDeletion() throws {
        let directory = folder()
        let storage = WidgetSnapshotStorage(directory: directory)
        try storage.write(snapshot())
        let workers = ConcurrentWidgetVerification(storage: storage, producer: producer)
        defer { workers.release.signal() }
        DispatchQueue.global().async { workers.writeReceipt() }
        XCTAssertEqual(workers.entered.wait(timeout: .now() + 5), .success)
        DispatchQueue.global().async { workers.deleteSnapshot() }
        XCTAssertEqual(workers.deleteAttempted.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(workers.deleteFinished.wait(timeout: .now() + 0.15), .timedOut,
                       "Deletion cannot pass a writer paused inside the same shared-file operation")
        workers.release.signal()
        XCTAssertEqual(workers.writeFinished.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(workers.deleteFinished.wait(timeout: .now() + 5), .success)
        XCTAssertTrue(workers.recordedErrors().isEmpty)
        XCTAssertNil(storage.read().snapshot)
        XCTAssertTrue(WidgetStorageVerificationStore(directory: directory, producer: producer).timelineReads().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("garden-widget-read-small-v1.json").path))
    }

    func testOldVerifiedReceiptIsIgnoredAfterSummaryDisappearsOrChangesDay() throws {
        let directory = folder()
        let storage = WidgetSnapshotStorage(directory: directory)
        let checks = WidgetStorageVerificationStore(directory: directory, producer: producer)
        try storage.write(snapshot())
        try checks.recordTimelineRead(family: "small", result: storage.read(), at: Date(), isPreview: false)
        XCTAssertEqual(checks.timelineReads().count, 1)
        try storage.write(snapshot(day: "2026-11-01"))
        XCTAssertTrue(checks.timelineReads().isEmpty)
        try storage.write(nil)
        XCTAssertTrue(checks.timelineReads().isEmpty)
    }

}
