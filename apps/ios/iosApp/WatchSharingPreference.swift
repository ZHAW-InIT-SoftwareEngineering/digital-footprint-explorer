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

// [01] A screen test can switch Watch sharing without changing the owner's saved choice.
enum WatchSharingPreference {
    static let key = "dfe.watchSharingEnabled"
    static let defaults: UserDefaults = makeStore()

    static func makeStore(arguments: [String] = ProcessInfo.processInfo.arguments,
                          environment: [String: String] = ProcessInfo.processInfo.environment) -> UserDefaults {
        #if DEBUG
        let isUI = arguments.contains("-ui-testing")
        let isUnit = environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
        guard isUI || isUnit else { return .standard }
        let isolated = UserDefaults(suiteName: isUI ? "dfe.watch.ui-testing" : "dfe.watch.unit-testing")!
        if arguments.contains("-reset-ui-state") { isolated.removeObject(forKey: key) }
        return isolated
        #else
        return .standard
        #endif
    }
}
