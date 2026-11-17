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
import CoreGraphics
@testable import DFE

final class AdaptiveDeviceLayoutTests: XCTestCase {
    // [04] Tablet support must explain the unchanged model, without adding that warning to a phone.
    func testOnlyIPadShowsThePhoneReferenceModelNote() {
        XCTAssertNil(AdaptiveDeviceLayout.modelScopeNote(isPad: false))
        XCTAssertEqual(AdaptiveDeviceLayout.modelScopeNote(isPad: true),
            "On iPad, this estimate uses the app's phone reference model. It is not a measurement of iPad energy use.")
    }

    // [01] Turning a phone sideways must not squeeze the garden into two columns just because it is wider.
    func testCompactWidthKeepsOneColumnAtEveryWindowWidth() {
        for width: CGFloat in [320, 390, 760, 960, 1_366] {
            XCTAssertFalse(AdaptiveDeviceLayout(width: width, regularWidth: false, accessibilityText: false).usesColumns)
        }
    }

    // [02] A split window uses the available width, even when the physical device is much larger.
    func testRegularWindowsChangeLayoutAtTheReadableWidthBoundary() {
        XCTAssertFalse(AdaptiveDeviceLayout(width: 759, regularWidth: true, accessibilityText: false).usesColumns)
        for width: CGFloat in [760, 820, 1_024, 1_366] {
            let layout = AdaptiveDeviceLayout(width: width, regularWidth: true, accessibilityText: false)
            XCTAssertTrue(layout.usesColumns)
            XCTAssertGreaterThanOrEqual(layout.detailWidth, 260)
            XCTAssertGreaterThanOrEqual(layout.gardenWidth, 294.3)
            XCTAssertLessThanOrEqual(layout.gardenWidth, 400)
            XCTAssertLessThanOrEqual(layout.gardenHeight, 300)
            let available = min(width, AdaptiveDeviceLayout.maximumContentWidth) - layout.horizontalPadding * 2
            XCTAssertLessThanOrEqual(layout.detailWidth + layout.gardenWidth + AdaptiveDeviceLayout.columnGap, available)
        }
    }

    // [03] Larger accessibility text gets the full line width instead of a narrow side column.
    func testAccessibilityAndInvalidWidthsNeverChooseColumns() {
        for width: CGFloat in [760, 1_024, 1_366] {
            XCTAssertFalse(AdaptiveDeviceLayout(width: width, regularWidth: true, accessibilityText: true).usesColumns)
        }
        for width: CGFloat in [.nan, .infinity, -.infinity, -1, 0] {
            let layout = AdaptiveDeviceLayout(width: width, regularWidth: true, accessibilityText: false)
            XCTAssertFalse(layout.usesColumns)
            XCTAssertTrue(layout.gardenWidth.isFinite)
        }
    }

    // [05] The saved-day summary moves beside the garden only where both columns have room to read.
    func testShortRegularWindowsGiveTheSavedContextMoreSpace() {
        let openWindow = AdaptiveDeviceLayout(width: 867, height: 553, regularWidth: true, accessibilityText: false)
        let tallWindow = AdaptiveDeviceLayout(width: 867, height: 728, regularWidth: true, accessibilityText: false)
        XCTAssertTrue(openWindow.usesSideBySideEstimate)
        XCTAssertGreaterThan(openWindow.detailWidth, tallWindow.detailWidth)
        XCTAssertFalse(tallWindow.usesSideBySideEstimate)
        for height: CGFloat in [298, 429, 641, .nan, .infinity] {
            XCTAssertFalse(AdaptiveDeviceLayout(width: 832, height: height,
                regularWidth: true, accessibilityText: false).usesSideBySideEstimate)
        }
        XCTAssertFalse(AdaptiveDeviceLayout(width: 382, height: 562,
            regularWidth: false, accessibilityText: false).usesSideBySideEstimate)
        XCTAssertFalse(AdaptiveDeviceLayout(width: 867, height: 553,
            regularWidth: true, accessibilityText: true).usesSideBySideEstimate)
    }
}
