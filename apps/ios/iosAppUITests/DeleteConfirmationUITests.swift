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

// [01] Deleting history should be a deliberate choice, and the removed history must stay gone
// after reopening

import XCTest

@MainActor
final class DeleteConfirmationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }

    // [02] Opening or cancelling the warning must not erase anything; only the confirmed action
    // may clear history.
    func testNativeDeleteAlertCancelsSafelyAndClearsOnlyAfterConfirmation() throws {
        try checkDeletion(largeText: false)
    }

    // [03] The largest text setting must keep both choices available, and confirmed deletion must
    // survive reopening.
    func testLargestTextDeleteAlertKeepsBothChoicesReadableAndPersistsDeletion() throws {
        try checkDeletion(largeText: true)
    }

    private let confirmationMessage = "This permanently deletes your saved days and settings. Screen Time access is unchanged."

    private func checkDeletion(largeText: Bool) throws {
        let app = openFixture(largeText: largeText)
        XCTAssertTrue(app.staticTexts["footprint.total"].waitForExistence(timeout: 8))
        let savedTotal = app.staticTexts["footprint.total"].label
        let choice = largeText ? "Dark" : "System"
        try chooseAppearance(choice, in: app)
        let settings = show("Settings", contentID: "settings.form", in: app)
        let notification = settings.switches["settings.dailyGardenNotification"]
        reachSettings(notification, in: app)
        XCTAssertEqual(notification.value as? String, "0")
        // [04] This test never asks Apple for notification access. Tap the switch itself, since
        // its reported area also includes the label.
        notification.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        waitForNotification("1", in: notification)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)

        let first = openConfirmation(in: app)
        assertChoices(first.alert, app: app)
        let geometry = XCTAttachment(string: "Message: \(first.alert.staticTexts[confirmationMessage].frame). Cancel: \(action("Cancel", in: first.alert).frame). Delete: \(action("Delete all entries", in: first.alert).frame). Alert: \(first.alert.frame). Window: \(app.windows.firstMatch.frame).")
        geometry.name = largeText ? "Native delete alert AX5 geometry" : "Native delete alert normal geometry"
        geometry.lifetime = .keepAlways
        self.add(geometry)
        AutomaticUITestSupport.capture(largeText ? "Native delete alert at largest text" : "Native delete alert at normal text")
        AutomaticUITestSupport.captureElement(first.alert,
            name: largeText ? "native Delete alert, large SwiftUI text" : "native Delete alert, normal text")
        try app.performAccessibilityAudit(for: [.textClipped, .hitRegion])

        AutomaticUITestSupport.tapBackground(outside: first.alert,
                                              preferring: first.backgroundHistoryFrame, in: app)
        XCTAssertTrue(first.alert.exists, "A background tap must not answer the destructive decision")
        tapAction("Cancel", in: first.alert, app: app)
        waitForDismissal(first.alert)
        XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected)
        let savedAppearance = AutomaticUITestSupport.element("settings.appearance", in: settings)
        reachSettings(savedAppearance, in: app)
        XCTAssertEqual(savedAppearance.value as? String, choice)
        reachSettings(notification, in: app)
        XCTAssertEqual(notification.value as? String, "1")
        show("Today", contentID: "today.content", in: app)
        XCTAssertTrue(app.staticTexts["footprint.total"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["footprint.total"].label, savedTotal)
        XCTAssertFalse(app.buttons["today.automaticSetup"].exists,
                       "Cancel must keep the saved automatic setup as well as its result")

        let confirmed = openConfirmation(in: app)
        tapAction("Delete all entries", in: confirmed.alert, app: app)
        waitForDismissal(confirmed.alert)
        assertLocalReset(in: app)
        AutomaticUITestSupport.capture("Delete confirmed clears local data")

        app.terminate()
        // [05] Reopen without creating another example; deleted history must stay gone.
        let reopened = openFixture(reset: false, largeText: largeText)
        assertLocalReset(in: reopened)
        AutomaticUITestSupport.assertNoManualEntry(in: reopened)
    }

    private typealias Confirmation = (alert: XCUIElement, backgroundHistoryFrame: CGRect)

    private func openConfirmation(in app: XCUIApplication) -> Confirmation {
        let settings = show("Settings", contentID: "settings.form", in: app)
        let action = AutomaticUITestSupport.element("settings.delete", in: settings)
        reachSettings(action, in: app)
        let history = app.tabBars.buttons["History"].frame
        let window = app.windows.firstMatch
        action.tap()
        let alert = app.alerts["Delete all entries?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        XCTAssertEqual(app.alerts.count, 1)
        XCTAssertEqual(app.sheets.count, 0, "Deletion should use the same native alert style as disconnect")
        XCTAssertTrue(alert.staticTexts[confirmationMessage].exists)
        XCTAssertEqual(alert.frame.midX, window.frame.midX, accuracy: 2)
        XCTAssertFalse(app.navigationBars["Automatic setup"].exists)
        AutomaticUITestSupport.readNativeAlertMessage(confirmationMessage, in: alert, app: app)
        return (alert, history)
    }

    private func assertChoices(_ alert: XCUIElement, app: XCUIApplication) {
        let buttons = alert.buttons.allElementsBoundByIndex
        let inventory = buttons.enumerated().map { index, button in
            "\(index): label=\(button.label); identifier=\(button.identifier); frame=\(button.frame); hittable=\(button.isHittable)"
        }.joined(separator: "\n")
        let diagnostic = XCTAttachment(string: "\(inventory)\n\n\(alert.debugDescription)")
        diagnostic.name = "Native delete alert action inventory"
        diagnostic.lifetime = .keepAlways
        self.add(diagnostic)
        let titles = ["Cancel", "Delete all entries"]
        XCTAssertEqual(Set(buttons.map(\.label)), Set(titles))
        // [06] If iOS reports the same action twice, both entries must describe the same visible
        // button.
        let physicalActions = Set(buttons.map { "\($0.label)|\($0.frame)" })
        XCTAssertEqual(physicalActions.count, 2, "Only two physical action targets should be present")
        for title in titles {
            let button = action(title, in: alert)
            AutomaticUITestSupport.revealNativeAlertAction(button, in: alert, app: app)
            XCTAssertTrue(button.exists && button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44 - 0.000001)
        }
    }

    private func tapAction(_ title: String, in alert: XCUIElement, app: XCUIApplication) {
        let button = action(title, in: alert)
        AutomaticUITestSupport.revealNativeAlertAction(button, in: alert, app: app)
        button.tap()
    }

    private func action(_ title: String, in alert: XCUIElement) -> XCUIElement {
        alert.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private func assertLocalReset(in app: XCUIApplication) {
        let today = show("Today", contentID: "today.content", in: app)
        // [07] Erasing the saved days leaves permission in place, so the garden can start again.
        let pending = today.staticTexts["today.automaticPending"]
        XCTAssertTrue(pending.waitForExistence(timeout: 8))
        XCTAssertEqual(pending.label, "Let your next day take shape")
        XCTAssertFalse(today.buttons["onboarding.automatic"].exists)
        XCTAssertFalse(today.buttons["today.automaticSetup"].exists)
        XCTAssertFalse(today.buttons["today.dayDetails"].exists)
        XCTAssertFalse(today.staticTexts["footprint.total"].exists)
        let history = show("History", contentID: "history.content", in: app)
        let empty = history.staticTexts["history.empty"]
        AutomaticUITestSupport.reach(empty, in: app, inside: history,
            below: app.navigationBars["History"], verticalMargin: 16)
        XCTAssertEqual(empty.label, "No saved days yet")
        XCTAssertEqual(history.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.day.")).count, 0)
        let settings = show("Settings", contentID: "settings.form", in: app)
        let status = AutomaticUITestSupport.element("screen-time.status", in: settings)
        reachSettings(status, in: app)
        XCTAssertEqual(status.label, "Connected")
        XCTAssertFalse(settings.buttons["settings.automaticSetup"].exists)
        let notification = settings.switches["settings.dailyGardenNotification"]
        reachSettings(notification, in: app)
        waitForNotification("0", in: notification)
        let appearance = AutomaticUITestSupport.element("settings.appearance", in: settings)
        reachSettings(appearance, in: app)
        XCTAssertEqual(appearance.value as? String, "Light")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
    }

    @discardableResult
    private func show(_ title: String, contentID: String, in app: XCUIApplication) -> XCUIElement {
        let tab = app.tabBars.buttons[title]
        let bar = app.navigationBars[title]
        let content = AutomaticUITestSupport.element(contentID, in: app)
        if !(tab.isSelected && bar.exists && content.exists && content.isHittable) { tab.tap() }
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in tab.isSelected }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 8), .completed)
        XCTAssertTrue(bar.waitForExistence(timeout: 8))
        XCTAssertTrue(content.waitForExistence(timeout: 8))
        return content
    }

    private func reachSettings(_ element: XCUIElement, in app: XCUIApplication) {
        let settings = AutomaticUITestSupport.element("settings.form", in: app)
        AutomaticUITestSupport.reach(element, in: app, inside: settings,
            below: app.navigationBars["Settings"], verticalMargin: 16)
    }

    private func chooseAppearance(_ title: String, in app: XCUIApplication) throws {
        let settings = show("Settings", contentID: "settings.form", in: app)
        let appearance = AutomaticUITestSupport.element("settings.appearance", in: settings)
        reachSettings(appearance, in: app)
        appearance.tap()
        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 8))
        let option = AutomaticUITestSupport.element("appearance." + title.lowercased(), in: app)
        AutomaticUITestSupport.reach(option, in: app)
        option.tap()
        func settingsVisible(_ timeout: TimeInterval) -> Bool {
            let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.navigationBars["Settings"].exists && app.navigationBars["Settings"].isHittable
                    && settings.exists && settings.isHittable && app.tabBars.buttons["Settings"].isSelected
            }, object: nil)
            return XCTWaiter.wait(for: [visible], timeout: timeout) == .completed
        }
        if !settingsVisible(3) {
            let bar = app.navigationBars["Appearance"]
            let back = bar.buttons["Settings"]
            XCTAssertTrue(bar.exists && bar.isHittable && back.exists && back.isHittable)
            back.tap()
        }
        XCTAssertTrue(settingsVisible(8))
        XCTAssertEqual(appearance.value as? String, title)
    }

    private func waitForNotification(_ value: String, in control: XCUIElement) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            control.exists && control.value as? String == value
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 8), .completed)
    }

    private func waitForDismissal(_ alert: XCUIElement) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !alert.exists }, object: alert)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 8), .completed)
    }

    private func openFixture(reset: Bool = true, largeText: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-automatic-preview"]
            + (reset ? ["-reset-ui-state", "-ui-reset-appearance", "-ui-example-history"] : [])
            + (largeText ? ["-ui-extra-large-text"] : [])
        app.launch()
        return app
    }
}
