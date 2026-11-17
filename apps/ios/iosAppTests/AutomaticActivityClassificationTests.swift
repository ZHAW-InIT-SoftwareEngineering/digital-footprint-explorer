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

// [01] Known app identities help choose local categories, but they do not reveal what someone did
// in an app

import XCTest
@testable import DFE

final class AutomaticActivityClassificationTests: XCTestCase {
    // [02] Known built-in apps should use the agreed model category, so automatic setup stays
    // predictable.
    func testBuiltInAppsUseTheirVerifiedModelDefaults() {
        XCTAssertEqual(AutomaticActivityClassification.category(bundleIdentifier: "com.apple.Music"), .audio)
        XCTAssertEqual(AutomaticActivityClassification.category(bundleIdentifier: "com.apple.podcasts"), .audio)
        XCTAssertEqual(AutomaticActivityClassification.category(bundleIdentifier: "com.apple.Maps"), .navigation)
        XCTAssertEqual(AutomaticActivityClassification.category(bundleIdentifier: "com.apple.mobilemail"), .email)
        XCTAssertEqual(AutomaticActivityClassification.category(bundleIdentifier: "com.apple.MobileSMS"), .messaging)
    }

    // [03] An app's category is only a starting assumption; its time does not reveal which feature
    // someone used.
    func testKnownThirdPartyAppsUseLocalDefaultsWithoutInferringTheirCurrentActivity() {
        XCTAssertEqual(AutomaticActivityClassification.category(bundleIdentifier: "com.google.ios.youtube"), .video)
        XCTAssertEqual(AutomaticActivityClassification.category(bundleIdentifier: "com.spotify.client"), .audio)
        XCTAssertEqual(AutomaticActivityClassification.category(bundleIdentifier: "com.burbn.instagram"), .social)
        // [04] A messaging app can also make calls. Its minutes do not tell us which action occurred.
        XCTAssertEqual(AutomaticActivityClassification.category(bundleIdentifier: "net.whatsapp.WhatsApp"), .messaging)
        XCTAssertEqual(AutomaticActivityClassification.category(bundleIdentifier: "com.google.Gmail"), .email)
        XCTAssertEqual(AutomaticActivityClassification.category(bundleIdentifier: "com.google.Maps"), .navigation)
        XCTAssertEqual(AutomaticActivityClassification.category(bundleIdentifier: "com.openai.chat"), .ai)
        XCTAssertEqual(AutomaticActivityClassification.category(bundleIdentifier: "com.roblox.robloxmobile"), .gaming)
    }

    // [05] Similar names are not proof of identity. Unrecognized apps should stay in Other.
    func testUnknownMissingSimilarAndDifferentlyCasedIdentifiersStayInOther() {
        for identifier in [nil, "", "Music", "com.apple.music", "com.apple.Music.extra",
                           "net.whatsapp.WhatsAppBusiness", "com.example.social-video-chat"] {
            XCTAssertEqual(AutomaticActivityClassification.category(bundleIdentifier: identifier), .other)
        }
    }

    // [06] Automatic setup should replace measured time without discarding the assumptions already
    // reviewed.
    func testAllCategorySetupKeepsReviewedAssumptionsAndClearsOnlyDurations() throws {
        let original = FootprintInputs(usages: [
            CategoryUsage(category: .video, minutes: 93, gigabytesPerHour: 2.75, wifiShare: 0.63),
            CategoryUsage(category: .other, minutes: 11, gigabytesPerHour: 0.02, wifiShare: 0.99)
        ], brightness: 0.71, gpsHours: 0.3, bluetoothHours: 4)
        let result = AutomaticActivityClassification.assumptions(preserving: original)
        try result.validate()
        XCTAssertEqual(result.usages.map(\.category), FootprintCategory.allCases)
        XCTAssertEqual(Set(result.usages.map(\.category)).count, 10)
        XCTAssertTrue(result.usages.allSatisfy { $0.minutes == 0 })
        XCTAssertEqual(result.usages.first { $0.category == .video }?.gigabytesPerHour, 2.75)
        XCTAssertEqual(result.usages.first { $0.category == .video }?.wifiShare, 0.63)
        XCTAssertEqual(result.usages.first { $0.category == .other }?.gigabytesPerHour, 0.02)
        XCTAssertEqual(result.usages.first { $0.category == .other }?.wifiShare, 0.99)
        XCTAssertEqual(result.brightness, original.brightness)
        XCTAssertEqual(result.gpsHours, original.gpsHours)
        XCTAssertEqual(result.bluetoothHours, original.bluetoothHours)
        XCTAssertEqual(original.totalMinutes, 104)
    }

    // [07] When an assumption is missing, both platforms should start from the same shared
    // calculation model.
    func testMissingAssumptionsComeFromTheExistingSharedModel() throws {
        let result = AutomaticActivityClassification.assumptions(preserving: nil)
        try result.validate()
        XCTAssertEqual(result.usages.count, 10)
        XCTAssertEqual(result.totalMinutes, 0)
        XCTAssertEqual(result.brightness, FootprintInputs.empty.brightness)
        XCTAssertEqual(result.gpsHours, FootprintInputs.empty.gpsHours)
        XCTAssertEqual(result.bluetoothHours, FootprintInputs.empty.bluetoothHours)
        for category in [FootprintCategory.audio, .calls, .other] {
            let expected = SharedFootprintCalculator.exampleUsage(for: category)
            let actual = try XCTUnwrap(result.usages.first { $0.category == category })
            XCTAssertEqual(actual.gigabytesPerHour, expected.gigabytesPerHour)
            XCTAssertEqual(actual.wifiShare, expected.wifiShare)
        }
    }
}
