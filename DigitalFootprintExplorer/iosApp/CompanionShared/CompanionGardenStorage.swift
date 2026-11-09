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

protocol CompanionGardenPersistence {
    func load(now: Date) throws -> CompanionGardenEnvelope?
    func save(_ envelope: CompanionGardenEnvelope, now: Date) throws
}

// [01] The Watch app and its complications share one small local file. App Groups do not copy files between devices.
struct CompanionGardenStorage: CompanionGardenPersistence {
    static let fileName = "phone-garden-companion-v1.json"
    let directory: URL

    init(directory: URL) { self.directory = directory }

    static func watchGroup(bundle: Bundle = .main, fileManager: FileManager = .default) throws -> Self {
        #if os(iOS) || os(watchOS)
        guard let identifier = bundle.object(forInfoDictionaryKey: "DFEWatchAppGroupIdentifier") as? String,
              identifier.hasPrefix("group."), !identifier.contains("$("),
              let directory = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw CompanionGardenError.storageUnavailable
        }
        return Self(directory: directory)
        #else
        throw CompanionGardenError.storageUnavailable
        #endif
    }

    func load(now: Date = Date()) throws -> CompanionGardenEnvelope? {
        try loadInbox(now: now).envelope
    }

    func loadInbox(now: Date = Date()) throws -> CompanionGardenInbox {
        let path = directory.appendingPathComponent(Self.fileName)
        guard FileManager.default.fileExists(atPath: path.path) else { return CompanionGardenInbox() }
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        guard let size = attributes[.size] as? NSNumber,
              size.intValue <= CompanionGardenEnvelope.maximumBytes else {
            throw CompanionGardenError.oversizedPayload
        }
        let data = try Data(contentsOf: path)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        if let inbox = try? decoder.decode(CompanionGardenInbox.self, from: data) {
            guard inbox.cacheVersion == 1 else { throw CompanionGardenError.unsupportedVersion }
            guard !inbox.requiresInteractiveResume || inbox.envelope?.snapshot == nil else {
                throw CompanionGardenError.invalidEnvelope
            }
            try inbox.envelope?.validate(now: now)
            return inbox
        }
        // [03] Accept an older one-result file without weakening the new local ordering guard.
        return CompanionGardenInbox(envelope: try CompanionGardenEnvelope.decode(data, now: now))
    }

    func save(_ envelope: CompanionGardenEnvelope, now: Date = Date()) throws {
        let data = try envelope.encoded(now: now)
        try write(data)
    }

    func saveInbox(_ inbox: CompanionGardenInbox, now: Date = Date()) throws {
        guard inbox.cacheVersion == 1 else { throw CompanionGardenError.unsupportedVersion }
        guard !inbox.requiresInteractiveResume || inbox.envelope?.snapshot == nil else {
            throw CompanionGardenError.invalidEnvelope
        }
        try inbox.envelope?.validate(now: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(inbox)
        guard data.count <= CompanionGardenEnvelope.maximumBytes else { throw CompanionGardenError.oversizedPayload }
        try write(data)
    }

    // [04] Replacing a file can need spare disk space. A small in-place blocked record also prevents the old amount being read after a failed clear.
    func invalidateSavedResult() throws {
        let path = directory.appendingPathComponent(Self.fileName)
        let data = try JSONEncoder().encode(CompanionGardenInbox.blocked)
        guard FileManager.default.fileExists(atPath: path.path) else { try write(data); return }
        let file = try FileHandle(forWritingTo: path)
        defer { try? file.close() }
        try file.truncate(atOffset: 0)
        try file.write(contentsOf: data)
        try file.synchronize()
    }

    private func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // [02] Atomic replacement keeps a complication from reading half a result. Protection allows updates after the first unlock.
        #if os(iOS) || os(watchOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                              ofItemAtPath: directory.path)
        try data.write(to: directory.appendingPathComponent(Self.fileName),
                       options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
        #endif
    }
}
