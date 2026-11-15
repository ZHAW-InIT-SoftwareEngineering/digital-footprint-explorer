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

    static func widgets(language: AppLanguage) -> URL {
        guide(language, phone: "iphb8f1bf206", pad: "ipad1b2665da")
    }

    static func screenTime(language: AppLanguage) -> URL {
        guide(language, phone: "iphb0c7313c9", pad: "ipad37239c84", englishPhonePrefix: "set-schedules-with-screen-time-")
    }

    static func notifications(language: AppLanguage) -> URL {
        guide(language, phone: "iph7c3d96bab", pad: "ipad870e28f5", englishPhonePrefix: "change-notification-settings-")
    }

    static func focus(language: AppLanguage) -> URL {
        guide(language, phone: "iphd6288a67f", pad: "ipad2789d162", englishPhonePrefix: "set-up-a-focus-")
    }

    // [02] Use Apple's Swiss guides when the app is in German, along with the familiar English guides.
    private static func guide(_ language: AppLanguage, phone: String, pad: String,
                              englishPhonePrefix: String = "") -> URL {
        if language.locale.language.languageCode?.identifier == "de" {
            let path = isPad ? "ipad/\(pad)/27/ipados/27" : "iphone/\(phone)/27/ios/27"
            return URL(string: "https://support.apple.com/de-ch/guide/\(path)")!
        }
        let path = isPad ? "ipad/\(pad)/ipados" : "iphone/\(englishPhonePrefix)\(phone)/ios"
        return URL(string: "https://support.apple.com/guide/\(path)")!
    }
}
