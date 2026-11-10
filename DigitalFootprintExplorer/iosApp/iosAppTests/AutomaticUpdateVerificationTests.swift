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

@MainActor
final class AutomaticUpdateVerificationTests: XCTestCase {
    private let release = AutomaticVerificationProducer(appVersion: "1.0", appBuild: "2", isDebug: false, isSimulator: false)
    private let development = AutomaticVerificationProducer(appVersion: "1.0", appBuild: "1", isDebug: true, isSimulator: true)

    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private func file() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("automatic-update-verification.json")
    }

    // [01] A receipt takes its time when the successful save is reported, not when the service was created.
    func testReadsActualClockOnlyWhenSuccessfulSaveIsReported() throws {
        let url = try file()
        var now = date("2026-11-01T07:00:00Z")
        var reads = 0
        let verification = AutomaticUpdateVerification(fileURL: url, clock: { reads += 1; return now }, producer: release)
        XCTAssertEqual(reads, 0)
        now = date("2026-11-01T07:00:19Z")

        verification.recordSuccessfulSave(day: "2026-10-31", wasAlreadyImported: false, origin: .backgroundRefresh)

        let saved = try XCTUnwrap(verification.record(for: "2026-10-31"))
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(saved.firstObservedAt, now)
        XCTAssertEqual(saved.lastObservedAt, now)
        XCTAssertTrue(saved.initialSaveObserved)
        XCTAssertEqual(saved.firstOrigin, .backgroundRefresh)
        XCTAssertFalse(verification.persistenceFailed)
    }

    // [02] Opening the app later must not erase the earlier background evidence.
    func testForegroundRefreshPreservesFirstBackgroundObservationAcrossRelaunch() throws {
        let url = try file()
        let morning = date("2026-11-01T07:12:46Z")
        let first = AutomaticUpdateVerification(fileURL: url, clock: { morning }, producer: release)
        first.recordSuccessfulSave(day: "2026-10-31", wasAlreadyImported: false, origin: .backgroundProcessing,
                                   completionState: .background)
        let afternoon = date("2026-11-01T12:20:25Z")
        let reopened = AutomaticUpdateVerification(fileURL: url, clock: { afternoon }, producer: release)

        reopened.recordSuccessfulSave(day: "2026-10-31", wasAlreadyImported: true, origin: .foreground,
                                      completionState: .active)

        let saved = try XCTUnwrap(reopened.record(for: "2026-10-31"))
        XCTAssertEqual(saved.firstObservedAt, morning)
        XCTAssertEqual(saved.lastObservedAt, afternoon)
        XCTAssertEqual(saved.firstOrigin, .backgroundProcessing)
        XCTAssertEqual(saved.lastOrigin, .foreground)
        XCTAssertEqual(saved.firstCompletionState, .background)
        XCTAssertEqual(saved.lastCompletionState, .active)
        XCTAssertTrue(saved.initialSaveObserved)
        XCTAssertEqual(reopened.records.count, 1)
    }

    // [12] A task that began in the background is not proof that its save also happened there.
    func testBackgroundOriginCanFinishWhileTheAppIsActive() throws {
        let now = date("2026-11-01T12:20:25Z")
        let verification = AutomaticUpdateVerification(fileURL: try file(), clock: { now }, producer: release)

        verification.recordSuccessfulSave(day: "2026-10-31", wasAlreadyImported: false,
            origin: .backgroundRefresh, completionState: .active)

        let saved = try XCTUnwrap(verification.record(for: "2026-10-31"))
        XCTAssertEqual(saved.firstOrigin, .backgroundRefresh)
        XCTAssertEqual(saved.lastOrigin, .backgroundRefresh)
        XCTAssertEqual(saved.firstCompletionState, .active)
        XCTAssertEqual(saved.lastCompletionState, .active)
    }

    // [03] A day saved by an older build has no verified original time. Later checks must keep that distinction.
    func testExistingImportedDayStartsWithOriginalImportTimeUnknown() throws {
        let now = date("2026-11-01T12:20:25Z")
        let verification = AutomaticUpdateVerification(fileURL: try file(), clock: { now }, producer: release)
        verification.recordSuccessfulSave(day: "2026-10-31", wasAlreadyImported: true, origin: .foreground)
        XCTAssertFalse(try XCTUnwrap(verification.record(for: "2026-10-31")).initialSaveObserved)

        verification.recordSuccessfulSave(day: "2026-10-31", wasAlreadyImported: false, origin: .backgroundRefresh)

        let saved = try XCTUnwrap(verification.record(for: "2026-10-31"))
        XCTAssertFalse(saved.initialSaveObserved, "A later caller cannot turn an unknown first import into a known one")
        XCTAssertEqual(saved.firstOrigin, .foreground)
        XCTAssertEqual(saved.firstObservedAt, now)
    }

    // [04] Build stamps keep a development save from being presented as a first save in a later beta.
    func testProducerStampsRemainSeparateAcrossAnUpgrade() throws {
        let url = try file()
        let firstTime = date("2026-11-01T07:12:46Z")
        let oldBuild = AutomaticUpdateVerification(fileURL: url, clock: { firstTime }, producer: development)
        oldBuild.recordSuccessfulSave(day: "2026-10-31", wasAlreadyImported: false, origin: .backgroundRefresh)
        let later = date("2026-11-01T12:20:25Z")
        let beta = AutomaticUpdateVerification(fileURL: url, clock: { later }, producer: release)
        beta.recordSuccessfulSave(day: "2026-10-31", wasAlreadyImported: true, origin: .foreground)

        let saved = try XCTUnwrap(beta.record(for: "2026-10-31"))
        XCTAssertEqual(saved.firstProducer, development)
        XCTAssertEqual(saved.lastProducer, release)
        XCTAssertEqual(saved.firstObservedAt, firstTime)
        XCTAssertEqual(saved.lastObservedAt, later)
    }

    // [05] The local record should contain only the date, timing, origin and DFE's own build details.
    func testPersistedFieldsContainNoUsageOrGardenPayload() throws {
        let url = try file()
        let now = date("2026-11-01T07:12:46Z")
        let verification = AutomaticUpdateVerification(fileURL: url, clock: { now }, producer: release)
        verification.recordSuccessfulSave(day: "2026-10-31", wasAlreadyImported: false, origin: .backgroundRefresh)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(Set(root.keys), ["schemaVersion", "records"])
        let saved = try XCTUnwrap((root["records"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(saved.keys), ["day", "firstObservedAt", "lastObservedAt", "firstOrigin", "lastOrigin", "firstCompletionState", "lastCompletionState", "initialSaveObserved", "firstProducer", "lastProducer"])
        for key in ["firstProducer", "lastProducer"] {
            let stamp = try XCTUnwrap(saved[key] as? [String: Any])
            XCTAssertEqual(Set(stamp.keys), ["appVersion", "appBuild", "isDebug", "isSimulator"])
        }
        let reopened = AutomaticUpdateVerification(fileURL: url, producer: release)
        XCTAssertEqual(reopened.records, verification.records)
        XCTAssertFalse(reopened.persistenceFailed)
    }

    // [06] A technical write can fail while the daily result remains valid. Do not display a receipt that was never saved.
    func testWriteFailureDoesNotPublishAnUnsavedSuccess() throws {
        let url = try file()
        let blockedParent = url.deletingLastPathComponent().appendingPathComponent("blocked")
        let original = Data("not a folder".utf8)
        try original.write(to: blockedParent)
        let now = date("2026-11-01T07:12:46Z")
        let verification = AutomaticUpdateVerification(fileURL: blockedParent.appendingPathComponent("verification.json"),
            clock: { now }, producer: release)

        verification.recordSuccessfulSave(day: "2026-10-31", wasAlreadyImported: false, origin: .backgroundRefresh)

        XCTAssertTrue(verification.persistenceFailed)
        XCTAssertTrue(verification.records.isEmpty)
        XCTAssertNil(verification.record(for: "2026-10-31"))
        XCTAssertEqual(try Data(contentsOf: blockedParent), original)
    }

    func testLaterWriteFailureKeepsTheEarlierVerifiedRecord() throws {
        let url = try file()
        let now = date("2026-11-01T07:12:46Z")
        let verification = AutomaticUpdateVerification(fileURL: url, clock: { now }, producer: release)
        verification.recordSuccessfulSave(day: "2026-10-31", wasAlreadyImported: false, origin: .backgroundRefresh)
        let original = verification.records
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let sentinel = url.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)

        verification.recordSuccessfulSave(day: "2026-11-01", wasAlreadyImported: false, origin: .foreground)

        XCTAssertTrue(verification.persistenceFailed)
        XCTAssertEqual(verification.records, original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
    }

    // [07] A damaged note is not evidence. A newly observed save may repair it without inventing earlier dates.
    func testCorruptFileIsRejectedThenReplacedOnlyByANewObservation() throws {
        let url = try file()
        let corrupt = Data("damaged technical note".utf8)
        try corrupt.write(to: url)
        let now = date("2026-11-01T12:20:25Z")
        let verification = AutomaticUpdateVerification(fileURL: url, clock: { now }, producer: release)
        XCTAssertTrue(verification.persistenceFailed)
        XCTAssertTrue(verification.records.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), corrupt)

        verification.recordSuccessfulSave(day: "2026-10-31", wasAlreadyImported: true, origin: .foreground)

        let saved = try XCTUnwrap(verification.record(for: "2026-10-31"))
        XCTAssertEqual(saved.firstObservedAt, now)
        XCTAssertFalse(saved.initialSaveObserved)
        XCTAssertFalse(verification.persistenceFailed)
        XCTAssertEqual(AutomaticUpdateVerification(fileURL: url, producer: release).records, verification.records)
    }

    // [08] Bad dates and unexpected fields must not survive as apparently valid timing evidence.
    func testInvalidStoredRecordsAreRejectedWithoutChangingTheirFiles() throws {
        let originalURL = try file()
        let now = date("2026-11-01T12:20:25Z")
        let seed = AutomaticUpdateVerification(fileURL: originalURL, clock: { now }, producer: release)
        seed.recordSuccessfulSave(day: "2026-10-31", wasAlreadyImported: false, origin: .backgroundRefresh)
        let valid = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: originalURL)) as? [String: Any])
        let record = try XCTUnwrap((valid["records"] as? [[String: Any]])?.first)
        var cases: [(String, [String: Any])] = []
        var value = valid
        value["schemaVersion"] = 2
        cases.append(("unsupported schema", value))
        for badDay in ["2026-02-30", "2026-13-01", "0000-01-01", "2026-1-01", "٢٠٢٦-١٠-٣١"] {
            var changed = record
            changed["day"] = badDay
            value = valid
            value["records"] = [changed]
            cases.append((badDay, value))
        }
        var reversed = record
        reversed["firstObservedAt"] = (now.timeIntervalSince1970 + 10) * 1_000
        value = valid
        value["records"] = [reversed]
        cases.append(("reversed times", value))
        value = valid
        value["records"] = [record, record]
        cases.append(("duplicate days", value))
        var earlier = record
        earlier["day"] = "2026-10-30"
        value = valid
        value["records"] = [record, earlier]
        cases.append(("unsorted days", value))
        let tooManyDays = ["2026-09-30"] + (1...31).map { String(format: "2026-10-%02d", $0) } + ["2026-11-01"]
        value = valid
        value["records"] = tooManyDays.map { day -> [String: Any] in
            var changed = record
            changed["day"] = day
            return changed
        }
        cases.append(("more than 32 stored days", value))
        value = valid
        value["history"] = []
        cases.append(("unexpected root field", value))
        var extra = record
        extra["usageMinutes"] = 42
        value = valid
        value["records"] = [extra]
        cases.append(("unexpected private field", value))
        var wrongProducer = record
        wrongProducer["lastProducer"] = ["appVersion": "1.0", "appBuild": "", "isDebug": false, "isSimulator": false]
        value = valid
        value["records"] = [wrongProducer]
        cases.append(("invalid build stamp", value))
        var wrongCompletion = record
        wrongCompletion["lastCompletionState"] = "running"
        value = valid
        value["records"] = [wrongCompletion]
        cases.append(("invalid completion state", value))

        for (name, contents) in cases {
            let url = try file()
            let bytes = try JSONSerialization.data(withJSONObject: contents, options: [.sortedKeys])
            try bytes.write(to: url)
            let verification = AutomaticUpdateVerification(fileURL: url, producer: release)
            XCTAssertTrue(verification.persistenceFailed, name)
            XCTAssertTrue(verification.records.isEmpty, name)
            XCTAssertEqual(try Data(contentsOf: url), bytes, name)
        }
    }

    // [09] Only the most recent 32 days belong in this small verification file.
    func testRetentionKeepsTheLatestDaysEvenWhenBackfillArrivesLater() throws {
        let url = try file()
        let now = date("2026-11-10T12:00:00Z")
        let verification = AutomaticUpdateVerification(fileURL: url, clock: { now }, producer: release)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let start = date("2026-10-01T12:00:00Z")
        let days = (0..<40).map { formatter.string(from: calendar.date(byAdding: .day, value: $0, to: start)!) }
        for day in days.reversed() {
            verification.recordSuccessfulSave(day: day, wasAlreadyImported: false, origin: .backgroundProcessing)
        }

        XCTAssertEqual(verification.records.map(\.day), Array(days.suffix(32)))
        XCTAssertNil(verification.record(for: days[0]))
        XCTAssertEqual(AutomaticUpdateVerification(fileURL: url, producer: release).records, verification.records)
    }

    // [10] A clock correction must not turn an earlier time into a claimed new verification.
    func testBackwardOrInvalidClockDoesNotReplaceKnownEvidence() throws {
        let url = try file()
        var now = date("2026-11-01T07:12:46Z")
        let verification = AutomaticUpdateVerification(fileURL: url, clock: { now }, producer: release)
        verification.recordSuccessfulSave(day: "2026-10-31", wasAlreadyImported: false, origin: .backgroundRefresh)
        let original = verification.records
        let bytes = try Data(contentsOf: url)
        now = date("2026-11-01T07:00:00Z")
        verification.recordSuccessfulSave(day: "2026-10-31", wasAlreadyImported: true, origin: .foreground)
        XCTAssertTrue(verification.persistenceFailed)
        XCTAssertEqual(verification.records, original)
        XCTAssertEqual(try Data(contentsOf: url), bytes)

        now = Date(timeIntervalSince1970: .infinity)
        verification.recordSuccessfulSave(day: "2026-11-01", wasAlreadyImported: false, origin: .foreground)
        XCTAssertTrue(verification.persistenceFailed)
        XCTAssertEqual(verification.records, original)
    }

    func testInvalidNewDayDoesNotCreateAReceipt() throws {
        let url = try file()
        let now = date("2026-11-01T07:12:46Z")
        let verification = AutomaticUpdateVerification(fileURL: url, clock: { now }, producer: release)
        verification.recordSuccessfulSave(day: "2026-02-30", wasAlreadyImported: false, origin: .backgroundRefresh)
        XCTAssertTrue(verification.persistenceFailed)
        XCTAssertTrue(verification.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // [11] Deleting entries should also remove their verification dates, including after reopening.
    func testClearRemovesTheStoredRecordAndResetsFailureState() throws {
        let url = try file()
        let now = date("2026-11-01T07:12:46Z")
        let verification = AutomaticUpdateVerification(fileURL: url, clock: { now }, producer: release)
        verification.recordSuccessfulSave(day: "2026-10-31", wasAlreadyImported: false, origin: .backgroundRefresh)
        verification.recordSuccessfulSave(day: "bad day", wasAlreadyImported: false, origin: .foreground)
        XCTAssertTrue(verification.persistenceFailed)

        try verification.clear()

        XCTAssertTrue(verification.records.isEmpty)
        XCTAssertFalse(verification.persistenceFailed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(AutomaticUpdateVerification(fileURL: url, producer: release).records.isEmpty)
    }

    func testFailedClearDoesNotClaimThatItsRecordWasRemoved() throws {
        let url = try file()
        let now = date("2026-11-01T07:12:46Z")
        let verification = AutomaticUpdateVerification(fileURL: url, clock: { now }, producer: release)
        verification.recordSuccessfulSave(day: "2026-10-31", wasAlreadyImported: false, origin: .backgroundRefresh)
        let original = verification.records
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)

        XCTAssertThrowsError(try verification.clear())

        XCTAssertTrue(verification.persistenceFailed)
        XCTAssertEqual(verification.records, original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
