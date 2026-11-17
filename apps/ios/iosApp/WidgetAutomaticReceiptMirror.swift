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

#if DFE_WIDGET_AUTOMATIC_IMPORT
import Foundation

// [01] Keep the widget's own saved time when the app opens later.
// Copy only the small technical receipt, never its pending category record or history.
enum WidgetAutomaticReceiptMirror {
    static let storageCheckFileName = "widget-automatic-storage-check-v1.json"

    // [04] Delete only these two technical copies, leaving unrelated documents alone.
    static func clearCopies(in documents: URL) throws {
        for name in [WidgetAutomaticReceipt.fileName, storageCheckFileName] {
            let file = documents.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
    }

    static func copyIfPresent() {
        guard let group = WidgetSnapshotStorage.configured().directory,
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        do {
            let source = group.appendingPathComponent(WidgetAutomaticReceipt.fileName)
            guard let length = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  (1..<16_384).contains(length) else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let receipt = try decoder.decode(WidgetAutomaticReceipt.self, from: Data(contentsOf: source))
            let producer = WidgetVerificationProducer.current
            let revision = WidgetAutomaticBuildIdentity.sourceRevision
            guard revision != "unavailable", receipt.formatVersion == 1, receipt.elapsedMillis >= 0,
                  receipt.finishedAt.timeIntervalSince1970.isFinite,
                  receipt.sourceRevision == revision, receipt.build == producer.build,
                  receipt.configuration == producer.configuration,
                  receipt.isSimulator == producer.isSimulator else { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(receipt).write(to: documents.appendingPathComponent(WidgetAutomaticReceipt.fileName),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #if os(iOS)
            // [03] Read the protection label on the real phone without copying the shared record.
            let state = group.appendingPathComponent(WidgetAutomaticExchange.fileName)
            let attributes = try FileManager.default.attributesOfItem(atPath: state.path)
            let protection = attributes[.protectionKey] as? FileProtectionType
            let check = StorageProtectionCheck(checkedAt: Date(),
                protectedUntilFirstUnlock: protection == .completeUntilFirstUserAuthentication)
            try encoder.encode(check).write(to: documents.appendingPathComponent(storageCheckFileName),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #endif
        } catch {
            // [02] A missing diagnostic must not prevent the app from opening or merging a saved day.
        }
    }

    private struct StorageProtectionCheck: Codable {
        let checkedAt: Date
        let protectedUntilFirstUnlock: Bool
    }
}
#endif
