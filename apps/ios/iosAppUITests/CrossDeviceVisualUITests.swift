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

import XCTest
import UIKit

@MainActor
final class CrossDeviceVisualUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }

    // [01] Review the real native pages with the same saved example, rather than drawing a mock screen.
    func testLightMainRoutesKeepTheCompletedDay() throws { try captureMainRoutes(dark: false) }

    func testDarkMainRoutesKeepTheCompletedDay() throws { try captureMainRoutes(dark: true) }

    // [02] An older manual entry must stay readable without hiding the unfinished automatic day.
    func testDryLegacyGardenKeepsItsDateAndWaitingMessage() throws {
        for dark in [false, true] {
            let theme = dark ? "dark" : "light"
            let app = AutomaticUITestSupport.open(fixture: true, legacyToday: true, dark: dark)
            let today = page("today.content", in: app)
            XCTAssertTrue(app.staticTexts["footprint.total"].waitForExistence(timeout: 8))
            let savedAmount = app.staticTexts["footprint.total"].label
            let savedDate = app.staticTexts["today.recordDate"].firstMatch.label
            XCTAssertFalse(savedAmount.isEmpty)
            XCTAssertFalse(savedDate.isEmpty)
            XCTAssertEqual(app.staticTexts["today.periodLabel"].firstMatch.label, "Saved today")
            XCTAssertTrue(app.staticTexts["garden.state"].label.contains("above your recent average"))
            reach("today.welcome", in: today, app: app, title: "Today")
            capture("gallery-\(theme)-today-dry", in: app)
            let pending = reach("today.pendingExplanation", in: today, app: app, title: "Today")
            XCTAssertTrue(pending.label.contains("Today's estimate waits until this day ends"))
            XCTAssertTrue(pending.label.contains("Missing activity stays pending"))
            XCTAssertEqual(app.staticTexts["today.automaticPending"].label, "Let your next day take shape")
            capture("gallery-\(theme)-dry-pending", in: app)
            select("Settings", in: app)
            select("Today", in: app)
            XCTAssertEqual(app.staticTexts["footprint.total"].label, savedAmount)
            XCTAssertEqual(app.staticTexts["today.recordDate"].firstMatch.label, savedDate)
            AutomaticUITestSupport.assertNoManualEntry(in: app)
            XCTAssertFalse(app.buttons["today.automaticSetup"].exists)
            app.terminate()
        }
    }

    private func captureMainRoutes(dark: Bool) throws {
        let theme = dark ? "dark" : "light"
        let app = AutomaticUITestSupport.open(fixture: true, dark: dark)
        let today = page("today.content", in: app)
        XCTAssertTrue(app.staticTexts["footprint.total"].waitForExistence(timeout: 8))
        let savedAmount = app.staticTexts["footprint.total"].label
        let savedDate = app.staticTexts["today.recordDate"].firstMatch.label
        XCTAssertFalse(savedAmount.isEmpty)
        XCTAssertFalse(savedDate.isEmpty)
        XCTAssertEqual(app.staticTexts["today.periodLabel"].firstMatch.label, "Latest completed day")
        reach("today.welcome", in: today, app: app, title: "Today")
        capture("gallery-\(theme)-today-green", in: app)

        let details = app.buttons["today.dayDetails"]
        AutomaticUITestSupport.reach(details, in: app, inside: today,
                                     below: app.navigationBars["Today"], verticalMargin: 16)
        XCTAssertTrue(details.isHittable)
        details.tap()
        XCTAssertTrue(app.staticTexts["source.activityPeriod"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["footprint.total"].label, savedAmount)
        let detail = app.scrollViews.containing(.staticText, identifier: "source.activityPeriod").firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        let (detailBar, todayBack) = detailNavigation(in: app, returningTo: "Today", theme: theme)
        let period = app.staticTexts["source.activityPeriod"]
        AutomaticUITestSupport.reach(period, in: app, inside: detail, below: detailBar, verticalMargin: 16)
        XCTAssertTrue(period.label.contains("saved date on this device"))
        let modelNote = app.staticTexts["source.referenceModel"]
        if UIDevice.current.userInterfaceIdiom == .pad {
            AutomaticUITestSupport.reach(modelNote, in: app, inside: detail, below: detailBar, verticalMargin: 16)
            XCTAssertTrue(modelNote.label.contains("not a measurement of iPad energy"))
        }
        capture("gallery-\(theme)-source-note", in: app)

        // [03] The category screenshot includes its icon, time and estimate, with the source row below it.
        let category = AutomaticUITestSupport.element("breakdown.category.VIDEO_STREAMING", in: detail)
        AutomaticUITestSupport.reach(category, in: app, inside: detail, below: detailBar, verticalMargin: 16)
        XCTAssertTrue(category.label.contains("Video streaming"))
        XCTAssertTrue(category.label.contains("30 min"))
        XCTAssertTrue(category.label.contains("g CO₂e"))
        let categoryLabel = category.label
        let sources = detail.staticTexts["breakdown.sources.VIDEO_STREAMING"]
        AutomaticUITestSupport.reach(sources, in: app, inside: detail, below: detailBar, verticalMargin: 16)
        XCTAssertTrue(sources.label.contains("Device"))
        XCTAssertTrue(sources.label.contains("Network"))
        XCTAssertTrue(sources.label.contains("Servers"))
        capture("gallery-\(theme)-category-detail", in: app)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        todayBack.tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 8))
        XCTAssertTrue(page("today.content", in: app).isHittable)
        XCTAssertEqual(app.staticTexts["footprint.total"].label, savedAmount)
        XCTAssertEqual(app.staticTexts["today.recordDate"].firstMatch.label, savedDate)

        select("History", in: app)
        let history = page("history.content", in: app)
        reach("history.intro", in: history, app: app, title: "History")
        capture("gallery-\(theme)-history", in: app)
        let row = history.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "history.day.")).firstMatch
        AutomaticUITestSupport.reach(row, in: app, inside: history,
                                     below: app.navigationBars["History"], verticalMargin: 16)
        XCTAssertTrue(row.isHittable)
        capture("gallery-\(theme)-history-day", in: app)
        row.tap()
        XCTAssertTrue(app.staticTexts["source.activityPeriod"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["footprint.total"].label, savedAmount)
        let historyDetail = app.scrollViews.containing(.staticText, identifier: "source.activityPeriod").firstMatch
        let (historyBar, _) = detailNavigation(in: app, returningTo: "History", theme: theme)
        let historyCategory = AutomaticUITestSupport.element("breakdown.category.VIDEO_STREAMING", in: historyDetail)
        AutomaticUITestSupport.reach(historyCategory, in: app, inside: historyDetail,
                                     below: historyBar, verticalMargin: 16)
        XCTAssertEqual(historyCategory.label, categoryLabel,
                       "Today and History must explain the same saved day")

        select("Settings", in: app)
        let settings = page("settings.form", in: app)
        reach("settings.intro", in: settings, app: app, title: "Settings")
        let connected = reach("screen-time.status", in: settings, app: app, title: "Settings")
        XCTAssertEqual(connected.label, "Connected")
        XCTAssertFalse(AutomaticUITestSupport.element("settings.automaticSetup", in: settings).exists)
        capture("gallery-\(theme)-settings", in: app)
        AutomaticUITestSupport.assertNoManualEntry(in: app)

        // [04] A tour of the other pages must not replace the visible garden or restart setup.
        select("Today", in: app)
        XCTAssertEqual(app.staticTexts["footprint.total"].label, savedAmount)
        XCTAssertEqual(app.staticTexts["today.recordDate"].firstMatch.label, savedDate)
        XCTAssertFalse(app.buttons["today.automaticSetup"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        app.terminate()
    }

    // [06] Duo can put Back in a vertical system toolbar, outside the dated navigation bar.
    // Use that observed control too, but still require a real back action and the correct destination.
    private func detailNavigation(in app: XCUIApplication, returningTo title: String,
                                  theme: String) -> (XCUIElement, XCUIElement) {
        let standardBar = app.navigationBars.containing(.button, identifier: title).firstMatch
        if standardBar.exists {
            let back = standardBar.buttons[title]
            XCTAssertTrue(back.isHittable)
            return (standardBar, back)
        }
        let bar = app.navigationBars.firstMatch
        let back = app.toolbars.buttons["BackButton"].firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 8))
        XCTAssertTrue(back.waitForExistence(timeout: 8))
        XCTAssertTrue(back.isHittable)
        let receipt = XCTAttachment(string: "Return route: \(title)\nNavigation: \(bar.debugDescription)\nNative toolbar back: \(back.debugDescription)")
        receipt.name = "gallery-\(theme)-\(title.lowercased())-native-back"
        receipt.lifetime = .keepAlways
        add(receipt)
        return (bar, back)
    }

    private func page(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let content = AutomaticUITestSupport.element(identifier, in: app)
        XCTAssertTrue(content.waitForExistence(timeout: 8))
        return content
    }

    @discardableResult
    private func reach(_ identifier: String, in content: XCUIElement,
                       app: XCUIApplication, title: String) -> XCUIElement {
        let element = AutomaticUITestSupport.element(identifier, in: content)
        // [05] On a wide screen, the sidebar is another scroll view. Scroll this page instead.
        AutomaticUITestSupport.reach(element, in: app, inside: content,
                                     below: app.navigationBars[title], verticalMargin: 16)
        return element
    }

    private func select(_ title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title].firstMatch
        if tab.exists && tab.isHittable {
            if !tab.isSelected { tab.tap() }
        } else {
            let button = app.buttons[title].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 8))
            XCTAssertTrue(button.isHittable)
            button.tap()
        }
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 8))
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        AutomaticUITestSupport.capture(name)
        let window = app.windows.firstMatch.frame
        let note = XCTAttachment(string: "Isolated example only. Window: \(window.width) x \(window.height) pt; orientation: \(XCUIDevice.shared.orientation.rawValue).")
        note.name = name + "-geometry"
        note.lifetime = .keepAlways
        add(note)
    }
}
