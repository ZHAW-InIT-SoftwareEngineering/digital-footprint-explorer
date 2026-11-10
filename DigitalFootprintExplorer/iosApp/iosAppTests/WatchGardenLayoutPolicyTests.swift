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

final class WatchGardenLayoutPolicyTests: XCTestCase {
    // [01] A compact viewport must keep its reading space instead of using the larger screen's full garden height.
    func testSmallViewportReservesRoomForPrimaryAmountAndDate() {
        let height = WatchGardenLayoutPolicy.gardenHeight(availableHeight: 223, accessibilityText: false)
        XCTAssertGreaterThanOrEqual(height, 64)
        XCTAssertLessThan(height, 108)
        XCTAssertLessThanOrEqual(height + WatchGardenLayoutPolicy.primaryContentReserve, 223)
        for tinyHeight in [0.001, 10, 100, WatchGardenLayoutPolicy.primaryContentReserve] {
            XCTAssertEqual(WatchGardenLayoutPolicy.gardenHeight(availableHeight: tinyHeight, accessibilityText: false), 64)
        }
    }

    func testLargeViewportKeepsGardenWithinItsUpperBound() {
        XCTAssertEqual(WatchGardenLayoutPolicy.gardenHeight(availableHeight: 300, accessibilityText: false), 108)
        XCTAssertEqual(WatchGardenLayoutPolicy.gardenHeight(availableHeight: 700, accessibilityText: false), 108)
    }

    func testAccessibilityAndInvalidViewportRemainSafe() {
        let height = WatchGardenLayoutPolicy.gardenHeight(availableHeight: 223, accessibilityText: true)
        XCTAssertEqual(height, 108)
        XCTAssertEqual(WatchGardenLayoutPolicy.gardenHeight(availableHeight: 208, accessibilityText: true), 98)
        for tinyHeight in [0.001, 10, 120, WatchGardenLayoutPolicy.accessibilityContentReserve] {
            XCTAssertEqual(WatchGardenLayoutPolicy.gardenHeight(availableHeight: tinyHeight, accessibilityText: true), 88)
        }
        for invalid in [Double.nan, .infinity, -.infinity, -1, 0] {
            let fallback = WatchGardenLayoutPolicy.gardenHeight(availableHeight: invalid, accessibilityText: true)
            XCTAssertTrue(fallback.isFinite)
            XCTAssertEqual(fallback, 88)
            XCTAssertEqual(WatchGardenLayoutPolicy.gardenHeight(availableHeight: invalid, accessibilityText: false), 64)
        }
    }
}
