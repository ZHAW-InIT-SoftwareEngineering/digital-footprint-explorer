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

// [01] Real pull gestures need layout checks, but those checks must not borrow activity from the
// owner's phone

import XCTest

@MainActor
final class AutomaticRefreshUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    // [02] Pulling to refresh should update the view without losing saved days or the chosen
    // appearance.
    func testPullRefreshAcrossTabsKeepsSavedResultsAndChosenTheme() throws {
        let app = AutomaticUITestSupport.open(fixture: true, refreshTesting: true)
        XCTAssertTrue(app.staticTexts["footprint.total"].waitForExistence(timeout: 8))
        let savedTotal = app.staticTexts["footprint.total"].label
        let savedDays = historyLabels(in: app)
        XCTAssertEqual(savedDays.count, 1)
        chooseDark(in: app)

        for tab in RefreshTab.allCases {
            let content = open(tab, in: app)
            try pullToRefresh(tab, content: content, in: app)
            XCTAssertTrue(app.tabBars.buttons[tab.title].isSelected)
            XCTAssertFalse(app.navigationBars["Automatic setup"].exists)
            XCTAssertFalse(app.alerts.firstMatch.exists)
            AutomaticUITestSupport.assertNoManualEntry(in: app)
            if tab == .today {
                XCTAssertEqual(app.staticTexts["footprint.total"].label, savedTotal)
                XCTAssertFalse(app.buttons["today.automaticSetup"].exists)
            } else if tab == .history {
                XCTAssertEqual(dayRows(in: content).allElementsBoundByIndex.map(\.label).sorted(), savedDays)
            }
            AutomaticUITestSupport.capture("Pull refresh keeps \(tab.title) in the chosen theme")
            try app.performAccessibilityAudit(for: [.textClipped, .hitRegion])
        }
        assertDarkChoice(in: app)

        app.terminate()
        // [03] Do not add the example again; the saved garden and appearance need to survive on
        // their own.
        let reopened = AutomaticUITestSupport.open(reset: false, refreshTesting: true)
        XCTAssertTrue(reopened.staticTexts["footprint.total"].waitForExistence(timeout: 8))
        XCTAssertEqual(reopened.staticTexts["footprint.total"].label, savedTotal)
        XCTAssertEqual(historyLabels(in: reopened), savedDays)
        assertDarkChoice(in: reopened)
        AutomaticUITestSupport.assertNoManualEntry(in: reopened)
    }

    // [04] A refresh is not consent to set up activity access, and empty history must not grow a
    // made-up day.
    func testLargestTextPullRefreshDoesNotConfigureOrInventAHistoryDay() throws {
        let app = AutomaticUITestSupport.open(largeText: true, refreshTesting: true)
        for tab in RefreshTab.allCases {
            let content = open(tab, in: app)
            try pullToRefresh(tab, content: content, in: app)
            XCTAssertTrue(app.tabBars.buttons[tab.title].isSelected)
            XCTAssertFalse(app.navigationBars["Automatic setup"].exists)
            XCTAssertFalse(app.staticTexts["footprint.total"].exists)
            XCTAssertFalse(app.alerts.firstMatch.exists)
            AutomaticUITestSupport.assertNoManualEntry(in: app)
            if tab == .today {
                XCTAssertTrue(app.buttons["onboarding.automatic"].exists)
            } else if tab == .history {
                let empty = AutomaticUITestSupport.element("history.empty", in: content)
                AutomaticUITestSupport.reach(empty, in: app, inside: content,
                                             below: app.navigationBars[tab.title], verticalMargin: 16)
                XCTAssertTrue(empty.exists)
                XCTAssertEqual(empty.label, "No saved days yet")
                let guidance = content.staticTexts["history.empty.guidance"]
                AutomaticUITestSupport.reach(guidance, in: app, inside: content,
                                             below: app.navigationBars[tab.title], verticalMargin: 16)
                XCTAssertEqual(guidance.label,
                    "Connect Screen Time from Today. Completed days appear here when data is available.")
                XCTAssertEqual(dayRows(in: content).count, 0)
            }
            AutomaticUITestSupport.capture("Largest-text \(tab.title) after pull refresh without setup")
            try app.performAccessibilityAudit(for: [.textClipped, .hitRegion])
        }
    }

    // [05] People using large text should still be able to find and read the empty-history
    // explanation.
    func testEmptyHistoryExposesItsMessageAtLargestText() throws {
        let app = AutomaticUITestSupport.open(largeText: true, refreshTesting: true)
        let content = open(.history, in: app)
        try pullToRefresh(.history, content: content, in: app)
        // [06] A short scroll should reveal this empty page without an endless search for missing
        // content.
        for _ in 0..<4 { content.swipeUp() }
        AutomaticUITestSupport.capture("Empty History after four upward swipes, AX5")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Empty History accessibility after bounded scrolling"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)

        XCTAssertTrue(app.tabBars.buttons["History"].isSelected)
        XCTAssertEqual(dayRows(in: content).count, 0)
        let title = content.staticTexts["history.empty"]
        let guidance = content.staticTexts["history.empty.guidance"]
        XCTAssertTrue(title.waitForExistence(timeout: 2), "The rendered empty title must be exposed to accessibility")
        XCTAssertEqual(title.label, "No saved days yet")
        XCTAssertTrue(guidance.waitForExistence(timeout: 2), "The empty-state guidance must be exposed to accessibility")
        XCTAssertEqual(guidance.label,
            "Connect Screen Time from Today. Completed days appear here when data is available.")
        let viewport = visibleViewport(content, tab: .history, in: app)
        for element in [title, guidance] {
            XCTAssertTrue(element.isHittable)
            let shown = element.frame.intersection(viewport)
            XCTAssertGreaterThan(shown.width, 0)
            XCTAssertGreaterThan(shown.height, 0)
        }
    }

    // [07] The refresh indicator needs room above the greeting throughout a pull, not only once
    // the screen settles.
    func testConfiguredTodayGreetingDuringShortThresholdAndFullPulls() throws {
        for largestText in [false, true] {
            let app = AutomaticUITestSupport.open(fixture: true, largeText: largestText, refreshTesting: true)
            let content = open(.today, in: app)
            let greeting = content.staticTexts["today.welcome"]
            let date = content.staticTexts["today.date"]
            XCTAssertEqual(greeting.label, "Good to have you here")
            let savedTotal = app.staticTexts["footprint.total"].label
            XCTAssertFalse(savedTotal.isEmpty)
            func assertReservedSpace(_ greeting: XCUIElement, in app: XCUIApplication, context: String) {
                let gap = greeting.frame.minY - app.navigationBars["Today"].frame.maxY
                let receipt = XCTAttachment(string: "Context: \(context), AX5: \(largestText), greeting gap: \(gap) pt")
                receipt.name = "Today greeting reserved space"
                receipt.lifetime = .keepAlways
                self.add(receipt)
                XCTAssertGreaterThanOrEqual(gap, 48,
                    "The greeting needs reserved space below the navigation bar for the native spinner's rebound")
            }
            let stages: [(String, CGFloat, CGFloat, TimeInterval)] = [
                ("short-release", 0.15, 0.26, 0),
                ("threshold-release", 0.15, 0.34, 0.1),
                ("full-release", 0.18, 0.86, 0)
            ]
            for (name, start, end, hold) in stages {
                AutomaticUITestSupport.reach(greeting, in: app, inside: content,
                    below: app.navigationBars["Today"], verticalMargin: 40)
                let before = try completedRefreshes(in: content)
                let viewport = visibleViewport(content, tab: .today, in: app)
                print("DFE_GREETING_REFRESH_STAGE:\(name):\(Date().timeIntervalSince1970):AX5=\(largestText)")
                AutomaticUITestSupport.capture("Configured Today before \(name), AX5=\(largestText)")
                assertReservedSpace(greeting, in: app, context: "before " + name)
                drag(in: viewport, from: start, to: end, hold: hold, nativePullTab: .today, in: app)
                // [08] A still image cannot prove the whole animation is clear. Review the
                // recording through the pull and its return.
                XCTAssertEqual(greeting.label, "Good to have you here")
                XCTAssertFalse(app.navigationBars["Automatic setup"].exists)
                XCTAssertFalse(app.alerts.firstMatch.exists)
                AutomaticUITestSupport.assertNoManualEntry(in: app)
                if name == "full-release" {
                    let completion = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                        content.value as? String == "Completed refreshes: \(before + 1)"
                    }, object: content)
                    XCTAssertEqual(XCTWaiter.wait(for: [completion], timeout: 10), .completed,
                                   "The full native pull should complete a refresh")
                }
                let after = try completedRefreshes(in: content)
                XCTAssertGreaterThanOrEqual(after, before)
                AutomaticUITestSupport.capture("Configured Today after \(name), AX5=\(largestText)")
                print("DFE_GREETING_REFRESH_RETURN:\(name):\(Date().timeIntervalSince1970):AX5=\(largestText):COUNT=\(after)")
                AutomaticUITestSupport.reach(greeting, in: app, inside: content,
                    below: app.navigationBars["Today"], verticalMargin: 40)
                XCTAssertGreaterThanOrEqual(date.frame.minY - greeting.frame.maxY, 8 - 1)
                assertReservedSpace(greeting, in: app, context: "after " + name)
                XCTAssertEqual(app.staticTexts["footprint.total"].label, savedTotal)
            }
            app.terminate()
            // [09] Reopen the saved example without adding it again, so a hidden persistence
            // failure cannot be covered up.
            let reopened = AutomaticUITestSupport.open(reset: false, fixture: false,
                                                       largeText: largestText, refreshTesting: true)
            let reopenedContent = open(.today, in: reopened)
            let reopenedGreeting = reopenedContent.staticTexts["today.welcome"]
            AutomaticUITestSupport.reach(reopenedGreeting, in: reopened, inside: reopenedContent,
                below: reopened.navigationBars["Today"], verticalMargin: 40)
            XCTAssertEqual(reopenedGreeting.label, "Good to have you here")
            assertReservedSpace(reopenedGreeting, in: reopened, context: "cold relaunch")
            XCTAssertEqual(reopened.staticTexts["footprint.total"].label, savedTotal)
            XCTAssertFalse(reopened.navigationBars["Automatic setup"].exists)
            AutomaticUITestSupport.assertNoManualEntry(in: reopened)
            AutomaticUITestSupport.capture("Configured greeting after cold relaunch, AX5=\(largestText)")
            reopened.terminate()
        }
    }

    private enum RefreshTab: CaseIterable {
        case today, history, settings

        var title: String {
            switch self {
            case .today: "Today"
            case .history: "History"
            case .settings: "Settings"
            }
        }

        var contentID: String {
            switch self {
            case .today: "today.content"
            case .history: "history.content"
            case .settings: "settings.form"
            }
        }

        var introID: String {
            switch self {
            case .today: "today.welcome"
            case .history: "history.intro"
            case .settings: "settings.intro"
            }
        }
    }

    private func open(_ tab: RefreshTab, in app: XCUIApplication) -> XCUIElement {
        let button = app.tabBars.buttons[tab.title]
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        let content = AutomaticUITestSupport.element(tab.contentID, in: app)
        // [10] Today opens first. On other routes, check the visible page rather than trusting a
        // tab left in memory.
        let alreadyOnToday = tab == .today && button.isSelected && content.exists && content.isHittable
        if !alreadyOnToday { button.tap() }
        let selection = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in button.isSelected }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [selection], timeout: 8), .completed)
        XCTAssertTrue(app.navigationBars[tab.title].waitForExistence(timeout: 8))
        XCTAssertTrue(content.waitForExistence(timeout: 8))
        XCTAssertTrue(content.isHittable)
        XCTAssertTrue(button.isSelected)
        return content
    }

    private func pullToRefresh(_ tab: RefreshTab, content: XCUIElement,
                               in app: XCUIApplication) throws {
        let intro = AutomaticUITestSupport.element(tab.introID, in: content)
        AutomaticUITestSupport.reach(intro, in: app, inside: content,
                                     below: app.navigationBars[tab.title], verticalMargin: 40)
        let clearance = intro.frame.minY - app.navigationBars[tab.title].frame.maxY
        XCTAssertGreaterThanOrEqual(clearance, 32,
                                    "The first heading needs room below the navigation bar and refresh area")
        let geometry = XCTAttachment(string: "\(tab.title): heading clearance \(clearance) pt; native pull starts at \(Date().timeIntervalSince1970)")
        geometry.name = "\(tab.title) before the native pull"
        geometry.lifetime = .keepAlways
        XCTContext.runActivity(named: "\(tab.title) native refresh spacing") { $0.add(geometry) }
        AutomaticUITestSupport.capture("\(tab.title) heading clear before native pull")
        let before = try completedRefreshes(in: content)
        let viewport = visibleViewport(content, tab: tab, in: app)
        // [11] Hold the pull long enough to review its indicator. The app still waits for real
        // refresh work, not a fake delay.
        drag(in: viewport, from: 0.18, to: 0.86, hold: 2, nativePullTab: tab, in: app)
        let expected = "Completed refreshes: \(before + 1)"
        let completion = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            content.value as? String == expected
        }, object: content)
        XCTAssertEqual(XCTWaiter.wait(for: [completion], timeout: 10), .completed,
                       "A downward pull must await the shared refresh on \(tab.title)")

        // [12] Reading further down the page must not start another data request.
        let afterPull = try completedRefreshes(in: content)
        drag(in: visibleViewport(content, tab: tab, in: app), from: 0.78, to: 0.34, in: app)
        XCTAssertEqual(try completedRefreshes(in: content), afterPull,
                       "An ordinary upward scroll must not refresh \(tab.title)")
        AutomaticUITestSupport.reach(intro, in: app, inside: content,
                                     below: app.navigationBars[tab.title], verticalMargin: 16)
    }

    private func completedRefreshes(in content: XCUIElement) throws -> Int {
        let value = try XCTUnwrap(content.value as? String)
        let prefix = "Completed refreshes: "
        XCTAssertTrue(value.hasPrefix(prefix), "The isolated refresh probe must be available")
        return try XCTUnwrap(Int(value.dropFirst(prefix.count)))
    }

    private func visibleViewport(_ content: XCUIElement, tab: RefreshTab,
                                 in app: XCUIApplication) -> CGRect {
        var frame = content.frame.intersection(app.windows.firstMatch.frame)
        let top = max(frame.minY, app.navigationBars[tab.title].frame.maxY)
        let bottom = min(frame.maxY, app.tabBars.firstMatch.frame.minY)
        frame = CGRect(x: frame.minX, y: top, width: frame.width, height: bottom - top)
        XCTAssertGreaterThan(frame.height, 100)
        return frame.insetBy(dx: 12, dy: 12)
    }

    private func drag(in viewport: CGRect, from start: CGFloat, to end: CGFloat,
                      hold: TimeInterval = 0.25, nativePullTab: RefreshTab? = nil,
                      in app: XCUIApplication) {
        let window = app.windows.firstMatch
        let frame = window.frame
        func coordinate(_ fraction: CGFloat) -> XCUICoordinate {
            window.coordinate(withNormalizedOffset: CGVector(
                dx: (viewport.midX - frame.minX) / frame.width,
                dy: (viewport.minY + viewport.height * fraction - frame.minY) / frame.height))
        }
        let startCoordinate = coordinate(start)
        let endCoordinate = coordinate(end)
        if let tab = nativePullTab {
            let largestText = app.launchArguments.contains("-ui-extra-large-text")
            // [13] Match this test pull to its recording so a layout problem can be reviewed at
            // the right moment.
            print("DFE_NATIVE_PULL:\(tab.title):\(Date().timeIntervalSince1970):AX5=\(largestText):H=\(frame.height)")
        }
        startCoordinate.press(forDuration: 0, thenDragTo: endCoordinate,
                              withVelocity: .slow, thenHoldForDuration: hold)
    }

    private func dayRows(in content: XCUIElement) -> XCUIElementQuery {
        content.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.day."))
    }

    private func historyLabels(in app: XCUIApplication) -> [String] {
        let content = open(.history, in: app)
        let rows = dayRows(in: content)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 8))
        return rows.allElementsBoundByIndex.map(\.label).sorted()
    }

    private func chooseDark(in app: XCUIApplication) {
        app.tabBars.buttons["Settings"].tap()
        AutomaticUITestSupport.reachSettings("settings.appearance", in: app).tap()
        let option = AutomaticUITestSupport.element("appearance.dark", in: app)
        AutomaticUITestSupport.reach(option, in: app)
        option.tap()
        if app.navigationBars["Appearance"].exists {
            app.navigationBars["Appearance"].buttons["Settings"].tap()
        }
        assertDarkChoice(in: app)
    }

    private func assertDarkChoice(in app: XCUIApplication) {
        app.tabBars.buttons["Settings"].tap()
        let appearance = AutomaticUITestSupport.reachSettings("settings.appearance", in: app)
        XCTAssertEqual(appearance.value as? String, "Dark")
    }
}
