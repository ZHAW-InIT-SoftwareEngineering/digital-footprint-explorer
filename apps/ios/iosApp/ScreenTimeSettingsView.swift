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

// [01] Show one connection summary, with the detailed status available when the person wants it.
struct ScreenTimeSettingsView: View {
    @ObservedObject var store: FootprintStore
    @ObservedObject var service: ScreenTimeService
    let showSetup: () -> Void
    @State private var showDetails = false
    @State private var confirmDisconnect = false
    @State private var isDisconnecting = false
    #if DEBUG
    @State private var previewDisconnected = false
    #endif

    // [02] This separate test screen cannot grant or remove Apple's permission.
    private static var isControlledDisconnectPreview: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-ui-testing") && args.contains("-ui-automatic-preview")
            && args.contains("-ui-disconnect-preview")
        #else
        return false
        #endif
    }

    private var setupSaved: Bool { service.hasSavedAutomaticSetup(store: store) }

    // [03] Green means both the saved automatic setup and live data access are ready.
    // Permission alone does not mean the setup is complete.
    private var connected: Bool {
        #if DEBUG
        if Self.isControlledDisconnectPreview { return !previewDisconnected }
        #endif
        return setupSaved && service.state.canImport
    }

    private var canDisconnect: Bool {
        #if DEBUG
        if Self.isControlledDisconnectPreview { return !previewDisconnected }
        #endif
        #if SCREEN_TIME_ENABLED
        return service.state == .dataAccess || service.state == .reportOnly
        #else
        return false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Screen Time")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("screen-time.heading")
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 20) {
                // [04] Read the connection as one short message. The shield is decoration,
                // so older iOS versions should not read its name instead of the status.
                Label {
                    Text(connected ? "Connected" : "Not connected")
                } icon: {
                    Image(systemName: statusSymbol).accessibilityHidden(true)
                }
                .font(.headline)
                .foregroundStyle(statusColor)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(connected ? "Connected" : "Not connected")
                .accessibilityIdentifier("screen-time.status")
                Text(statusExplanation)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)

            if store.widgetDaysWaitingForAutomaticSetup {
                Text("The widget has saved estimates that aren’t in your history. It won’t collect new activity until automatic estimates are set up.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("screen-time.widgetDaysWaiting")
            }

            if !connected {
                Button(action: showSetup) {
                    SettingsActionLabel(service.state == .revoked ? "Reconnect Screen Time"
                                        : setupSaved ? "Review connection" : "Enable automatic estimates",
                                        symbol: "arrow.triangle.2.circlepath")
                }
                .foregroundStyle(FootprintAppearance.accent)
                .accessibilityHint(service.state == .revoked
                    ? "Resume automatic estimates. Your saved results stay available." : "")
                .accessibilityIdentifier("settings.automaticSetup")
            }

            #if DFE_WIDGET_AUTOMATIC_IMPORT
            // [12] A failed disconnect keeps widget reads paused. Let the person resume explicitly
            // instead of quietly undoing their choice during the next refresh.
            if connected && store.widgetAutomaticUpdatesPaused {
                Button(action: showSetup) {
                    SettingsActionLabel("Resume widget updates", symbol: "arrow.triangle.2.circlepath")
                }
                .foregroundStyle(FootprintAppearance.accent)
                .accessibilityHint("Review automatic access. Your saved results stay available.")
                .accessibilityIdentifier("screen-time.resumeWidgetUpdates")
            }
            #endif

            if connected || setupSaved || service.state == .reportOnly {
                DisclosureGroup(isExpanded: $showDetails) {
                    connectionDetails.padding(.top, 12)
                } label: {
                    SettingsActionLabel("Connection details", symbol: "link")
                        .accessibilityIdentifier("screen-time.management")
                }
            }

            if let error = service.lastError { notice(error) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(DisconnectScreenTimeConfirmation(isPresented: $confirmDisconnect,
                                                  disconnect: disconnect))
    }

    // [05] Explain the scope and last import in one place, then keep Disconnect behind an explicit confirmation.
    private var connectionDetails: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(service.activityScope == .allAuthorizedApps
                 ? "All available app activity is included. Unknown apps are grouped under Other apps."
                 : "Your saved activity choices are kept. Review the connection to include all available app activity.")
                .accessibilityIdentifier("screen-time.allActivity")
            Text("Completed days update when the app opens and when iOS allows background work. Missing or incomplete days stay pending.")
            AutomaticUpdateChecksView(store: store, verification: store.importVerification)
            if canDisconnect {
                Divider()
                Button(role: .destructive) {
                    confirmDisconnect = true
                } label: {
                    SettingsActionLabel("Disconnect Screen Time", symbol: "xmark.shield")
                }
                .foregroundStyle(.red)
                .disabled(isDisconnecting)
                .accessibilityHint("Asks for confirmation. Your saved daily estimates are kept.")
                .accessibilityIdentifier("screen-time-disconnect")
            }
        }
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func disconnect() {
        // [06] Only the alert's Disconnect action reaches Apple's permission API.
        guard !isDisconnecting else { return }
        #if DEBUG
        if Self.isControlledDisconnectPreview {
            previewDisconnected = true
            return
        }
        #endif
        isDisconnecting = true
        Task {
            await service.disconnect()
            isDisconnecting = false
        }
    }

    private var statusExplanation: String {
        #if DEBUG
        if Self.isControlledDisconnectPreview && previewDisconnected {
            return "Automatic estimates are off. Your saved days stay on this device."
        }
        #endif
        if connected {
            return "Automatic daily estimates are on. Your app activity stays on this device."
        }
        if service.state == .dataAccess {
            return "Screen Time access is available. Enable automatic estimates to finish the setup."
        }
        return service.state.explanation
    }

    // [07] Use words and a distinct symbol alongside colour, so the connection does not depend on colour vision.
    private var statusSymbol: String {
        #if DEBUG
        if Self.isControlledDisconnectPreview && previewDisconnected { return "xmark.shield" }
        #endif
        if connected { return "checkmark.shield" }
        switch service.state {
        case .unavailable: return "clock"
        case .notRequested, .dataAccess: return "hourglass"
        case .denied: return "hand.raised"
        case .reportOnly: return "doc.text"
        case .revoked: return "xmark.shield"
        }
    }

    private var statusColor: Color {
        if connected { return FootprintAppearance.accent }
        // [08] A deeper red stays readable on white; dark mode uses a lighter shade.
        return Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: 1, green: 0.59, blue: 0.59, alpha: 1)
            }
            return traits.accessibilityContrast == .high
                ? UIColor(red: 0.57, green: 0.08, blue: 0.10, alpha: 1)
                : UIColor(red: 0.70, green: 0.12, blue: 0.15, alpha: 1)
        })
    }

    private func notice(_ error: String) -> some View {
        Label {
            Text(error).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Screen Time notice. \(error)")
    }
}

// [09] Keep saved checks behind the connection details. They explain what ran on this
// iPhone without exposing app choices, usage amounts or the garden's calculation inputs.
private struct AutomaticUpdateChecksView: View {
    @ObservedObject var store: FootprintStore
    @ObservedObject var verification: AutomaticUpdateVerification
    @State private var expanded = false
    @State private var copyMessage: String?

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 18) {
                importDetails
                Divider()
                sharedDetails
                Button {
                    copyChecks()
                } label: {
                    SettingsActionLabel("Copy update checks", symbol: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(FootprintAppearance.accent)
                .accessibilityIdentifier("screen-time.copyUpdateChecks")
                if let copyMessage {
                    Text(copyMessage).font(.footnote).foregroundStyle(.secondary)
                }
                Text("These checks stay on this device. Times use your current time zone. A widget data read does not tell us exactly when iOS displayed it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)
        } label: {
            SettingsActionLabel("Automatic update checks", symbol: "clock.arrow.circlepath")
                .accessibilityIdentifier("screen-time.updateChecks")
        }
    }

    @ViewBuilder private var importDetails: some View {
        if verification.persistenceFailed {
            Text("The import check could not be saved. Your daily results are kept separately.")
                .foregroundStyle(.secondary)
        }
        if let check = store.latestVerifiedAutomaticSave {
            checkRow("Completed day", detail: check.day)
            checkRow("Last verified import", detail: timestamp(check.lastObservedAt) + " · " + origin(check.lastOrigin))
            checkRow("App at saved time", detail: completion(check.lastCompletionState))
            checkRow("Recorded by", detail: "DFE " + check.lastProducer.appVersion + " (" + check.lastProducer.appBuild + ")"
                     + (check.lastProducer.isDebug ? " · Development check" : " · Release check")
                     + (check.lastProducer.isSimulator ? " · Simulator" : " · Device"))
            if check.initialSaveObserved {
                checkRow("First save for this day", detail: timestamp(check.firstObservedAt) + " · " + completion(check.firstCompletionState))
                if check.firstProducer.isDebug || check.firstProducer.isSimulator {
                    Text("That first saved check came from a development run.").foregroundStyle(.secondary)
                }
            } else {
                Text("The first import time for this older day was not recorded. The time above belongs to a later verified save.")
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("No verified import has been recorded for this day yet. Older saved days keep their results, with no guessed import time.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var sharedDetails: some View {
        if store.widgetCheckSaveFailed {
            Text("The local copy of the widget check could not be saved.").foregroundStyle(.secondary)
        }
        if let check = store.widgetVerification {
            let current = check.status == .verified && check.day == store.latest?.day && check.receiptStored
            checkRow("Shared garden data", detail: current ? "Verified for " + (check.day ?? "this day") : sharedStatus(check))
            checkRow("Checked on this device", detail: timestamp(check.checkedAt))
        } else {
            checkRow("Shared garden data", detail: store.widgetStorageAvailable
                     ? "Not verified on this device yet" : "Shared storage is unavailable")
        }
        ForEach(["small", "medium"], id: \.self) { family in
            let check = store.widgetReadChecks.first { $0.family == family }
            let title = family == "small" ? "Small widget data read" : "Medium widget data read"
            if let check {
                let current = check.status == .verified && check.day == store.latest?.day
                checkRow(title, detail: current
                    ? (check.day ?? "") + " · " + timestamp(check.readAt)
                    : "Waiting for the latest saved day")
            } else {
                checkRow(title, detail: "Waiting for iOS to read the widget data")
            }
        }
    }

    private func checkRow(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).fontWeight(.medium)
            Text(detail).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func timestamp(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .standard) }
    private func origin(_ value: AutomaticUpdateOrigin) -> String {
        value == .foreground ? "Started while open" : "Started by background work"
    }
    private func completion(_ value: AutomaticUpdateCompletionState) -> String {
        switch value {
        case .active: return "App open"
        case .inactive: return "App inactive"
        case .background: return "App in background"
        case .unknown: return "Not recorded"
        }
    }
    // [10] Copy only the fixed support fields. The full history and widget values are never part of this report.
    private func copyChecks() {
        let report = AutomaticUpdateSupportReport(capturedAt: Date(),
            producer: .current, latestSavedDay: store.latest?.day,
            verifiedSave: store.latestVerifiedAutomaticSave,
            importCheckSaveFailed: verification.persistenceFailed,
            publication: store.widgetVerification, widgetReads: store.widgetReadChecks,
            widgetCheckSaveFailed: store.widgetCheckSaveFailed)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            guard let text = String(data: data, encoding: .utf8) else { return }
            // [11] Keep these copied checks off nearby devices and remove them after a short handover.
            UIPasteboard.general.setObjects([text], localOnly: true,
                                           expirationDate: Date().addingTimeInterval(300))
            copyMessage = "Checks copied. They contain dates and status, with no app usage amounts."
        } catch {
            copyMessage = "The update checks could not be copied."
        }
    }
    private func sharedStatus(_ value: WidgetPublicationVerification) -> String {
        if value.status == .empty { return "No saved garden yet" }
        if value.status == .unavailable { return "Shared storage is unavailable" }
        guard value.receiptStored else { return "The data was checked, but its check could not be saved" }
        switch value.status {
        case .verified: return "Waiting for the latest saved day"
        case .empty: return "No saved garden yet"
        case .unavailable: return "Shared storage is unavailable"
        case .unreadable: return "Shared data could not be read"
        case .mismatch: return "Shared data needs another check"
        case .writeFailed: return "Shared data could not be saved"
        }
    }
}
