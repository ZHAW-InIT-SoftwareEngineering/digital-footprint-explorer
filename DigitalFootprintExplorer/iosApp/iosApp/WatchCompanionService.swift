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

#if os(iOS)
import Combine
import Foundation
import UIKit
import WatchConnectivity

// [01] Watch sharing is a separate choice. Connecting the phone to a Watch must not send an estimate by itself.
@MainActor
final class WatchCompanionService: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var sharingEnabled = false
    @Published private(set) var watchIsPaired = false
    @Published private(set) var transferStatus = "Watch sharing is off"
    var onRefreshRequested: (@MainActor () async -> Void)?

    static var isSupported: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && WCSession.isSupported()
    }

    private var policy = CompanionSharingPolicy()
    private let storage: (any CompanionGardenPersistence)?
    private let isolated: Bool
    private let injectedTransport: ((CompanionGardenEnvelope) throws -> Void)?
    private var latest: CompanionGardenEnvelope?
    private var producer: UUID?
    private var sequence: UInt64 = 0
    private var savedSenderHadSnapshot = false
    private var pendingUpdate: (availability: CompanionGardenAvailability, snapshot: CompanionGardenSnapshot?)?
    private var started = false
    private var refreshInFlight = false

    static var isTestProcess: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
        #else
        false
        #endif
    }

    override convenience init() { self.init(isolated: Self.isTestProcess) }

    init(isolated: Bool) {
        let shouldIsolate = isolated || Self.isTestProcess
        self.isolated = shouldIsolate
        injectedTransport = nil
        let root = shouldIsolate ? nil : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let localStorage = root.map { CompanionGardenStorage(directory: $0.appendingPathComponent("WatchCompanion", isDirectory: true)) }
        storage = localStorage
        super.init()
        restoreSender()
    }

    // [09] A test can fail a save or capture a transfer without touching a person's files or their paired Watch.
    init(storage: any CompanionGardenPersistence, transport: @escaping (CompanionGardenEnvelope) throws -> Void) {
        self.storage = storage
        injectedTransport = transport
        isolated = false
        super.init()
        restoreSender()
    }

    // [11] A clock correction can make a saved result too new to display. Its sender
    // and sequence still tell the Watch which message came first.
    private func restoreSender() {
        guard !isolated, producer == nil, let storage else { return }
        let now = Date()
        do {
            let saved = try storage.load(now: .distantFuture)
            let queued = queuedEnvelope()
            let previous: CompanionGardenEnvelope?
            if let saved, let queued,
               (queued.producer == saved.producer && queued.sequence > saved.sequence
                || queued.producer != saved.producer && queued.snapshot == nil && queued.sentAt >= saved.sentAt) {
                // A privacy clear may have reached Apple's queue even if its local save failed.
                previous = queued
            } else {
                previous = saved ?? queued
            }
            producer = previous?.producer ?? UUID()
            sequence = previous?.sequence ?? 0
            savedSenderHadSnapshot = previous?.snapshot != nil
            if let previous, (previous == saved || previous.snapshot == nil),
               (try? previous.validate(now: now)) != nil { latest = previous }
        } catch {
            // [12] If the file cannot be read, recover ordering from the message Apple has
            // already queued. With neither copy, wait for a direct reply or a privacy clear.
            if let queued = queuedEnvelope() {
                producer = queued.producer
                sequence = queued.sequence
            }
        }
    }

    private func queuedEnvelope() -> CompanionGardenEnvelope? {
        guard injectedTransport == nil, Self.isSupported,
              let data = WCSession.default.applicationContext[CompanionGardenEnvelope.contextKey] as? Data else { return nil }
        return try? CompanionGardenEnvelope.decode(data, now: .distantFuture)
    }

    // [02] Restoring the user's choice at launch does not send an empty garden first.
    func restoreSharingPreference(_ enabled: Bool) {
        guard !isolated, !started else { return }
        sharingEnabled = enabled
        policy.setEnabled(enabled)
    }

    func setSharingEnabled(_ enabled: Bool) {
        guard !isolated else { return }
        guard enabled != sharingEnabled else { return }
        sharingEnabled = enabled
        policy.setEnabled(enabled)
        saveAndQueue(availability: enabled ? .empty : .sharingOff, snapshot: nil)
    }

    func start() {
        guard !isolated, !started, injectedTransport != nil || Self.isSupported else { return }
        started = true
        // [03] Replace a queued old estimate when the saved privacy choice is off, including after an interrupted shutdown.
        if !sharingEnabled, savedSenderHadSnapshot || queuedEnvelope()?.snapshot != nil {
            saveAndQueue(availability: .sharingOff, snapshot: nil)
            if injectedTransport != nil { return }
        }
        if injectedTransport != nil { sendCurrentContext(); return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func publish(snapshot: GardenWidgetSnapshot?, screenTimeAccess: Bool? = true) {
        guard sharingEnabled else { return }
        guard let snapshot else {
            saveAndQueue(availability: .empty, snapshot: nil)
            return
        }
        // [13] A saved manual or routine estimate does not depend on Screen Time.
        // Wait for a definite answer before changing a Screen Time result at launch.
        if snapshot.source == .screenTimeWithEstimates {
            guard let screenTimeAccess else { return }
            guard screenTimeAccess else { disconnect(); return }
        }
        guard let garden = CompanionGardenState(rawValue: snapshot.garden.rawValue),
              let source = CompanionEstimateSource(rawValue: snapshot.source.rawValue) else { return }
        // [14] The phone archive saves whole seconds. Use the same time before and after a restart.
        let savedAtSeconds = snapshot.calculatedAt.timeIntervalSince1970.rounded(.down)
        let phoneResult = CompanionGardenSnapshot(day: snapshot.day, totalKg: snapshot.totalKg,
                                                 garden: garden, source: source,
                                                 calculatedAt: Date(timeIntervalSince1970: savedAtSeconds),
                                                 isCompleted: snapshot.isCompleted)
        saveAndQueue(availability: .available, snapshot: phoneResult)
    }

    func clear() {
        saveAndQueue(availability: sharingEnabled ? .empty : .sharingOff, snapshot: nil, permitSenderRecovery: true)
    }

    func disconnect() {
        saveAndQueue(availability: sharingEnabled ? .disconnected : .sharingOff, snapshot: nil)
    }

    private func saveAndQueue(availability: CompanionGardenAvailability, snapshot: CompanionGardenSnapshot?,
                              permitSenderRecovery: Bool = false) {
        guard !isolated else { return }
        let availability = policy.responseAvailability(for: availability)
        let snapshot = policy.allowedSnapshot(snapshot)
        restoreSender()
        // [04] A launch or a tab change need not write or send the same result or status again.
        if latest?.availability == availability, latest?.snapshot == snapshot {
            pendingUpdate = nil
            return
        }
        if producer == nil, permitSenderRecovery || availability == .sharingOff || availability == .disconnected {
            producer = UUID()
        }
        guard let producer else {
            pendingUpdate = (availability, snapshot)
            transferStatus = "Open DFE on your Watch to check sharing"
            return
        }
        pendingUpdate = nil
        guard sequence < UInt64.max else {
            transferStatus = "Open DFE again to check Watch sharing"
            return
        }
        let next = CompanionGardenEnvelope(producer: producer, sequence: sequence + 1, sentAt: Date(),
                                           availability: availability, snapshot: snapshot)
        do {
            guard let storage else { throw CompanionGardenError.storageUnavailable }
            try storage.save(next, now: Date())
            latest = next
            sequence = next.sequence
            savedSenderHadSnapshot = next.snapshot != nil
            sendCurrentContext()
        } catch {
            // [05] A failed result save must not send an untracked estimate. A privacy clear still replaces the system's old queued result.
            if next.snapshot == nil {
                latest = next
                sequence = next.sequence
                savedSenderHadSnapshot = false
                sendCurrentContext()
                transferStatus = "Watch clear queued; local saving needs attention"
            } else {
                transferStatus = "Watch sharing could not be saved"
            }
        }
    }

    private func sendCurrentContext() {
        guard !isolated, started else { return }
        if let injectedTransport {
            guard let latest, sharingEnabled || latest.snapshot == nil else { return }
            do { try injectedTransport(latest) }
            catch { transferStatus = "Open DFE on your Watch to try again" }
            return
        }
        guard Self.isSupported else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        // [10] Detect a paired Watch even before sharing is enabled, so an iPhone without one does not show an unused setting.
        watchIsPaired = session.isPaired
        if !sharingEnabled, latest?.availability != .sharingOff, queuedEnvelope()?.snapshot != nil {
            saveAndQueue(availability: .sharingOff, snapshot: nil)
            return
        }
        guard let latest, sharingEnabled || latest.snapshot == nil else { return }
        guard session.isPaired, session.isWatchAppInstalled else {
            transferStatus = "Install DFE on your paired Apple Watch, then open it"
            return
        }
        do {
            // [06] A latest-state transfer replaces an older queued result. It can wait safely while the Watch is offline.
            if queuedEnvelope() != latest {
                let data = try latest.encoded()
                try session.updateApplicationContext([CompanionGardenEnvelope.contextKey: data])
            }
            transferStatus = sharingEnabled ? "Latest phone result queued for Apple Watch" : "Watch sharing is off"
        } catch {
            transferStatus = "Open DFE on your Watch to try again"
        }
    }

    func resultForWatchRefresh() -> CompanionGardenEnvelope? {
        if !sharingEnabled {
            if latest?.availability != .sharingOff { saveAndQueue(availability: .sharingOff, snapshot: nil) }
        } else if let pendingUpdate {
            saveAndQueue(availability: pendingUpdate.availability, snapshot: pendingUpdate.snapshot, permitSenderRecovery: true)
        } else if latest == nil {
            saveAndQueue(availability: .empty, snapshot: nil, permitSenderRecovery: true)
        }
        guard let latest, sharingEnabled || latest.snapshot == nil else { return nil }
        return latest
    }

    private func replyToRefresh(_ reply: @escaping ([String: Any]) -> Void) {
        if let latest = resultForWatchRefresh(), let data = try? latest.encoded() {
            reply([CompanionGardenEnvelope.contextKey: data])
        } else {
            reply(["dfeCompanionUnavailable": true])
        }
        // [07] Reply with the saved result first. A slow phone import must not leave the Watch waiting without an answer.
        guard sharingEnabled, !refreshInFlight, let onRefreshRequested else { return }
        refreshInFlight = true
        Task { @MainActor [weak self] in
            await onRefreshRequested()
            self?.refreshInFlight = false
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let pendingUpdate = self.pendingUpdate {
                self.saveAndQueue(availability: pendingUpdate.availability, snapshot: pendingUpdate.snapshot)
            } else {
                self.sendCurrentContext()
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.watchIsPaired = false }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // [08] Apple supports changing the paired Watch. Activate again for the Watch that is now in use.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.sendCurrentContext() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard message[CompanionGardenEnvelope.refreshRequestKey] as? Bool == true else {
            replyHandler(["dfeCompanionUnavailable": true])
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { replyHandler(["dfeCompanionUnavailable": true]); return }
            self.replyToRefresh(replyHandler)
        }
    }
}
#endif
