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

// [01] Keep connection, daily notices, app information and appearance in one predictable order.
struct SettingsScreen: View {
    @ObservedObject var store: FootprintStore
    @ObservedObject var screenTime: ScreenTimeService
    @EnvironmentObject private var notifications: GardenNotificationService
    @EnvironmentObject private var watch: WatchCompanionService
    @AppStorage(AppServices.watchSharingKey, store: WatchSharingPreference.defaults) private var watchSharing = false
    @AppStorage(AppAppearance.storageKey, store: AppAppearance.preferenceStore)
    private var appearance: AppAppearance = .light
    @State private var delete = false
    @State private var isDeleting = false
    @State private var automaticSetup = false
    private let rowSpacing: CGFloat = 16

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TabPageLayout.sectionSpacing) {
                VStack(alignment: .leading, spacing: TabPageLayout.introSpacing) {
                    Text("Make yourself at home")
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("settings.intro")
                    Text("Check your connection, choose a look you like, and manage the estimates saved on this device.")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("settings.introExplanation")
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)

                // [02] Related connection rows share one rhythm; whole sections stay farther apart.
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ScreenTimeSettingsView(store: store, service: screenTime) {
                        automaticSetup = true
                    }

                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("The iOS app uses the same category-based calculation as the Android app. It combines app use, estimated data traffic, screen brightness and background activity.")
                            Text("Traffic rates are fixed starting scenarios. They are not measured averages. A different rate can change the result a lot, especially for video.")
                            Text("The garden compares each day's estimate with your average from up to seven earlier days. Lower estimates help it grow, while higher estimates make it wilt. It shows a change in model estimates, rather than a measured environmental impact.")
                            if let note = AdaptiveDeviceLayout.modelScopeNote(isPad: UIDevice.current.userInterfaceIdiom == .pad) {
                                Text(note)
                            }
                        }
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                    } label: {
                        // [03] Use the system's title and icon together for the row that opens this explanation.
                        Label {
                            Text("How the estimate works")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "slider.horizontal.3").accessibilityHidden(true)
                        }
                        .labelStyle(.titleAndIcon)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("settings.modelDetails")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settings.section.connection")

                GardenNotificationSettingsSection(notifications: notifications) {
                    await AppServices.shared.refresh()
                }

                if WatchCompanionService.isSupported && watch.watchIsPaired {
                    settingsSection("On your Apple Watch", id: "watch") {
                        Toggle(isOn: $watchSharing) {
                            SettingsActionLabel("Show my garden on Apple Watch", symbol: "applewatch")
                        }
                        .tint(.green)
                        .accessibilityIdentifier("settings.watchSharing")
                        .onChange(of: watchSharing) { _, enabled in
                            AppServices.shared.setWatchSharing(enabled)
                        }
                        Text(watchSharing
                             ? "Only the latest saved estimate, date and garden are sent to your paired Watch. Updates may wait for a connection."
                             : "Share your latest garden with your paired Watch when you choose. App names and activity times stay on your iPhone.")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        if watchSharing {
                            Text(watch.transferStatus).font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                settingsSection("About this app", id: "about") {
                    NavigationLink { PrivacyPolicyView(publicURL: ReleaseLinks.privacyPolicy) } label: {
                        SettingsActionLabel("Privacy policy", symbol: "hand.raised", showsChevron: true)
                    }
                    .accessibilityIdentifier("settings.privacy")
                    if let support = ReleaseLinks.support {
                        Link(destination: support) {
                            SettingsActionLabel("Help and support", symbol: "questionmark.circle", showsChevron: true)
                        }
                        .accessibilityIdentifier("settings.support")
                    }
                    SettingsValueRow(title: "Version", value: ReleaseLinks.versionLabel)
                        .accessibilityIdentifier("settings.version")
                }

                settingsSection("Appearance", id: "appearance") {
                    NavigationLink {
                        AppearanceSelectionView(selection: $appearance)
                    } label: {
                        SettingsValueRow(title: "Theme", value: appearance.title, showsChevron: true)
                            .frame(minHeight: 44)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Appearance")
                    .accessibilityValue(appearance.title)
                    .accessibilityIdentifier("settings.appearance")
                }

                settingsSection("Your data", id: "data") {
                    Text("Your daily estimates are stored on this device and are not sent to a server. Earlier saved entries remain available to read.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if store.archive?.containsScreenTimeDerivedData == true {
                        Text("History with Screen Time data stays on this device. Export is not available.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("settings.exportUnavailable")
                    }
                    Button(role: .destructive) { delete = true } label: {
                        SettingsActionLabel("Delete all entries", symbol: "trash")
                    }
                    .foregroundStyle(.red)
                    .disabled(isDeleting)
                    .accessibilityIdentifier("settings.delete")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, TabPageLayout.horizontal)
            .padding(.top, TabPageLayout.top)
            .padding(.bottom, TabPageLayout.bottom)
            .frame(maxWidth: TabPageLayout.contentWidth)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .automaticRefresh()
        .accessibilityIdentifier("settings.form")
        .background(FootprintAppearance.page)
        .accessibilityHidden(automaticSetup)
        .navigationTitle("Settings")
        .sheet(isPresented: $automaticSetup, onDismiss: { Task { await AppServices.shared.refresh() } }) {
            AutomaticOnboardingView(store: store, service: screenTime).withUITestTextSize()
        }
        // [04] Deletion and disconnection have different effects. This confirmation names the permanent
        // local deletion clearly, while leaving Apple permission unchanged.
        .alert("Delete all entries?", isPresented: $delete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete all entries", role: .destructive) {
                guard !isDeleting else { return }
                isDeleting = true
                Task {
                    defer { isDeleting = false }
                    do {
                        // [05] Clear saved data first; only a successful deletion should reset the related local choices and notices.
                        try screenTime.deleteSavedEntries(in: store)
                        AppServices.shared.watch.clear()
                        watchSharing = false
                        AppServices.shared.setWatchSharing(false)
                        AppAppearance.resetLocalPreferences()
                        await notifications.resetAfterDeletingHistory()
                    } catch { store.report(error) }
                }
            }
        } message: {
            Text("This permanently deletes your saved days and settings. Screen Time access is unchanged.")
        }
    }

    // [06] Reuse one spacing pattern so each section feels like part of the same Settings screen.
    private func settingsSection<Content: View>(
        _ title: String, id: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            Text(title).font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.section." + id)
    }
}

// [07] Give related actions the same icon gap and touch area, including longer labels.
struct SettingsActionLabel: View {
    let title: String
    let symbol: String
    var showsChevron = false

    init(_ title: String, symbol: String, showsChevron: Bool = false) {
        self.title = title
        self.symbol = symbol
        self.showsChevron = showsChevron
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(title).fixedSize(horizontal: false, vertical: true)
            if showsChevron {
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote)
                    .foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
        .font(.body)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// [08] Keep the current value at the trailing edge when it fits; larger text gets its own line.
private struct SettingsValueRow: View {
    let title: String
    let value: String
    var showsChevron = false
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if textSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).fixedSize(horizontal: false, vertical: true)
                    Text(value).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(title).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Text(value).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsChevron {
                if textSize.isAccessibilitySize { Spacer(minLength: 12) }
                Image(systemName: "chevron.right").font(.footnote)
                    .foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
        .font(.body)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
    }
}

// [09] Offer one appearance choice for the whole app, with a checkmark that is also read by VoiceOver.
private struct AppearanceSelectionView: View {
    @Binding var selection: AppAppearance

    var body: some View {
        List(AppAppearance.allCases) { mode in
            Button { selection = mode } label: {
                HStack(spacing: 12) {
                    Text(mode.title).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    if selection == mode {
                        Image(systemName: "checkmark").accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selection == mode ? .isSelected : [])
            .accessibilityIdentifier("appearance." + mode.rawValue)
        }
        .scrollContentBackground(.hidden)
        .background(FootprintAppearance.page)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}
