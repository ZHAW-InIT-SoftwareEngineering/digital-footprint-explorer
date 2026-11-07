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
import BackgroundTasks

// [01] Ask iOS for a useful morning opportunity. This is a request, not a promise
// that the phone will wake the app at an exact time.
struct BackgroundSchedule {
    static let retryInterval: TimeInterval = 60 * 60

    // [02] Count calendar days rather than 24-hour blocks, because the clocks can change overnight.
    static func nextDay(after date: Date, calendar: Calendar = FootprintCalendar.localCalendar) -> Date? {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
    }

    static func nextAttempt(after date: Date, importEligible: Bool, completedDates: [Date],
                            notificationRetryNeeded: Bool = false,
                            calendar: Calendar = FootprintCalendar.localCalendar,
                            deliveryCalendar: Calendar = FootprintCalendar.localCalendar) -> Date? {
        guard let tomorrow = nextDay(after: date, calendar: deliveryCalendar),
              let nextMorning = deliveryCalendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) else { return nil }
        guard importEligible else { return nextMorning }
        // [03] A day saved before dawn still needs a morning opportunity for its optional notice.
        if let morning = deliveryCalendar.date(bySettingHour: 8, minute: 0, second: 0, of: date), date < morning {
            return morning
        }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)) else { return nil }
        if completedDates.contains(where: { calendar.isDate($0, inSameDayAs: yesterday) }) {
            // [26] An early saved day is not proof that its morning notice had a chance.
            // Keep retries inside the daytime window, leaving the evening quiet.
            let retry = date.addingTimeInterval(retryInterval)
            if notificationRetryNeeded,
               let evening = deliveryCalendar.date(bySettingHour: 20, minute: 0, second: 0, of: date),
               retry < evening { return retry }
            return nextMorning
        }
        // [04] Apple may publish a completed day later. A retry stays bounded by the next morning.
        return min(date.addingTimeInterval(retryInterval), nextMorning)
    }

    static func shouldSubmit(earliest: Date, pending: [Date?]) -> Bool {
        // [05] A request with no date can already run. Keep it, or any earlier request, rather than delaying an update.
        !pending.contains { $0 == nil || $0! <= earliest }
    }
}

/// [06] Prefer a short refresh. Keep the longer background route available too,
/// so earlier requests and another system opportunity can still help.
enum BackgroundTaskKind: String, CaseIterable, Hashable, Sendable {
    case refresh = "app_refresh"
    case processing

    var identifier: String {
        switch self {
        case .refresh: "ch.zhaw.digitalfootprintexplorer.daily-footprint-refresh"
        case .processing: "ch.zhaw.digitalfootprintexplorer.daily-footprint"
        }
    }
    var requiredBackgroundMode: String { self == .refresh ? "fetch" : "processing" }

    // [07] The saved data is local, so a background opportunity need not wait for internet or charging.
    func makeRequest(earliest: Date) -> BGTaskRequest {
        let request: BGTaskRequest
        switch self {
        case .refresh:
            request = BGAppRefreshTaskRequest(identifier: identifier)
        case .processing:
            let processing = BGProcessingTaskRequest(identifier: identifier)
            processing.requiresExternalPower = false
            processing.requiresNetworkConnectivity = false
            request = processing
        }
        request.earliestBeginDate = earliest
        return request
    }

    // [08] Reject an unexpected kind of system task instead of treating it as a successful daily update.
    func accepts(_ task: BGTask) -> Bool {
        switch self {
        case .refresh: task is BGAppRefreshTask
        case .processing: task is BGProcessingTask
        }
    }
}

enum BackgroundTaskRegistration {
    static func registerAll(using register: (BackgroundTaskKind) -> Bool) -> Set<BackgroundTaskKind> {
        // [09] If iOS refuses one background route, still try to register the other one.
        Set(BackgroundTaskKind.allCases.filter { register($0) })
    }
}

protocol BackgroundRequestClient: Sendable {
    func pendingDates() async throws -> [Date?]
    func submit(earliest: Date) async throws
}

private struct SystemBackgroundRequestClient: BackgroundRequestClient {
    let kind: BackgroundTaskKind

    func pendingDates() async -> [Date?] {
        await BGTaskScheduler.shared.pendingTaskRequests()
            .filter { $0.identifier == kind.identifier }
            .map(\.earliestBeginDate)
    }

    func submit(earliest: Date) async throws {
        let request = kind.makeRequest(earliest: earliest)
        if #available(iOS 27.0, *) {
            try await BGTaskScheduler.shared.submitTaskRequest(request)
        } else {
            try BGTaskScheduler.shared.submit(request)
        }
    }
}

/// [10] The open app and a background update may both ask for another opportunity.
/// Handle those requests in order so a later one does not delay an earlier one.
actor BackgroundRequestCoordinator {
    private let client: any BackgroundRequestClient
    private var tail: Task<Void, Never>?

    init(client: any BackgroundRequestClient) { self.client = client }

    func submitIfNeeded(earliest: Date) async throws -> Bool {
        let previous = tail
        let client = client
        let work = Task {
            await previous?.value
            let pending = try await client.pendingDates()
            guard BackgroundSchedule.shouldSubmit(earliest: earliest, pending: pending) else { return false }
            try await client.submit(earliest: earliest)
            return true
        }
        // [11] Let this failed attempt finish so the next request can try again.
        tail = Task { _ = try? await work.value }
        return try await work.value
    }
}

enum BackgroundLaneSubmission: Equatable, Sendable {
    case submitted, earlierRequestKept, failed
}

/// [12] The two background routes keep their own requests and errors.
/// If one fails, the other can still ask iOS for an opportunity.
struct BackgroundRequestLanes: Sendable {
    let refresh: BackgroundRequestCoordinator
    let processing: BackgroundRequestCoordinator

    func submit(earliest: Date, enabled: Set<BackgroundTaskKind>) async -> [BackgroundTaskKind: BackgroundLaneSubmission] {
        await withTaskGroup(of: (BackgroundTaskKind, BackgroundLaneSubmission).self) { group in
            for kind in BackgroundTaskKind.allCases where enabled.contains(kind) {
                let coordinator = kind == .refresh ? refresh : processing
                group.addTask {
                    do {
                        let submitted = try await coordinator.submitIfNeeded(earliest: earliest)
                        return (kind, submitted ? .submitted : .earlierRequestKept)
                    } catch { return (kind, .failed) }
                }
            }
            var results: [BackgroundTaskKind: BackgroundLaneSubmission] = [:]
            for await (kind, result) in group { results[kind] = result }
            return results
        }
    }
}

/// [13] iOS can end an update while a day is being saved.
/// Share the stop signal and report completion once, even if both actions finish together.
final class BackgroundTaskLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var completed = false
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
    }
    // [14] The time limit and the update can finish together. Only one may tell iOS the task is done.
    func claimCompletion() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}

@MainActor
// [15] Connect the shared history, Screen Time and notices to the opportunities that iOS provides.
final class BackgroundScheduler {
    // [16] Keep the original identifier for existing profiles and debugger checks.
    nonisolated static let identifier = "ch.zhaw.digitalfootprintexplorer.daily-footprint"
    nonisolated static let refreshIdentifier = "ch.zhaw.digitalfootprintexplorer.daily-footprint-refresh"
    private let store: FootprintStore
    private let screenTime: ScreenTimeService?
    private let notifications: GardenNotificationService?
    private var registrationAttempted = false
    private var registeredKinds: Set<BackgroundTaskKind> = []
    private var failedSchedulingKinds: Set<BackgroundTaskKind> = []
    private let requests = BackgroundRequestLanes(
        refresh: BackgroundRequestCoordinator(client: SystemBackgroundRequestClient(kind: .refresh)),
        processing: BackgroundRequestCoordinator(client: SystemBackgroundRequestClient(kind: .processing)))
    var lastSchedulingError: String? {
        if registrationAttempted && registeredKinds.isEmpty {
            return "Daily background updates could not be registered. Updates will run when the app opens."
        }
        if registrationAttempted && registeredKinds.count < BackgroundTaskKind.allCases.count {
            return "Some background update opportunities are unavailable. Updates also run when the app opens."
        }
        if !failedSchedulingKinds.isEmpty {
            return "Some background updates could not be scheduled. Completed days will also update when the app opens."
        }
        return nil
    }

    init(store: FootprintStore, screenTime: ScreenTimeService? = nil, notifications: GardenNotificationService? = nil) {
        self.store = store
        self.screenTime = screenTime
        self.notifications = notifications
    }

    /// [17] Register once before launch finishes, as iOS requires for background work.
    func register() {
        #if DEBUG
        guard !UITestIsolation(arguments: ProcessInfo.processInfo.arguments).isActive else { return }
        #endif
        guard !registrationAttempted else { return }
        registrationAttempted = true
        registeredKinds = BackgroundTaskRegistration.registerAll { kind in
            BGTaskScheduler.shared.register(forTaskWithIdentifier: kind.identifier, using: nil) { [weak self] task in
                guard kind.accepts(task) else {
                    task.setTaskCompleted(success: false)
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self else { task.setTaskCompleted(success: false); return }
                    self.run(task, kind: kind)
                }
            }
        }
        #if DEBUG
        BackgroundUpdateDiagnostics.record(event: "register", source: "background", trigger: "application_launch",
            store: store, service: screenTime,
            outcome: registeredKinds.count == BackgroundTaskKind.allCases.count ? "registered" : "registration_error")
        #endif
    }

    /// [18] iOS chooses the actual run time. An unavailable completed day gets a later retry request.
    func schedule(now: Date = Date()) {
        #if DEBUG
        guard !UITestIsolation(arguments: ProcessInfo.processInfo.arguments).isActive else { return }
        #endif
        // [19] Only the saved all-app setup can request these automatic imports.
        // An unfinished setup stays pending instead of creating an empty day.
        guard !registeredKinds.isEmpty, store.usesAutomaticInput, let screenTime,
              screenTime.activityScope == .allAuthorizedApps else { return }
        screenTime.refreshAuthorization()
        let importEligible = screenTime.state.canImport && screenTime.hasEligibleCompletedDay(store: store, now: now)
        let completedDates = store.records.filter(\.isCompleted).compactMap { store.date(for: $0.day) }
        let calendar = store.aggregationCalendar
        let deliveryCalendar = FootprintCalendar.localCalendar
        let notifications = notifications
        let store = store
        let requests = requests
        let enabled = registeredKinds
        Task.detached { [weak self] in
            let owner = self
            let notificationRetryNeeded: Bool
            if importEligible, let notifications {
                notificationRetryNeeded = await notifications.needsRetry(store: store,
                    automaticAccessReady: true, now: now)
            } else { notificationRetryNeeded = false }
            guard let earliest = BackgroundSchedule.nextAttempt(after: now, importEligible: importEligible,
                completedDates: completedDates, notificationRetryNeeded: notificationRetryNeeded,
                calendar: calendar, deliveryCalendar: deliveryCalendar) else { return }
            let results = await requests.submit(earliest: earliest, enabled: enabled)
            await MainActor.run {
                guard let owner else { return }
                for (kind, result) in results {
                    if result == .failed { owner.failedSchedulingKinds.insert(kind) }
                    else { owner.failedSchedulingKinds.remove(kind) }
                    #if DEBUG
                    let outcome = result == .submitted ? "submitted"
                        : result == .earlierRequestKept ? "earlier_request_kept" : "submission_error"
                    BackgroundUpdateDiagnostics.record(event: "schedule", source: "background",
                        trigger: "daily_update_request_" + kind.rawValue,
                        store: owner.store, service: owner.screenTime, outcome: outcome)
                    #endif
                }
            }
        }
    }

    private func run(_ backgroundTask: BGTask, kind: BackgroundTaskKind) {
        // [20] Request the next opportunity before this run can expire or be suspended.
        schedule()
        let lifetime = BackgroundTaskLifetime()
        #if DEBUG
        let launch = BackgroundUpdateDiagnostics.nextLaunchContext()
        let trigger = launch.trigger == "system_callback_observed"
            ? launch.trigger + "_" + kind.rawValue : launch.trigger
        BackgroundUpdateDiagnostics.record(event: "start", source: "background", trigger: trigger,
            store: store, service: screenTime)
        #endif
        let work = Task { @MainActor [weak self] in
            var success = false
            var result: ScreenTimeRefreshResult?
            #if DEBUG
            var outcome: String?
            let diagnosticOwner = self
            #endif
            defer {
                // [27] The new result or notice reservation can change the next useful time.
                // A temporary morning failure should keep a later chance on the same day.
                self?.schedule()
                if lifetime.claimCompletion() {
                    backgroundTask.setTaskCompleted(success: success)
                    #if DEBUG
                    if let diagnosticOwner {
                        BackgroundUpdateDiagnostics.record(event: "finish", source: "background", trigger: trigger,
                            store: diagnosticOwner.store, service: diagnosticOwner.screenTime, result: result, outcome: outcome,
                            taskCompleted: true, taskSuccess: success)
                    }
                    #endif
                }
            }
            guard let self else { return }
            do {
                try Task.checkCancellation()
                // [21] Read the same saved history whether iOS opens the app in the background or the person opens it.
                try store.reload()
                if store.usesAutomaticInput {
                    if let screenTime {
                        // [22] Background time is limited, so both routes focus on yesterday.
                        // When the person opens the app, it can also revisit older missing days.
                        result = try await screenTime.refreshAutomaticDays(store: store, backfillLimit: 0,
                            origin: kind == .refresh ? .backgroundRefresh : .backgroundProcessing)
                    } else {
                        result = ScreenTimeRefreshResult(stoppedForAccess: true)
                    }
                }
                // [23] Keep the next requested opportunity even when Apple has not supplied a complete day yet.
                #if DEBUG
                if launch.probe && trigger == "simulated_debugger" {
                    let probe = await IsolatedBackgroundProbe.run(normalStore: store)
                    BackgroundUpdateDiagnostics.record(event: "probe", source: "background", trigger: trigger,
                        store: store, service: screenTime, outcome: probe.outcome, probe: probe)
                }
                #endif
                try Task.checkCancellation()
                if !lifetime.isCancelled, let result, result.canNotifyLatestCompletedDay,
                   let notifications, let screenTime {
                    await notifications.afterRefresh(store: store,
                        automaticAccessReady: screenTime.state.canImport && screenTime.activityScope == .allAuthorizedApps)
                }
                try Task.checkCancellation()
                success = !lifetime.isCancelled && (result?.completedWithoutFatalError ?? true)
                #if DEBUG
                if result == nil { outcome = ScreenTimeRefreshOutcome.noNewRecord.rawValue }
                #endif
            } catch is CancellationError {
                #if DEBUG
                outcome = "cancelled"
                #endif
                // [24] A waiting foreground request can retry after this work stops.
            } catch {
                #if DEBUG
                outcome = "error"
                #endif
                store.report(error)
            }
        }
        // [25] When iOS takes back its time, stop further work and keep already saved days.
        // The app can try the missing days again later.
        backgroundTask.expirationHandler = { [weak self] in
            lifetime.cancel()
            work.cancel()
            if lifetime.claimCompletion() {
                backgroundTask.setTaskCompleted(success: false)
                #if DEBUG
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    BackgroundUpdateDiagnostics.record(event: "finish", source: "background", trigger: trigger,
                        store: self.store, service: self.screenTime, outcome: "cancelled",
                        taskCompleted: true, taskSuccess: false)
                }
                #endif
            }
        }
    }
}
