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

// [01] The chosen appearance should feel consistent, and a widget tap should lead back to the
// garden

import SwiftUI
import UIKit
import XCTest
@testable import DFE

final class AppAppearanceTests: XCTestCase {
    // [02] White is the agreed starting appearance; following the phone is a separate choice.
    func testDefaultIsLightAndSystemRemainsAnExplicitChoice() {
        XCTAssertEqual(AppAppearance.defaultPreference.colorScheme, .light)
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }

    // [03] A normal launch should respect the person's saved choice, rather than a test-only
    // setting.
    func testNormalLaunchUsesTheSavedChoiceInsteadOfTestOverrides() {
        XCTAssertEqual(AppAppearance.resolvedColorScheme(
            for: .dark, arguments: [], environment: ["UI_TEST_COLOR_SCHEME": "light"]), .dark)
        XCTAssertEqual(AppAppearance.resolvedColorScheme(
            for: .light, arguments: ["-ui-dark-mode"], environment: [:]), .light)
        XCTAssertNil(AppAppearance.resolvedColorScheme(for: .system, arguments: [], environment: [:]))
    }

    #if DEBUG
    // [04] A fixed test appearance lets us compare layouts without changing the person's own
    // preference.
    func testIsolatedInterfaceLaunchCanRequestADeterministicAppearance() {
        XCTAssertEqual(AppAppearance.resolvedColorScheme(
            for: .light, arguments: ["-ui-testing", "-ui-dark-mode"], environment: [:]), .dark)
        XCTAssertEqual(AppAppearance.resolvedColorScheme(
            for: .dark, arguments: ["-ui-testing"], environment: ["UI_TEST_COLOR_SCHEME": "light"]), .light)
        XCTAssertEqual(AppAppearance.resolvedColorScheme(
            for: .dark, arguments: ["-ui-testing"], environment: ["UI_TEST_COLOR_SCHEME": "invalid"]), .dark)
    }
    #endif

    // [05] All tabs need the same background, so moving between them does not cause an unexpected
    // flash.
    @MainActor func testCanvasIsPureWhiteInLightModeAndUsesTheNativeDarkBackground() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let canvas = AppSurface.canvasUIColor
        assertSameRGB(canvas.resolvedColor(with: light), UIColor.white)
        assertSameRGB(canvas.resolvedColor(with: dark), UIColor.systemBackground.resolvedColor(with: dark))
    }

    // [06] A widget should open Today, while an unrelated link must leave the current screen
    // alone.
    @MainActor func testWidgetLinksReturnToTodayAndIgnoreUnrelatedURLs() {
        let navigation = AppNavigationState()
        navigation.selectedTab = .settings
        let originalRoot = navigation.todayRootID
        navigation.openWidgetURL(URL(string: "https://example.com/today")!)
        XCTAssertEqual(navigation.selectedTab, .settings)
        XCTAssertEqual(navigation.todayRootID, originalRoot)

        navigation.openWidgetURL(URL(string: "digitalfootprint://today")!)
        XCTAssertEqual(navigation.selectedTab, .today)
        XCTAssertNotEqual(navigation.todayRootID, originalRoot)
        let firstVisit = navigation.todayRootID
        navigation.openWidgetURL(URL(string: "digitalfootprint://today")!)
        XCTAssertNotEqual(navigation.todayRootID, firstVisit,
                          "A second widget tap must also leave a saved-day detail")
    }

    private func assertSameRGB(_ actual: UIColor, _ expected: UIColor,
                               file: StaticString = #filePath, line: UInt = #line) {
        var actualRed: CGFloat = 0, actualGreen: CGFloat = 0, actualBlue: CGFloat = 0, actualAlpha: CGFloat = 0
        var expectedRed: CGFloat = 0, expectedGreen: CGFloat = 0, expectedBlue: CGFloat = 0, expectedAlpha: CGFloat = 0
        XCTAssertTrue(actual.getRed(&actualRed, green: &actualGreen, blue: &actualBlue, alpha: &actualAlpha), file: file, line: line)
        XCTAssertTrue(expected.getRed(&expectedRed, green: &expectedGreen, blue: &expectedBlue, alpha: &expectedAlpha), file: file, line: line)
        XCTAssertEqual(actualRed, expectedRed, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualGreen, expectedGreen, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualBlue, expectedBlue, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualAlpha, expectedAlpha, accuracy: 0.001, file: file, line: line)
    }
}
