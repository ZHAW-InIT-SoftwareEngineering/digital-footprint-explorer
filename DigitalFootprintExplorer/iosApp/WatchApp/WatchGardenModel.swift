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

#if os(watchOS)
import Combine
import Foundation
import WatchConnectivity
import WidgetKit

@MainActor
final class WatchGardenModel: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchGardenModel()
    @Published private(set) var envelope: CompanionGardenEnvelope?
    @Published private(set) var isRefreshing = false
    @Published private(set) var connectionNote = "Open DFE on your iPhone to share its latest garden."
    let isPreviewing: Bool
    private let storage: CompanionGardenStorage?
    private var inbox = CompanionGardenInbox()
    private var started = false
    private var refreshAttempt = CompanionRefreshAttempt()
    private var timeout: Task<Void, Never>?
    private var activationFailed = false

    override init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let position = arguments.firstIndex(of: "-ui-watch-example"),
           arguments.indices.contains(position + 1),
           let example = Self.visualExample(arguments[position + 1], now: Date()) {
            // [04] A visual check must not open someone's saved result or activate a connection to their phone.
            storage = nil
            isPreviewing = true
            super.init()
            envelope = example
            connectionNote = "Example only. No phone activity is read or saved."
            return
        }
        #endif
        isPreviewing = false
        let localStorage = try? CompanionGardenStorage.watchGroup()
        var initialInbox = CompanionGardenInbox()
        var initialNote = "Open DFE on your iPhone to share its latest garden."
        if let localStorage {
            do {
                initialInbox = try localStorage.loadInbox()
                if initialInbox.envelope?.snapshot != nil { initialNote = "Showing the last saved phone result." }
            } catch {
                initialInbox = .blocked
                initialNote = "The saved phone result could not be read. Try refreshing."
            }
        } else {
            initialNote = "Local Watch storage is unavailable. Open DFE on your iPhone for your result."
        }
        storage = localStorage
        super.init()
        inbox = initialInbox
        envelope = initialInbox.envelope
        connectionNote = initialNote
    }

    #if DEBUG
    private static func visualExample(_ name: String, now: Date) -> CompanionGardenEnvelope? {
        let garden = CompanionGardenState(rawValue: name) ?? (name == "stale" ? .stable : nil)
        let status: CompanionGardenAvailability
        if garden != nil { status = .available }
        else if name == "pending" { status = .empty }
        else if let requested = CompanionGardenAvailability(rawValue: name), requested != .available { status = requested }
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let day = calendar.date(byAdding: .day, value: name == "stale" ? -4 : -1, to: now) ?? now
        let snapshot = garden.map {
            CompanionGardenSnapshot(day: CompanionGardenSnapshot.dayKey(day, calendar: calendar),
                                    totalKg: 0.06, garden: $0, source: .screenTimeWithEstimates,
                                    calculatedAt: now, isCompleted: true)
        }
        return CompanionGardenEnvelope(producer: UUID(), sequence: 1, sentAt: now,
                                       availability: status, snapshot: snapshot)
    }
    #endif

    func start() {
        guard !isPreviewing, WCSession.isSupported(), !started else { return }
        started = true
        activationFailed = false
        let session = WCSession.default
        session.delegate = self
        session.activate()
        receive(session.receivedApplicationContext, allowProducerChange: false)
    }

    // [03] watchOS can launch us without showing a view. Keep this task alive until Apple's pending context has been handled and saved.
    func handleConnectivityBackground() async {
        guard !isPreviewing else { return }
        start()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        while !Task.isCancelled, !activationFailed {
            if session.activationState == .activated {
                receive(session.receivedApplicationContext, allowProducerChange: false)
                if !session.hasContentPending {
                    // Let a delegate call already waiting on the main actor finish before returning the background time to watchOS.
                    await Task.yield()
                    receive(session.receivedApplicationContext, allowProducerChange: false)
                    if !session.hasContentPending { return }
                }
            }
            do { try await Task.sleep(nanoseconds: 75_000_000) }
            catch { return }
        }
    }

    func refresh() {
        guard !isPreviewing, !isRefreshing else { return }
        guard WCSession.isSupported() else {
            connectionNote = "Your iPhone connection is unavailable."
            return
        }
        let wasStarted = started
        start()
        let session = WCSession.default
        guard let id = refreshAttempt.begin(now: ProcessInfo.processInfo.systemUptime) else { return }
        isRefreshing = true
        // [01] Start the deadline before activation too. A missing activation reply must leave a clear way to try again.
        timeout?.cancel()
        timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled, let self, self.refreshAttempt.id == id else { return }
            self.finishRequest(id, note: "Your iPhone connection timed out. Your saved result is unchanged. Try refreshing again.")
        }
        if session.activationState == .activated {
            sendRefreshRequest(id)
        } else {
            connectionNote = "Connecting to your iPhone…"
            activationFailed = false
            // [05] start() handles a first launch. Later attempts explicitly retry an activation that failed or timed out.
            if wasStarted { session.activate() }
        }
    }

    private func sendRefreshRequest(_ id: UUID) {
        guard refreshAttempt.beginReply(for: id, now: ProcessInfo.processInfo.systemUptime) else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            finishRequest(id, note: envelope?.snapshot == nil
                ? "Open DFE on your paired iPhone to get its latest result."
                : "Showing the last saved phone result. Open DFE on your iPhone to sync.")
            return
        }
        connectionNote = "Checking your phone's latest saved result…"
        session.sendMessage([CompanionGardenEnvelope.refreshRequestKey: true], replyHandler: { [weak self] reply in
            Task { @MainActor [weak self] in
                guard let self, self.refreshAttempt.id == id else { return }
                guard self.refreshAttempt.accepts(id, now: ProcessInfo.processInfo.systemUptime) else {
                    self.finishRequest(id, note: "Your iPhone connection timed out. Try refreshing again.")
                    return
                }
                let accepted = self.receive(reply, allowProducerChange: true)
                self.finishRequest(id, note: accepted ? "Phone result checked just now."
                    : "The phone result is unavailable. Open DFE on your iPhone to check it.")
            }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.finishRequest(id, note: "Your iPhone could not be reached. Showing the last saved result.")
            }
        })
    }

    private func finishRequest(_ id: UUID, note: String) {
        let wasActivating = refreshAttempt.id == id && refreshAttempt.phase == .activation
        guard refreshAttempt.finish(id) else { return }
        if wasActivating { started = false }
        timeout?.cancel()
        timeout = nil
        isRefreshing = false
        connectionNote = note
    }

    // [02] Save before changing the screen so the Watch app and its complications see the same accepted result.
    @discardableResult
    private func receive(_ context: [String: Any], allowProducerChange: Bool) -> Bool {
        guard !isPreviewing else { return false }
        guard let data = context[CompanionGardenEnvelope.contextKey] as? Data else { return false }
        do {
            let next = try CompanionGardenEnvelope.decode(data)
            guard let storage else { return false }
            let previous = inbox
            guard try inbox.receive(next, trustedReply: allowProducerChange,
                                    persist: { try storage.saveInbox($0) },
                                    invalidateSavedResult: { try storage.invalidateSavedResult() }) else { return false }
            guard inbox != previous else { return true }
            envelope = inbox.envelope
            connectionNote = next.snapshot == nil ? next.availability.explanation : "Showing the latest saved phone result."
            WidgetCenter.shared.reloadTimelines(ofKind: CompanionGardenEnvelope.widgetKind)
            return true
        } catch {
            if inbox.envelope != envelope, inbox.envelope?.snapshot == nil {
                envelope = inbox.envelope
                WidgetCenter.shared.reloadTimelines(ofKind: CompanionGardenEnvelope.widgetKind)
                connectionNote = "The phone result was cleared. Local saving needs attention; refresh to reconnect."
            } else {
                connectionNote = "The new phone result could not be read. Your saved result has not changed."
            }
            return false
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.activationFailed = error != nil && session.activationState != .activated
            if self.activationFailed { self.started = false }
            self.receive(session.receivedApplicationContext, allowProducerChange: false)
            if session.activationState == .activated, let id = self.refreshAttempt.id {
                self.sendRefreshRequest(id)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor [weak self] in self?.receive(applicationContext, allowProducerChange: false) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            guard let self, let id = self.refreshAttempt.id,
                  session.activationState == .activated, session.isReachable else { return }
            self.sendRefreshRequest(id)
        }
    }
}
#endif
