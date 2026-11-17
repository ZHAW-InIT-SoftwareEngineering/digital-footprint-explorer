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

// [01] One appearance choice should carry through every tab, detail screen and fresh launch

import XCTest
import UIKit

@MainActor
final class AppearanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    // [02] The agreed white background should stay white when the person moves between screens.
    func testDefaultLightSurfaceStaysWhiteAcrossTabsAndSheets() throws {
        let app = launch()
        try checkTabs(in: app, dark: false)
        app.tabBars.buttons["Settings"].tap()
        openSetupAfterControlledDisconnect(in: app)
        try checkSurface(in: app, dark: false, name: "Light automatic setup")
        // [03] The same visible action can appear as a Link or Button to the test tools; either
        // must stay usable.
        let privacy = AutomaticUITestSupport.element("automatic.privacy", in: app)
        let setupContent = app.scrollViews.containing(.any, identifier: "automatic.privacy").firstMatch
        XCTAssertTrue(setupContent.waitForExistence(timeout: 8))
        AutomaticUITestSupport.reach(privacy, in: app, inside: setupContent,
                                     below: app.navigationBars["Automatic setup"])
        privacy.tap()
        XCTAssertTrue(app.navigationBars["Privacy policy"].waitForExistence(timeout: 8))
        try checkSurface(in: app, dark: false, name: "Light privacy policy")
        AutomaticUITestSupport.assertNoManualEntry(in: app)
    }

    // [04] Choosing dark appearance should update the whole app and remain in place after
    // reopening.
    func testDarkChoiceAppliesAcrossTabsAndSheetsAndSurvivesRelaunch() throws {
        let app = launch()
        choose("Dark", in: app)
        try checkTabs(in: app, dark: true)
        app.tabBars.buttons["Today"].tap()
        let help = app.buttons["today.widgetHelp"]
        AutomaticUITestSupport.reach(help, in: app)
        help.tap()
        XCTAssertTrue(app.navigationBars["Your garden widget"].waitForExistence(timeout: 8))
        try checkSurface(in: app, dark: true, name: "Dark widget instructions")
        app.navigationBars["Your garden widget"].buttons["Done"].tap()
        app.tabBars.buttons["Settings"].tap()
        openSetupAfterControlledDisconnect(in: app)
        try checkSurface(in: app, dark: true, name: "Dark automatic setup")
        app.navigationBars["Automatic setup"].buttons["Cancel"].tap()
        app.terminate()
        let reopened = launch(reset: false)
        try checkTabs(in: reopened, dark: true)
        AutomaticUITestSupport.assertNoManualEntry(in: reopened)
    }

    // [05] Returning to light appearance should also update screens that have no completed setup
    // or history.
    func testReturningToLightAlsoUpdatesTheUnconfiguredWelcomeAndEmptyHistory() throws {
        let app = launch(fixture: false)
        choose("Dark", in: app)
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["onboarding.automatic"].waitForExistence(timeout: 8))
        try checkSurface(in: app, dark: true, name: "Dark welcome")
        choose("Light", in: app)
        try checkTabs(in: app, dark: false)
        app.terminate()
        let reopened = launch(reset: false, fixture: false)
        try checkTabs(in: reopened, dark: false)
        XCTAssertTrue(reopened.tabBars.buttons["Settings"].exists)
        AutomaticUITestSupport.assertNoManualEntry(in: reopened)
    }

    private func openSetupAfterControlledDisconnect(in app: XCUIApplication) {
        let status = AutomaticUITestSupport.reachSettings("screen-time.status", in: app)
        XCTAssertEqual(status.label, "Connected")
        // [06] Completed setup should stay out of the way. Use its reconnect route to check this
        // screen again.
        AutomaticUITestSupport.reachSettings("screen-time.management", in: app).tap()
        AutomaticUITestSupport.reachSettings("screen-time-disconnect", in: app).tap()
        let confirmation = app.alerts["Disconnect Screen Time?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 8))
        confirmation.buttons.matching(NSPredicate(format: "label == %@", "Disconnect")).firstMatch.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !confirmation.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 8), .completed)
        XCTAssertEqual(AutomaticUITestSupport.reachSettings("screen-time.status", in: app).label, "Not connected")
        AutomaticUITestSupport.openSetup(in: app, id: "settings.automaticSetup")
    }

    private func launch(reset: Bool = true, fixture: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        // [07] Use separate appearance and history settings, keeping these layout checks away from
        // real activity.
        app.launchArguments = ["-ui-testing", "-ui-automatic-preview"]
            + (reset ? ["-reset-ui-state", "-ui-reset-appearance"] : [])
            + (fixture ? ["-ui-example-history", "-ui-disconnect-preview"] : [])
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 8))
        return app
    }

    private func choose(_ title: String, in app: XCUIApplication) {
        app.tabBars.buttons["Settings"].tap()
        let picker = AutomaticUITestSupport.reachSettings("settings.appearance", in: app)
        XCTAssertGreaterThanOrEqual(picker.frame.height, 44 - 0.000001)
        picker.tap()
        let identified = AutomaticUITestSupport.element("appearance.\(title.lowercased())", in: app)
        let option = identified.waitForExistence(timeout: 3) ? identified : app.staticTexts[title]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        AutomaticUITestSupport.reach(option, in: app)
        option.tap()
        let settingsBar = app.navigationBars["Settings"]
        let settingsForm = AutomaticUITestSupport.element("settings.form", in: app)
        func waitForSettings(_ timeout: TimeInterval) -> Bool {
            let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                settingsBar.exists && settingsBar.isHittable
                    && settingsForm.exists && settingsForm.isHittable
                    && app.tabBars.buttons["Settings"].isSelected
            }, object: nil)
            return XCTWaiter.wait(for: [visible], timeout: timeout) == .completed
        }
        // [08] A theme choice may already return to Settings. Only leave the picker if it is still
        // on screen.
        if !waitForSettings(3) {
            let appearanceBar = app.navigationBars["Appearance"]
            let back = appearanceBar.buttons["Settings"]
            XCTAssertTrue(appearanceBar.exists && appearanceBar.isHittable && back.exists && back.isHittable)
            back.tap()
        }
        XCTAssertTrue(waitForSettings(8))
    }

    private func checkTabs(in app: XCUIApplication, dark: Bool) throws {
        for title in ["Today", "History", "Settings"] {
            let tab = app.tabBars.buttons[title]
            XCTAssertTrue(tab.isHittable)
            tab.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 8))
            try checkSurface(in: app, dark: dark, name: "\(dark ? "Dark" : "Light") \(title)")
        }
    }

    private func checkSurface(in app: XCUIApplication, dark: Bool, name: String) throws {
        let screenshot = app.screenshot()
        let pixels = try XCTUnwrap(screenshot.image.cgImage)
        let width = pixels.width
        let height = pixels.height
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(pixels, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let windowWidth = app.windows.firstMatch.frame.width
        XCTAssertGreaterThan(windowWidth, 0)
        let x = min(width - 1, max(0, Int(4 * CGFloat(width) / windowWidth)))
        // [09] Sample the clear outer margin so a small overlay or rounded corner does not look
        // like the page background.
        let sampleRows = [0.45, 0.55, 0.65].map { min(height - 1, Int(Double(height) * $0)) }
        let channels = (0..<3).map { channel in
            sampleRows.map { Double(data[($0 * width + x) * 4 + channel]) / 255 }.sorted()[1]
        }
        for value in channels {
            if dark { XCTAssertLessThan(value, 0.20, "\(name) must use the same dark canvas") }
            else { XCTAssertGreaterThan(value, 0.95, "\(name) must use a white canvas") }
        }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name + " (isolated synthetic UI data)"
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: name) { $0.add(attachment) }
    }
}
