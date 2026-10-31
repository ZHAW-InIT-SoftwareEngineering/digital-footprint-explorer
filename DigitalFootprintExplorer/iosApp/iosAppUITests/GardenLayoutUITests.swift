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

// [01] The garden is the focus, with enough room around its date, actions and explanations to keep
// them usable

import XCTest

@MainActor
final class GardenLayoutUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }

    // [02] The welcome and saved date should be readable before the widget action, without
    // crowding the garden.
    func testGardenWelcomeAndDateRemainAboveTheWidgetAction() {
        let app = AutomaticUITestSupport.open(fixture: true, legacyToday: true)
        XCTAssertTrue(app.staticTexts["footprint.total"].waitForExistence(timeout: 8))
        let welcome = app.staticTexts["today.welcome"]
        let date = app.staticTexts["today.date"]
        let setup = app.buttons["today.widgetHelp"]
        AutomaticUITestSupport.reach(welcome, in: app)
        XCTAssertFalse(welcome.label.isEmpty)
        XCTAssertFalse(date.label.isEmpty)
        XCTAssertGreaterThanOrEqual(date.frame.minY, welcome.frame.maxY - 1)
        AutomaticUITestSupport.reach(setup, in: app)
        XCTAssertGreaterThanOrEqual(setup.frame.height, 44)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        XCTAssertFalse(app.buttons["today.automaticSetup"].exists)
        AutomaticUITestSupport.capture("Garden after completed automatic setup")
    }

    // [03] After setup, the widget action still needs space above the tab bar so it remains easy
    // to tap.
    func testCompletedSetupKeepsWidgetActionClearOfTheTabs() {
        for legacyToday in [false, true] {
            let app = AutomaticUITestSupport.open(fixture: true, legacyToday: legacyToday)
            let action = app.buttons["today.widgetHelp"]
            AutomaticUITestSupport.reach(action, in: app)
            XCTAssertFalse(app.buttons["today.automaticSetup"].exists)
            XCTAssertTrue(action.isHittable)
            XCTAssertGreaterThanOrEqual(action.frame.height, 44)
            XCTAssertLessThanOrEqual(action.frame.maxY, app.tabBars.firstMatch.frame.minY - 4,
                                     "The widget action must be clear of the floating tabs")
            let details = app.buttons["today.dayDetails"]
            AutomaticUITestSupport.reach(details, in: app)
            let bottomGap = app.tabBars.firstMatch.frame.minY - details.frame.maxY
            XCTAssertGreaterThanOrEqual(bottomGap, 4,
                                        "The last action must remain clear of the floating tabs")
            XCTAssertLessThanOrEqual(bottomGap, 48,
                                     "Short days should use the screen instead of leaving a large blank footer")
            AutomaticUITestSupport.capture("Full-height Today after completed setup")
            app.terminate()
        }
    }

    // [04] A pending day needs a clear explanation with room below the garden, rather than a
    // squeezed warning.
    func testPendingExplanationHasRoomBelowTheGardenAfterSetup() {
        let app = AutomaticUITestSupport.open(fixture: true)
        let state = app.staticTexts["garden.state"]
        let explanation = app.staticTexts["today.automaticPending"]
        AutomaticUITestSupport.reach(explanation, in: app)
        XCTAssertGreaterThanOrEqual(explanation.frame.minY - state.frame.maxY, 26)
        XCTAssertFalse(state.label == "Growing", "The state needs a sentence, not a badge label")
        XCTAssertFalse(app.buttons["today.automaticSetup"].exists)
        AutomaticUITestSupport.capture("Pending explanation after completed setup")
    }

    // [05] The welcome should respond to the estimate itself, without asking the person to name or
    // customize a garden.
    func testGardenFeedbackFollowsTheSavedEstimateWithoutPersonalizationForms() {
        for legacyToday in [false, true] {
            let app = AutomaticUITestSupport.open(fixture: true, legacyToday: legacyToday)
            let message = app.staticTexts["garden.state"]
            AutomaticUITestSupport.reach(message, in: app)
            XCTAssertTrue(message.label.contains(legacyToday ? "above your recent average" : "starting point"))
            XCTAssertEqual(app.staticTexts["today.welcome"].label, "Good to have you here")
            XCTAssertFalse(AutomaticUITestSupport.element("today.personalize", in: app).exists)
            AutomaticUITestSupport.capture("Automatic garden feedback without personal questions")
            app.tabBars.buttons["Settings"].tap()
            XCTAssertFalse(AutomaticUITestSupport.element("settings.personalize",
                in: AutomaticUITestSupport.element("settings.form", in: app)).exists)
            XCTAssertFalse(app.textFields["gardenPreferences.name"].exists)
            AutomaticUITestSupport.assertNoManualEntry(in: app)
            app.terminate()
        }
    }

    // [06] Opening widget instructions should help with the widget, rather than restart Screen
    // Time setup.
    func testTodayOpensTheWidgetGuideWithoutStartingScreenTimeSetup() {
        let app = AutomaticUITestSupport.open(fixture: true)
        let link = app.buttons["today.widgetHelp"]
        AutomaticUITestSupport.reach(link, in: app)
        XCTAssertGreaterThanOrEqual(link.frame.height, 44)
        link.tap()
        let bar = app.navigationBars["Your garden widget"]
        XCTAssertTrue(bar.waitForExistence(timeout: 8))
        let content = AutomaticUITestSupport.element("widget-help.content", in: app)
        let instruction = content.staticTexts["widget-help.quickStart"]
        AutomaticUITestSupport.reach(instruction, in: app, inside: content, below: bar)
        XCTAssertTrue(instruction.label.contains("Home Screen"))
        AutomaticUITestSupport.capture("Optional Home Screen widget setup")
        bar.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.navigationBars["Automatic setup"].exists)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
    }

    // [07] Large text should leave the result and category breakdown readable without losing their
    // meaning.
    func testLargestTextResultAndBreakdownRemainReadable() throws {
        let app = AutomaticUITestSupport.open(fixture: true, largeText: true)
        AutomaticUITestSupport.openHistoryDay(in: app)
        let state = app.staticTexts["garden.state"]
        AutomaticUITestSupport.reach(state, in: app)
        XCTAssertFalse(state.label.isEmpty)
        for id in ["breakdown.app", "breakdown.screen", "breakdown.background"] {
            let row = AutomaticUITestSupport.element(id, in: app)
            AutomaticUITestSupport.reach(row, in: app)
            XCTAssertFalse(row.frame.isEmpty)
        }
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        AutomaticUITestSupport.capture("Largest-text read-only breakdown")
        try app.performAccessibilityAudit(for: [.textClipped, .hitRegion])
    }

    // [08] Dark landscape use should keep both widget help and the day's result navigation
    // available.
    func testDarkLandscapeKeepsWidgetInstructionsAndResultNavigationUsable() throws {
        let app = AutomaticUITestSupport.open(fixture: true, dark: true)
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed)
        let help = app.buttons["today.widgetHelp"]
        AutomaticUITestSupport.reach(help, in: app)
        // [09] Rotating can leave a fraction-of-a-point difference; that should not look like a
        // clipped button.
        XCTAssertGreaterThanOrEqual(help.frame.height, 44 - 0.001)
        help.tap()
        let navigationBar = app.navigationBars["Your garden widget"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 8))
        let content = AutomaticUITestSupport.element("widget-help.content", in: app)
        XCTAssertTrue(content.waitForExistence(timeout: 8))
        let introduction = content.staticTexts["A little piece of your garden, right on your Home Screen."]
        AutomaticUITestSupport.reach(introduction, in: app, inside: content, below: navigationBar)
        AutomaticUITestSupport.capture("Widget instructions in dark landscape")
        app.navigationBars["Your garden widget"].buttons["Done"].tap()
        app.tabBars.buttons["Today"].tap()
        let latest = AutomaticUITestSupport.element("today.latestResult", in: app)
        AutomaticUITestSupport.reach(latest, in: app)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
    }
    // [10] The visible app time belongs to this saved day. Its explanation should stay
    // readable at large text without suggesting that modelled traffic was measured.
    func testImportedActivityAndModelLimitsRemainClearAtNormalAndLargestText() throws {
        for largeText in [false, true] {
            let app = AutomaticUITestSupport.open(fixture: true, largeText: largeText)
            let activity = app.staticTexts["footprint.importedActivity"]
            AutomaticUITestSupport.reach(activity, in: app)
            XCTAssertEqual(activity.label, "Imported app activity: 1 h")
            let details = app.buttons["today.dayDetails"]
            AutomaticUITestSupport.reach(details, in: app)
            details.tap()
            let period = app.staticTexts["source.activityPeriod"]
            XCTAssertTrue(period.waitForExistence(timeout: 8))
            // [11] The navigation transition briefly exposes both scroll views. Find the
            // detail by its content instead of keeping an index that can disappear mid-check.
            let content = app.scrollViews.containing(.staticText, identifier: "source.activityPeriod").firstMatch
            let navigation = app.navigationBars.containing(.button, identifier: "Today").firstMatch
            XCTAssertTrue(content.waitForExistence(timeout: 8))
            XCTAssertTrue(navigation.waitForExistence(timeout: 8))
            AutomaticUITestSupport.reach(period, in: app, inside: content, below: navigation)
            XCTAssertTrue(period.label.contains("can differ from the daily total in Screen Time"))
            let limits = app.staticTexts["source.modelLimits"]
            AutomaticUITestSupport.reach(limits, in: app, inside: content, below: navigation)
            XCTAssertTrue(limits.label.contains("saved category assumptions"))
            XCTAssertTrue(limits.label.contains("Background listening"))
            AutomaticUITestSupport.assertNoManualEntry(in: app)
            AutomaticUITestSupport.capture(largeText ? "Large-text imported activity and model limits" : "Imported activity and model limits")
            try app.performAccessibilityAudit(for: [.textClipped, .hitRegion])
            app.terminate()
        }
    }

}
