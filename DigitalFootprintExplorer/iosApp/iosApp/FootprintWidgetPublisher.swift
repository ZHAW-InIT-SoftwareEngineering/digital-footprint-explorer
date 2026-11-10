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
import WidgetKit

protocol WidgetSnapshotPublishing {
    var verification: WidgetPublicationVerification? { get }
    var timelineReadChecks: [WidgetTimelineReadCheck] { get }
    func publish(_ snapshot: GardenWidgetSnapshot?) throws
    func reloadAfterClearing()
}

extension WidgetSnapshotPublishing {
    var verification: WidgetPublicationVerification? { nil }
    var timelineReadChecks: [WidgetTimelineReadCheck] { [] }
    func reloadAfterClearing() { }
}

enum WidgetPublicationError: Error { case readBackFailed }

/// [01] The app creates a small summary from saved history.
/// A widget problem must not undo a successfully saved day.
final class FootprintWidgetPublisher: WidgetSnapshotPublishing {
    private let storage: WidgetSnapshotStorage
    private let reload: () -> Void
    private let clock: () -> Date
    private let readBack: (() -> WidgetSnapshotReadResult)?
    private let verificationStore: WidgetStorageVerificationStore
    private var requestedProofReload = false
    private(set) var verification: WidgetPublicationVerification?
    // [11] Deletion may clear the shared files before the publisher sees them.
    // Still ask iOS to replace a picture already visible on the Home Screen.
    func reloadAfterClearing() { reload() }
    var timelineReadChecks: [WidgetTimelineReadCheck] { verificationStore.timelineReads() }
    static var appGroupIdentifier: String? { WidgetSnapshotStorage.appGroupIdentifier() }
    static var isAvailable: Bool { WidgetSnapshotStorage.configured().directory != nil }
    // [02] A build without the shared group can still keep history; it simply cannot publish a widget summary.
    static func availablePublisher() -> FootprintWidgetPublisher? {
        let storage = WidgetSnapshotStorage.configured()
        guard storage.directory != nil else { return nil }
        return FootprintWidgetPublisher(storage: storage)
    }

    init(storage: WidgetSnapshotStorage, clock: @escaping () -> Date = Date.init,
         readBack: (() -> WidgetSnapshotReadResult)? = nil,
         producer: WidgetVerificationProducer = .current, reload: @escaping () -> Void = {
        WidgetCenter.shared.reloadTimelines(ofKind: GardenWidgetSnapshot.widgetKind)
    }) {
        self.storage = storage
        self.clock = clock
        self.readBack = readBack
        self.reload = reload
        verificationStore = WidgetStorageVerificationStore(directory: storage.directory, producer: producer)
        verification = verificationStore.publication()
    }

    // [03] Read the saved file back, even when its content did not change. The check time
    // is separate from the write time, so a later refresh cannot invent an earlier save.
    func publish(_ snapshot: GardenWidgetSnapshot?) throws {
        var entered = false
        do {
            try verificationStore.withExclusiveAccess { checks in
                entered = true
                try publishDuringCoordinatedAccess(snapshot,
                    storage: WidgetSnapshotStorage(directory: checks.directory), checks: checks)
            }
        } catch {
            if !entered {
                verification = WidgetPublicationVerification(status: storage.directory == nil ? .unavailable : .writeFailed,
                    day: snapshot?.day, checkedAt: clock(), publishedAt: verification?.publishedAt,
                    producer: verificationStore.producer, receiptStored: false)
            }
            throw error
        }
    }

    private func publishDuringCoordinatedAccess(_ requestedSnapshot: GardenWidgetSnapshot?,
                                                storage: WidgetSnapshotStorage,
                                                checks: WidgetStorageVerificationStore) throws {
        var snapshot = requestedSnapshot
        #if DFE_WIDGET_AUTOMATIC_IMPORT
        // [10] A widget may have saved a completed day while the app was opening.
        // Keep that durable result until the private history has caught up with it.
        let pending: WidgetAutomaticPendingRecord?
        do {
            pending = try WidgetAutomaticExchange(directory: checks.directory)
                .latestPendingForSnapshotDuringCoordinatedAccess(now: clock())
        } catch {
            // [12] A saved phone result can still be shared. With no phone result, keep
            // the last picture because we cannot tell whether there is a newer widget day.
            guard snapshot != nil else { throw error }
            pending = nil
        }
        if let pending {
            let saved = GardenWidgetSnapshot(record: pending.record)
            if snapshot == nil || saved.day > snapshot!.day
                || (saved.day == snapshot!.day && snapshot!.source != .manual
                    && saved.calculatedAt > snapshot!.calculatedAt) {
                snapshot = saved
            }
        }
        #endif
        let previous = storage.read().snapshot
        let hadProof = verification?.status == .verified
        let changed: Bool
        do { changed = try storage.write(snapshot) }
        catch {
            keepCheck(status: .writeFailed, day: snapshot?.day, publishedAt: verification?.publishedAt, using: checks)
            throw error
        }
        let publishedAt = changed && snapshot != nil ? clock() : verification?.publishedAt
        let read = readBack?() ?? storage.read()
        let status = checkedStatus(expected: snapshot, actual: read)
        if snapshot == nil, status == .empty {
            // [06] Deletion clears both widget sizes' evidence as well as the shared result.
            let cleared: Bool
            do { cleared = try checks.clearDuringCoordinatedAccess() }
            catch {
                verification = WidgetPublicationVerification(status: .writeFailed, day: nil, checkedAt: clock(),
                    publishedAt: nil, producer: verificationStore.producer, receiptStored: false)
                throw error
            }
            verification = WidgetPublicationVerification(status: .empty, day: nil, checkedAt: clock(),
                publishedAt: nil, producer: verificationStore.producer, receiptStored: false)
            if changed || cleared { reload() }
            return
        }
        keepCheck(status: status, day: snapshot?.day, publishedAt: publishedAt, using: checks)
        guard status == .verified else { throw WidgetPublicationError.readBackFailed }
        // [07] A newly upgraded extension needs one real read, even if its old garden is unchanged.
        // Do not keep requesting reloads while waiting for a size the person has not installed.
        let needsProofReload = !hadProof && !requestedProofReload
        if needsProofReload { requestedProofReload = true }
        let sameGarden: Bool
        if let previous, let snapshot { sameGarden = showsSameGarden(previous, snapshot) }
        else { sameGarden = false }
        if needsProofReload || (changed && !sameGarden) { reload() }
    }

    private func checkedStatus(expected: GardenWidgetSnapshot?, actual: WidgetSnapshotReadResult) -> WidgetVerificationStatus {
        switch actual {
        case .unavailable: return .unavailable
        case .unreadable: return .unreadable
        case .empty: return expected == nil ? .empty : .mismatch
        case .saved(let value):
            guard let expected else { return .mismatch }
            do {
                // [09] Shared dates use whole seconds. Compare that saved form so a fraction
                // from Date() does not turn a correct round trip into a failed check.
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.sortedKeys]
                let saved = try encoder.encode(value)
                let intended = try encoder.encode(expected)
                return saved == intended ? .verified : .mismatch
            } catch { return .mismatch }
        }
    }

    private func keepCheck(status: WidgetVerificationStatus, day: String?, publishedAt: Date?,
                           using checks: WidgetStorageVerificationStore) {
        var value = WidgetPublicationVerification(status: status, day: day, checkedAt: clock(),
            publishedAt: publishedAt, producer: verificationStore.producer)
        do { try checks.recordPublicationDuringCoordinatedAccess(value) }
        catch {
            // [08] A missing check file must not undo a garden that was already saved successfully.
            value.receiptStored = false
        }
        verification = value
    }

    // [04] A missing or damaged summary has no earlier garden to compare, so repairing it still
    // requests a reload. Only the time of an otherwise unchanged save can wait for the next read.
    private func showsSameGarden(_ previous: GardenWidgetSnapshot, _ current: GardenWidgetSnapshot) -> Bool {
        previous.day == current.day && previous.totalKg == current.totalKg
            && previous.garden == current.garden && previous.source == current.source
            && previous.isCompleted == current.isCompleted
    }
}

extension GardenWidgetSnapshot {
    // [05] Copy only the last saved result needed by the widget. App identities and detailed inputs stay out.
    init(record: FootprintRecord) {
        day = record.day
        totalKg = record.result.totalKg
        garden = WidgetGardenState(rawValue: record.garden.rawValue)!
        source = WidgetEstimateSource(rawValue: record.source.rawValue)!
        calculatedAt = record.calculatedAt
        isCompleted = record.isCompleted
    }
}
