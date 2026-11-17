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

// [01] No saved result, a missing shared group and an unreadable file need different explanations.
enum WidgetSnapshotReadResult {
    case saved(GardenWidgetSnapshot)
    case empty
    case unavailable
    case unreadable
    var snapshot: GardenWidgetSnapshot? {
        if case .saved(let value) = self { return value }
        return nil
    }
}

/// [02] The widget reads a separate file and never opens the app's full archive.
struct WidgetSnapshotStorage {
    let directory: URL?
    var fileURL: URL? { directory?.appendingPathComponent("garden-widget-v1.json") }

    // [03] Reject an unfinished build setting instead of trying to open the wrong shared storage.
    static func appGroupIdentifier(bundle: Bundle = .main) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: "DFEAppGroupIdentifier") as? String,
              value.hasPrefix("group."), value.count > 6, !value.contains("$(") else { return nil }
        return value
    }

    // [04] Use only the shared group approved for this app and widget; do not fall back to the full history.
    static func configured(bundle: Bundle = .main) -> WidgetSnapshotStorage {
        let container = appGroupIdentifier(bundle: bundle).flatMap {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
        }
        return WidgetSnapshotStorage(directory: container)
    }

    // [05] Check the file format and saved values before presenting them.
    // An unreadable summary becomes an unavailable state, not a zero footprint.
    func read() -> WidgetSnapshotReadResult {
        guard let fileURL else { return .unavailable }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try decoder.decode(WidgetSnapshotEnvelope.self, from: Data(contentsOf: fileURL))
            guard envelope.version == 1 else { throw WidgetSnapshotError.unsupportedVersion }
            guard let snapshot = envelope.snapshot else { return .empty }
            try snapshot.validate()
            return .saved(snapshot)
        } catch { return .unreadable }
    }

    /// [06] Keep the newest saved summary, including its check time. The publisher separately
    /// decides whether this change needs a new garden timeline.
    @discardableResult
    func write(_ snapshot: GardenWidgetSnapshot?) throws -> Bool {
        guard let fileURL else { return false }
        guard let snapshot else {
            // [07] Remove the summary file directly, so deleting it still works when storage is full.
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }
            try FileManager.default.removeItem(at: fileURL)
            return true
        }
        try snapshot.validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(WidgetSnapshotEnvelope(snapshot: snapshot))
        if (try? Data(contentsOf: fileURL)) == data { return false }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // [08] Until the first unlock, a widget can safely show its unavailable state.
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return true
    }
}
