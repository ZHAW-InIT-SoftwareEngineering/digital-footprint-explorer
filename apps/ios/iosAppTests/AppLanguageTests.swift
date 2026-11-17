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
import UserNotifications
@testable import DFE

final class AppLanguageTests: XCTestCase {
    func testGermanDeviceLanguagesUseSwissSpelling() {
        XCTAssertEqual(AppLanguage.preferred(for: "de-DE"), .swissGerman)
        XCTAssertEqual(AppLanguage.preferred(for: "de-CH"), .swissGerman)
        XCTAssertEqual(AppLanguage.preferred(for: "fr-CH"), .english)
        XCTAssertEqual(AppLanguage.swissGerman.locale.identifier, "de_CH")
        XCTAssertEqual(AppLanguage.swissGerman.text("Estimated carbon footprint"), "Geschätzter CO₂-Fussabdruck")
        XCTAssertEqual(AppLanguage.english.text("Estimated carbon footprint"), "Estimated carbon footprint")
        XCTAssertEqual(AppLanguage.swissGerman.format("Imported app activity: %@", "42 min"),
                       "Importierte App-Nutzungszeit: 42 min")
    }

    // [01] The German policy should cover the same choices as the English policy on the phone.
    func testOfflinePolicyHasNoUntranslatedParagraphs() {
        let policy = [PrivacyPolicyContent.title, PrivacyPolicyContent.updatedText] + PrivacyPolicyContent.introduction
            + PrivacyPolicyContent.sections.flatMap { [$0.title] + $0.paragraphs }
        for key in policy {
            XCTAssertNotEqual(AppLanguage.swissGerman.text(key), key, key)
        }
    }

    // [02] Changing wording has to keep the same date, ID and Today action.
    func testPendingReminderLanguageChangesWithoutReschedulingItsDate() throws {
        // [03] The second reminder is outside the brief delivery window, even if the test runs at 08:00.
        let plan = try XCTUnwrap(DailyGardenNotificationPlan.morningReminders(after: Date(), count: 2).last)
        let english = GardenNotificationRequestBuilder.make(plan, language: .english)
        let german = try XCTUnwrap(GardenNotificationRequestBuilder.relocalized(english, to: .swissGerman))
        XCTAssertNotEqual(german.content.body, english.content.body)
        XCTAssertNotEqual(german.content.title, english.content.title)
        XCTAssertEqual(german.identifier, english.identifier)
        XCTAssertEqual(german.trigger, english.trigger)
        XCTAssertEqual(german.content.userInfo["gardenURL"] as? String, DailyGardenNotificationPlan.gardenURL)
        XCTAssertNil(GardenNotificationRequestBuilder.relocalized(german, to: .swissGerman))
        let restored = try XCTUnwrap(GardenNotificationRequestBuilder.relocalized(german, to: .english))
        XCTAssertEqual(restored.content.body, english.content.body)
    }
}
