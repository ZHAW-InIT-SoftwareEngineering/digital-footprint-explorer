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

enum WidgetAutomaticReceiptStoreError: Error { case unavailable, invalidReceipt }

// [01] Two widget processes may finish the same day in a different order.
// Keep proof of the saved day instead of replacing it with the losing query's later error.
struct WidgetAutomaticReceiptStore {
    let directory: URL?
    var producer: WidgetVerificationProducer = .current
    private static let maximumBytes = 32 * 1_024

    func latest() throws -> WidgetAutomaticReceipt? {
        guard directory != nil else { throw WidgetAutomaticReceiptStoreError.unavailable }
        return try WidgetStorageVerificationStore(directory: directory, producer: producer).withExclusiveAccess { checks in
            try WidgetAutomaticReceiptStore(directory: checks.directory, producer: producer).readDuringCoordinatedAccess()
        }
    }

    @discardableResult
    func save(_ receipt: WidgetAutomaticReceipt, contextEpoch: UUID? = nil) throws -> Bool {
        guard directory != nil else { throw WidgetAutomaticReceiptStoreError.unavailable }
        try Self.validate(receipt)
        return try WidgetStorageVerificationStore(directory: directory, producer: producer).withExclusiveAccess { checks in
            let store = WidgetAutomaticReceiptStore(directory: checks.directory, producer: producer)
            // [05] Check the original ticket while saving, including after automatic updates resume.
            guard try WidgetAutomaticExchange(directory: checks.directory, producer: producer)
                .allowsReceiptDuringCoordinatedAccess(contextEpoch: contextEpoch) else { return false }
            // [02] A damaged technical note must not block fresh evidence. This does not change a garden or history file.
            if let previous = try? store.readDuringCoordinatedAccess(), Self.shouldKeep(previous, insteadOf: receipt) {
                return false
            }
            guard let directory = store.directory else { throw WidgetAutomaticReceiptStoreError.unavailable }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(receipt)
            guard data.count <= Self.maximumBytes else { throw WidgetAutomaticReceiptStoreError.invalidReceipt }
            try data.write(to: directory.appendingPathComponent(WidgetAutomaticReceipt.fileName),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        }
    }

    static func shouldKeep(_ previous: WidgetAutomaticReceipt,
                           insteadOf incoming: WidgetAutomaticReceipt) -> Bool {
        // [03] A failure from a new build should remain visible. Old success cannot approve another version.
        guard previous.build == incoming.build, previous.sourceRevision == incoming.sourceRevision,
              previous.configuration == incoming.configuration, previous.isSimulator == incoming.isSimulator,
              let previousDay = previous.day, let incomingDay = incoming.day,
              previous.pendingSaved else { return false }
        if incomingDay < previousDay { return true }
        guard incomingDay == previousDay else { return false }
        if !incoming.pendingSaved { return true }
        // [04] Both succeeded. Keep the later recorded save, within this format's whole-second precision.
        if let old = previous.savedAt, let new = incoming.savedAt {
            let oldSecond = old.timeIntervalSince1970.rounded(.down)
            let newSecond = new.timeIntervalSince1970.rounded(.down)
            if newSecond != oldSecond { return newSecond < oldSecond }
        }
        return incoming.finishedAt.timeIntervalSince1970.rounded(.down)
            <= previous.finishedAt.timeIntervalSince1970.rounded(.down)
    }

    private func readDuringCoordinatedAccess() throws -> WidgetAutomaticReceipt? {
        guard let directory else { throw WidgetAutomaticReceiptStoreError.unavailable }
        let file = directory.appendingPathComponent(WidgetAutomaticReceipt.fileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= Self.maximumBytes else {
            throw WidgetAutomaticReceiptStoreError.invalidReceipt
        }
        let data = try Data(contentsOf: file)
        guard data.count <= Self.maximumBytes else { throw WidgetAutomaticReceiptStoreError.invalidReceipt }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let receipt = try decoder.decode(WidgetAutomaticReceipt.self, from: data)
        try Self.validate(receipt)
        return receipt
    }

    private static func validate(_ receipt: WidgetAutomaticReceipt) throws {
        let dates = [receipt.queryStartedAt, receipt.finishedAt, receipt.savedAt].compactMap { $0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let validDay = receipt.day.map { FootprintCalendar(calendar: calendar).date($0) != nil } ?? true
        guard receipt.formatVersion == 1, validDay, receipt.elapsedMillis >= 0,
              dates.allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              !receipt.sourceRevision.isEmpty, receipt.sourceRevision.count <= 256,
              !receipt.build.isEmpty, receipt.build.count <= 128,
              !receipt.configuration.isEmpty, receipt.configuration.count <= 128,
              receipt.runtime.count <= 256,
              receipt.queryStartedAt.map({ $0 <= receipt.finishedAt.addingTimeInterval(1) }) ?? true,
              receipt.savedAt.map({ $0 <= receipt.finishedAt.addingTimeInterval(1) }) ?? true else {
            throw WidgetAutomaticReceiptStoreError.invalidReceipt
        }
        let savedStatus = receipt.status == .pendingSaved || receipt.status == .pendingSavedSnapshotPending
        guard savedStatus == receipt.pendingSaved,
              !receipt.pendingSaved || (receipt.savedAt != nil && receipt.queryStartedAt != nil
                  && receipt.day != nil && receipt.calculationSucceeded),
              receipt.pendingSaved || receipt.savedAt == nil else {
            throw WidgetAutomaticReceiptStoreError.invalidReceipt
        }
    }
}
