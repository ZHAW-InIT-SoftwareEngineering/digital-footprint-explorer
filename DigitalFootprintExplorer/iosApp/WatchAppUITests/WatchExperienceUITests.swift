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

@MainActor
final class WatchExperienceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(_ example: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-watch-example", example] + extra
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func reach(_ item: XCUIElement, in app: XCUIApplication, fullyVisible: Bool = false) {
        let scroll = app.scrollViews["watch.scroll"]
        let viewport = scroll.exists ? scroll : app
        let lower = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68))
        let upper = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        // [04] XCUITest includes the clock and bottom edge in the scroll frame. Center screenshot targets within that frame.
        let focus = fullyVisible ? viewport.frame.insetBy(dx: 0, dy: viewport.frame.height * 0.20) : viewport.frame
        for _ in 0..<12 {
            let frame = item.exists ? item.frame : .null
            let visible = frame.minY >= focus.minY && frame.maxY <= focus.maxY
            if item.exists && item.isHittable && (!fullyVisible || visible) { return }
            let isAbove = !frame.isNull && frame.minY < focus.minY
            let start = isAbove ? upper : lower
            let end = isAbove ? lower : upper
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        let frame = item.exists ? item.frame : .null
        XCTAssertTrue(item.exists && item.isHittable, "The Crown or a swipe should reach this content: \(item.identifier) \(frame)")
        if fullyVisible {
            XCTAssertGreaterThanOrEqual(frame.minY, focus.minY)
            XCTAssertLessThanOrEqual(frame.maxY, focus.maxY)
        }
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name + " — isolated example"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // [01] The same named garden and phone estimate must remain readable across all five visual states.
    func testAllFiveGardenStatesKeepTheirMeaning() {
        for state in ["flourishing", "growing", "stable", "wilting", "withered"] {
            let app = launch(state)
            let heading = app.staticTexts["watch.heading"]
            XCTAssertTrue(heading.waitForExistence(timeout: 10))
            XCTAssertEqual(heading.label, "Example preview")
            XCTAssertEqual(element("watch.garden", in: app).label, "Garden state: \(state.capitalized)")
            let amount = app.staticTexts["watch.estimate"]
            XCTAssertTrue(amount.exists)
            XCTAssertTrue(amount.label.contains("CO₂e"))
            XCTAssertTrue(app.staticTexts["watch.day"].exists)
            capture("Watch garden \(state)", app: app)
            app.terminate()
        }
    }

    func testPrimaryAmountFitsInitialViewportAtDefaultTextSize() {
        let app = launch("growing")
        let amount = app.staticTexts["watch.estimate"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        let window = app.windows.firstMatch.frame
        let scroll = app.scrollViews["watch.scroll"]
        let viewport = scroll.exists ? scroll.frame : window
        print("Watch default geometry: viewport \(viewport), amount \(amount.frame)")
        XCTAssertGreaterThan(amount.frame.width, 0)
        XCTAssertGreaterThanOrEqual(amount.frame.minY, viewport.minY)
        XCTAssertLessThanOrEqual(amount.frame.maxY, viewport.maxY)
        XCTAssertGreaterThan(element("watch.garden", in: app).frame.height, 40)
        capture("Watch first viewport", app: app)
    }

    // [02] Large text keeps a recognisable garden and a usable action. Scrolling reaches the full saved date and amount.
    func testAccessibilityTextCanReachSavedContextAndRefresh() {
        for size in ["accessibility3", "accessibility5"] {
            let app = launch("growing", extra: ["-ui-watch-text-size", size])
            XCTAssertTrue(app.staticTexts["watch.heading"].waitForExistence(timeout: 10))
            let garden = element("watch.garden", in: app)
            XCTAssertGreaterThanOrEqual(garden.frame.height, 80, "Large text must leave a recognisable garden")
            let scroll = app.scrollViews["watch.scroll"]
            let viewport = scroll.exists ? scroll.frame : app.frame
            print("Watch \(size) geometry: viewport \(viewport), garden \(garden.frame)")
            XCTAssertTrue(app.staticTexts["watch.day"].exists)
            capture("Watch \(size) garden", app: app)

            let amount = app.staticTexts["watch.estimate"]
            reach(amount, in: app, fullyVisible: true)
            XCTAssertTrue(amount.label.contains("CO₂e"))
            capture("Watch \(size) estimate", app: app)
            let savedAt = element("watch.savedAt", in: app)
            reach(savedAt, in: app, fullyVisible: true)
            XCTAssertTrue(savedAt.label.contains("Last saved"))
            capture("Watch \(size) saved date", app: app)

            let refresh = app.buttons["watch.refresh"]
            reach(refresh, in: app, fullyVisible: true)
            XCTAssertFalse(refresh.isEnabled, "An isolated example cannot contact a phone")
            XCTAssertEqual(refresh.label, "Refresh from iPhone")
            XCTAssertGreaterThanOrEqual(refresh.frame.height, 44)
            print("Watch \(size) refresh frame: \(refresh.frame)")
            capture("Watch \(size) refresh", app: app)
            let note = app.staticTexts["watch.connectionNote"]
            reach(note, in: app)
            XCTAssertTrue(note.label.contains("No phone activity is read or saved"))
            app.terminate()
        }
    }

    func testOrdinaryEmptyWatchOffersRefresh() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Use an empty simulator for this ordinary app check")
        #else
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("DFE Watch") == true else {
            throw XCTSkip("Use an owned, empty DFE Watch simulator")
        }
        let app = XCUIApplication()
        app.launch()
        let status = app.staticTexts["watch.status.title"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Watch sharing is off")
        XCTAssertFalse(app.staticTexts["watch.estimate"].exists)
        let refresh = app.buttons["watch.refresh"]
        reach(refresh, in: app, fullyVisible: true)
        XCTAssertTrue(refresh.isEnabled)
        XCTAssertEqual(refresh.label, "Refresh from iPhone")
        print("Watch ordinary refresh frame: \(refresh.frame)")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Watch ordinary refresh enabled — empty simulator"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        #endif
    }

    func testPendingAndUnavailableStatesDoNotInventAnAmount() {
        let examples = ["pending": "Your garden is on its way", "disconnected": "Screen Time is disconnected",
                        "sharingOff": "Watch sharing is off", "unavailable": "Your phone result is unavailable"]
        for (example, title) in examples.sorted(by: { $0.key < $1.key }) {
            let app = launch(example)
            let status = app.staticTexts["watch.status.title"]
            XCTAssertTrue(status.waitForExistence(timeout: 10))
            XCTAssertEqual(status.label, title)
            XCTAssertFalse(app.staticTexts["watch.estimate"].exists)
            capture("Watch \(example)", app: app)
            app.terminate()
        }
    }

    func testOlderResultKeepsItsSavedDayWarning() {
        let app = launch("stale")
        XCTAssertTrue(app.staticTexts["watch.heading"].waitForExistence(timeout: 10))
        let warning = element("watch.stale", in: app)
        reach(warning, in: app)
        XCTAssertTrue(warning.label.contains("Last saved day"))
        capture("Watch older saved result", app: app)
    }

    // [03] These checks exercise the exact shared content. They do not replace adding a real watch-face complication or Smart Stack widget.
    func testThreeComplicationContentFamiliesKeepDateAmountAndGarden() {
        for family in ["rectangular", "circular", "inline"] {
            let app = launch("growing", extra: ["-ui-watch-complication", family])
            XCTAssertTrue(app.staticTexts["watch.complication.preview"].waitForExistence(timeout: 10))
            let content = element("watch.complication.content", in: app)
            XCTAssertTrue(content.exists)
            XCTAssertTrue(content.label.contains("Growing"))
            XCTAssertTrue(content.label.contains("Estimated phone footprint"))
            XCTAssertTrue(content.label.contains("grams"))
            XCTAssertGreaterThan(content.frame.width, 0)
            XCTAssertLessThanOrEqual(content.frame.maxX, app.windows.firstMatch.frame.maxX)
            capture("Complication content \(family)", app: app)
            app.terminate()
        }
    }

    func testComplicationPrivacyAndPendingHaveNoAmountInAccessibleContent() {
        let pending = launch("pending", extra: ["-ui-watch-complication", "rectangular"])
        XCTAssertTrue(pending.staticTexts["watch.complication.preview"].waitForExistence(timeout: 10))
        let pendingContent = element("watch.complication.content", in: pending)
        XCTAssertFalse(pendingContent.label.contains("grams"))
        capture("Complication pending content", app: pending)
        pending.terminate()

        let redacted = launch("growing", extra: ["-ui-watch-complication", "rectangular", "-ui-watch-privacy-redacted"])
        XCTAssertTrue(redacted.staticTexts["watch.complication.preview"].waitForExistence(timeout: 10))
        let privateContent = element("watch.complication.content", in: redacted)
        XCTAssertTrue(privateContent.label.contains("Unlock"))
        XCTAssertFalse(privateContent.label.contains("grams"))
        XCTAssertFalse(privateContent.label.contains("Growing"))
        capture("Complication privacy content", app: redacted)
    }

    func testComplicationOlderDayRemainsClearlySaved() {
        let app = launch("stale", extra: ["-ui-watch-complication", "circular"])
        XCTAssertTrue(app.staticTexts["watch.complication.preview"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("watch.complication.content", in: app).label.contains("Last saved day"))
        capture("Complication older day content", app: app)
    }
}
