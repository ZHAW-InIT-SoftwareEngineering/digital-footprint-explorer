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

/// [01] Explain the scope once; daily imports never need an app-by-app selection.
struct AutomaticOnboardingView: View {
    @ObservedObject var store: FootprintStore
    @ObservedObject var service: ScreenTimeService
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var previewConnected = false
    @State private var error: String?
    @State private var activationTask: Task<Void, Never>?

    // [02] This test screen cannot grant Apple access or read real activity.
    static var isControlledPreview: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-ui-testing") && args.contains("-ui-automatic-preview")
        #else
        return false
        #endif
    }
    private var hasDataAccess: Bool { Self.isControlledPreview ? previewConnected : service.state.canImport }
    private var reportOnly: Bool { service.state == .reportOnly }
    private var presentedAccessState: ScreenTimeState {
        #if DEBUG
        if Self.isControlledPreview && !reportOnly {
            // The setup preview starts from the requested scenario even when test data is already saved.
            return ProcessInfo.processInfo.arguments.contains("-ui-revoked-preview") ? .revoked : .notRequested
        }
        #endif
        return service.state
    }
    private var connectionActionTitle: String {
        if service.isRequesting { return "Connecting…" }
        return presentedAccessState == .revoked ? "Reconnect Screen Time" : "Enable automatic estimates"
    }
    private var connectionActionHint: String {
        presentedAccessState == .revoked
            ? "Resume automatic estimates. Your saved results stay available."
            : "Allow Screen Time to start automatic daily estimates."
    }
    private var assumptions: FootprintInputs {
        AutomaticActivityClassification.assumptions(preserving: store.profile)
    }

    var body: some View {
        NavigationStack {
            Group {
                if reportOnly {
                    limitedAccessAction
                } else {
                    setupContent
                }
            }
            .background(FootprintAppearance.page)
            .onDisappear { activationTask?.cancel() }
            .navigationTitle("Automatic setup").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(appLanguage.text(reportOnly ? "Done" : "Cancel")) { dismiss() }
            } }
            .alert("Could not start automatic input", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) { Button("OK") { error = nil } } message: { Text(appLanguage.text(error ?? "")) }
        }
    }

    private var limitedAccessAction: some View {
        Link(destination: ReleaseLinks.support ?? DeviceHelpLinks.screenTime(language: appLanguage)) {
            Text("Get Screen Time help")
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .modifier(TodayActionStyle()).controlSize(.large)
        .accessibilityIdentifier("automatic.support")
        .frame(maxWidth: 320)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("automatic.limitedAccess")
    }

    private var setupContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !textSize.isAccessibilitySize {
                    GardenArtwork(state: .stable).frame(height: 110).frame(maxWidth: .infinity)
                }
                Text("Let your garden follow your day")
                    .font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                Text("A little space to notice your device habits, one day at a time. Allow Screen Time once and leave the daily estimates to the app. No app selection or daily forms.")
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 12) {
                    Label("Your activity stays on this device", systemImage: "lock.shield")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("automatic.localPrivacy")
                    Text("Screen Time supplies available app usage from this device. Carbon emissions, data traffic and the other calculation inputs remain estimates.")
                        .accessibilityIdentifier("automatic.estimateScope")
                    Text("Your first estimate waits for a completed day and usable activity from Apple. Until then, your garden will wait with you.")
                        .accessibilityIdentifier("automatic.firstCompletedDay")
                }.font(.subheadline).fixedSize(horizontal: false, vertical: true)
                NavigationLink { PrivacyPolicyView(publicURL: ReleaseLinks.privacyPolicy) } label: {
                    Label("Read the privacy policy", systemImage: "hand.raised")
                        .frame(minHeight: 44).fixedSize(horizontal: false, vertical: true)
                }.accessibilityIdentifier("automatic.privacy")
                if hasDataAccess {
                    activationButton("Start automatic estimates")
                        .accessibilityIdentifier("automatic.start")
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if presentedAccessState != .notRequested && presentedAccessState != .revoked {
                            Text(appLanguage.text(presentedAccessState.title)).font(.headline)
                            Text(appLanguage.text(presentedAccessState.explanation))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if service.supportsAutomaticSetup || Self.isControlledPreview {
                            activationButton(connectionActionTitle)
                                .accessibilityHint(appLanguage.text(connectionActionHint))
                                .accessibilityIdentifier("automatic.connect")
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Automatic input needs a supported build, iOS 26.4 or later and Apple's expanded Screen Time access. Access for App Store customers also depends on Apple's EU conditions.")
                                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("automatic.unavailable")
                        }
                        if let error = service.lastError { Text(appLanguage.screenTimeMessage(error)).font(.footnote) }
                    }
                }
                Text("You can disconnect in Settings whenever you like. There is no account to create and no daily target to meet.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
    }

    private func activationButton(_ title: String) -> some View {
        Button { start(with: assumptions) } label: {
            HStack(spacing: 10) {
                Text(appLanguage.text(title)).font(.headline).multilineTextAlignment(.center)
                if service.isRequesting { ProgressView().accessibilityHidden(true) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 28)
        }
        .modifier(TodayActionStyle()).controlSize(.large)
        .disabled(service.isRequesting)
        .frame(maxWidth: 360)
    }

    // [05] A second tap replaces the earlier start attempt, rather than opening two permission requests.
    private func start(with inputs: FootprintInputs) {
        activationTask?.cancel()
        activationTask = Task { await activate(with: inputs) }
    }

    // [06] Save the automatic setup only after Apple allows data access.
    // If permission is missing or the screen closes, leave the previous setup alone.
    private func activate(with inputs: FootprintInputs) async {
        error = nil
        if Self.isControlledPreview { previewConnected = true }
        else if !service.state.canImport { await service.requestAuthorization() }
        guard !Task.isCancelled, hasDataAccess else { return }
        do {
            if Self.isControlledPreview {
                #if DEBUG
                try service.saveControlledAllActivitySetup(inputs: inputs, store: store)
                #endif
            }
            else {
                #if SCREEN_TIME_ENABLED
                try service.saveAllActivitySetup(inputs: inputs, store: store)
                #else
                throw ScreenTimeImportError.permissionRequired
                #endif
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
