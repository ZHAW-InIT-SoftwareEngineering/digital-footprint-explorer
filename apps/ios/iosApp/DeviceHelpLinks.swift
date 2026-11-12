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

import Foundation
import UIKit

// [01] A tablet user should reach the tablet guide. These links only open after a tap.
@MainActor
enum DeviceHelpLinks {
    private static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    static var widgets: URL { URL(string: isPad
        ? "https://support.apple.com/guide/ipad/ipad1b2665da/ipados"
        : "https://support.apple.com/guide/iphone/iphb8f1bf206/ios")! }
    static var screenTime: String { isPad
        ? "https://support.apple.com/guide/ipad/ipad37239c84/ipados"
        : "https://support.apple.com/guide/iphone/set-schedules-with-screen-time-iphb0c7313c9/ios" }
    static var notifications: String { isPad
        ? "https://support.apple.com/guide/ipad/ipad870e28f5/ipados"
        : "https://support.apple.com/guide/iphone/change-notification-settings-iph7c3d96bab/ios" }
    static var focus: String { isPad
        ? "https://support.apple.com/guide/ipad/ipad2789d162/ipados"
        : "https://support.apple.com/guide/iphone/set-up-a-focus-iphd6288a67f/ios" }
}
