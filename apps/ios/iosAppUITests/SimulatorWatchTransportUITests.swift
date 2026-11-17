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

// [01] This separate smoke test attaches to a normal app on an owned, empty simulator. It never relaunches with UI-test guards disabled.
@MainActor
final class SimulatorWatchTransportUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func capture(_ step: String, app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Owned simulator Watch transport — " + step
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Owned simulator Watch transport accessibility — " + step
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    private func findSharingToggle(in app: XCUIApplication) -> XCUIElement? {
        let toggle = app.switches["settings.watchSharing"]
        for attempt in 0..<12 {
            if toggle.exists && toggle.isHittable { return toggle }
            // [02] The section sits below the connection and notice settings. A bounded search must fail clearly if pairing is unavailable.
            if attempt == 6 { app.swipeDown() } else { app.swipeUp() }
        }
        return nil
    }

    private func changeSharing(_ toggle: XCUIElement, to value: String, in app: XCUIApplication) {
        capture("before changing real switch to \(value)", app: app)
        let nativeSwitch = toggle.switches.firstMatch
        let diagnostics = XCTAttachment(string: "Outer switch frame: \(toggle.frame); value: \(String(describing: toggle.value)); nested switch present: \(nativeSwitch.exists)")
        diagnostics.name = "Real Watch sharing switch hit area"
        diagnostics.lifetime = .keepAlways
        add(diagnostics)
        // [04] A SwiftUI switch can expose its whole labelled row. On this LTR test screen, hit the visible trailing control instead of the label.
        if nativeSwitch.exists && nativeSwitch.isHittable {
            nativeSwitch.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: toggle)
        let outcome = XCTWaiter.wait(for: [changed], timeout: 5)
        if outcome != .completed { capture("real switch did not reach \(value)", app: app) }
        XCTAssertEqual(outcome, .completed, "The native switch did not change within five seconds")
        XCTAssertEqual(toggle.value as? String, value)
    }

    func testExplicitEmptyContextTransportActionOnOwnedSimulatorPair() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This transport smoke test cannot run on a personal physical device")
        #else
        let environment = ProcessInfo.processInfo.environment
        let enabled = environment["DFE_SIMULATOR_WATCH_TRANSPORT"] ?? environment["TEST_RUNNER_DFE_SIMULATOR_WATCH_TRANSPORT"]
        guard enabled == "1" else { throw XCTSkip("Opt in to the separate, owned simulator Watch transport check") }
        let simulatorName = environment["SIMULATOR_DEVICE_NAME"] ?? ""
        guard simulatorName.hasPrefix("DFE") else {
            throw XCTSkip("Use a fresh, owned simulator whose name starts with DFE")
        }
        let action = environment["DFE_WATCH_TRANSPORT_ACTION"] ?? environment["TEST_RUNNER_DFE_WATCH_TRANSPORT_ACTION"]
        guard action == "enable" || action == "disable" else {
            XCTFail("Choose enable or disable explicitly; inspect the Watch between these two runs")
            return
        }

        let app = XCUIApplication()
        // Do not call launch() or activate(): the normal app must already be running without -ui-testing or XCTest launch inputs.
        XCTAssertEqual(app.state, .runningForeground, "Launch the normal empty app with simctl before starting this test")
        let history = app.tabBars.buttons["History"]
        XCTAssertTrue(history.waitForExistence(timeout: 8))
        history.tap()
        let empty = element("history.empty", in: app)
        XCTAssertTrue(empty.waitForExistence(timeout: 8), "This audit must not use a saved person's history")
        XCTAssertTrue(empty.label.contains("No saved days yet"))

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))
        guard let toggle = findSharingToggle(in: app) else {
            capture("paired Watch setting unavailable", app: app)
            XCTFail("The normal app did not expose a paired Watch. Pairing or Watch app registration must be resolved first")
            return
        }

        if action == "enable" {
            XCTAssertEqual(toggle.value as? String, "0", "Start this stage with sharing off")
            changeSharing(toggle, to: "1", in: app)
            let accepted = app.staticTexts["Latest phone result queued for Apple Watch"]
            XCTAssertTrue(accepted.waitForExistence(timeout: 15), "Apple has not accepted the context, or the companion is not registered")
            capture("empty context accepted for queue", app: app)
        } else {
            XCTAssertEqual(toggle.value as? String, "1", "Run the enable stage and inspect the Watch before this stage")
            changeSharing(toggle, to: "0", in: app)
            capture("sharing switched off", app: app)
        }
        // [03] Queue acceptance and an off switch are phone-side evidence only. The Watch receipt and stored clear need separate verification.
        XCTAssertEqual(app.state, .runningForeground)
        #endif
    }
}
