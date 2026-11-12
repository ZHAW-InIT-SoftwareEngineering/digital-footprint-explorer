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

// [01] Saved days should be easy to revisit, with tips and details that agree about the same
// result

import XCTest

@MainActor
final class HistoryExperienceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }

    // [02] A setup waiting for activity should explain the gap instead of displaying a fictional
    // history day.
    func testPendingAutomaticSetupDoesNotInventAHistoryDay() throws {
        let app = AutomaticUITestSupport.open()
        AutomaticUITestSupport.openSetup(in: app)
        let connect = app.buttons["automatic.connect"]
        AutomaticUITestSupport.reach(connect, in: app)
        connect.tap()
        XCTAssertTrue(app.staticTexts["today.automaticPending"].waitForExistence(timeout: 10))
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "history.day.")).count, 0)
        try assertHistoryTips(in: app, personalized: false)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
    }

    // [03] Completed automatic days need clear month headings and readable details without a
    // manual editor.
    func testSavedAutomaticDaysHaveMonthHeadingsAndReadOnlyDetails() throws {
        let app = AutomaticUITestSupport.open(fixture: true)
        try assertSharedTabSpacing(in: app, largestText: false)
        app.tabBars.buttons["History"].tap()
        try assertHistoryTips(in: app, personalized: true)
        let month = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "history.month.")).firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 8))
        XCTAssertFalse(month.label.isEmpty)
        AutomaticUITestSupport.openHistoryDay(in: app)
        XCTAssertFalse(app.staticTexts["footprint.total"].label.isEmpty)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        XCTAssertFalse(app.navigationBars.buttons["Edit"].exists)
        let assumptions = app.staticTexts["record.assumptions"]
        AutomaticUITestSupport.reach(assumptions, in: app)
        let otherApps = AutomaticUITestSupport.element("breakdown.category.MISCELLANEOUS", in: app)
        XCTAssertTrue(otherApps.exists)
        XCTAssertTrue(otherApps.label.contains("10 min"))
        let lastSources = app.staticTexts["breakdown.sources.VIDEO_CALL"]
        XCTAssertGreaterThanOrEqual(assumptions.frame.minY - lastSources.frame.maxY, 18)
        XCTAssertFalse(app.staticTexts["Inputs for this day"].exists)
        XCTAssertEqual(assumptions.frame.midX, app.windows.firstMatch.frame.midX, accuracy: 1)
        AutomaticUITestSupport.capture("Read-only automatic history detail")
    }

    // [04] Simply reading History or Settings must not change the saved estimate when the app is
    // reopened.
    func testReadingHistoryAndSettingsKeepSavedResultsAfterRelaunch() {
        let app = AutomaticUITestSupport.open(fixture: true)
        AutomaticUITestSupport.openHistoryDay(in: app)
        let savedTotal = app.staticTexts["footprint.total"].label
        app.tabBars.buttons["Today"].tap()
        XCTAssertFalse(app.buttons["today.automaticSetup"].exists)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))
        let settings = AutomaticUITestSupport.element("settings.form", in: app)
        let status = AutomaticUITestSupport.reachSettings("screen-time.status", in: app)
        let recovery = settings.buttons["settings.automaticSetup"]
        XCTAssertEqual(status.label, "Connected",
                       "The saved, isolated setup must not depend on the phone's real Apple permission")
        XCTAssertFalse(recovery.exists, "A completed setup must not ask for setup again")
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        app.terminate()
        let reopened = AutomaticUITestSupport.open(reset: false)
        AutomaticUITestSupport.openHistoryDay(in: reopened)
        XCTAssertEqual(reopened.staticTexts["footprint.total"].label, savedTotal)
        AutomaticUITestSupport.assertNoManualEntry(in: reopened)
        XCTAssertFalse(reopened.alerts.firstMatch.exists)
    }

    // [05] Today and History should lead to the same day details, so their category story cannot
    // drift apart.
    func testTodaySummaryOpensTheSameCategoryDetailsAsHistory() {
        let app = AutomaticUITestSupport.open(fixture: true)
        XCTAssertFalse(app.buttons["breakdown.categories"].exists)
        let details = app.buttons["today.dayDetails"]
        AutomaticUITestSupport.reach(details, in: app)
        XCTAssertGreaterThanOrEqual(details.frame.height, 44)
        details.tap()
        XCTAssertTrue(app.buttons["breakdown.categories"].waitForExistence(timeout: 8))
        let video = AutomaticUITestSupport.element("breakdown.category.VIDEO_STREAMING", in: app)
        AutomaticUITestSupport.reach(video, in: app)
        let savedLabel = video.label
        XCTAssertTrue(savedLabel.contains("Video streaming"))
        XCTAssertTrue(savedLabel.contains("30 min"))
        XCTAssertTrue(savedLabel.contains("g CO₂e"))
        let sources = app.staticTexts["breakdown.sources.VIDEO_STREAMING"]
        AutomaticUITestSupport.reach(sources, in: app)
        XCTAssertTrue(sources.label.contains("Device"))
        XCTAssertTrue(sources.label.contains("Network"))
        XCTAssertTrue(sources.label.contains("Servers"))
        XCTAssertGreaterThanOrEqual(sources.frame.minY - video.frame.maxY, 18)
        XCTAssertEqual(sources.frame.midX, app.windows.firstMatch.frame.midX, accuracy: 1)
        AutomaticUITestSupport.capture("Category details opened from Today")
        app.tabBars.buttons["History"].tap()
        AutomaticUITestSupport.openHistoryDay(in: app)
        let savedVideo = AutomaticUITestSupport.element("breakdown.category.VIDEO_STREAMING", in: app)
        AutomaticUITestSupport.reach(savedVideo, in: app)
        XCTAssertEqual(savedVideo.label, savedLabel)
        XCTAssertFalse(app.staticTexts["Inputs for this day"].exists)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
    }

    // [06] At the largest text size, people should still be able to read category details and
    // reach useful advice.
    func testCategoryDetailsRemainReadableAtLargestText() throws {
        let app = AutomaticUITestSupport.open(fixture: true, largeText: true)
        try assertSharedTabSpacing(in: app, largestText: true)
        try assertHistoryTips(in: app, personalized: true)
        AutomaticUITestSupport.openHistoryDay(in: app)
        let video = AutomaticUITestSupport.element("breakdown.category.VIDEO_STREAMING", in: app)
        AutomaticUITestSupport.reach(video, in: app)
        XCTAssertTrue(video.label.contains("30 min"))
        XCTAssertTrue(video.label.contains("g CO₂e"))
        AutomaticUITestSupport.capture("Category time and emissions at largest text")
        try app.performAccessibilityAudit(for: [.textClipped, .hitRegion])
        let assumptions = app.staticTexts["record.assumptions"]
        AutomaticUITestSupport.reach(assumptions, in: app)
        XCTAssertTrue(assumptions.label.contains("Brightness"))
        XCTAssertTrue(assumptions.label.contains("GPS"))
        XCTAssertTrue(assumptions.label.contains("Bluetooth"))
        XCTAssertEqual(assumptions.frame.midX, app.windows.firstMatch.frame.midX, accuracy: 1)
        AutomaticUITestSupport.capture("Centered estimate settings at largest text")
        try app.performAccessibilityAudit(for: [.textClipped, .hitRegion])
    }

    private func assertHistoryTips(in app: XCUIApplication, personalized: Bool) throws {
        let history = AutomaticUITestSupport.element("history.content", in: app)
        let navigation = app.navigationBars["History"]
        func reach(_ element: XCUIElement) {
            AutomaticUITestSupport.reach(element, in: app, inside: history,
                                         below: navigation, verticalMargin: 16)
        }
        let context = history.staticTexts["history.tips.context"]
        reach(context)
        let action = history.staticTexts["history.tips.action"]
        reach(action)
        if personalized {
            XCTAssertTrue(context.label.contains("saved estimate for"))
            XCTAssertTrue(context.label.contains("Video streaming"))
            XCTAssertTrue(action.label.contains("autoplay"))
        } else {
            XCTAssertTrue(context.label.contains("general ideas"))
            XCTAssertFalse(context.label.contains("saved estimate for"))
            XCTAssertFalse(app.staticTexts["footprint.total"].exists)
        }
        let more = AutomaticUITestSupport.element("history.tips.more", in: history)
        reach(more)
        XCTAssertGreaterThanOrEqual(more.frame.height, 44)
        more.tap()
        for id in ["limit", "notifications", "focus"] {
            let guide = AutomaticUITestSupport.element("history.tips.guide." + id, in: history)
            reach(guide)
            XCTAssertTrue(guide.isHittable)
            // [07] A tiny measurement-rounding difference should not fail an otherwise full-size
            // touch target.
            XCTAssertGreaterThanOrEqual(guide.frame.height, 44 - 0.000001)
        }
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        AutomaticUITestSupport.capture(personalized ? "History tips from a dated saved estimate" : "General tips while a day stays pending")
        try app.performAccessibilityAudit(for: [.textClipped, .hitRegion])
        reach(more)
        more.tap()
        XCTAssertFalse(AutomaticUITestSupport.element("history.tips.guide.limit", in: history).exists)
    }

    private func assertSharedTabSpacing(in app: XCUIApplication, largestText: Bool) throws {
        app.tabBars.buttons["History"].tap()
        let history = AutomaticUITestSupport.element("history.content", in: app)
        let historyTitle = app.navigationBars["History"]
        XCTAssertTrue(historyTitle.waitForExistence(timeout: 8))
        let historyIntro = history.staticTexts["history.intro"]
        let historyExplanation = history.staticTexts["history.introExplanation"]
        XCTAssertTrue(historyIntro.waitForExistence(timeout: 8))
        let historyTopGap = historyIntro.frame.minY - historyTitle.frame.maxY
        let historyLeft = historyIntro.frame.minX
        let tipsHeading = history.staticTexts["history.tips.heading"]
        AutomaticUITestSupport.reach(tipsHeading, in: app, inside: history,
                                     below: historyTitle, verticalMargin: 16)
        XCTAssertTrue(historyExplanation.exists)
        let historyGap = tipsHeading.frame.minY - historyExplanation.frame.maxY
        // [08] Both tabs leave 32 points after the introduction's four-point bottom inset.
        XCTAssertEqual(historyGap, 36, accuracy: 1)
        AutomaticUITestSupport.capture(largestText ? "History spacing at largest text" : "History spacing")
        try app.performAccessibilityAudit(for: [.textClipped, .hitRegion]) { issue in
            // [09] Keep the failed element available for review instead of relaxing the
            // accessibility check.
            let target = issue.element?.debugDescription ?? "No element supplied by the audit"
            let detail = XCTAttachment(string: "\(issue.compactDescription)\n\(issue.detailedDescription)\n\(target)\n\(app.debugDescription)")
            detail.name = "History accessibility issue and viewport"
            detail.lifetime = .keepAlways
            XCTContext.runActivity(named: "History accessibility diagnosis") { $0.add(detail) }
            return false
        }

        app.tabBars.buttons["Settings"].tap()
        let settingsTitle = app.navigationBars["Settings"]
        XCTAssertTrue(settingsTitle.waitForExistence(timeout: 8))
        let settings = AutomaticUITestSupport.element("settings.form", in: app)
        let settingsIntro = settings.staticTexts["settings.intro"]
        let settingsExplanation = settings.staticTexts["settings.introExplanation"]
        XCTAssertTrue(settingsIntro.waitForExistence(timeout: 8))
        let settingsTopGap = settingsIntro.frame.minY - settingsTitle.frame.maxY
        let heading = AutomaticUITestSupport.reachSettings("screen-time.heading", in: app)
        XCTAssertTrue(settingsExplanation.exists)
        let settingsGap = heading.frame.minY - settingsExplanation.frame.maxY
        XCTAssertEqual(settingsGap, 36, accuracy: 1)
        XCTAssertEqual(historyGap, settingsGap, accuracy: 1)
        XCTAssertEqual(historyLeft, settingsIntro.frame.minX, accuracy: 1)
        if !largestText {
            XCTAssertEqual(historyTopGap, settingsTopGap, accuracy: 1)
        }
        AutomaticUITestSupport.capture(largestText ? "Matching Settings spacing at largest text" : "Matching Settings spacing")
        app.tabBars.buttons["History"].tap()
    }
}
