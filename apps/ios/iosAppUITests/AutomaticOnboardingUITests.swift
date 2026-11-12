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

// [01] Automatic setup should be brief and readable, without bringing daily entry forms into the
// experience

import XCTest

@MainActor
final class AutomaticOnboardingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }

    // [02] One deliberate action should start the automatic route and remain saved without making
    // someone pick apps.
    func testOneActionStartsAutomaticInputWithoutAPickerAndPersists() {
        let app = AutomaticUITestSupport.open()
        AutomaticUITestSupport.openSetup(in: app)
        assertSetupExplanation(in: app)
        let connect = app.buttons["automatic.connect"]
        AutomaticUITestSupport.reach(connect, in: app)
        XCTAssertGreaterThanOrEqual(connect.frame.height, 44)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        XCTAssertFalse(app.buttons["automatic.category.VIDEO_STREAMING"].exists)
        XCTAssertFalse(app.staticTexts["Not connected"].exists)
        XCTAssertFalse(app.staticTexts["Screen Time permission"].exists)
        AutomaticUITestSupport.capture("Initial setup with one clear enable action")
        connect.tap()
        XCTAssertTrue(app.staticTexts["today.automaticPending"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["footprint.total"].exists)
        XCTAssertFalse(app.buttons["today.automaticSetup"].exists)
        app.terminate()
        let reopened = AutomaticUITestSupport.open(reset: false)
        XCTAssertTrue(reopened.staticTexts["today.automaticPending"].waitForExistence(timeout: 8))
        XCTAssertFalse(reopened.buttons["today.automaticSetup"].exists)
        reopened.tabBars.buttons["Settings"].tap()
        let status = AutomaticUITestSupport.reachSettings("screen-time.status", in: reopened)
        XCTAssertEqual(status.label, "Connected")
        let settingsAfterSetup = AutomaticUITestSupport.element("settings.form", in: reopened)
        XCTAssertFalse(AutomaticUITestSupport.element("settings.automaticSetup", in: settingsAfterSetup).exists,
                       "A completed connection must not ask for automatic setup again")
        XCTAssertFalse(reopened.navigationBars["Automatic setup"].exists)
        XCTAssertFalse(reopened.staticTexts["Screen Time is ready"].exists)
        AutomaticUITestSupport.assertNoManualEntry(in: reopened)
        let modelDetails = AutomaticUITestSupport.reachSettings("settings.modelDetails", in: reopened)
        modelDetails.tap()
        let modelExplanation = reopened.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@",
            "The iOS app uses the same category-based calculation")).firstMatch
        let settings = AutomaticUITestSupport.element("settings.form", in: reopened)
        AutomaticUITestSupport.reach(modelExplanation, in: reopened, inside: settings,
                                     below: reopened.navigationBars["Settings"], verticalMargin: 16)
        XCTAssertTrue(modelExplanation.isHittable,
                      "The full model explanation remains available in Settings after setup.")
    }

    // [03] Lost access needs one clear reconnect action, including when the person uses the
    // largest text size.
    func testRevokedAccessUsesOneReadableReconnectActionAtLargestText() throws {
        let app = AutomaticUITestSupport.open(largeText: true, revokedPreview: true)
        AutomaticUITestSupport.openSetup(in: app)
        assertSetupExplanation(in: app)
        let reconnect = app.buttons["automatic.connect"]
        AutomaticUITestSupport.reach(reconnect, in: app)
        XCTAssertEqual(reconnect.label, "Reconnect Screen Time")
        XCTAssertTrue(reconnect.isHittable)
        XCTAssertGreaterThanOrEqual(reconnect.frame.height, 44)
        XCTAssertFalse(app.staticTexts["Permission removed"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label == %@",
            "Screen Time access has been removed. Your saved results remain available. You can reconnect Screen Time to resume automatic input.")).firstMatch.exists)
        XCTAssertFalse(app.buttons["automatic.start"].exists)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        try app.performAccessibilityAudit(for: [.textClipped, .hitRegion])
        AutomaticUITestSupport.capture("One clear reconnect action at largest text")

        // [04] The isolated preview exercises the existing one-action setup without Apple access.
        reconnect.tap()
        XCTAssertTrue(app.staticTexts["today.automaticPending"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Automatic setup"].exists)
        XCTAssertFalse(app.staticTexts["footprint.total"].exists)
        XCTAssertFalse(app.buttons["today.automaticSetup"].exists)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        app.terminate()
        let reopened = AutomaticUITestSupport.open(reset: false)
        XCTAssertTrue(reopened.staticTexts["today.automaticPending"].waitForExistence(timeout: 8))
        XCTAssertFalse(reopened.buttons["today.automaticSetup"].exists)
        AutomaticUITestSupport.assertNoManualEntry(in: reopened)
    }

    // [05] Leaving setup should not silently save consent or send the person to an old manual
    // form.
    func testCancellingSetupDoesNotSaveOrOpenManualInput() {
        let app = AutomaticUITestSupport.open()
        AutomaticUITestSupport.openSetup(in: app)
        app.navigationBars["Automatic setup"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["onboarding.automatic"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["footprint.total"].exists)
        app.terminate()
        let reopened = AutomaticUITestSupport.open(reset: false)
        XCTAssertTrue(reopened.buttons["onboarding.automatic"].waitForExistence(timeout: 8))
        AutomaticUITestSupport.assertNoManualEntry(in: reopened)
    }

    // [06] Large text should not hide the connect action or the explanation someone needs before
    // accepting.
    func testLargestTextSetupKeepsConnectAndReadOnlyContentReachable() throws {
        let app = AutomaticUITestSupport.open(largeText: true)
        AutomaticUITestSupport.openSetup(in: app)
        let connect = app.buttons["automatic.connect"]
        AutomaticUITestSupport.reach(connect, in: app)
        XCTAssertGreaterThanOrEqual(connect.frame.height, 44)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        AutomaticUITestSupport.capture("Largest-text automatic setup")
        try app.performAccessibilityAudit(for: [.textClipped, .hitRegion])
    }

    // [07] Turning the phone sideways should not make the automatic action impossible to reach.
    func testLandscapeSetupKeepsTheAutomaticActionReachable() throws {
        let app = AutomaticUITestSupport.open()
        XCUIDevice.shared.orientation = .landscapeRight
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            return frame.width > frame.height && abs(frame.minX) < 1 && abs(frame.minY) < 1
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed)
        AutomaticUITestSupport.openSetup(in: app)
        let connect = app.buttons["automatic.connect"]
        AutomaticUITestSupport.reach(connect, in: app)
        XCTAssertGreaterThanOrEqual(connect.frame.height, 44)
        connect.tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Automatic setup"].exists)
        let pending = app.staticTexts["today.automaticPending"]
        let todayContent = app.scrollViews.containing(.any, identifier: "today.welcome").firstMatch
        AutomaticUITestSupport.reach(pending, in: app, inside: todayContent,
                                     below: app.navigationBars["Today"])
        XCTAssertTrue(pending.exists)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        AutomaticUITestSupport.capture("Automatic pending day in landscape")
    }

    // [08] The privacy explanation must remain readable before permission, even without opening an
    // external website.
    func testPrivacyBeforeSetupIsReadableWithoutAWebsiteAtLargestText() throws {
        let app = AutomaticUITestSupport.open(largeText: true, preview: false)
        let privacy = app.buttons["onboarding.privacy"]
        AutomaticUITestSupport.reach(privacy, in: app)
        privacy.tap()
        XCTAssertTrue(app.navigationBars["Privacy policy"].waitForExistence(timeout: 8))
        let contact = AutomaticUITestSupport.element("privacy.contact", in: app)
        AutomaticUITestSupport.reach(contact, in: app)
        XCTAssertGreaterThanOrEqual(contact.frame.height, 44)
        // [09] The online copy is an extra choice. The local policy stays open without visiting it.
        let online = AutomaticUITestSupport.element("privacy.online", in: app)
        AutomaticUITestSupport.reach(online, in: app)
        XCTAssertGreaterThanOrEqual(online.frame.height, 44)
        XCTAssertTrue(app.navigationBars["Privacy policy"].exists)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        AutomaticUITestSupport.capture("Offline privacy contact at largest text")
    }

    private func assertSetupExplanation(in app: XCUIApplication) {
        let privacyHeading = AutomaticUITestSupport.element("automatic.localPrivacy", in: app)
        AutomaticUITestSupport.reach(privacyHeading, in: app)
        XCTAssertTrue(privacyHeading.label.contains("Your activity stays on this device"))
        AutomaticUITestSupport.capture("Local privacy with a distinct shield icon")
        let scope = app.staticTexts["automatic.estimateScope"]
        AutomaticUITestSupport.reach(scope, in: app)
        XCTAssertTrue(scope.label.contains("remain estimates"))
        let firstDay = app.staticTexts["automatic.firstCompletedDay"]
        AutomaticUITestSupport.reach(firstDay, in: app)
        XCTAssertTrue(firstDay.label.contains("completed day"))
        let policy = AutomaticUITestSupport.element("automatic.privacy", in: app)
        AutomaticUITestSupport.reach(policy, in: app)
        XCTAssertTrue(policy.isHittable)
        XCTAssertGreaterThanOrEqual(policy.frame.height, 44)
        AutomaticUITestSupport.capture("Distinct privacy policy action")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@",
            "What goes into your estimate?")).firstMatch.exists,
            "Setup should show its consent explanation once; Settings keeps the full model details.")
    }

}
