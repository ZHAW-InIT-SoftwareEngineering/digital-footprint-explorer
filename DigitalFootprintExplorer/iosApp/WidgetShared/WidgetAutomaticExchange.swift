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
import CryptoKit

struct WidgetAutomaticBaseline: Codable, Equatable {
    let day: String
    let totalKg: Double
}

// [01] The widget gets just the setup and recent comparison it needs, never the full history.
struct WidgetAutomaticConfiguration: Codable, Equatable {
    let enabled: Bool
    let timeZoneIdentifier: String
    let eligibleStartDay: String?
    let classificationRevision: String
    let modelRevision: String
    let revisions: [RoutineRevision]
    let baseline: [WidgetAutomaticBaseline]
    let knownRecordDays: [String]
    let knownAutomaticRecordDays: [String]?
}

struct WidgetAutomaticContext: Codable, Equatable {
    let epoch: UUID
    let configuration: WidgetAutomaticConfiguration
    var enabled: Bool { configuration.enabled }
    var timeZoneIdentifier: String { configuration.timeZoneIdentifier }
    var fingerprint: String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let bytes = try? encoder.encode(self) else { return "invalid" }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

struct WidgetAutomaticRequest: Equatable {
    let context: WidgetAutomaticContext
    let day: String
    let date: Date
    let interval: DateInterval
    let inputs: FootprintInputs
    let baselineKg: Double?
    let allowsExistingAutomaticDay: Bool
}

struct WidgetAutomaticPendingRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let contextEpoch: UUID
    let contextFingerprint: String
    let timeZoneIdentifier: String
    let classificationRevision: String
    let modelRevision: String
    let originSavedAt: Date
    let producer: WidgetVerificationProducer
    let record: FootprintRecord
}

enum WidgetAutomaticExchangeError: Error {
    case unavailable, invalidData, unsupportedVersion, staleContext, mailboxFull, snapshotMismatch, blocked
}

// [02] A saved pending day is a real handoff, not a second private archive.
// The app acknowledges it only after its own history has reached disk.
struct WidgetAutomaticExchange {
    static let fileName = "widget-automatic-exchange-v1.json"
    static let blockedFileName = "widget-automatic-input-blocked-v1"
    static let maximumPendingRecords = 32
    private static let maximumBytes = 524_288
    let directory: URL?
    var producer: WidgetVerificationProducer = .current

    private struct State: Codable {
        var version = 1
        var context: WidgetAutomaticContext
        var pending: [WidgetAutomaticPendingRecord]
    }

    func currentContext() throws -> WidgetAutomaticContext? {
        try coordinated { try $0.read()?.context }
    }

    // [11] Withdrawing access must work even if a previous saved handoff cannot be decoded.
    func blockNewQueries() throws {
        try coordinated { try $0.writeBlockMarker() }
    }

    func isQueryBlocked() throws -> Bool {
        try coordinated { $0.hasBlockMarker }
    }

    func newQueriesAreBlocked() throws -> Bool { try isQueryBlocked() }

    @discardableResult
    func publishContext(from archive: FootprintArchive?, enabled: Bool,
                        calendar: Calendar = FootprintCalendar.localCalendar,
                        classificationRevision: String, modelRevision: String = "shared-ios-v1",
                        eligibleStartDay: String? = nil,
                        now: Date = Date()) throws -> WidgetAutomaticContext {
        return try coordinated { exchange in
            if !enabled { try exchange.writeBlockMarker() }
            let configuration = try exchange.makeConfiguration(archive: archive, enabled: enabled, calendar: calendar,
                classificationRevision: classificationRevision, modelRevision: modelRevision,
                eligibleStartDay: eligibleStartDay, now: now)
            if !configuration.enabled { try exchange.writeBlockMarker() }
            let old = try exchange.read()
            // [03] Any changed setup gets a new ticket. A query holding the old ticket cannot save later.
            let mustRenewConsentTicket = configuration.enabled && exchange.hasBlockMarker
            let context = old?.context.configuration == configuration && !mustRenewConsentTicket ? old!.context
                : WidgetAutomaticContext(epoch: UUID(), configuration: configuration)
            try exchange.write(State(context: context, pending: old?.pending ?? []))
            // [12] Only a complete valid setup can remove the separate stop sign.
            guard let persisted = try exchange.read(), persisted.context == context else {
                throw WidgetAutomaticExchangeError.invalidData
            }
            if configuration.enabled { try exchange.removeBlockMarker() }
            return context
        }
    }

    func contextForYesterday(now: Date = Date(),
                             calendar: Calendar = FootprintCalendar.localCalendar) throws -> WidgetAutomaticRequest? {
        try coordinated { exchange in
            guard !exchange.hasBlockMarker else { return nil }
            guard let state = try exchange.read() else { return nil }
            return try exchange.request(from: state, now: now, calendar: calendar)
        }
    }

    #if DEBUG
    // [13] Isolated regression fixtures can recheck a saved automatic day. Release has no such entry point.
    func contextForYesterday(now: Date = Date(), calendar: Calendar = FootprintCalendar.localCalendar,
                             allowExistingAutomaticDay: Bool) throws -> WidgetAutomaticRequest? {
        try coordinated { exchange in
            guard !exchange.hasBlockMarker else { return nil }
            guard let state = try exchange.read() else { return nil }
            return try exchange.request(from: state, now: now, calendar: calendar,
                allowExistingAutomaticDay: allowExistingAutomaticDay)
        }
    }
    #endif

    func validateRequest(_ request: WidgetAutomaticRequest, now: Date = Date(),
                         calendar: Calendar = FootprintCalendar.localCalendar) throws -> Bool {
        try coordinated { exchange in
            guard !exchange.hasBlockMarker else { return false }
            guard let state = try exchange.read(), state.context == request.context else { return false }
            return try exchange.request(from: state, now: now, calendar: calendar,
                allowExistingAutomaticDay: request.allowsExistingAutomaticDay) == request
        }
    }

    // [04] Persist the complete day first. A later snapshot failure must not throw that saved work away.
    @discardableResult
    func commit(_ record: FootprintRecord, expected request: WidgetAutomaticRequest,
                at now: Date = Date(), calendar: Calendar = FootprintCalendar.localCalendar) throws -> Bool {
        try coordinated { exchange in
            guard !exchange.hasBlockMarker else { throw WidgetAutomaticExchangeError.blocked }
            guard var state = try exchange.read(), state.context == request.context else {
                throw WidgetAutomaticExchangeError.staleContext
            }
            let config = state.context.configuration
            #if DEBUG
            let existingIsAllowed = request.allowsExistingAutomaticDay
                && (config.knownAutomaticRecordDays ?? []).contains(record.day)
            #else
            let existingIsAllowed = false
            #endif
            if state.pending.contains(where: { $0.record.day == record.day })
                || (config.knownRecordDays.contains(record.day) && !existingIsAllowed) { return false }
            guard let current = try exchange.request(from: state, now: now, calendar: calendar,
                allowExistingAutomaticDay: request.allowsExistingAutomaticDay), current == request else {
                throw WidgetAutomaticExchangeError.staleContext
            }
            guard state.pending.count < Self.maximumPendingRecords else { throw WidgetAutomaticExchangeError.mailboxFull }
            try exchange.validate(record: record, for: request, at: now)
            var storedRecord = record
            storedRecord.calculatedAt = Date(timeIntervalSince1970: record.calculatedAt.timeIntervalSince1970.rounded(.down))
            let saved = WidgetAutomaticPendingRecord(id: UUID(), contextEpoch: request.context.epoch,
                contextFingerprint: request.context.fingerprint, timeZoneIdentifier: request.context.timeZoneIdentifier,
                classificationRevision: request.context.configuration.classificationRevision,
                modelRevision: request.context.configuration.modelRevision, originSavedAt: now,
                producer: producer, record: storedRecord)
            state.pending.append(saved)
            state.pending.sort { $0.record.day < $1.record.day }
            try exchange.write(state)
            // [05] Both sizes read the same saved day. Their own timeline receipts still record their actual reads.
            let snapshot = exchange.snapshot(for: storedRecord)
            let storage = WidgetSnapshotStorage(directory: exchange.directory)
            _ = try storage.write(snapshot)
            guard storage.read().snapshot == snapshot else { throw WidgetAutomaticExchangeError.snapshotMismatch }
            return true
        }
    }

    func pendingRecords() throws -> [WidgetAutomaticPendingRecord] {
        try coordinated { try $0.read()?.pending ?? [] }
    }

    // [09] The publisher already holds the shared turn. Taking another lock here would block both processes.
    func pendingRecordsDuringCoordinatedAccess() throws -> [WidgetAutomaticPendingRecord] {
        try read()?.pending ?? []
    }

    // [15] The receipt writer holds the same lock. A resumed connection uses a different
    // ticket, so a late note cannot restore the checks that deletion removed.
    func allowsReceiptDuringCoordinatedAccess(contextEpoch: UUID?) throws -> Bool {
        guard !hasBlockMarker else { return false }
        guard let contextEpoch else { return true }
        return try read()?.context.epoch == contextEpoch
    }

    // [08] If the phone stopped between the durable day and its picture, repair the picture from that same day.
    @discardableResult
    func recoverPendingSnapshot() throws -> GardenWidgetSnapshot? {
        try coordinated { exchange in
            guard let state = try exchange.read(), state.context.enabled,
                  let last = state.pending.max(by: { $0.record.day < $1.record.day }) else { return nil }
            let storage = WidgetSnapshotStorage(directory: exchange.directory)
            let existing = storage.read().snapshot
            let saved = exchange.snapshot(for: last.record)
            if let existing, existing.day > saved.day { return existing }
            _ = try storage.write(saved)
            guard storage.read().snapshot == saved else { throw WidgetAutomaticExchangeError.snapshotMismatch }
            return saved
        }
    }

    // [06] A crash after the app saves history but before this acknowledgement is safe: the same ID can be merged again.
    func acknowledge(ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        try coordinated { exchange in
            guard var state = try exchange.read() else { return }
            let before = state.pending.count
            state.pending.removeAll { ids.contains($0.id) }
            if state.pending.count != before { try exchange.write(state) }
        }
    }

    // [07] Keep a disabled ticket on disk after deletion. An older query must not recreate the garden.
    func disableAndClear() throws {
        try coordinated { exchange in
            try exchange.writeBlockMarker()
            let disabled = WidgetAutomaticConfiguration(enabled: false,
                timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier, eligibleStartDay: nil,
                classificationRevision: "disabled", modelRevision: "disabled", revisions: [], baseline: [],
                knownRecordDays: [], knownAutomaticRecordDays: [])
            try exchange.write(State(context: WidgetAutomaticContext(epoch: UUID(), configuration: disabled), pending: []))
            _ = try WidgetSnapshotStorage(directory: exchange.directory).write(nil)
            _ = try WidgetStorageVerificationStore(directory: exchange.directory, producer: producer)
                .clearDuringCoordinatedAccess()
            // [14] Delete also removes the widget's completed-day diagnostic. The stop marker
            // remains, so a query already running cannot write that old check back afterwards.
            if let directory = exchange.directory {
                let receipt = directory.appendingPathComponent(WidgetAutomaticReceipt.fileName)
                if FileManager.default.fileExists(atPath: receipt.path) { try FileManager.default.removeItem(at: receipt) }
            }
        }
    }

    private func makeConfiguration(archive: FootprintArchive?, enabled: Bool, calendar: Calendar,
                                   classificationRevision: String, modelRevision: String,
                                   eligibleStartDay: String?, now: Date) throws -> WidgetAutomaticConfiguration {
        guard calendar.identifier == .gregorian, !classificationRevision.isEmpty, !modelRevision.isEmpty,
              now.timeIntervalSince1970.isFinite else { throw WidgetAutomaticExchangeError.invalidData }
        let days = FootprintCalendar(calendar: calendar)
        let today = days.key(now)
        let cutoff = calendar.date(byAdding: .day, value: -32, to: calendar.startOfDay(for: now))!
        let cutoffDay = days.key(cutoff)
        guard let archive else {
            return WidgetAutomaticConfiguration(enabled: false, timeZoneIdentifier: calendar.timeZone.identifier,
                eligibleStartDay: nil, classificationRevision: classificationRevision, modelRevision: modelRevision,
                revisions: [], baseline: [], knownRecordDays: [], knownAutomaticRecordDays: [])
        }
        guard archive.version == 1, archive.revisions.allSatisfy({ days.date($0.effectiveDay) != nil }),
              archive.records.allSatisfy({ days.date($0.day) != nil }) else { throw WidgetAutomaticExchangeError.invalidData }
        var byDay: [String: RoutineRevision] = [:]
        for revision in archive.revisions {
            try revision.inputs.validate()
            var inputs = revision.inputs
            inputs.calendarDayMinutes = nil
            for index in inputs.usages.indices { inputs.usages[index].minutes = 0 }
            byDay[revision.effectiveDay] = RoutineRevision(effectiveDay: revision.effectiveDay,
                savedAt: Date(timeIntervalSince1970: revision.savedAt.timeIntervalSince1970.rounded(.down)), inputs: inputs)
        }
        let sorted = byDay.values.sorted { $0.effectiveDay < $1.effectiveDay }
        let earlier = sorted.last { $0.effectiveDay < cutoffDay }
        let revisions = (earlier.map { [$0] } ?? []) + sorted.filter { $0.effectiveDay >= cutoffDay && $0.effectiveDay <= today }
        // [10] The latest date may be rechecked in the isolated probe, so keep its seven preceding comparisons too.
        let baseline = try archive.records.filter { $0.day < today }.suffix(8).map { record -> WidgetAutomaticBaseline in
            try record.result.validate()
            return WidgetAutomaticBaseline(day: record.day, totalKg: record.result.totalKg)
        }
        let known = archive.records.filter { $0.day >= cutoffDay && $0.day <= today }.map(\.day).sorted()
        let automaticKnown = archive.records.filter { $0.day >= cutoffDay && $0.day <= today && $0.source == .screenTimeWithEstimates }.map(\.day).sorted()
        guard eligibleStartDay.map({ days.date($0) != nil }) ?? true else { throw WidgetAutomaticExchangeError.invalidData }
        let eligible = archive.automaticStartDay.map { max($0, eligibleStartDay ?? $0) }
        let mayImport = enabled && archive.usesAutomaticInput && eligible.flatMap(days.date) != nil
            && !revisions.isEmpty
        return WidgetAutomaticConfiguration(enabled: mayImport, timeZoneIdentifier: calendar.timeZone.identifier,
            eligibleStartDay: eligible, classificationRevision: classificationRevision, modelRevision: modelRevision,
            revisions: revisions, baseline: baseline, knownRecordDays: known, knownAutomaticRecordDays: automaticKnown)
    }

    private func request(from state: State, now: Date, calendar: Calendar,
                         allowExistingAutomaticDay: Bool = false) throws -> WidgetAutomaticRequest? {
        let config = state.context.configuration
        guard config.enabled, calendar.identifier == .gregorian,
              config.timeZoneIdentifier == calendar.timeZone.identifier,
              now.timeIntervalSince1970.isFinite,
              let previous = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
              let interval = calendar.dateInterval(of: .day, for: previous) else { return nil }
        let days = FootprintCalendar(calendar: calendar)
        let key = days.key(interval.start)
        #if DEBUG
        let permittedRecheck = allowExistingAutomaticDay && (config.knownAutomaticRecordDays ?? []).contains(key)
        #else
        let permittedRecheck = false
        #endif
        guard let eligible = config.eligibleStartDay, key >= eligible,
              (!config.knownRecordDays.contains(key) || permittedRecheck), !state.pending.contains(where: { $0.record.day == key }),
              state.pending.count < Self.maximumPendingRecords,
              let inputs = config.revisions.last(where: { $0.effectiveDay <= key })?.inputs else { return nil }
        var totals = Dictionary(uniqueKeysWithValues: config.baseline.filter { $0.day < key }.map { ($0.day, $0.totalKg) })
        for pending in state.pending where pending.record.day < key { totals[pending.record.day] = pending.record.result.totalKg }
        let previousTotals = totals.sorted { $0.key < $1.key }.suffix(7).map(\.value)
        let baseline = previousTotals.isEmpty ? nil : previousTotals.reduce(0, +) / Double(previousTotals.count)
        return WidgetAutomaticRequest(context: state.context, day: key, date: interval.start,
            interval: interval, inputs: inputs, baselineKg: baseline, allowsExistingAutomaticDay: permittedRecheck)
    }

    private func validate(record: FootprintRecord, for request: WidgetAutomaticRequest, at now: Date) throws {
        try record.inputs.validate()
        try record.result.validate()
        guard record.day == request.day, record.source == .screenTimeWithEstimates, record.isCompleted,
              record.calculatedAt.timeIntervalSince1970.isFinite,
              record.calculatedAt <= now.addingTimeInterval(5),
              record.inputs.calendarDayMinutes == request.interval.duration / 60,
              record.inputs.brightness == request.inputs.brightness,
              record.inputs.gpsHours == request.inputs.gpsHours,
              record.inputs.bluetoothHours == request.inputs.bluetoothHours,
              record.inputs.usages.map(\.category) == request.inputs.usages.map(\.category),
              record.inputs.usages.allSatisfy({ usage in
                  request.inputs.usages.contains { $0.category == usage.category
                      && $0.gigabytesPerHour == usage.gigabytesPerHour && $0.wifiShare == usage.wifiShare }
              }),
              Set(record.automaticCategories ?? []) == Set(record.inputs.usages.map(\.category)),
              record.baselineKg == request.baselineKg,
              record.garden == FootprintGarden.state(total: record.result.totalKg, baseline: request.baselineKg) else {
            throw WidgetAutomaticExchangeError.invalidData
        }
    }

    private func coordinated<Value>(_ operation: (WidgetAutomaticExchange) throws -> Value) throws -> Value {
        guard directory != nil else { throw WidgetAutomaticExchangeError.unavailable }
        return try WidgetStorageVerificationStore(directory: directory, producer: producer).withExclusiveAccess { checks in
            try operation(WidgetAutomaticExchange(directory: checks.directory, producer: producer))
        }
    }

    private var hasBlockMarker: Bool {
        guard let directory else { return true }
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent(Self.blockedFileName).path)
    }

    private func writeBlockMarker() throws {
        guard let directory else { throw WidgetAutomaticExchangeError.unavailable }
        try Data([1]).write(to: directory.appendingPathComponent(Self.blockedFileName),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func removeBlockMarker() throws {
        guard let directory else { throw WidgetAutomaticExchangeError.unavailable }
        let url = directory.appendingPathComponent(Self.blockedFileName)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private func snapshot(for record: FootprintRecord) -> GardenWidgetSnapshot {
        GardenWidgetSnapshot(day: record.day, totalKg: record.result.totalKg,
            garden: WidgetGardenState(rawValue: record.garden.rawValue)!, source: .screenTimeWithEstimates,
            calculatedAt: record.calculatedAt, isCompleted: record.isCompleted)
    }

    private func read() throws -> State? {
        guard let directory else { throw WidgetAutomaticExchangeError.unavailable }
        let url = directory.appendingPathComponent(Self.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let length = attributes[.size] as? NSNumber, length.intValue <= Self.maximumBytes else {
            throw WidgetAutomaticExchangeError.invalidData
        }
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maximumBytes else { throw WidgetAutomaticExchangeError.invalidData }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state: State
        do { state = try decoder.decode(State.self, from: data) }
        catch { throw WidgetAutomaticExchangeError.invalidData }
        guard state.version == 1 else { throw WidgetAutomaticExchangeError.unsupportedVersion }
        let config = state.context.configuration
        guard TimeZone(identifier: config.timeZoneIdentifier) != nil,
              !config.classificationRevision.isEmpty, !config.modelRevision.isEmpty,
              config.revisions.count <= 34, config.baseline.count <= 8, config.knownRecordDays.count <= 34,
              (config.knownAutomaticRecordDays?.count ?? 0) <= 34,
              state.pending.count <= Self.maximumPendingRecords,
              Set(state.pending.map(\.id)).count == state.pending.count,
              Set(state.pending.map { $0.record.day }).count == state.pending.count,
              Set(config.baseline.map(\.day)).count == config.baseline.count,
              Set(config.knownRecordDays).count == config.knownRecordDays.count,
              Set(config.knownAutomaticRecordDays ?? []).isSubset(of: Set(config.knownRecordDays)),
              config.baseline.allSatisfy({ $0.totalKg.isFinite && $0.totalKg >= 0 }),
              config.revisions.map(\.effectiveDay) == config.revisions.map(\.effectiveDay).sorted() else {
            throw WidgetAutomaticExchangeError.invalidData
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: config.timeZoneIdentifier)!
        let days = FootprintCalendar(calendar: calendar)
        guard config.eligibleStartDay.map({ days.date($0) != nil }) ?? !config.enabled,
              config.knownRecordDays.allSatisfy({ days.date($0) != nil }),
              config.baseline.allSatisfy({ days.date($0.day) != nil }),
              config.revisions.allSatisfy({ days.date($0.effectiveDay) != nil }) else {
            throw WidgetAutomaticExchangeError.invalidData
        }
        for revision in config.revisions { try revision.inputs.validate() }
        for item in state.pending {
            try item.record.inputs.validate(); try item.record.result.validate()
            guard days.date(item.record.day) != nil, item.record.source == .screenTimeWithEstimates,
                  item.record.isCompleted, item.originSavedAt.timeIntervalSince1970.isFinite,
                  item.contextFingerprint.count == 64,
                  item.contextFingerprint.allSatisfy({ "0123456789abcdef".contains($0) }),
                  !item.classificationRevision.isEmpty, !item.modelRevision.isEmpty,
                  Set(item.record.automaticCategories ?? []) == Set(item.record.inputs.usages.map(\.category)),
                  TimeZone(identifier: item.timeZoneIdentifier) != nil else { throw WidgetAutomaticExchangeError.invalidData }
        }
        return state
    }

    private func write(_ state: State) throws {
        guard let directory else { throw WidgetAutomaticExchangeError.unavailable }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(state)
        guard bytes.count <= Self.maximumBytes else { throw WidgetAutomaticExchangeError.invalidData }
        try bytes.write(to: directory.appendingPathComponent(Self.fileName),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
