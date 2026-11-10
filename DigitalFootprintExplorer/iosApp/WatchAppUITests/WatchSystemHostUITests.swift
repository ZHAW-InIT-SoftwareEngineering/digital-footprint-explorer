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

// [01] Run this separately on a fresh simulator. It checks Apple's real host, without copying an example into shared storage.
@MainActor
final class WatchSystemHostUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func record(_ step: String, application: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: application.screenshot())
        screenshot.name = "Watch system host — " + step
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let tree = XCTAttachment(string: application.debugDescription)
        tree.name = "Watch system accessibility — " + step
        tree.lifetime = .keepAlways
        add(tree)
    }

    private func find(_ predicate: NSPredicate, in application: XCUIApplication, swipes: Int = 0) -> XCUIElement? {
        let item = application.descendants(matching: .any).matching(predicate).firstMatch
        for attempt in 0...swipes {
            if item.exists && item.isHittable { return item }
            if attempt < swipes { application.swipeUp() }
        }
        return nil
    }

    func testSmartStackOffersRealGardenAndItsTapOpensTheWatchApp() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This system-host audit runs only on a simulator, to avoid capturing personal Watch content.")
        #else
        guard ProcessInfo.processInfo.environment["DFE_WATCH_SYSTEM_HOST_AUDIT"] == "1"
                || ProcessInfo.processInfo.environment["TEST_RUNNER_DFE_WATCH_SYSTEM_HOST_AUDIT"] == "1" else {
            throw XCTSkip("Set DFE_WATCH_SYSTEM_HOST_AUDIT=1 for the separate, OS-dependent Smart Stack audit")
        }
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        let status = app.staticTexts["watch.status.title"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Watch sharing is off", "Use a fresh simulator with sharing off")
        XCTAssertFalse(app.staticTexts["watch.estimate"].exists)
        record("native sharing off", application: app)

        // [05] A Crown press can merely wake the display. Stop DFE first so a host gesture cannot accidentally scroll the app.
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 8))
        let carousel = XCUIApplication(bundleIdentifier: "com.apple.Carousel")
        let shell = XCUIApplication(bundleIdentifier: "com.apple.clockface")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(shell.wait(for: .runningForeground, timeout: 8))
        XCTAssertNotEqual(app.state, .runningForeground)
        // [03] Clockface hosts this system surface. Carousel may expose only blank remote windows, even while the sheet is visible.
        record("Home Carousel context", application: carousel)
        record("Home Clockface context", application: shell)
        let contexts = XCTAttachment(string: "Carousel state: \(carousel.state.rawValue); Clockface state: \(shell.state.rawValue)")
        contexts.name = "Watch host process states"
        contexts.lifetime = .keepAlways
        add(contexts)
        let retainedSuggestions = shell.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@",
                                                                         "Current Suggestions", "Widget Suggestions")).firstMatch
        if retainedSuggestions.exists {
            let dismiss = NSPredicate(format: "elementType == %d AND (label ==[c] %@ OR label ==[c] %@ OR label ==[c] %@)",
                                      XCUIElement.ElementType.button.rawValue, "Done", "Confirm", "Checkmark")
            guard let button = find(dismiss, in: shell) else {
                record("retained suggestions cannot be dismissed", application: shell)
                XCTFail("Start this host audit on a fresh Watch simulator; the retained suggestions sheet has no accessible dismiss control")
                return
            }
            button.tap()
            XCUIDevice.shared.press(.home)
        }
        shell.swipeUp()
        record("Smart Stack", application: shell)
        let editPredicate = NSPredicate(format: "elementType == %d AND (label CONTAINS[c] %@ OR identifier CONTAINS[c] %@)",
                                        XCUIElement.ElementType.button.rawValue, "Edit", "Edit")
        guard let edit = find(editPredicate, in: shell, swipes: 8) else {
            record("Edit control unavailable", application: shell)
            XCTFail("The real Smart Stack Edit control was not accessible; host placement is not verified")
            return
        }
        edit.tap()
        record("Smart Stack editor", application: shell)
        // [04] Apple's editor exposes Add widget as a collection cell, not a button.
        let addPredicate = NSPredicate(format: "(elementType == %d AND label ==[c] %@) OR (elementType == %d AND (label == %@ OR label CONTAINS[c] %@))",
                                       XCUIElement.ElementType.cell.rawValue, "Add widget",
                                       XCUIElement.ElementType.button.rawValue, "+", "Add")
        guard let add = find(addPredicate, in: shell) else {
            record("Add control unavailable", application: shell)
            XCTFail("The Smart Stack Add control was not accessible")
            return
        }
        add.tap()
        record("real widget gallery", application: shell)
        let appPredicate = NSPredicate(format: "label ==[c] %@ OR label ==[c] %@ OR label ==[c] %@",
                                       "Digital Footprint", "Digital Footprint Explorer", "DFE")
        guard let galleryRow = find(appPredicate, in: shell, swipes: 8) else {
            record("DFE absent from gallery", application: shell)
            XCTFail("The real gallery did not expose Digital Footprint; registration alone is not a placement test")
            return
        }
        galleryRow.tap()
        record("DFE gallery choices", application: shell)
        let confirmPredicate = NSPredicate(format: "elementType == %d AND label CONTAINS[c] %@",
                                           XCUIElement.ElementType.button.rawValue, "Add")
        if let confirm = find(confirmPredicate, in: shell, swipes: 1) {
            confirm.tap()
        } else {
            let gardenPredicate = NSPredicate(format: "label CONTAINS[c] %@", "Your phone garden")
            guard let choice = find(gardenPredicate, in: shell, swipes: 2) else {
                record("DFE choice unavailable", application: shell)
                XCTFail("No addable garden choice was accessible in the real gallery")
                return
            }
            choice.tap()
        }
        record("after adding real widget", application: shell)
        let donePredicate = NSPredicate(format: "elementType == %d AND label ==[c] %@",
                                        XCUIElement.ElementType.button.rawValue, "Done")
        if let done = find(donePredicate, in: shell) { done.tap() }
        let savedWidgetPredicate = NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                                               "Turn on Apple Watch sharing", "Watch sharing is off")
        guard let realWidget = find(savedWidgetPredicate, in: shell, swipes: 5) else {
            record("added widget not readable", application: shell)
            XCTFail("The added real widget did not expose the expected sharing-off state")
            return
        }
        XCTAssertFalse(realWidget.label.contains("grams"))
        record("real sharing-off widget", application: shell)
        // [02] Do not open the app ourselves here. Only tapping the real widget may satisfy this routing check.
        realWidget.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.staticTexts["watch.status.title"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["watch.estimate"].exists)
        record("widget opened native app", application: app)
        #endif
    }
}
