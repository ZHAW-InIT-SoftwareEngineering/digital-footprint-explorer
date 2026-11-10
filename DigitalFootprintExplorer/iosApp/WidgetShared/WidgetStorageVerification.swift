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

// [01] A successful file check, an empty garden and a broken read need different explanations.
enum WidgetVerificationStatus: String, Codable, Equatable, Sendable {
    case verified, empty, unavailable, unreadable, mismatch, writeFailed
}

// [02] A development or simulator check must never look like evidence from a later release.
struct WidgetVerificationProducer: Codable, Equatable, Sendable {
    let build: String
    let configuration: String
    let isSimulator: Bool

    static var current: Self {
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif
        return Self(build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                    configuration: configuration, isSimulator: simulator)
    }
}

// [03] Keep dates and fixed status words only. The garden's values stay in its protected summary.
struct WidgetPublicationVerification: Codable, Equatable, Sendable {
    let status: WidgetVerificationStatus
    let day: String?
    let checkedAt: Date
    let publishedAt: Date?
    let producer: WidgetVerificationProducer
    var receiptStored = true
}

struct WidgetTimelineReadCheck: Codable, Equatable, Sendable {
    let family: String
    let status: WidgetVerificationStatus
    let day: String?
    let readAt: Date
    let producer: WidgetVerificationProducer
}

// [04] Each widget size has its own small file, so two extension processes cannot replace each other's check.
struct WidgetStorageVerificationStore {
    let directory: URL?
    var producer: WidgetVerificationProducer = .current
    static let publicationFile = "garden-widget-check-v1.json"
    static let families = ["small", "medium"]
    #if DEBUG
    var beforeTimelineReceiptWrite: (() -> Void)? = nil
    #endif

    private struct Envelope<Value: Codable>: Codable {
        let version: Int
        let check: Value
        init(_ check: Value) { version = 1; self.check = check }
    }

    func publication() -> WidgetPublicationVerification? {
        guard let value: WidgetPublicationVerification = read(Self.publicationFile),
              value.producer == producer, value.receiptStored, valid(value.day), valid(value.checkedAt),
              value.publishedAt.map(valid) ?? true,
              value.status != .verified || value.day != nil,
              value.status != .empty || value.day == nil else { return nil }
        return value
    }

    func timelineReads() -> [WidgetTimelineReadCheck] {
        let currentDay = WidgetSnapshotStorage(directory: directory).read().snapshot?.day
        return Self.families.compactMap { family in
            guard let value: WidgetTimelineReadCheck = read(file(for: family)),
                  value.family == family, value.producer == producer,
                  valid(value.day), valid(value.readAt),
                  value.status != .verified || (value.day != nil && value.day == currentDay),
                  value.status != .empty || value.day == nil,
                  [WidgetVerificationStatus.verified, .empty, .unavailable, .unreadable].contains(value.status) else { return nil }
            return value
        }
    }

    func recordPublication(_ check: WidgetPublicationVerification) throws {
        try withExclusiveAccess { try $0.recordPublicationDuringCoordinatedAccess(check) }
    }

    func recordPublicationDuringCoordinatedAccess(_ check: WidgetPublicationVerification) throws {
        guard check.producer == producer, check.receiptStored, valid(check.day), valid(check.checkedAt),
              check.publishedAt.map(valid) ?? true,
              check.status != .verified || check.day != nil,
              check.status != .empty || check.day == nil else { throw WidgetSnapshotError.invalidData }
        try write(Envelope(check), name: Self.publicationFile)
    }

    // [05] Gallery work is an example, not proof that a Home Screen widget read a real saved day.
    @discardableResult
    func recordTimelineRead(family: String, result: WidgetSnapshotReadResult,
                            at date: Date, isPreview: Bool) throws -> Bool {
        guard !isPreview, Self.families.contains(family) else { return false }
        guard valid(date) else { throw WidgetSnapshotError.invalidData }
        return try withExclusiveAccess { checks in
            try checks.recordTimelineReadDuringCoordinatedAccess(family: family, result: result, at: date)
        }
    }

    private func recordTimelineReadDuringCoordinatedAccess(family: String, result: WidgetSnapshotReadResult,
                                                          at date: Date) throws -> Bool {
        // [08] The person may delete or replace the garden while a timeline is being prepared.
        // Do not keep a successful check for a result that has already disappeared.
        guard sameRead(result, WidgetSnapshotStorage(directory: directory).read()) else { return false }
        let status: WidgetVerificationStatus
        let day: String?
        switch result {
        case .saved(let snapshot):
            try snapshot.validate()
            status = .verified
            day = snapshot.day
        case .empty: status = .empty; day = nil
        case .unavailable: status = .unavailable; day = nil
        case .unreadable: status = .unreadable; day = nil
        }
        #if DEBUG
        beforeTimelineReceiptWrite?()
        #endif
        try write(Envelope(WidgetTimelineReadCheck(family: family, status: status, day: day,
                                                  readAt: date, producer: producer)), name: file(for: family))
        return true
    }

    // [06] Delete only our three check files. Clearing a garden must not leave an old verified day behind.
    @discardableResult
    func clear() throws -> Bool {
        guard directory != nil else { return false }
        return try withExclusiveAccess { try $0.clearDuringCoordinatedAccess() }
    }

    func clearDuringCoordinatedAccess() throws -> Bool {
        guard let directory else { return false }
        var removed = false
        for name in [Self.publicationFile] + Self.families.map({ file(for: $0) }) {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                removed = true
            }
        }
        return removed
    }

    // [09] The app and both widget processes take the same short turn before touching shared files.
    // No presenters or asynchronous work are kept inside this section.
    func withExclusiveAccess<Value>(_ operation: (WidgetStorageVerificationStore) throws -> Value) throws -> Value {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Value, Error>?
        coordinator.coordinate(writingItemAt: directory, options: [], error: &coordinationError) { actualDirectory in
            var checks = self
            // Apple may adjust the URL while coordinating. Use that directory for every operation.
            checks = WidgetStorageVerificationStore(directory: actualDirectory, producer: producer)
            #if DEBUG
            checks.beforeTimelineReceiptWrite = beforeTimelineReceiptWrite
            #endif
            result = Result { try operation(checks) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }

    private func sameRead(_ observed: WidgetSnapshotReadResult, _ current: WidgetSnapshotReadResult) -> Bool {
        switch (observed, current) {
        case (.empty, .empty), (.unavailable, .unavailable), (.unreadable, .unreadable): return true
        case (.saved(let left), .saved(let right)):
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            guard let lhs = try? encoder.encode(left), let rhs = try? encoder.encode(right) else { return false }
            return lhs == rhs
        default: return false
        }
    }

    private func file(for family: String) -> String { "garden-widget-read-\(family)-v1.json" }

    private func read<Value: Codable>(_ name: String) -> Value? {
        guard let directory else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try decoder.decode(Envelope<Value>.self,
                from: Data(contentsOf: directory.appendingPathComponent(name)))
            return envelope.version == 1 ? envelope.check : nil
        } catch { return nil }
    }

    private func write<Value: Encodable>(_ value: Value, name: String) throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        // [07] After the first unlock, a real background read can still save its small date stamp.
        try data.write(to: directory.appendingPathComponent(name),
                       options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func valid(_ date: Date) -> Bool { date.timeIntervalSince1970.isFinite }

    private func valid(_ day: String?) -> Bool {
        guard let day else { return true }
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard day.count == 10, parts.count == 3 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) else { return false }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", actual.year!, actual.month!, actual.day!) == day
    }
}
