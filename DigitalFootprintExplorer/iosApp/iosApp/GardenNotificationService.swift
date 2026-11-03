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
import Combine
import UserNotifications

// [01] iOS holds the dated reminders, so their delivery does not depend on DFE staying open.
// A reminder invites a visit; only a fresh saved result can describe yesterday's garden.
private actor SystemGardenNotificationClient: GardenNotificationClient {
    let center: UNUserNotificationCenter
    init(center: UNUserNotificationCenter) { self.center = center }

    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }
    // [02] Inspect only this feature's notices, so turning it off does not touch unrelated requests.
    func requestState() async -> GardenNotificationRequestState {
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let delivered = await center.deliveredNotifications().map { $0.request.identifier }
        return GardenNotificationRequestState(
            pendingIdentifiers: pending.filter { $0.hasPrefix(DailyGardenNotificationPlan.prefix) },
            deliveredIdentifiers: delivered.filter { $0.hasPrefix(DailyGardenNotificationPlan.prefix) })
    }
    func add(_ plan: DailyGardenNotificationPlan) async throws {
        let request = GardenNotificationRequestBuilder.make(plan)
        // [17] If eight o'clock passed while we were preparing a replacement, leave the
        // existing morning card alone rather than turning an old request into another immediate alert.
        if let trigger = request.trigger as? UNCalendarNotificationTrigger,
           trigger.nextTriggerDate() == nil { throw GardenNotificationRequestError.deliveryWindowPassed }
        try await center.add(request)
    }

    func remove(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

private enum GardenNotificationRequestError: Error { case deliveryWindowPassed }

// [18] Keep the native request in one place so tests can check the same calendar trigger
// that iOS receives. No network service or activity details are needed for a reminder.
enum GardenNotificationRequestBuilder {
    static func make(_ plan: DailyGardenNotificationPlan) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        content.threadIdentifier = "dfe.garden.daily"
        content.userInfo = ["gardenURL": DailyGardenNotificationPlan.gardenURL,
            "deliveryDay": plan.deliveryDay, "recordDay": plan.recordDay,
            "timeZone": plan.timeZoneIdentifier, "noticeKind": plan.kind.rawValue]
        let trigger: UNNotificationTrigger?
        if plan.scheduledForMorning || plan.kind == .reminder {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: plan.timeZoneIdentifier) ?? .autoupdatingCurrent
            // [19] Leave the trigger's time zone unset: its dated eight o'clock follows
            // the iPhone's local clock, including daylight-saving changes.
            let fields = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: plan.deliverAt)
            trigger = UNCalendarNotificationTrigger(dateMatching: fields, repeats: false)
        } else { trigger = nil }
        return UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
    }
}

#if DEBUG
/// [04] Interface and unit tests use their own notice list, leaving the person's real notifications alone.
private actor IsolatedGardenNotificationClient: GardenNotificationClient {
    private var pending: [String] = []
    func isAuthorized() async -> Bool { true }
    func requestState() async -> GardenNotificationRequestState { .init(pendingIdentifiers: pending) }
    func add(_ plan: DailyGardenNotificationPlan) async throws {
        if !pending.contains(plan.identifier) { pending.append(plan.identifier) }
    }
    func remove(identifiers: [String]) async { pending.removeAll { identifiers.contains($0) } }
}

#endif

@MainActor
// [05] Keep the person's choice and Apple's live permission separate.
// A saved switch alone is not proof that the system will display a notice.
final class GardenNotificationService: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var authorizationDenied = false
    @Published private(set) var isUpdating = false
    @Published private(set) var errorMessage: String?
    private let coordinator: DailyGardenNotificationCoordinator
    private let center: UNUserNotificationCenter
    private let isolated: Bool
    private enum ErrorSource { case preference, setting, scheduling, reminders, reset }
    private var errorSource: ErrorSource?
    #if DEBUG
    private var lastTechnicalSubmission: String?
    #endif

    init(ledgerURL: URL, center: UNUserNotificationCenter = .current(), isolated: Bool = false) {
        self.center = center
        #if DEBUG
        self.isolated = isolated
        let client: any GardenNotificationClient = isolated
            ? IsolatedGardenNotificationClient() : SystemGardenNotificationClient(center: center)
        #else
        self.isolated = false
        let client: any GardenNotificationClient = SystemGardenNotificationClient(center: center)
        #endif
        coordinator = DailyGardenNotificationCoordinator(client: client,
            ledgerStore: FileGardenNotificationLedgerStore(url: ledgerURL))
    }

    convenience init(store: FootprintStore, center: UNUserNotificationCenter = .current()) {
        let url = store.fileURL.deletingPathExtension().appendingPathExtension("garden-notifications.json")
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        let environment = ProcessInfo.processInfo.environment
        let uiTest = args.contains("-ui-testing")
        let unitTest = environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
        if uiTest, args.contains("-reset-ui-state"), store.fileURL.lastPathComponent == "dfe-ui-testing.json",
           store.fileURL.deletingLastPathComponent().standardizedFileURL == FileManager.default.temporaryDirectory.standardizedFileURL {
            // [06] Reset only the notice file next to the separate test history, before its test service is created.
            try? FileManager.default.removeItem(at: url)
        }
        self.init(ledgerURL: url, center: center, isolated: uiTest || unitTest)
        #else
        self.init(ledgerURL: url, center: center)
        #endif
    }

    // [07] Read the current choice and renew the next thirty mornings when DFE gets time.
    // Permission may have changed outside the app; reading it never opens another permission prompt.
    func refreshPreference() async {
        do {
            enabled = try await coordinator.isEnabled()
            if isolated { authorizationDenied = false }
            else {
                let status = await center.notificationSettings().authorizationStatus
                authorizationDenied = status == .denied
            }
            clearError(from: .preference)
            if enabled {
                let result = try await coordinator.prepareMorningReminders(now: Date())
                if result == .schedulingFailed {
                    showError("Some morning reminders could not be prepared. Please try again.", from: .reminders)
                } else if result == .scheduled || result == .alreadyReserved {
                    clearError(from: .reminders)
                }
            }
        } catch {
            enabled = false
            showError("Daily garden updates could not be read. Your estimates are safe.", from: .preference)
        }
        #if DEBUG
        // [21] Keep a current technical receipt after renewal, so device checks can verify
        // the queued dates and wording variety without reading anyone's usage or notice text.
        await captureTechnicalState()
        #endif
    }

    /// [08] Permission is requested only after the person chooses the Settings toggle.
    func setEnabled(_ requested: Bool) async {
        guard !isUpdating else { return }
        isUpdating = true
        clearError(from: .setting)
        defer { isUpdating = false }
        do {
            if requested {
                let allowed = isolated ? true : try await center.requestAuthorization(options: [.alert, .sound])
                guard allowed else {
                    try await coordinator.setEnabled(false)
                    await refreshPreference()
                    return
                }
            }
            try await coordinator.setEnabled(requested)
            if !requested { clearError(from: .scheduling); clearError(from: .reminders) }
            clearError(from: .setting)
            await refreshPreference()
        } catch {
            showError("Daily garden updates could not be changed. Please try again.", from: .setting)
            await refreshPreference()
        }
    }

    // [09] A fresh history also starts a fresh notice record, without leaving old pending garden updates behind.
    func resetAfterDeletingHistory() async {
        do {
            try await coordinator.reset()
            errorMessage = nil
            errorSource = nil
            await refreshPreference()
        } catch { showError("Daily garden updates could not be reset. Please try again.", from: .reset) }
    }

    /// [10] Run only after saving the result that also feeds the garden and widget.
    func afterRefresh(store: FootprintStore, automaticAccessReady: Bool, now: Date = Date()) async {
        let plan = DailyGardenNotificationPlan.make(records: store.records,
            automaticAccessReady: store.usesAutomaticInput && automaticAccessReady,
            now: now, recordCalendar: store.aggregationCalendar, deliveryCalendar: FootprintCalendar.localCalendar)
        do {
            let result = try await coordinator.submit(plan, now: now, calendar: FootprintCalendar.localCalendar)
            #if DEBUG
            lastTechnicalSubmission = String(describing: result)
            #endif
            if result == .schedulingFailed {
                showError("Your estimate is safe, but its daily update could not be sent.", from: .scheduling)
            } else if result == .scheduled || result == .disabled {
                clearError(from: .scheduling)
            }
        } catch is CancellationError { return }
        catch { showError("Your estimate is safe, but its daily update could not be prepared.", from: .scheduling) }
        await refreshPreference()
    }

    // [14] This is only a request for another data check. The old saved day is never
    // sent here; a later successful import must still pass the normal delivery checks.
    func needsRetry(store: FootprintStore, automaticAccessReady: Bool, now: Date = Date()) async -> Bool {
        let candidate = DailyGardenNotificationPlan.make(records: store.records,
            automaticAccessReady: store.usesAutomaticInput && automaticAccessReady,
            now: now, recordCalendar: store.aggregationCalendar, deliveryCalendar: FootprintCalendar.localCalendar)
        return (try? await coordinator.needsRetry(for: candidate, now: now, calendar: FootprintCalendar.localCalendar)) ?? false
    }

    #if DEBUG
    // [20] A clearly labelled development reminder lets the owner close DFE and check
    // native delivery today. It uses the real request builder, but never reserves a production day.
    @discardableResult
    func scheduleForceQuitReminderTest() async -> Bool {
        guard !isolated, BackgroundUpdateDiagnostics.isAllowed,
              (try? await coordinator.isEnabled()) == true else { return false }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return false }
        let now = Date()
        let plan = DailyGardenNotificationPlan(kind: .reminder, scheduledForMorning: true,
            deliveryDay: "test-force-quit", recordDay: "", title: "DFE Reminder Test",
            body: "This reminder was prepared before DFE closed. Tap to open your garden.",
            deliverAt: now.addingTimeInterval(120), timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier)
        do {
            try await center.add(GardenNotificationRequestBuilder.make(plan))
            let receipt: [String: String] = ["prepared_at": ISO8601DateFormatter().string(from: now),
                "scheduled_for": ISO8601DateFormatter().string(from: plan.deliverAt),
                "identifier": plan.identifier, "purpose": "Explicit force-quit delivery test; not a daily estimate"]
            let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let file = cache.appendingPathComponent("DFENotificationDiagnostics/force-quit-test-v1.json")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
                .write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch { return false }
    }

    /// [11] Read-only system state for a connected development session. It never
    /// adds, cancels or reveals notification text, app identities or usage.
    @discardableResult
    func captureTechnicalState(now: Date = Date()) async -> Bool {
        guard !isolated, BackgroundUpdateDiagnostics.isAllowed else { return false }
        let settings = await center.notificationSettings()
        let pendingRequests = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(DailyGardenNotificationPlan.prefix) }
        let pending = pendingRequests.map(\.identifier)
        let copyCount = Set(pendingRequests.filter {
            !GardenNotificationTechnicalSnapshot.deliveryDays(from: [$0.identifier]).isEmpty
        }.map { $0.content.title + "\n" + $0.content.body }).count
        let delivered = await center.deliveredNotifications().map { $0.request.identifier }
            .filter { $0.hasPrefix(DailyGardenNotificationPlan.prefix) }
        let preference = try? await coordinator.isEnabled()
        let snapshot = GardenNotificationTechnicalSnapshot(capturedAt: now,
            enabled: preference, authorization: GardenNotificationTechnicalSnapshot.authorizationLabel(settings.authorizationStatus),
            alert: GardenNotificationTechnicalSnapshot.settingLabel(settings.alertSetting),
            sound: GardenNotificationTechnicalSnapshot.settingLabel(settings.soundSetting),
            notificationCenter: GardenNotificationTechnicalSnapshot.settingLabel(settings.notificationCenterSetting),
            lockScreen: GardenNotificationTechnicalSnapshot.settingLabel(settings.lockScreenSetting),
            scheduledDelivery: GardenNotificationTechnicalSnapshot.settingLabel(settings.scheduledDeliverySetting),
            alertStyle: GardenNotificationTechnicalSnapshot.alertStyleLabel(settings.alertStyle),
            previews: GardenNotificationTechnicalSnapshot.previewLabel(settings.showPreviewsSetting),
            pendingCount: pending.count, deliveredCount: delivered.count,
            pendingDistinctCopyCount: copyCount,
            pendingDeliveryDays: GardenNotificationTechnicalSnapshot.deliveryDays(from: pending),
            deliveredDeliveryDays: GardenNotificationTechnicalSnapshot.deliveryDays(from: delivered),
            lastSubmission: lastTechnicalSubmission)
        do {
            let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let file = cache.appendingPathComponent(GardenNotificationTechnicalSnapshot.relativePath)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(snapshot).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch { return false }
    }
    #endif

    private func showError(_ message: String, from source: ErrorSource) {
        errorSource = source
        errorMessage = message
    }
    // [12] A successful permission check must not hide a different error, such as a notice that could not be sent.
    private func clearError(from source: ErrorSource) {
        guard errorSource == source else { return }
        errorSource = nil
        errorMessage = nil
    }
}

/// [13] A notification opens the same Today route as either Home Screen widget.
final class GardenNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let openGarden: @MainActor () -> Void
    init(openGarden: @escaping @MainActor () -> Void) { self.openGarden = openGarden }

    // [14] Accept only this feature's saved route, then open Today on the main screen thread.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              response.notification.request.identifier.hasPrefix(DailyGardenNotificationPlan.prefix),
              response.notification.request.content.userInfo["gardenURL"] as? String == DailyGardenNotificationPlan.gardenURL else {
            completionHandler()
            return
        }
        Task { @MainActor [openGarden] in
            openGarden()
            completionHandler()
        }
    }
    /// [15] Let an optional daily notice appear even if the open app imports first.
    /// The saved date stamp still prevents a second notice from background work.
    static func foregroundPresentationOptions(identifier: String, gardenURL: String?) -> UNNotificationPresentationOptions {
        guard identifier.hasPrefix(DailyGardenNotificationPlan.prefix),
              gardenURL == DailyGardenNotificationPlan.gardenURL else { return [] }
        return [.banner, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(Self.foregroundPresentationOptions(
            identifier: notification.request.identifier,
            gardenURL: notification.request.content.userInfo["gardenURL"] as? String))
    }
}

#if DEBUG
/// [16] Keep fixed technical labels only, without the notice text or its attached details.
struct GardenNotificationTechnicalSnapshot: Codable {
    static let relativePath = "DFENotificationDiagnostics/state-v1.json"
    var schemaVersion = 1
    var debugOnly = true
    let capturedAt: Date
    let enabled: Bool?
    let authorization: String
    let alert: String
    let sound: String
    let notificationCenter: String
    let lockScreen: String
    let scheduledDelivery: String
    let alertStyle: String
    let previews: String
    let pendingCount: Int
    let deliveredCount: Int
    let pendingDistinctCopyCount: Int
    let pendingDeliveryDays: [String]
    let deliveredDeliveryDays: [String]
    let lastSubmission: String?

    static func deliveryDays(from identifiers: [String]) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let days = FootprintCalendar(calendar: calendar)
        return identifiers.compactMap { identifier in
            guard identifier.hasPrefix(DailyGardenNotificationPlan.prefix) else { return nil }
            let value = String(identifier.dropFirst(DailyGardenNotificationPlan.prefix.count))
            return value.count == 10 && days.date(value) != nil ? value : nil
        }.sorted()
    }
    static func authorizationLabel(_ value: UNAuthorizationStatus) -> String {
        switch value {
        case .notDetermined: "not_determined"
        case .denied: "denied"
        case .authorized: "authorized"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        @unknown default: "unknown"
        }
    }
    static func settingLabel(_ value: UNNotificationSetting) -> String {
        switch value {
        case .enabled: "enabled"
        case .disabled: "disabled"
        case .notSupported: "not_supported"
        @unknown default: "unknown"
        }
    }
    static func alertStyleLabel(_ value: UNAlertStyle) -> String {
        switch value {
        case .none: "none"
        case .banner: "banner"
        case .alert: "alert"
        @unknown default: "unknown"
        }
    }
    static func previewLabel(_ value: UNShowPreviewsSetting) -> String {
        switch value {
        case .always: "always"
        case .whenAuthenticated: "when_authenticated"
        case .never: "never"
        @unknown default: "unknown"
        }
    }
}
#endif
