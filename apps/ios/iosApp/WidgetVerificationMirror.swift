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

// [01] Keep a readable copy of the small checks in the app's own storage.
// The shared garden and its values are never copied into this file.
enum WidgetVerificationMirror {
    private struct Envelope: Encodable {
        let capturedAt: Date
        let publication: WidgetPublicationVerification?
        let timelineReads: [WidgetTimelineReadCheck]
        private enum CodingKeys: String, CodingKey { case version, capturedAt, publication, timelineReads }
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(1, forKey: .version)
            try values.encode(capturedAt, forKey: .capturedAt)
            if let publication { try values.encode(publication, forKey: .publication) }
            else { try values.encodeNil(forKey: .publication) }
            try values.encode(timelineReads, forKey: .timelineReads)
        }
    }

    static func write(to url: URL, publication: WidgetPublicationVerification?,
                      timelineReads: [WidgetTimelineReadCheck], at date: Date = Date()) throws {
        guard date.timeIntervalSince1970.isFinite, timelineReads.count <= 2,
              Set(timelineReads.map(\.family)).count == timelineReads.count,
              timelineReads.allSatisfy({ WidgetStorageVerificationStore.families.contains($0.family) }) else {
            throw WidgetSnapshotError.invalidData
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Envelope(capturedAt: date, publication: publication, timelineReads: timelineReads))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // [02] Clearing these checks must leave other saved files alone.
    static func clear(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard !isDirectory.boolValue else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.removeItem(at: url)
    }
}
