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

// [01] The system owns the modal layout, accessibility and Liquid Glass appearance.
struct DisconnectScreenTimeConfirmation: ViewModifier {
    @Environment(\.appLanguage) private var appLanguage
    @Binding var isPresented: Bool
    let connected: Bool
    let disconnect: () -> Void

    // [02] Removing permission can stop imports, and keeps saved days in either case.
    func body(content: Content) -> some View {
        content.alert(appLanguage.text(connected ? "Disconnect Screen Time?" : "Remove Screen Time access?"),
                      isPresented: $isPresented) {
            Button(appLanguage.text("Cancel"), role: .cancel) { }
                .accessibilityIdentifier("screen-time.cancelDisconnect")
            Button(appLanguage.text(connected ? "Disconnect" : "Remove access"),
                   role: .destructive, action: disconnect)
                .accessibilityIdentifier("screen-time.confirmDisconnect")
        } message: {
            Text(appLanguage.text(connected
                ? "Automatic estimates will pause. Your saved days will stay on this device."
                : "DFE will lose its Screen Time permission. Your saved days will stay on this device."))
        }
    }
}
