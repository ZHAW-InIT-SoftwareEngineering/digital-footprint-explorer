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

// [01] The connection stays in place until the person makes a clear choice in the confirmation

import XCTest

@MainActor
final class ConnectionConfirmationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    // [02] Cancelling must leave both the saved days and the existing connection in place.
    func testDisconnectAlertKeepsSavedDaysAndConnectionWhenCancelled() throws {
        try checkConfirmation(largeText: false, dark: false)
    }

    // [03] A dark screen and larger text should still leave both confirmation choices readable and
    // reachable.
    func testLargestTextDarkDisconnectAlertKeepsBothChoicesReadable() throws {
        try checkConfirmation(largeText: true, dark: true)
    }

    private func checkConfirmation(largeText: Bool, dark: Bool) throws {
        let app = openFixture(largeText: largeText, dark: dark)
        XCTAssertTrue(app.staticTexts["footprint.total"].waitForExistence(timeout: 8))
        let savedTotal = app.staticTexts["footprint.total"].label
        assertSavedConnection(in: app, savedTotal: savedTotal)

        let first = openConfirmation(in: app)
        assertChoices(in: first.alert, app: app)
        let geometry = XCTAttachment(string: "Message: \(first.alert.staticTexts[confirmationMessage].frame). Cancel: \(action("Cancel", in: first.alert).frame). Disconnect: \(action("Disconnect", in: first.alert).frame). Alert: \(first.alert.frame). Window: \(app.windows.firstMatch.frame).")
        geometry.name = largeText ? "Native alert AX5 geometry" : "Native alert normal geometry"
        geometry.lifetime = .keepAlways
        XCTContext.runActivity(named: "Record native alert layout") { $0.add(geometry) }
        AutomaticUITestSupport.capture(largeText ? "AX5 dark native disconnect alert" : "Light native disconnect alert")
        AutomaticUITestSupport.captureElement(first.alert,
            name: largeText ? "native Disconnect alert, large SwiftUI text" : "native Disconnect alert, normal text")
        try auditConfirmation(in: app)

        // [04] While confirmation is open, a tap behind it must not change tabs or escape the
        // decision.
        AutomaticUITestSupport.tapBackground(outside: first.alert,
                                              preferring: first.backgroundHistoryFrame, in: app)
        XCTAssertTrue(first.alert.exists)
        assertChoices(in: first.alert, app: app)
        tapAction("Cancel", in: first.alert, app: app)
        assertDismissed(first.alert)
        XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected,
                      "The alert must block interaction with the tab bar behind it")
        assertSavedConnection(in: app, savedTotal: savedTotal)

        let confirmed = openConfirmation(in: app)
        tapAction("Disconnect", in: confirmed.alert, app: app)
        assertDismissed(confirmed.alert)
        assertSpokenStatus("Not connected", in: app)
        XCTAssertFalse(AutomaticUITestSupport.element("screen-time-disconnect", in: app).exists)
        XCTAssertTrue(AutomaticUITestSupport.reachSettings("settings.automaticSetup", in: app).exists)
        assertSavedTotal(in: app, savedTotal: savedTotal)
        AutomaticUITestSupport.assertNoManualEntry(in: app)

        app.terminate()
        let reopened = openFixture(reset: false, largeText: largeText, dark: dark)
        XCTAssertTrue(reopened.staticTexts["footprint.total"].waitForExistence(timeout: 8))
        XCTAssertEqual(reopened.staticTexts["footprint.total"].label, savedTotal,
                       "Disconnect must keep the saved archive without reseeding it")
        // [05] The test connection exists only in memory, so this confirmation cannot revoke the
        // owner's real access.
        assertSavedConnection(in: reopened, savedTotal: savedTotal)
    }

    private let confirmationMessage = "Automatic estimates will pause. Your saved days will stay on this device."
    private typealias Confirmation = (alert: XCUIElement, backgroundHistoryFrame: CGRect)

    @discardableResult
    private func showSettings(in app: XCUIApplication) -> XCUIElement {
        let tab = app.tabBars.buttons["Settings"]
        let bar = app.navigationBars["Settings"]
        let settings = AutomaticUITestSupport.element("settings.form", in: app)
        if !(tab.isSelected && bar.exists && settings.exists && settings.isHittable) {
            tapVisibleTab(tab, in: app)
        }
        XCTAssertTrue(bar.waitForExistence(timeout: 8))
        XCTAssertTrue(tab.isSelected)
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        return settings
    }

    // [09] Use the tab's visible centre. XCTest can try to scroll a floating tab and then
    // tap above it, opening a day instead of the page this check needs.
    private func tapVisibleTab(_ tab: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        XCTAssertTrue(tab.isHittable)
        let window = app.windows.firstMatch
        let windowFrame = window.frame
        let tabFrame = tab.frame
        let tabBarFrame = app.tabBars.firstMatch.frame
        guard !tabFrame.isEmpty, windowFrame.insetBy(dx: -1, dy: -1).contains(tabFrame),
              tabBarFrame.insetBy(dx: -1, dy: -1).contains(tabFrame) else {
            XCTFail("The requested tab must be fully inside the visible tab bar")
            return
        }
        let point = CGPoint(x: tabFrame.midX, y: tabFrame.midY)
        let diagnostic = XCTAttachment(string: "Tab: \(tab.label). Frame: \(tabFrame). Tab bar: \(tabBarFrame). Window: \(windowFrame). Tap: \(point).")
        diagnostic.name = "Verified visible tab target before one tap"
        diagnostic.lifetime = .keepAlways
        XCTContext.runActivity(named: "Open the requested tab") { $0.add(diagnostic) }
        window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x - windowFrame.minX,
                                 dy: point.y - windowFrame.minY)).tap()
    }

    private func openConfirmation(in app: XCUIApplication) -> Confirmation {
        let settings = showSettings(in: app)
        let entry = AutomaticUITestSupport.element("screen-time-disconnect", in: settings)
        if !entry.exists {
            AutomaticUITestSupport.reachSettings("screen-time.management", in: app).tap()
        }
        AutomaticUITestSupport.reach(entry, in: app, inside: settings,
                                     below: app.navigationBars["Settings"], verticalMargin: 16)
        XCTAssertTrue(entry.isHittable)
        let history = app.tabBars.buttons["History"].frame
        entry.tap()
        let alert = app.alerts["Disconnect Screen Time?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        XCTAssertTrue(alert.staticTexts[confirmationMessage].exists)
        XCTAssertEqual(app.alerts.count, 1)
        XCTAssertEqual(app.sheets.count, 0, "This decision is a centered native alert, not a sheet")
        XCTAssertFalse(app.navigationBars["Automatic setup"].exists)
        AutomaticUITestSupport.readNativeAlertMessage(confirmationMessage, in: alert, app: app)
        return (alert, history)
    }

    private func assertChoices(in alert: XCUIElement, app: XCUIApplication) {
        let buttons = alert.buttons.allElementsBoundByIndex
        let inventory = buttons.enumerated().map { index, button in
            "\(index): label=\(button.label); identifier=\(button.identifier); frame=\(button.frame); hittable=\(button.isHittable)"
        }.joined(separator: "\n")
        let diagnostic = XCTAttachment(string: "\(inventory)\n\n\(alert.debugDescription)")
        diagnostic.name = "Native disconnect alert action inventory before strict assertion"
        diagnostic.lifetime = .keepAlways
        self.add(diagnostic)
        AutomaticUITestSupport.capture("Native disconnect alert before strict action inventory")
        let titles = ["Cancel", "Disconnect"]
        XCTAssertEqual(Set(buttons.map(\.label)), Set(titles))
        // [06] iOS exposes more than one test entry for the same visible action; they must share
        // the same position.
        let physicalActions = Set(buttons.map { "\($0.label)|\($0.frame)" })
        XCTAssertEqual(physicalActions.count, 2, "Only two physical action targets should be present")
        for title in titles {
            let button = action(title, in: alert)
            AutomaticUITestSupport.revealNativeAlertAction(button, in: alert, app: app)
            XCTAssertTrue(button.exists)
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
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

    private func assertDismissed(_ alert: XCUIElement) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !alert.exists }, object: alert)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 8), .completed)
    }

    private func assertSavedConnection(in app: XCUIApplication, savedTotal: String) {
        showSettings(in: app)
        assertSpokenStatus("Connected", in: app)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        assertSavedTotal(in: app, savedTotal: savedTotal)
    }

    // [07] Every exposed part of the status must use words, not the shield's name.
    // Checking all matches also catches an extra image that a first-match query could miss.
    private func assertSpokenStatus(_ expected: String, in app: XCUIApplication) {
        let status = AutomaticUITestSupport.reachSettings("screen-time.status", in: app)
        XCTAssertEqual(status.label, expected)
        let settings = AutomaticUITestSupport.element("settings.form", in: app)
        let matches = settings.descendants(matching: .any)
            .matching(identifier: "screen-time.status").allElementsBoundByIndex
        XCTAssertFalse(matches.isEmpty)
        XCTAssertEqual(Set(matches.map(\.label)), Set([expected]),
                       "The connection must not expose a decorative symbol as a separate status")
    }

    private func assertSavedTotal(in app: XCUIApplication, savedTotal: String) {
        let tab = app.tabBars.buttons["Today"]
        let bar = app.navigationBars["Today"]
        let total = app.staticTexts["footprint.total"]
        if !(tab.isSelected && bar.exists && total.exists && total.isHittable) {
            tapVisibleTab(tab, in: app)
        }
        XCTAssertTrue(bar.waitForExistence(timeout: 8))
        XCTAssertTrue(tab.isSelected)
        XCTAssertTrue(total.waitForExistence(timeout: 8))
        XCTAssertEqual(total.label, savedTotal)
    }

    private func auditConfirmation(in app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: [.textClipped, .hitRegion]) { issue in
            let detail = XCTAttachment(string: "\(issue.compactDescription)\n\(issue.detailedDescription)\n\(issue.element?.debugDescription ?? "No affected element supplied")\n\(app.debugDescription)")
            detail.name = "Native disconnect alert accessibility issue and viewport"
            detail.lifetime = .keepAlways
            XCTContext.runActivity(named: "Native disconnect alert accessibility diagnosis") { $0.add(detail) }
            return false
        }
    }

    private func openFixture(reset: Bool = true, largeText: Bool, dark: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        // [08] These launch choices use disposable history and leave Apple's real permission
        // untouched.
        app.launchArguments = ["-ui-testing", "-ui-automatic-preview", "-ui-disconnect-preview"]
            + (reset ? ["-reset-ui-state", "-ui-reset-appearance", "-ui-example-history"] : [])
            + (largeText ? ["-ui-extra-large-text"] : [])
            + (dark ? ["-ui-dark-mode"] : [])
        app.launch()
        return app
    }
}
