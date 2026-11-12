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
import UIKit

@MainActor
final class AdaptiveDeviceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }

    // [20] The real short window should show the saved estimate and its main action before a scroll.
    // A saved day with an earlier average must still explain that comparison in the detail view.
    func testTodayKeepsSavedContextAndReadableActions() throws {
        for legacyDay in [false, true] {
            let app = AutomaticUITestSupport.open(fixture: true, legacyToday: legacyDay, dark: legacyDay)
            let geometry = try settledGeometry(in: app, after: .portrait)
            let overview = geometry.expectsColumns && (430...640).contains(geometry.viewportHeight)
            if ProcessInfo.processInfo.environment["DFE_UI_REQUIRE_SHORT_WIDE_OVERVIEW"] == "1" {
                XCTAssertTrue(overview, "Prepare a real wide and short window for this run")
            }
            let content = AutomaticUITestSupport.element("today.content", in: app)
            let amount = app.staticTexts["footprint.total"]
            let details = app.buttons["today.dayDetails"]
            XCTAssertEqual(app.staticTexts.matching(identifier: "footprint.total").count, 1)
            let savedAmount = amount.label
            XCTAssertFalse(savedAmount.isEmpty)
            XCTAssertEqual(app.staticTexts["today.periodLabel"].firstMatch.label,
                legacyDay ? "Saved today" : "Latest completed day")
            if overview {
                let garden = AutomaticUITestSupport.element("today.gardenColumn", in: app)
                let actions = AutomaticUITestSupport.element("today.actionsColumn", in: app)
                let source = actions.staticTexts["today.overviewSource"]
                XCTAssertTrue(garden.staticTexts["today.recordDate"].exists)
                XCTAssertFalse(garden.staticTexts["footprint.total"].exists)
                XCTAssertTrue(actions.staticTexts["footprint.total"].exists)
                XCTAssertEqual(source.label, legacyDay ? "Manual entry" : "Screen Time with estimates")
                XCTAssertGreaterThan(amount.frame.height, source.frame.height)
                let origin = AutomaticUITestSupport.element("today.layoutGeometry", in: app).frame.origin
                let pane = CGRect(origin: origin, size: CGSize(width: CGFloat(geometry.viewportWidth),
                    height: CGFloat(geometry.viewportHeight))).insetBy(dx: -1, dy: -1)
                XCTAssertTrue(pane.contains(amount.frame))
                XCTAssertTrue(pane.contains(details.frame))
                let activity = actions.staticTexts["footprint.importedActivity"]
                if legacyDay {
                    XCTAssertFalse(activity.exists)
                    XCTAssertTrue(actions.staticTexts["garden.comparisonBasis"].exists)
                } else {
                    XCTAssertEqual(activity.label, "Imported app activity: 1 h")
                    XCTAssertTrue(pane.contains(activity.frame))
                }
            } else {
                XCTAssertFalse(app.staticTexts["today.overviewSource"].exists)
            }
            AutomaticUITestSupport.capture(legacyDay ? "Today saved comparison in dark appearance"
                : "Today completed estimate and actions in light appearance")
            AutomaticUITestSupport.reach(details, in: app, inside: content,
                below: app.navigationBars["Today"], verticalMargin: 16)
            XCTAssertGreaterThanOrEqual(details.frame.height, 44 - 0.001)
            XCTAssertTrue(details.isHittable)
            details.tap()
            let context = legacyDay ? app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@",
                "Your earlier daily average:")).firstMatch : app.staticTexts["source.activityPeriod"]
            XCTAssertTrue(context.waitForExistence(timeout: 8))
            XCTAssertEqual(app.staticTexts["footprint.total"].label, savedAmount)
            AutomaticUITestSupport.assertNoManualEntry(in: app)
            app.terminate()
        }
    }

    // [15] Reaching an already visible welcome should not pull the page or start a refresh.
    // Keep the coordinate receipt too, so an offset system window can expose the old snapshot-frame mix-up.
    func testWindowedWelcomeIsReachableWithoutStartingRefresh() throws {
        let app = AutomaticUITestSupport.open(fixture: true, refreshTesting: true)
        let content = AutomaticUITestSupport.element("today.content", in: app)
        let welcome = AutomaticUITestSupport.element("today.welcome", in: app)
        XCTAssertTrue(content.waitForExistence(timeout: 8))
        XCTAssertTrue(welcome.waitForExistence(timeout: 8))
        let initialPulls = try completedPulls(in: content)
        XCTAssertEqual(initialPulls, 0)
        let clear = visibleViewport(content, in: app).insetBy(dx: -1, dy: -1)
        XCTAssertTrue(welcome.isHittable)
        XCTAssertTrue(clear.contains(welcome.frame), "The initial welcome must already be visible below native bars")
        if ProcessInfo.processInfo.environment["DFE_UI_REQUIRE_OFFSET_WINDOW"] == "1" {
            let frame = app.windows.firstMatch.frame
            XCTAssertTrue(abs(frame.minX) > 0.5 || abs(frame.minY) > 0.5,
                "Prepare a real moved system window; the regression never fakes an offset")
        }
        func rectangle(_ value: CGRect) -> [String: CGFloat] {
            ["x": value.minX, "y": value.minY, "width": value.width, "height": value.height]
        }
        func frames(_ element: XCUIElement) throws -> [String: Any] {
            ["live": rectangle(element.frame), "snapshot": rectangle(try element.snapshot().frame),
             "hittable": element.isHittable]
        }
        let receipt = AutomaticUITestSupport.element("today.layoutGeometry", in: app)
        let result: [String: Any] = [
            "scope": "Isolated window-coordinate regression; no personal usage",
            "window": try frames(app.windows.firstMatch),
            "application": try frames(app),
            "content": try frames(content),
            "welcome": try frames(welcome),
            "navigationBars": try app.navigationBars.allElementsBoundByIndex.map { try frames($0) },
            "tabBars": try app.tabBars.allElementsBoundByIndex.map { try frames($0) },
            "layoutReceipt": receipt.value as? String ?? "missing"
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(string: try XCTUnwrap(String(data: data, encoding: .utf8)))
        attachment.name = "Live versus snapshot coordinates in the actual system window"
        attachment.lifetime = .keepAlways
        add(attachment)
        AutomaticUITestSupport.reach(welcome, in: app, inside: content,
                                     below: app.navigationBars["Today"], verticalMargin: 16)
        XCTAssertTrue(welcome.isHittable)
        XCTAssertEqual(try completedPulls(in: content), initialPulls,
            "Finding visible text must not make unnecessary pull gestures or refresh the saved day")
        XCTAssertFalse(app.navigationBars["Automatic setup"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        AutomaticUITestSupport.assertNoManualEntry(in: app)
        AutomaticUITestSupport.capture("Visible welcome reached without refresh in the actual system window")
    }

    // [01] Rotation should change the arrangement, never the saved date, pending message or available actions.
    func testRotationKeepsOneGardenAndReadableActions() throws {
        let app = AutomaticUITestSupport.open(fixture: true)
        let amount = app.staticTexts["footprint.total"]
        XCTAssertTrue(amount.waitForExistence(timeout: 8))
        let savedAmount = amount.label
        let savedDate = app.staticTexts["today.recordDate"].firstMatch.label
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let geometry = try settledGeometry(in: app, after: orientation)
            let content = AutomaticUITestSupport.element("today.content", in: app)
            assertLayoutMatches(geometry, in: app)
            try assertWelcomeRespectsSafeArea(geometry, content: content, in: app)
            XCTAssertEqual(amount.label, savedAmount)
            XCTAssertEqual(app.staticTexts["today.recordDate"].firstMatch.label, savedDate)
            XCTAssertEqual(app.staticTexts.matching(identifier: "footprint.total").count, 1)
            let pending = app.staticTexts["today.pendingExplanation"]
            // [05] A sidebar is another scroll view. Move the open page, not its navigation list.
            AutomaticUITestSupport.reach(pending, in: app, inside: content,
                                         below: app.navigationBars["Today"], verticalMargin: 16)
            XCTAssertTrue(pending.label.contains("Missing activity stays pending"))
            let details = app.buttons["today.dayDetails"]
            AutomaticUITestSupport.reach(details, in: app, inside: content,
                                         below: app.navigationBars["Today"], verticalMargin: 16)
            XCTAssertGreaterThanOrEqual(details.frame.height, 44)
            XCTAssertTrue(details.isHittable)
            AutomaticUITestSupport.assertNoManualEntry(in: app)
            AutomaticUITestSupport.capture("Adaptive Today after rotation; isolated saved day")
            try app.performAccessibilityAudit(for: [.textClipped, .hitRegion])
        }
        app.buttons["today.dayDetails"].tap()
        XCTAssertTrue(app.staticTexts["source.activityPeriod"].waitForExistence(timeout: 8))
        // [06] A tablet layout must not quietly present phone power values as measured iPad energy.
        let modelNote = app.staticTexts["source.referenceModel"]
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(modelNote.exists)
            XCTAssertTrue(modelNote.label.contains("not a measurement of iPad energy"))
        } else {
            XCTAssertFalse(modelNote.exists)
        }
    }

    // [02] Native tabs or the sidebar must reach the same pages, and every page keeps its real refresh action.
    func testAllTabsRefreshWithoutChangingSavedDay() throws {
        let app = AutomaticUITestSupport.open(fixture: true, refreshTesting: true)
        XCTAssertTrue(app.staticTexts["footprint.total"].waitForExistence(timeout: 8))
        let savedAmount = app.staticTexts["footprint.total"].label
        for (title, contentID, introID) in [
            ("Today", "today.content", "today.welcome"),
            ("History", "history.content", "history.intro"),
            ("Settings", "settings.form", "settings.intro")
        ] {
            select(title, in: app)
            let content = AutomaticUITestSupport.element(contentID, in: app)
            XCTAssertTrue(content.waitForExistence(timeout: 8))
            let intro = AutomaticUITestSupport.element(introID, in: content)
            AutomaticUITestSupport.reach(intro, in: app, inside: content,
                                         below: app.navigationBars[title], verticalMargin: 40)
            let oldCount = try completedPulls(in: content)
            let viewport = visibleViewport(content, in: app)
            recordPullGeometry(title: title, stage: "before", content: content,
                               viewport: viewport, count: oldCount)
            // [06] Start below native bars. A pull on a large navigation title does not refresh the page.
            let window = app.windows.firstMatch
            let windowFrame = window.frame
            func point(_ fraction: CGFloat) -> XCUICoordinate {
                window.coordinate(withNormalizedOffset: CGVector(
                    dx: (viewport.midX - windowFrame.minX) / windowFrame.width,
                    dy: (viewport.minY + viewport.height * fraction - windowFrame.minY) / windowFrame.height))
            }
            point(0.18).press(forDuration: 0, thenDragTo: point(0.86),
                              withVelocity: .slow, thenHoldForDuration: 2)
            let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                content.value as? String == "Completed refreshes: \(oldCount + 1)"
            }, object: nil)
            let result = XCTWaiter.wait(for: [refreshed], timeout: 12)
            recordPullGeometry(title: title, stage: "after", content: content,
                               viewport: visibleViewport(content, in: app), count: try completedPulls(in: content))
            XCTAssertEqual(result, .completed, "A native pull must complete exactly one refresh on \(title)")
            XCTAssertFalse(app.navigationBars["Automatic setup"].exists)
            XCTAssertFalse(app.alerts.firstMatch.exists)
            AutomaticUITestSupport.assertNoManualEntry(in: app)
        }
        select("Today", in: app)
        XCTAssertEqual(app.staticTexts["footprint.total"].label, savedAmount)
    }

    // [03] Larger text gets one full-width reading column, in both light and dark appearances.
    func testLargestTextKeepsOneColumnAndAllTabsReachable() throws {
        for dark in [false, true] {
            let app = AutomaticUITestSupport.open(fixture: true, largeText: true, dark: dark)
            XCTAssertTrue(app.staticTexts["footprint.total"].waitForExistence(timeout: 8))
            let geometry = try settledGeometry(in: app, after: .portrait)
            XCTAssertTrue(geometry.accessibilityText)
            assertLayoutMatches(geometry, in: app)
            XCTAssertTrue(AutomaticUITestSupport.element("today.compactLayout", in: app).exists)
            XCTAssertFalse(AutomaticUITestSupport.element("today.wideLayout", in: app).exists)
            let todayContent = AutomaticUITestSupport.element("today.content", in: app)
            let pending = app.staticTexts["today.pendingExplanation"]
            AutomaticUITestSupport.reach(pending, in: app, inside: todayContent,
                                         below: app.navigationBars["Today"], verticalMargin: 16)
            XCTAssertTrue(pending.isHittable)
            for (title, contentID, introID) in [
                ("History", "history.content", "history.intro"),
                ("Settings", "settings.form", "settings.intro")
            ] {
                select(title, in: app)
                let content = AutomaticUITestSupport.element(contentID, in: app)
                let intro = AutomaticUITestSupport.element(introID, in: content)
                AutomaticUITestSupport.reach(intro, in: app, inside: content,
                                             below: app.navigationBars[title], verticalMargin: 16)
                XCTAssertTrue(intro.isHittable)
                AutomaticUITestSupport.assertNoManualEntry(in: app)
                try app.performAccessibilityAudit(for: [.textClipped, .hitRegion])
            }
            AutomaticUITestSupport.capture("Adaptive larger-text Settings; isolated data")
            app.terminate()
        }
    }

    private struct GeometryRectangle: Decodable, Equatable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        var frame: CGRect {
            CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
        }
    }

    private struct LayoutGeometry: Decodable {
        let version: Int
        let viewportWidth: Double
        let viewportHeight: Double
        let regularWidth: Bool
        let accessibilityText: Bool
        let interfaceOrientation: Int
        let orientationLocked: Bool
        let supportedOrientations: UInt
        let interactivelyResizing: Bool
        let windowFrame: GeometryRectangle
        let safeFrame: GeometryRectangle

        var expectsColumns: Bool { viewportWidth >= 760 && regularWidth && !accessibilityText }
        func isStable(comparedWith other: LayoutGeometry) -> Bool {
            abs(viewportWidth - other.viewportWidth) < 0.5
                && abs(viewportHeight - other.viewportHeight) < 0.5
                && windowFrame == other.windowFrame && safeFrame == other.safeFrame
                && regularWidth == other.regularWidth && accessibilityText == other.accessibilityText
                && interfaceOrientation == other.interfaceOrientation
        }
    }

    // [09] Physical pose and window shape are different on Duo and in a resized iPad window.
    // Ordinary phones keep the strict interface-rotation check. A verified Duo test destination
    // uses an explicit runner-only contract, while still checking its real pose, space and content.
    private func settledGeometry(in app: XCUIApplication, after pose: UIDeviceOrientation) throws -> LayoutGeometry {
        let receipt = AutomaticUITestSupport.element("today.layoutGeometry", in: app)
        XCTAssertTrue(receipt.waitForExistence(timeout: 8))
        let independentWindowOrientation = ProcessInfo.processInfo.environment[
            "DFE_UI_WINDOW_ORIENTATION_INDEPENDENT"] == "1"
        var previous: LayoutGeometry?
        var stableSamples = 0
        func read() -> LayoutGeometry? {
            guard let text = receipt.value as? String, let data = text.data(using: .utf8),
                  let value = try? JSONDecoder().decode(LayoutGeometry.self, from: data),
                  value.version == 1, value.viewportWidth.isFinite, value.viewportHeight.isFinite,
                  value.viewportWidth > 0, value.viewportHeight > 0 else { return nil }
            return value
        }
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard XCUIDevice.shared.orientation == pose, let value = read(),
                  !value.interactivelyResizing,
                  let interface = UIInterfaceOrientation(rawValue: value.interfaceOrientation) else { return false }
            let supported = UIInterfaceOrientationMask(rawValue: value.supportedOrientations)
            // [13] Apple's Duo window can keep a landscape interface while the device is held upright.
            // This contract never changes the app; it only prevents a false link between pose and shape.
            if independentWindowOrientation {
                guard interface.isPortrait || interface.isLandscape,
                      supported.contains(UIInterfaceOrientationMask(rawValue:
                        UInt(1) << UInt(value.interfaceOrientation))) else { return false }
            } else {
                let targetSupported = pose.isLandscape ? !supported.intersection(.landscape).isEmpty
                    : supported.contains(.portrait)
                guard targetSupported, interface.isLandscape == pose.isLandscape,
                      interface.isPortrait == pose.isPortrait else { return false }
            }
            let compact = AutomaticUITestSupport.element("today.compactLayout", in: app)
            let wide = AutomaticUITestSupport.element("today.wideLayout", in: app)
            guard wide.exists == value.expectsColumns, compact.exists != wide.exists else { return false }
            stableSamples = previous.map { value.isStable(comparedWith: $0) } == true ? stableSamples + 1 : 1
            previous = value
            return stableSamples >= 2
        }, object: nil)
        let result = XCTWaiter.wait(for: [settled], timeout: 12)
        let detail = (receipt.value as? String) ?? "No geometry receipt"
        let contract = independentWindowOrientation ? "independent window orientation (explicit runner input)"
            : "interface orientation follows physical pose (strict default)"
        let attachment = XCTAttachment(string:
            "Window orientation contract: \(contract)\nRequested physical pose: \(pose.rawValue)\n\(detail)")
        attachment.name = "Actual Today window, interface orientation and safe area"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(result, .completed,
            "Physical pose and the live layout must settle under \(contract); window aspect is not an orientation signal. \(detail)")
        return try XCTUnwrap(read())
    }

    // [10] The expected arrangement comes from real available space, including a sidebar or resized window.
    private func assertLayoutMatches(_ geometry: LayoutGeometry, in app: XCUIApplication) {
        let content = AutomaticUITestSupport.element("today.content", in: app)
        let compact = AutomaticUITestSupport.element("today.compactLayout", in: app)
        let wide = AutomaticUITestSupport.element("today.wideLayout", in: app)
        XCTAssertEqual(wide.exists, geometry.expectsColumns)
        XCTAssertEqual(compact.exists, !geometry.expectsColumns)
        // [14] A scroll view's accessibility shell may include the sidebar or draw under display edges.
        // The small receipt marker sits at the real pane's top-left; its live frame supplies the screen origin.
        let bounds = liveGeometryBounds(geometry, in: app)
        let window = bounds.window
        let safe = bounds.safe
        XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(safe))
        let marker = AutomaticUITestSupport.element("today.layoutGeometry", in: app)
        let markerFrame = marker.frame
        let pane = CGRect(origin: markerFrame.origin,
            size: CGSize(width: CGFloat(geometry.viewportWidth), height: CGFloat(geometry.viewportHeight)))
        let shell = content.frame
        let paneProof = XCTAttachment(string:
            "Live marker: \(markerFrame)\nActual pane: \(pane)\nAX scroll shell: \(shell)\n"
            + "Live window: \(window)\nWindow safe area: \(safe)\n\n\(app.debugDescription)")
        paneProof.name = "Actual content pane inside native window and sidebar"
        paneProof.lifetime = .keepAlways
        add(paneProof)
        XCTAssertGreaterThan(markerFrame.width, 0)
        XCTAssertGreaterThan(markerFrame.height, 0)
        XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(pane))
        XCTAssertTrue(safe.insetBy(dx: -1, dy: -1).contains(pane))
        XCTAssertTrue(shell.insetBy(dx: -1, dy: -1).contains(pane))
        let safeViewport = shell.intersection(window).intersection(safe).intersection(pane)
        XCTAssertGreaterThan(safeViewport.width, 44)
        XCTAssertEqual(safeViewport.width, CGFloat(geometry.viewportWidth), accuracy: 1)
        if wide.exists {
            let garden = AutomaticUITestSupport.element("today.gardenColumn", in: app)
            let actions = AutomaticUITestSupport.element("today.actionsColumn", in: app)
            XCTAssertGreaterThanOrEqual(actions.frame.minX - garden.frame.maxX, 31)
            XCTAssertGreaterThanOrEqual(garden.frame.minX, safeViewport.minX + 20)
            XCTAssertLessThanOrEqual(actions.frame.maxX, safeViewport.maxX - 20)
            XCTAssertGreaterThanOrEqual(actions.frame.width, 259)
        }
        // [12] A narrow-window run must use an actual narrow system window, never a pretend layout width.
        // Set this runner-only check after preparing that window with Apple's resizing tools.
        if ProcessInfo.processInfo.environment["DFE_UI_REQUIRE_NARROW_VIEWPORT"] == "1" {
            XCTAssertLessThan(geometry.viewportWidth, 760,
                "Prepare a real narrow window before this run; the test does not change app geometry")
            XCTAssertTrue(compact.exists)
        }
    }

    // [11] The native title and welcome text must stay clear of the current display's protected edges.
    private func assertWelcomeRespectsSafeArea(_ geometry: LayoutGeometry, content: XCUIElement,
                                               in app: XCUIApplication) throws {
        let welcome = AutomaticUITestSupport.element("today.welcome", in: content)
        AutomaticUITestSupport.reach(welcome, in: app, inside: content,
                                     below: app.navigationBars["Today"], verticalMargin: 16)
        XCTAssertTrue(welcome.isHittable)
        let bounds = liveGeometryBounds(geometry, in: app)
        let safe = bounds.safe.insetBy(dx: -1, dy: -1)
        XCTAssertGreaterThan(safe.width, 44)
        XCTAssertGreaterThan(safe.height, 100)
        XCTAssertTrue(safe.contains(welcome.frame), "The welcome must remain inside the real window safe area")
        let navigation = app.navigationBars["Today"]
        XCTAssertTrue(navigation.exists)
        let nativeTitle = navigation.staticTexts["Today"].firstMatch
        if nativeTitle.exists {
            XCTAssertTrue(safe.contains(nativeTitle.frame), "The native title must avoid the sensor area")
        } else if ProcessInfo.processInfo.environment["DFE_UI_WINDOW_ORIENTATION_INDEPENDENT"] == "1" {
            // [16] System navigation can replace the title with a native tab, including Duo's separate strip.
            // Its identifier may name Today while its spoken label names the icon. Keep both routes testable.
            let bars = app.tabBars.allElementsBoundByIndex + app.toolbars.allElementsBoundByIndex
            let choices = bars.flatMap {
                $0.descendants(matching: .button).matching(NSPredicate(
                    format: "identifier == %@ OR label == %@", "Today", "Today"))
                    .allElementsBoundByIndex
            }
            // [18] Keep the real native controls in the evidence when a container-specific query fails.
            // A missing test match must not be mistaken for a missing or broken tab in the app.
            let globalChoices = app.buttons.matching(NSPredicate(
                format: "identifier == %@ OR label == %@", "Today", "Today")).allElementsBoundByIndex
            func describe(_ button: XCUIElement) -> String {
                guard button.exists else { return "Candidate disappeared" }
                return "identifier=\(button.identifier); label=\(button.label); selected=\(button.isSelected); "
                    + "hittable=\(button.isHittable); frame=\(button.frame)"
            }
            let controls = XCTAttachment(string:
                "Bar-scoped candidates:\n\(choices.map(describe).joined(separator: "\n"))\n"
                + "Global candidates:\n\(globalChoices.map(describe).joined(separator: "\n"))\n\n\(app.debugDescription)")
            controls.name = "Native Today control candidates and actual hierarchy"
            controls.lifetime = .keepAlways
            add(controls)
            var nativeSelection = choices.first { $0.exists && $0.isSelected && $0.isHittable }
            if nativeSelection == nil {
                // [19] iPad exposes its native horizontal tab row as Other, rather than TabBar.
                // The sidebar toggle, all three routes and real header bounds identify that row without guessing a device.
                let header = navigation.frame.insetBy(dx: -1, dy: -1)
                let groups = app.otherElements.containing(.button, identifier: "ToggleSideBar")
                    .allElementsBoundByIndex
                for group in groups where !group.frame.isEmpty && header.contains(group.frame) {
                    let toggle = group.buttons["ToggleSideBar"].firstMatch
                    let today = group.descendants(matching: .button).matching(NSPredicate(
                        format: "identifier == %@ OR label == %@", "Today", "Today"))
                        .allElementsBoundByIndex.first { $0.exists && $0.isSelected && $0.isHittable }
                    let history = group.buttons.matching(NSPredicate(
                        format: "identifier == %@ OR label == %@", "History", "History")).firstMatch
                    let settings = group.buttons.matching(NSPredicate(
                        format: "identifier == %@ OR label == %@", "Settings", "Settings")).firstMatch
                    guard let today, toggle.exists, toggle.isHittable,
                          history.exists, history.isHittable, settings.exists, settings.isHittable,
                          header.contains(today.frame), header.contains(toggle.frame),
                          header.contains(history.frame), header.contains(settings.frame) else { continue }
                    nativeSelection = today
                    break
                }
            }
            let selected = try XCTUnwrap(nativeSelection,
                "Today must remain selected and reachable in native system navigation")
            XCTAssertTrue(bounds.window.insetBy(dx: -1, dy: -1).contains(selected.frame),
                "Native navigation must stay inside the real window, including its separate system strip")
        } else {
            XCTFail("The strict ordinary-phone contract requires a visible native Today title")
        }
    }

    // [17] UIKit's receipt uses scene-local points in a moved iPad window, while live XCTest frames use the screen.
    // Match sizes first, then align origins; this changes the coordinate basis without hiding a wrong-sized window.
    private func liveGeometryBounds(_ geometry: LayoutGeometry, in app: XCUIApplication)
        -> (window: CGRect, safe: CGRect) {
        let liveWindow = app.windows.firstMatch.frame
        let recordedWindow = geometry.windowFrame.frame
        XCTAssertEqual(recordedWindow.width, liveWindow.width, accuracy: 1)
        XCTAssertEqual(recordedWindow.height, liveWindow.height, accuracy: 1)
        let dx = liveWindow.minX - recordedWindow.minX
        let dy = liveWindow.minY - recordedWindow.minY
        return (recordedWindow.offsetBy(dx: dx, dy: dy), geometry.safeFrame.frame.offsetBy(dx: dx, dy: dy))
    }

    // [07] A missing counter is a broken test setup, rather than a successful zero-count refresh.
    private func completedPulls(in content: XCUIElement) throws -> Int {
        let value = try XCTUnwrap(content.value as? String)
        let prefix = "Completed refreshes: "
        XCTAssertTrue(value.hasPrefix(prefix))
        return try XCTUnwrap(Int(value.dropFirst(prefix.count)))
    }

    // [08] Only horizontal bars over this page reduce its clear height. A sidebar beside it does not.
    private func visibleViewport(_ content: XCUIElement, in app: XCUIApplication) -> CGRect {
        let base = content.frame.intersection(app.windows.firstMatch.frame)
        var top = base.minY
        var bottom = base.maxY
        let bars = app.navigationBars.allElementsBoundByIndex + app.tabBars.allElementsBoundByIndex
        for bar in bars where bar.exists && bar.isHittable {
            let frame = bar.frame
            guard frame.intersects(base), frame.height < base.height / 2 else { continue }
            if frame.midY < base.midY { top = max(top, frame.maxY) }
            else { bottom = min(bottom, frame.minY) }
        }
        let viewport = CGRect(x: base.minX, y: top, width: base.width, height: bottom - top)
            .insetBy(dx: 12, dy: 12)
        XCTAssertGreaterThan(viewport.height, 100)
        XCTAssertGreaterThan(viewport.width, 44)
        return viewport
    }

    private func recordPullGeometry(title: String, stage: String, content: XCUIElement,
                                    viewport: CGRect, count: Int) {
        let receipt = XCTAttachment(string:
            "\(title) \(stage): content=\(content.frame); clear=\(viewport); completedPulls=\(count); time=\(Date().timeIntervalSince1970)")
        receipt.name = "Adaptive \(title) refresh geometry \(stage)"
        receipt.lifetime = .keepAlways
        add(receipt)
    }

    // [04] The system may move navigation to the top or a sidebar as a window changes shape.
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
}
