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

import XCTest
@testable import DFE

final class WatchSharingPreferenceTests: XCTestCase {
    // [01] Both kinds of test need their own switch; neither should reset real Watch consent.
    func testUIAndUnitStoresStaySeparateFromNormalPreferences() {
        let normal = WatchSharingPreference.makeStore(arguments: [], environment: [:])
        XCTAssertTrue(normal === UserDefaults.standard)
        let before = normal.object(forKey: WatchSharingPreference.key) as? Bool
        for (arguments, environment) in [(["-ui-testing"], [String: String]()),
                                          ([String](), ["XCTestBundlePath": "isolated-test"]) ] {
            let isolated = WatchSharingPreference.makeStore(arguments: arguments, environment: environment)
            XCTAssertFalse(isolated === normal)
            let saved = isolated.object(forKey: WatchSharingPreference.key)
            isolated.set(true, forKey: WatchSharingPreference.key)
            isolated.set(false, forKey: WatchSharingPreference.key)
            XCTAssertEqual(normal.object(forKey: WatchSharingPreference.key) as? Bool, before)
            if let saved { isolated.set(saved, forKey: WatchSharingPreference.key) }
            else { isolated.removeObject(forKey: WatchSharingPreference.key) }
        }
    }
}
