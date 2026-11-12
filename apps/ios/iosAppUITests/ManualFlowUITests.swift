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

// [01] Shared navigation helpers use a separate archive so screen checks never edit the owner's
// real history

import XCTest

@MainActor
enum AutomaticUITestSupport {
    static func open(reset: Bool = true, fixture: Bool = false, legacyToday: Bool = false,
                     largeText: Bool = false, dark: Bool = false, preview: Bool = true,
                     refreshTesting: Bool = false, revokedPreview: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        // [02] Every example uses separate history, so these navigation tests never read the
        // person's Screen Time.
        app.launchArguments = ["-ui-testing"] + (reset ? ["-reset-ui-state", "-ui-reset-appearance"] : [])
            + (fixture ? ["-ui-example-history"] : [])
            + (legacyToday ? ["-ui-legacy-today"] : [])
            + (largeText ? ["-ui-extra-large-text"] : [])
            + (dark ? ["-ui-dark-mode"] : [])
            + (preview ? ["-ui-automatic-preview"] : [])
            + (refreshTesting ? ["-ui-refresh-test"] : [])
            + (revokedPreview ? ["-ui-revoked-preview"] : [])
        app.launch()
        return app
    }

    static func element(_ id: String, in container: XCUIElement) -> XCUIElement {
        container.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    static func reachSettings(_ id: String, in app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected)
        let form = element("settings.form", in: app)
        // [03] Look only in the visible Settings page, or a hidden tab could answer for the wrong
        // screen.
        let target = element(id, in: form)
        reach(target, in: app, inside: form, below: app.navigationBars["Settings"], verticalMargin: 16)
        XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected)
        return target
    }

    static func reach(_ element: XCUIElement, in app: XCUIApplication,
                      inside scopedContainer: XCUIElement? = nil,
                      below scopedNavigationBar: XCUIElement? = nil,
                      verticalMargin: CGFloat = 4) {
        var recordedViewport = false
        var searchDirection = 1.0
        var searchSteps = 0
        var searchLimit = 4
        for _ in 0..<60 {
            let window = app.windows.firstMatch
            let bars: [XCUIElement]
            let container: XCUIElement
            if let scopedContainer {
                // [04] Scroll the open sheet itself. Dragging the page behind it could dismiss the
                // sheet and hide a navigation problem.
                guard scopedContainer.exists, let scopedNavigationBar,
                      scopedNavigationBar.exists else {
                    XCTFail("The requested sheet must stay open while reading its content")
                    return
                }
                container = scopedContainer
                bars = [scopedNavigationBar] + app.tabBars.allElementsBoundByIndex
            } else {
                bars = app.navigationBars.allElementsBoundByIndex + app.tabBars.allElementsBoundByIndex
                let candidates = Array(app.collectionViews.allElementsBoundByIndex.reversed())
                    + Array(app.tables.allElementsBoundByIndex.reversed())
                    + Array(app.scrollViews.allElementsBoundByIndex.reversed())
                container = candidates.first { $0.exists && $0.isHittable && $0.frame.intersects(window.frame) } ?? window
            }
            let frame = container.frame
            var visible = frame.intersection(window.frame)
            for bar in bars where bar.exists && bar.isHittable && bar.frame.intersects(visible) {
                if bar.frame.midY < visible.midY {
                    let top = max(visible.minY, bar.frame.maxY)
                    visible = CGRect(x: visible.minX, y: top, width: visible.width, height: visible.maxY - top)
                } else {
                    visible.size.height = min(visible.maxY, bar.frame.minY) - visible.minY
                }
            }
            visible = visible.insetBy(dx: 4, dy: verticalMargin)
            // [05] Keep one live screen frame for this step. A windowed iPad snapshot can use local
            // points, so mixing it with the live window and bars makes visible text look outside the page.
            let targetFrame = element.exists ? element.frame : nil
            if let targetFrame, element.isHittable {
                let inBar = bars.contains { $0.exists && $0.isHittable && $0.frame.insetBy(dx: -1, dy: -1).contains(targetFrame) }
                if inBar || visible.insetBy(dx: -1, dy: -1).contains(targetFrame) { return }
                // [06] A large-text row may be taller than the screen, but it still needs a usable
                // touch area. Ordinary buttons should fit fully.
                let shown = targetFrame.intersection(visible)
                if targetFrame.height > visible.height,
                   shown.height >= 44, shown.width >= min(44, targetFrame.width),
                   targetFrame.minX >= visible.minX - 1,
                   targetFrame.maxX <= visible.maxX + 1 { return }
            }
            XCTAssertGreaterThan(visible.height, 44)
            if !recordedViewport {
                recordedViewport = true
                let diagnostics = XCTAttachment(string: app.debugDescription)
                diagnostics.name = "Viewport before scrolling to requested content"
                diagnostics.lifetime = .keepAlways
                XCTContext.runActivity(named: "Scroll viewport diagnostics") { $0.add(diagnostics) }
            }
            let offset: Double
            if let targetFrame, !targetFrame.isEmpty {
                offset = targetFrame.midY - visible.midY
                searchDirection = offset < 0 ? -1 : 1
                searchSteps = 0
                searchLimit = 4
            } else {
                // [07] An offscreen row may have no reported position. Search both ways so the
                // test does not get stuck at one end.
                if searchSteps >= searchLimit {
                    searchDirection *= -1
                    searchSteps = 0
                    searchLimit = min(16, searchLimit * 2)
                }
                searchSteps += 1
                offset = visible.height * 0.5 * searchDirection
            }
            let movement = max(-visible.height * 0.55, min(visible.height * 0.55, offset))
            // [08] Small moves let tall text settle inside the clear area. A large minimum
            // can keep jumping past it in both directions, even when the whole text fits.
            let minimumTravel: CGFloat
            if let targetFrame, !targetFrame.isEmpty {
                let fittingRoom = max(0, (visible.height - targetFrame.height) / 2)
                minimumTravel = min(12, abs(movement) + fittingRoom)
            } else {
                minimumTravel = min(64, visible.height * 0.75)
            }
            let distance = max(minimumTravel, abs(movement)) * (movement < 0 ? -1.0 : 1.0)
            let x = visible.midX
            // [09] Start the gesture from the stable window so a hidden tab cannot change the page
            // while the test prepares a drag.
            let windowFrame = window.frame
            let start = window.coordinate(withNormalizedOffset: CGVector(
                dx: (x - windowFrame.minX) / windowFrame.width,
                dy: (visible.midY + distance / 2 - windowFrame.minY) / windowFrame.height))
            let end = window.coordinate(withNormalizedOffset: CGVector(
                dx: (x - windowFrame.minX) / windowFrame.width,
                dy: (visible.midY - distance / 2 - windowFrame.minY) / windowFrame.height))
            start.press(forDuration: 0, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.25)
        }
        // [10] Keep the failed screen area and control for review; do not make the check easier
        // just to pass.
        let diagnostics = XCTAttachment(string: "Requested element: \(element.debugDescription)\n\(app.debugDescription)")
        diagnostics.name = "Unreachable UI element and viewport"
        diagnostics.lifetime = .keepAlways
        XCTContext.runActivity(named: "Unreachable UI element diagnostics") { $0.add(diagnostics) }
        XCTAssertTrue(element.exists, "The requested content must exist")
        XCTAssertTrue(element.isHittable, "The requested content must remain reachable")
        XCTFail("The requested content did not become fully visible")
    }

    // [16] Pick a background point after the alert has settled. A larger alert can cover
    // the old tab position, and tapping there could answer the warning by accident.
    static func tapBackground(outside alert: XCUIElement, preferring preferredFrame: CGRect,
                              in app: XCUIApplication) {
        XCTAssertTrue(alert.exists)
        let window = app.windows.firstMatch
        let windowFrame = window.frame
        let safeArea = windowFrame.insetBy(dx: 4, dy: min(44, windowFrame.height / 4))
        let excluded = alert.frame.insetBy(dx: -8, dy: -8)
        func exposedParts(of frame: CGRect) -> [CGRect] {
            let area = frame.intersection(safeArea)
            guard !area.isNull, !area.isEmpty else { return [] }
            if !area.intersects(excluded) { return [area] }
            return [
                CGRect(x: area.minX, y: area.minY,
                       width: max(0, min(area.maxX, excluded.minX) - area.minX), height: area.height),
                CGRect(x: max(area.minX, excluded.maxX), y: area.minY,
                       width: max(0, area.maxX - max(area.minX, excluded.maxX)), height: area.height),
                CGRect(x: area.minX, y: area.minY,
                       width: area.width, height: max(0, min(area.maxY, excluded.minY) - area.minY)),
                CGRect(x: area.minX, y: max(area.minY, excluded.maxY),
                       width: area.width, height: max(0, area.maxY - max(area.minY, excluded.maxY)))
            ].filter { !$0.isEmpty }.sorted { $0.width * $0.height > $1.width * $1.height }
        }
        let preferred = exposedParts(of: preferredFrame)
        let fallback = exposedParts(of: safeArea)
        guard let region = preferred.first ?? fallback.first else {
            XCTFail("No exposed app background is available for a safe modal-blocking tap")
            return
        }
        let point = CGPoint(x: region.midX, y: region.midY)
        XCTAssertTrue(safeArea.contains(point))
        XCTAssertFalse(excluded.contains(point), "A background check must never tap the alert or its controls")
        let detail = XCTAttachment(string: "Target: \(point). Alert: \(alert.frame). Excluded: \(excluded). Preferred background: \(preferredFrame). Used exposed tab area: \(!preferred.isEmpty).")
        detail.name = "Verified background tap outside native alert"
        detail.lifetime = .keepAlways
        XCTContext.runActivity(named: "Check the modal's exposed background") { $0.add(detail) }
        window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x - windowFrame.minX, dy: point.y - windowFrame.minY)).tap()
    }

    // [17] Native warnings can scroll their message and actions separately at large text.
    // Read both ends of the message rather than treating a visible fragment as the whole warning.
    static func readNativeAlertMessage(_ message: String, in alert: XCUIElement, app: XCUIApplication) {
        let text = alert.staticTexts[message]
        XCTAssertTrue(text.exists)
        capture("Native warning before reading its scrollable message")
        revealNativeAlertElement(text, in: alert, app: app, goal: .start)
        capture("Native warning message beginning is readable")
        revealNativeAlertElement(text, in: alert, app: app, goal: .end)
        capture("Native warning message ending is readable")
    }

    static func revealNativeAlertAction(_ button: XCUIElement, in alert: XCUIElement, app: XCUIApplication) {
        revealNativeAlertElement(button, in: alert, app: app, goal: .full)
        capture("Native warning action fully visible: " + button.label)
    }

    private enum NativeAlertReadingGoal: Equatable { case start, end, full }

    // [18] Scroll only the native region that owns this text or button. Moving the page
    // behind the warning would not prove that the warning itself can be read.
    private static func revealNativeAlertElement(_ element: XCUIElement, in alert: XCUIElement,
                                                 app: XCUIApplication, goal: NativeAlertReadingGoal) {
        for _ in 0..<12 {
            XCTAssertTrue(alert.exists)
            XCTAssertTrue(element.exists)
            let lookup = element.identifier.isEmpty ? element.label : element.identifier
            let scrolls = alert.scrollViews.containing(element.elementType, identifier: lookup)
                .allElementsBoundByIndex.sorted { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
            let container = scrolls.first ?? alert
            let window = app.windows.firstMatch
            let windowFrame = window.frame
            let nativeViewport = container.frame.intersection(alert.frame).intersection(windowFrame)
            // [19] Apple's message already has its own padding. Another margin would make
            // readable words look hidden; action buttons still need their clear eight-point gap.
            let visible = goal == .full ? nativeViewport.insetBy(dx: 8, dy: 8) : nativeViewport
            let frame = element.frame
            XCTAssertGreaterThan(visible.height, 44)
            guard frame.minX >= visible.minX - 1, frame.maxX <= visible.maxX + 1 else {
                XCTFail("The native warning must keep its text and actions within the reading area")
                return
            }
            let shown = frame.intersection(visible)
            let readablePart = shown.height >= min(44, frame.height)
            let complete: Bool
            let offset: CGFloat
            switch goal {
            case .start:
                complete = frame.minY >= visible.minY - 1 && readablePart
                offset = frame.minY - visible.minY
            case .end:
                complete = frame.maxY <= visible.maxY + 1 && readablePart
                offset = frame.maxY - visible.maxY
            case .full:
                complete = visible.insetBy(dx: -1, dy: -1).contains(frame)
                offset = frame.midY - visible.midY
            }
            if complete {
                if goal == .full { XCTAssertTrue(element.isHittable) }
                return
            }
            guard !scrolls.isEmpty else {
                XCTFail("The native warning content does not fit and has no scrolling region")
                return
            }
            let movement = max(-visible.height * 0.55, min(visible.height * 0.55, offset))
            let fittingRoom = max(0, (visible.height - frame.height) / 2)
            let minimumTravel = goal == .full ? min(12, abs(movement) + fittingRoom) : 12
            let distance = max(minimumTravel, abs(movement)) * (movement < 0 ? -1.0 : 1.0)
            let start = window.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: visible.midX - windowFrame.minX,
                                     dy: visible.midY + distance / 2 - windowFrame.minY))
            let end = window.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: visible.midX - windowFrame.minX,
                                     dy: visible.midY - distance / 2 - windowFrame.minY))
            start.press(forDuration: 0, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.25)
        }
        let detail = XCTAttachment(string: "Requested native content: \(element.debugDescription)\n\(alert.debugDescription)")
        detail.name = "Native warning content could not be fully reviewed"
        detail.lifetime = .keepAlways
        XCTContext.runActivity(named: "Native warning reading failure") { $0.add(detail) }
        XCTFail("The native warning content did not reach its readable position")
    }

    static func assertNoManualEntry(in app: XCUIApplication) {
        for id in ["onboarding.setup", "today.edit", "history.edit", "settings.editRoutine", "automatic.review", "automatic.manual"] {
            XCTAssertFalse(app.buttons[id].exists, "Manual input route remains: \(id)")
        }
        for label in ["Add today's entry", "Edit today's use", "Edit my routine", "Set up my routine"] {
            XCTAssertFalse(app.buttons[label].exists, "Manual input action remains visible")
        }
        XCTAssertFalse(app.scrollViews["input.editor"].exists)
        XCTAssertEqual(app.textFields.count, 0)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "input.preset.")).count, 0)
    }

    static func openSetup(in app: XCUIApplication, id: String = "onboarding.automatic") {
        let action: XCUIElement
        if id.hasPrefix("settings.") {
            let management = element("screen-time.management", in: element("settings.form", in: app))
            if id == "settings.automaticSetup", management.exists,
               !element(id, in: element("settings.form", in: app)).exists {
                reachSettings("screen-time.management", in: app).tap()
            }
            action = reachSettings(id, in: app)
        }
        else {
            action = app.buttons[id]
            reach(action, in: app)
        }
        XCTAssertGreaterThanOrEqual(action.frame.height, 44)
        action.tap()
        XCTAssertTrue(app.navigationBars["Automatic setup"].waitForExistence(timeout: 8))
    }

    static func openHistoryDay(in app: XCUIApplication) {
        app.tabBars.buttons["History"].tap()
        let bar = app.navigationBars["History"]
        XCTAssertTrue(bar.waitForExistence(timeout: 8))
        let content = element("history.content", in: app)
        XCTAssertTrue(content.waitForExistence(timeout: 8))
        let row = content.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.day.")).firstMatch
        // [11] Find the day on the visible page before scrolling, so a hidden retained row cannot
        // open the wrong view.
        reach(row, in: app, inside: content, below: bar, verticalMargin: 16)
        XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        row.tap()
        XCTAssertTrue(app.staticTexts["footprint.total"].waitForExistence(timeout: 8))
    }

    static func captureElement(_ element: XCUIElement, name: String) {
        guard element.exists && element.isHittable else {
            XCTFail("The DFE component must be visible before its review image is captured")
            return
        }
        // [12] Capture only the component, leaving the phone's status bar and unrelated
        // notifications out of the report.
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = "DFE-only " + name + " (isolated synthetic UI data)"
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Review DFE component: " + name) { $0.add(attachment) }
    }

    static func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name + " (isolated synthetic UI data)"
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: name) { $0.add(attachment) }
    }
}

@MainActor
final class AutomaticReadOnlyFlowUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }

    // [13] Once setup is saved, Today should focus on the garden while connection controls remain
    // in Settings.
    func testSavedAutomaticSetupStaysAvailableOnlyInSettings() {
        let app = AutomaticUITestSupport.open(fixture: true)
        let latest = AutomaticUITestSupport.element("today.latestResult", in: app)
        XCTAssertTrue(latest.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["today.automaticSetup"].exists)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        app.tabBars.buttons["Settings"].tap()
        let status = AutomaticUITestSupport.reachSettings("screen-time.status", in: app)
        XCTAssertEqual(status.label, "Connected")
        let settings = AutomaticUITestSupport.element("settings.form", in: app)
        XCTAssertFalse(AutomaticUITestSupport.element("settings.automaticSetup", in: settings).exists)
        XCTAssertTrue(AutomaticUITestSupport.reachSettings("screen-time.management", in: app).exists)
        XCTAssertTrue(AutomaticUITestSupport.reachSettings("settings.modelDetails", in: app).exists)
        XCTAssertFalse(app.navigationBars["Automatic setup"].exists)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
    }

    // [14] Older results must stay readable without bringing manual entry back into the automatic
    // experience.
    func testLegacyResultsRemainReadableWithoutRestoringManualEditing() {
        let app = AutomaticUITestSupport.open(fixture: true, legacyToday: true)
        XCTAssertTrue(app.staticTexts["footprint.total"].waitForExistence(timeout: 8))
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        for title in ["Today", "History", "Settings"] {
            XCTAssertTrue(app.tabBars.buttons[title].exists)
            XCTAssertTrue(app.tabBars.buttons[title].isHittable)
        }
        AutomaticUITestSupport.openHistoryDay(in: app)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        AutomaticUITestSupport.capture("Read-only legacy result")
    }

    // [15] Settings should explain connection and privacy without repeating widget setup already
    // offered on Today.
    func testSettingsShowsConnectionAndPrivacyWithoutRepeatedWidgetSetup() {
        let app = AutomaticUITestSupport.open(fixture: true)
        app.tabBars.buttons["Settings"].tap()
        let status = AutomaticUITestSupport.reachSettings("screen-time.status", in: app)
        XCTAssertFalse(status.label.isEmpty)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        XCTAssertFalse(AutomaticUITestSupport.element("settings.widgetHelp", in: app).exists)
        let privacy = AutomaticUITestSupport.reachSettings("settings.privacy", in: app)
        XCTAssertGreaterThanOrEqual(privacy.frame.height, 44)
    }
}
