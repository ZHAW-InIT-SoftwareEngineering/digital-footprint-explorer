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

import SwiftUI
import UIKit
import UserNotifications

@MainActor
// [01] Share one history, connection and notification service across all tabs and system callbacks.
final class AppServices {
    static let shared = AppServices()
    let store: FootprintStore
    let screenTime: ScreenTimeService
    let notifications: GardenNotificationService
    let navigation = AppNavigationState()
    lazy var background = BackgroundScheduler(store: store, screenTime: screenTime, notifications: notifications)
    private let refreshCoordinator = RefreshCoordinator<Void>()
    private let refreshKey = UUID()

    init(store suppliedStore: FootprintStore? = nil, screenTime suppliedScreenTime: ScreenTimeService? = nil) {
        store = suppliedStore ?? FootprintStore()
        screenTime = suppliedScreenTime ?? ScreenTimeService()
        notifications = GardenNotificationService(store: store)
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-ui-testing"), args.contains("-ui-automatic-preview"),
           args.contains("-ui-example-history"), let profile = store.profile,
           store.automaticStartDate != nil {
            // [02] Date this test setup from today, keeping its sample earlier day in the past.
            do { try screenTime.saveControlledAllActivitySetup(inputs: profile, store: store) }
            catch { store.report(error) }
        }
        #endif
    }

    // [03] One update path keeps the pull gesture, launch recovery and daily results in step.
    func refresh(trigger: AppRefreshTrigger = .applicationRefresh) async {
        do {
            // [04] Share a pull only with work for the same day, zone and setup.
            let context = screenTime.refreshContext(store: store)
                + "|" + FootprintCalendar.localCalendar.timeZone.identifier
            try await refreshCoordinator.perform(key: refreshKey, context: context) { [self] in
                try await performRefresh(trigger: trigger)
            }
        } catch is CancellationError { }
        catch { store.report(error) }
    }

    // [05] Read the latest saved history before importing. Only a saved result may
    // feed the garden, widget or morning notice.
    func performRefresh(trigger: AppRefreshTrigger) async throws {
        #if DEBUG
        // [14] The one-shot comparison reads Apple's answers without refreshing normal history.
        if ProcessInfo.processInfo.arguments.contains(ScreenTimeCoverageDiagnostics.alternativeLaunchArgument) { return }
        #endif
        var result: ScreenTimeRefreshResult?
        #if DEBUG
        var outcome: String?
        BackgroundUpdateDiagnostics.record(event: "start", source: "foreground", trigger: trigger.rawValue,
            store: store, service: screenTime)
        #endif
        defer {
            #if DEBUG
            BackgroundUpdateDiagnostics.record(event: "finish", source: "foreground", trigger: trigger.rawValue,
                store: store, service: screenTime, result: result,
                outcome: outcome ?? (result == nil ? ScreenTimeRefreshOutcome.noNewRecord.rawValue : nil))
            #endif
        }
        do {
            try Task.checkCancellation()
            // [06] Reload before writing so a damaged or replaced archive is protected.
            try store.reload()
        } catch is CancellationError {
            #if DEBUG
            outcome = "cancelled"
            #endif
            throw CancellationError()
        } catch {
            #if DEBUG
            outcome = "error"
            #endif
            store.report(error)
            return
        }
        // [07] Older routines stay readable, but this interface creates automatic days only.
        screenTime.refreshAuthorization()
        if store.usesAutomaticInput {
            do {
                let backfillLimit = AppRefreshBackfillPolicy.limit(
                    isApplicationActive: UIApplication.shared.applicationState == .active)
                result = try await screenTime.refreshAutomaticDays(store: store, backfillLimit: backfillLimit)
            } catch is CancellationError {
                #if DEBUG
                outcome = "cancelled"
                #endif
                throw CancellationError()
            } catch {
                #if DEBUG
                outcome = "error"
                #endif
                store.report(error)
            }
        }
        try Task.checkCancellation()
        if let result, result.canNotifyLatestCompletedDay {
            await notifications.afterRefresh(store: store,
                automaticAccessReady: screenTime.state.canImport && screenTime.activityScope == .allAuthorizedApps)
        }
        await notifications.refreshPreference()
        background.schedule()
    }

}

@MainActor
// [08] Connect Apple's background and notification callbacks during launch, before the first screen appears.
final class ApplicationDelegate: NSObject, UIApplicationDelegate {
    private var gardenNotificationDelegate: GardenNotificationDelegate?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // [09] iOS requires registration before application launch finishes.
        let services = AppServices.shared
        #if DEBUG
        // [10] Separate interface tests leave the system's real background requests and notices untouched.
        if UITestIsolation(arguments: ProcessInfo.processInfo.arguments).isActive { return true }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(ScreenTimeCoverageDiagnostics.alternativeLaunchArgument) {
            if BackgroundUpdateDiagnostics.isAllowed {
                Task { @MainActor in await services.screenTime.captureAlternativeCoverage(store: services.store) }
            }
            return true
        }
        #endif
        let notificationDelegate = GardenNotificationDelegate {
            services.navigation.openWidgetURL(URL(string: DailyGardenNotificationPlan.gardenURL)!)
        }
        gardenNotificationDelegate = notificationDelegate
        UNUserNotificationCenter.current().delegate = notificationDelegate
        services.background.register()
        #if DEBUG
        // [12] A named development launch can prepare one labelled delivery check without
        // keeping a debugger attached. Ordinary launches never request this test reminder.
        if ProcessInfo.processInfo.arguments.contains("-dfe-force-quit-reminder-test") {
            Task { @MainActor in
                await services.notifications.scheduleForceQuitReminderTest()
                await services.notifications.captureTechnicalState()
            }
        }
        #endif
        return true
    }
}

@main
// [11] Apply the chosen appearance at the app root so tabs and open sheets agree.
struct iOSApp: App {
    @UIApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = AppServices.shared.store
    @StateObject private var screenTime = AppServices.shared.screenTime
    @StateObject private var navigation = AppServices.shared.navigation
    @StateObject private var notifications = AppServices.shared.notifications
    @AppStorage(AppAppearance.storageKey, store: AppAppearance.preferenceStore)
    private var appearance: AppAppearance = AppAppearance.defaultPreference

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(AppAppearance.resolvedColorScheme(for: appearance))
                .background(AppSurface.canvas.ignoresSafeArea())
                .environmentObject(store)
                .environmentObject(screenTime)
                .environmentObject(navigation)
                .environmentObject(notifications)
                .task {
                    // [12] If iOS opens the app in the background, leave the daily work to that system request.
                    // If the screen becomes active later, the change handler below starts the open-app update.
                    if scenePhase == .active { await AppServices.shared.refresh() }
                }
                // [13] Update when the app becomes active, even if iOS skipped background work.
                // Also handle midnight while the app stays open, without needing a restart.
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                    if scenePhase == .active { Task { await AppServices.shared.refresh() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                    if scenePhase == .active { Task { await AppServices.shared.refresh() } }
                    else { AppServices.shared.background.schedule() }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    if scenePhase == .active { Task { await AppServices.shared.refresh() } }
                    else { AppServices.shared.background.schedule() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await AppServices.shared.refresh() } }
                    if phase == .background { AppServices.shared.background.schedule() }
                }
        }
    }
}
