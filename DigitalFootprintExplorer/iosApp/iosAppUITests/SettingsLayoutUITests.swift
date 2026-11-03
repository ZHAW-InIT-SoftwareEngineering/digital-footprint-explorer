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

// [01] Settings needs clear spacing and consistent connection controls, including its optional
// morning notices

import XCTest

@MainActor
final class SettingsLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }
    override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }

    // [02] Related settings need clear spacing, with appearance near the bottom and deletion easy
    // to identify.
    func testSettingsKeepsAppearanceNearDeletionAndSectionsReadable() throws {
        try checkSettingsLayout(largeText: false)
    }

    // [03] The largest text setting should keep sections distinct and the destructive action
    // reachable.
    func testSettingsKeepsSectionsAndDeletionReadableAtLargestText() throws {
        try checkSettingsLayout(largeText: true)
    }

    private func checkSettingsLayout(largeText: Bool) throws {
        let app = XCUIApplication()
        // [04] Show a test-only connection using separate storage, without changing the owner's
        // Apple permission.
        app.launchArguments = ["-ui-testing", "-ui-automatic-preview", "-ui-disconnect-preview",
                               "-reset-ui-state", "-ui-reset-appearance", "-ui-example-history"]
            + (largeText ? ["-ui-extra-large-text"] : [])
        app.launch()
        app.tabBars.buttons["History"].tap()
        let historyTitle = app.navigationBars["History"].staticTexts["History"]
        XCTAssertTrue(historyTitle.waitForExistence(timeout: 8))
        let titleHeight = historyTitle.frame.height
        app.tabBars.buttons["Settings"].tap()
        let settings = AutomaticUITestSupport.element("settings.form", in: app)
        let navigation = app.navigationBars["Settings"]
        let settingsTitle = navigation.staticTexts["Settings"]
        XCTAssertTrue(settingsTitle.waitForExistence(timeout: 8))
        XCTAssertEqual(settingsTitle.frame.height, titleHeight, accuracy: 1,
                       "Settings and History should use the same native title size")
        func reach(_ element: XCUIElement) {
            XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected)
            AutomaticUITestSupport.reach(element, in: app, inside: settings, below: navigation, verticalMargin: 8)
            XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected)
        }

        XCTAssertFalse(AutomaticUITestSupport.element("settings.widgetHelp", in: settings).exists)
        let intro = settings.staticTexts["settings.intro"]
        reach(intro)
        XCTAssertTrue(settings.staticTexts["settings.introExplanation"].exists)
        let status = AutomaticUITestSupport.element("screen-time.status", in: settings)
        reach(status)
        XCTAssertEqual(status.label, "Connected",
                       "The isolated connected presentation must be clear without relying on its color")
        XCTAssertEqual(settings.staticTexts.matching(identifier: "screen-time.heading").count, 1)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        AutomaticUITestSupport.capture(largeText ? "AX5 Settings single connection summary" : "Settings single connection summary")
        if !largeText {
            AutomaticUITestSupport.captureElement(
                AutomaticUITestSupport.element("settings.section.connection", in: settings),
                name: "Settings connection section")
        }
        try auditSettings(app)

        // [05] The model explanation replaces the extra estimate-settings action.
        XCTAssertFalse(settings.buttons["Review estimate settings"].exists)
        let management = AutomaticUITestSupport.element("screen-time.management", in: settings)
        reach(management)
        assertSingleNativeDisclosure("screen-time.management", title: "Connection details",
                                     in: settings, app: app, navigation: navigation)
        XCTAssertEqual(management.label, "Connection details",
                       "The disclosure should keep one clear label without reading its decorative icon")
        XCTAssertGreaterThanOrEqual(management.frame.height, 52)
        let modelDetails = AutomaticUITestSupport.element("settings.modelDetails", in: settings)
        reach(modelDetails)
        assertSingleNativeDisclosure("settings.modelDetails", title: "How the estimate works",
                                     in: settings, app: app, navigation: navigation)
        XCTAssertGreaterThanOrEqual(modelDetails.frame.height, 52)
        if !largeText {
            XCTAssertEqual(modelDetails.frame.height, management.frame.height, accuracy: 1,
                           "The two disclosure rows should use the same normal-text tap area")
        }
        XCTAssertEqual(modelDetails.frame.minY - management.frame.maxY, 16, accuracy: 1,
                       "Related connection and model rows should share the same 16-point spacing")
        AutomaticUITestSupport.capture(largeText ? "AX5 related Settings rows with uniform spacing" : "Related Settings rows with uniform spacing")
        modelDetails.tap()
        let modelExplanation = settings.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@",
            "The iOS app uses the same category-based calculation")).firstMatch
        XCTAssertTrue(modelExplanation.waitForExistence(timeout: 5))
        reach(modelExplanation)
        XCTAssertTrue(modelExplanation.isHittable)
        AutomaticUITestSupport.capture(largeText ? "AX5 model explanation in Settings" : "Model explanation in Settings")
        try auditSettings(app)
        reach(modelDetails)
        modelDetails.tap()
        XCTAssertFalse(modelExplanation.exists)

        let notificationHeading = settings.staticTexts["settings.notificationHeading"]
        reach(notificationHeading)
        let notificationRow = AutomaticUITestSupport.element("settings.dailyGardenNotificationRow", in: settings)
        reach(notificationRow)
        let notificationRowHeight = notificationRow.frame.height
        XCTAssertGreaterThanOrEqual(notificationRowHeight, 52 - 0.000001)
        XCTAssertEqual(notificationRow.frame.minY - notificationHeading.frame.maxY, 16, accuracy: 1,
                       "The morning section should use the same heading-to-row spacing as About")
        let notificationToggle = settings.switches["settings.dailyGardenNotification"]
        reach(notificationToggle)
        XCTAssertEqual(notificationToggle.label, "Daily garden update",
                       "The native switch should speak its title once and keep its separate on/off value")
        XCTAssertEqual(notificationToggle.value as? String, "0",
                       "A fresh isolated setup should leave optional notifications off")
        let notificationTiming = settings.staticTexts["settings.notificationTiming"]
        reach(notificationTiming)
        XCTAssertFalse(notificationTiming.label.isEmpty)
        XCTAssertTrue(notificationTiming.label.contains("around 8:00"))
        XCTAssertTrue(notificationTiming.label.contains("closed"))
        XCTAssertTrue(notificationTiming.label.contains("Fresh estimates"))
        XCTAssertEqual(notificationToggle.value as? String, "0")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists,
                       "Reading notification settings must not request system permission")
        AutomaticUITestSupport.capture(largeText ? "AX5 optional garden notifications off" : "Optional garden notifications off")
        if !largeText {
            AutomaticUITestSupport.captureElement(
                AutomaticUITestSupport.element("settings.section.notifications", in: settings),
                name: "Settings morning notification section")
        }
        try auditSettings(app)

        // [06] The test never requests real notification access. Tap the switch itself because its
        // reported area also covers the label.
        for expected in ["1", "0"] {
            reach(notificationToggle)
            notificationToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                notificationToggle.value as? String == expected
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 8), .completed)
            XCTAssertFalse(app.alerts.firstMatch.exists)
            XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        }
        reach(notificationRow)
        XCTAssertEqual(notificationToggle.value as? String, "0")
        try auditSettings(app)

        let sectionPairs = [("connection", "notifications"), ("notifications", "about"),
                            ("about", "appearance"), ("appearance", "data")]
        for (previousID, nextID) in sectionPairs {
            let previous = AutomaticUITestSupport.element("settings.section." + previousID, in: settings)
            let next = AutomaticUITestSupport.element("settings.section." + nextID, in: settings)
            reach(next)
            XCTAssertTrue(previous.exists)
            XCTAssertTrue(next.exists)
            XCTAssertEqual(next.frame.minY - previous.frame.maxY, 32, accuracy: 1,
                           "Separate Settings sections should share the same 32-point spacing")
        }

        let privacy = settings.buttons["settings.privacy"]
        reach(privacy)
        XCTAssertEqual(privacy.label, "Privacy policy",
                       "The native navigation action should keep one clear spoken title")
        let aboutHeading = settings.staticTexts["About this app"]
        XCTAssertTrue(aboutHeading.exists)
        XCTAssertEqual(privacy.frame.minY - aboutHeading.frame.maxY, 16, accuracy: 1)
        if !largeText {
            XCTAssertEqual(notificationRowHeight, privacy.frame.height, accuracy: 1,
                           "Notification and privacy actions should share the same normal-text row height")
        }

        let appearance = settings.buttons["settings.appearance"]
        reach(appearance)
        XCTAssertGreaterThanOrEqual(appearance.frame.height, 44)
        AutomaticUITestSupport.capture(largeText ? "AX5 Settings appearance action" : "Settings appearance action")

        let deletion = settings.buttons["settings.delete"]
        reach(deletion)
        if !largeText {
            // [07] Compare spacing while both rows are visible, so scrolling does not make the gap
            // look larger or smaller.
            XCTAssertTrue(appearance.isHittable)
            XCTAssertLessThan(appearance.frame.maxY, deletion.frame.minY)
        }
        XCTAssertGreaterThanOrEqual(deletion.frame.height, 44)
        XCTAssertLessThanOrEqual(deletion.frame.maxY, app.tabBars.firstMatch.frame.minY - 4)
        AutomaticUITestSupport.capture(largeText ? "AX5 Settings deletion clear of tabs" : "Appearance before local data deletion")
        try auditSettings(app)
    }

    private func assertSingleNativeDisclosure(_ identifier: String, title: String,
                                              in settings: XCUIElement, app: XCUIApplication,
                                              navigation: XCUIElement) {
        let controls = settings.buttons.matching(identifier: identifier).allElementsBoundByIndex
        XCTAssertFalse(controls.isEmpty, "The disclosure must remain a native button")
        var targets = Set<String>()
        let window = app.windows.firstMatch.frame
        let content = settings.frame.intersection(window)
        let top = max(content.minY, navigation.frame.maxY)
        let bottom = min(content.maxY, app.tabBars.firstMatch.frame.minY)
        let viewport = CGRect(x: content.minX, y: top, width: content.width, height: bottom - top)
        XCTAssertGreaterThan(viewport.height, 44)
        for control in controls {
            XCTAssertEqual(control.label, title, "The disclosure title must be spoken once, without its decorative icon")
            XCTAssertTrue(control.isHittable)
            XCTAssertTrue(viewport.insetBy(dx: -1, dy: -1).contains(control.frame),
                          "Audit the complete disclosure row inside the visible Settings page")
            // [08] iOS may report one visible button through several test entries; they must still
            // describe a single action.
            targets.insert(String(describing: control.frame))
        }
        XCTAssertEqual(targets.count, 1, "The row must offer one logical disclosure target")
    }

    private func auditSettings(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: [.textClipped, .hitRegion]) { issue in
            // [09] Keep the affected element for review without weakening the accessibility audit.
            let details = XCTAttachment(string: "Issue: \(issue)\nElement: \(issue.element?.debugDescription ?? "unknown")\n\(app.debugDescription)")
            details.name = "Settings accessibility issue details"
            details.lifetime = .keepAlways
            self.add(details)
            return false
        }
    }
}
