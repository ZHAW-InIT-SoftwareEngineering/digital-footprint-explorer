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

import Foundation
import Combine

// [01] These labels describe how an update started, without recording which apps were used.
enum AutomaticUpdateOrigin: String, Codable, Sendable {
    case foreground, backgroundRefresh, backgroundProcessing
}

// [13] A background request can finish after the person opens DFE.
// Keep the app's state at the save separate from the request that started it.
enum AutomaticUpdateCompletionState: String, Codable, Sendable {
    case active, inactive, background, unknown
}

// [02] Keep a development run separate from evidence collected by a later beta.
// The stamp describes DFE itself; it has no phone, account or signing identifiers.
struct AutomaticVerificationProducer: Codable, Equatable, Sendable {
    let appVersion: String
    let appBuild: String
    let isDebug: Bool
    let isSimulator: Bool

    static var current: AutomaticVerificationProducer {
        #if DEBUG
        let debug = true
        #else
        let debug = false
        #endif
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif
        return AutomaticVerificationProducer(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            isDebug: debug, isSimulator: simulator)
    }
}

// [03] A later check must not erase the first save we actually observed.
// Older imported days keep their original import time unknown.
struct VerifiedAutomaticSave: Codable, Equatable, Sendable {
    let day: String
    let firstObservedAt: Date
    let lastObservedAt: Date
    let firstOrigin: AutomaticUpdateOrigin
    let lastOrigin: AutomaticUpdateOrigin
    let firstCompletionState: AutomaticUpdateCompletionState
    let lastCompletionState: AutomaticUpdateCompletionState
    let initialSaveObserved: Bool
    let firstProducer: AutomaticVerificationProducer
    let lastProducer: AutomaticVerificationProducer
}

@MainActor
// [04] This small local record answers when a successful save was observed.
// Usage amounts and garden values stay in the protected history, outside this file.
final class AutomaticUpdateVerification: ObservableObject {
    static let maximumRecords = 32
    @Published private(set) var records: [VerifiedAutomaticSave] = []
    @Published private(set) var persistenceFailed = false

    private let fileURL: URL
    private let clock: () -> Date
    private let producer: AutomaticVerificationProducer

    private struct Envelope: Codable {
        let schemaVersion: Int
        let records: [VerifiedAutomaticSave]
    }

    init(fileURL: URL, clock: @escaping () -> Date = Date.init,
         producer: AutomaticVerificationProducer = .current) {
        self.fileURL = fileURL
        self.clock = clock
        self.producer = producer
        load()
    }

    func record(for day: String) -> VerifiedAutomaticSave? {
        records.first { $0.day == day }
    }

    // [05] Call this only after the history save succeeds. Reading the clock here avoids
    // reporting the earlier query start as the time that the result became available.
    func recordSuccessfulSave(day: String, wasAlreadyImported: Bool, origin: AutomaticUpdateOrigin,
                              completionState: AutomaticUpdateCompletionState = .unknown) {
        let observedAt = clock()
        guard Self.validDay(day), Self.validDate(observedAt), Self.validProducer(producer) else {
            persistenceFailed = true
            return
        }
        let previous = record(for: day)
        // [06] If the phone clock moves backwards, keep the known record rather than inventing a later time.
        guard previous.map({ observedAt >= $0.lastObservedAt }) ?? true else {
            persistenceFailed = true
            return
        }
        let saved = VerifiedAutomaticSave(day: day,
            firstObservedAt: previous?.firstObservedAt ?? observedAt,
            lastObservedAt: observedAt,
            firstOrigin: previous?.firstOrigin ?? origin,
            lastOrigin: origin,
            firstCompletionState: previous?.firstCompletionState ?? completionState,
            lastCompletionState: completionState,
            initialSaveObserved: previous?.initialSaveObserved ?? !wasAlreadyImported,
            firstProducer: previous?.firstProducer ?? producer, lastProducer: producer)
        var next = records.filter { $0.day != day }
        next.append(saved)
        next.sort { $0.day < $1.day }
        // [07] Keep recent verification dates only. This is not another copy of the person's history.
        next = Array(next.suffix(Self.maximumRecords))
        do {
            try save(next)
            records = next
            persistenceFailed = false
        } catch {
            // [08] The daily result is already saved. A failed technical note must not undo it
            // or appear in memory as though it had been stored successfully.
            persistenceFailed = true
        }
    }

    // [09] Delete this note with the saved entries. A failed removal stays visible to the caller.
    func clear() throws {
        do {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) {
                guard !isDirectory.boolValue else { throw CocoaError(.fileWriteUnknown) }
                try FileManager.default.removeItem(at: fileURL)
            }
            records = []
            persistenceFailed = false
        } catch {
            persistenceFailed = true
            throw error
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            guard data.count <= 65_536, Self.knownShape(data) else { throw CocoaError(.fileReadCorruptFile) }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let envelope = try decoder.decode(Envelope.self, from: data)
            let loaded = envelope.records
            guard envelope.schemaVersion == 1, loaded.count <= Self.maximumRecords,
                  loaded.map(\.day) == loaded.map(\.day).sorted(),
                  Set(loaded.map(\.day)).count == loaded.count,
                  loaded.allSatisfy(Self.validRecord) else { throw CocoaError(.fileReadCorruptFile) }
            records = loaded
        } catch {
            // [10] Unknown or damaged notes cannot prove an import time. A later real save
            // may start new observations, without rebuilding dates from the history file.
            records = []
            persistenceFailed = true
        }
    }

    private func save(_ next: [VerifiedAutomaticSave]) throws {
        guard fileURL.isFileURL else { throw CocoaError(.fileWriteUnknown) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Envelope(schemaVersion: 1, records: next))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        // [11] Morning updates can save after the phone's first unlock, without leaving an unprotected copy.
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
    }

    private static func validRecord(_ value: VerifiedAutomaticSave) -> Bool {
        validDay(value.day) && validDate(value.firstObservedAt) && validDate(value.lastObservedAt)
            && value.firstObservedAt <= value.lastObservedAt
            && validProducer(value.firstProducer) && validProducer(value.lastProducer)
    }

    private static func validDate(_ value: Date) -> Bool {
        value.timeIntervalSince1970.isFinite
    }

    private static func validProducer(_ value: AutomaticVerificationProducer) -> Bool {
        [value.appVersion, value.appBuild].allSatisfy { text in
            !text.isEmpty && text.utf8.count <= 64
                && text.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
        }
    }

    private static func validDay(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in index == 4 || index == 7 || (48...57).contains(byte) }) else { return false }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 0 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) else { return false }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        return actual.year == parts[0] && actual.month == parts[1] && actual.day == parts[2]
    }

    // [12] Accept only the fields this feature writes. Unexpected payloads must not be
    // treated as a safe technical record that can be shared for testing.
    private static func knownShape(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == ["schemaVersion", "records"], let values = root["records"] as? [[String: Any]] else { return false }
        let recordKeys: Set<String> = ["day", "firstObservedAt", "lastObservedAt", "firstOrigin", "lastOrigin", "firstCompletionState", "lastCompletionState", "initialSaveObserved", "firstProducer", "lastProducer"]
        let producerKeys: Set<String> = ["appVersion", "appBuild", "isDebug", "isSimulator"]
        return values.allSatisfy { value in
            guard Set(value.keys) == recordKeys,
                  let first = value["firstProducer"] as? [String: Any],
                  let last = value["lastProducer"] as? [String: Any] else { return false }
            return Set(first.keys) == producerKeys && Set(last.keys) == producerKeys
        }
    }
}
