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

@MainActor
final class LanguageUITests: XCTestCase {
    // [01] Read the actual tabs and a saved result after changing languages and reopening DFE.
    func testChangeLanguageAndKeepChoiceAcrossLaunches() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-example-history", "-ui-automatic-preview",
                               "-reset-ui-state", "-ui-keep-language", "-ui-reset-language"]
        app.launch()
        choose("language.de-CH", using: "Settings", in: app)
        XCTAssertTrue(app.navigationBars["App-Sprache"].waitForExistence(timeout: 8), app.debugDescription)
        app.tabBars.buttons["Heute"].tap()
        XCTAssertEqual(app.staticTexts["today.welcome"].label, "Schön, dass du da bist")
        XCTAssertTrue(app.staticTexts["footprint.total"].exists)
        app.tabBars.buttons["Verlauf"].tap()
        XCTAssertTrue(app.navigationBars["Verlauf"].waitForExistence(timeout: 8))

        app.terminate()
        app.launchArguments.removeAll { $0 == "-ui-reset-language" || $0 == "-reset-ui-state" }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Heute"].waitForExistence(timeout: 12))
        choose("language.en", using: "Einstellungen", in: app)
        app.tabBars.buttons["Today"].tap()
        XCTAssertEqual(app.staticTexts["today.welcome"].label, "Good to have you here")
        XCTAssertTrue(app.staticTexts["footprint.total"].exists)
    }

    // [02] The in-app choice takes priority for DFE text, even on a German iPhone.
    func testEnglishChoiceWithGermanSystemLanguage() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-state", "-AppleLanguages", "(de-CH)",
                               "-AppleLocale", "de_CH"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["onboarding.automatic"].label, "Automatic setup")
    }

    private func choose(_ identifier: String, using settingsTitle: String, in app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons[settingsTitle].waitForExistence(timeout: 12))
        app.tabBars.buttons[settingsTitle].tap()
        let row = AutomaticUITestSupport.element("settings.language", in: app)
        AutomaticUITestSupport.reach(row, in: app)
        XCTAssertTrue(row.exists && row.isHittable)
        row.tap()
        let option = app.buttons[identifier]
        XCTAssertTrue(option.waitForExistence(timeout: 8))
        option.tap()
    }
}
