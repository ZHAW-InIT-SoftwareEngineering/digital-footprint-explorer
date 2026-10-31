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

// [01] Daily updates are optional. Let the person choose them without making notifications
// a condition for seeing their garden or importing Screen Time.
struct GardenNotificationSettingsSection: View {
    @ObservedObject var notifications: GardenNotificationService
    var afterEnable: () async -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A morning moment").font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("settings.notificationHeading")
            VStack(spacing: 0) {
                Toggle(isOn: Binding(get: { notifications.enabled }, set: { requested in
                    Task {
                        await notifications.setEnabled(requested)
                        if notifications.enabled { await afterEnable() }
                    }
                })) {
                    SettingsActionLabel("Daily garden update", symbol: "bell.badge")
                }
                .tint(FootprintAppearance.accent)
                .disabled(notifications.isUpdating)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("settings.dailyGardenNotification")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("settings.dailyGardenNotificationRow")
            Text("A gentle reminder around 8:00 in your local time, even when DFE is closed. Fresh estimates still depend on Apple's data and time to refresh.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.notificationTiming")
            // [02] After Apple refuses access, send the person to the system control rather than repeatedly asking.
            if notifications.authorizationDenied {
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                } label: {
                    SettingsActionLabel("Open notification settings", symbol: "bell", showsChevron: true)
                }
                .accessibilityIdentifier("settings.notificationPermissions")
            }
            if let message = notifications.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.section.notifications")
        .task { await notifications.refreshPreference() }
    }
}
