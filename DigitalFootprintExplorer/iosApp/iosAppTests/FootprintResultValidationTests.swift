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
@testable import DFE

// [01] A saved total should tell the same story as its parts. A readable number alone
// does not make a damaged estimate safe to show in the garden.
final class FootprintResultValidationTests: XCTestCase {
    private func category(_ kind: FootprintCategory = .video, total: Double = 1,
                          device: Double = 1, network: Double = 0,
                          backend: Double = 0) -> CategoryFootprint {
        CategoryFootprint(category: kind, totalKg: total, deviceKg: device,
                          networkKg: network, backendKg: backend)
    }

    private func result(total: Double = 1, app: Double = 1, display: Double = 0,
                        background: Double = 0, categories: [CategoryFootprint] = []) -> FootprintResult {
        FootprintResult(totalKg: total, appUsageKg: app, displayKg: display,
                        backgroundKg: background, categories: categories)
    }

    // [02] This is the original gap: every value is positive, but the parts add up to two,
    // while the garden would show one.
    func testMismatchedOverallTotalIsRejected() {
        XCTAssertThrowsError(try result(total: 1, app: 2).validate())
    }

    // [03] A category cannot claim a smaller footprint than its device, network and server parts.
    func testMismatchedCategoryPartsAreRejected() {
        let invalid = category(total: 1, device: 0.5, network: 0.5, backend: 0.5)
        XCTAssertThrowsError(try result(categories: [invalid]).validate())
    }

    // [04] The app total and its category list need to agree, otherwise the detail screen
    // could give a different answer from Today.
    func testCategorySumMustMatchAppUsage() {
        let invalid = result(total: 2, app: 2, categories: [category()])
        XCTAssertThrowsError(try invalid.validate())
    }

    // [05] Repeated category IDs can hide a missing category or show the same row twice.
    func testDuplicateCategoriesAreRejectedEvenWhenTheSumsMatch() {
        let repeated = category(total: 0.5, device: 0.5)
        XCTAssertThrowsError(try result(categories: [repeated, repeated]).validate())
    }

    // [06] Finite inputs can still add up to infinity. That must not become a saved result.
    func testOverflowInAnyResultSumIsRejected() {
        let huge = Double.greatestFiniteMagnitude
        XCTAssertThrowsError(try result(total: huge, app: huge / 2,
            display: huge / 2, background: huge / 2).validate())
        XCTAssertThrowsError(try result(total: huge, app: huge,
            categories: [category(total: huge, device: huge, network: huge)]).validate())
        let parts = [category(.video, total: huge / 2, device: huge / 2),
                     category(.audio, total: huge / 2, device: huge / 2),
                     category(.social, total: huge / 2, device: huge / 2)]
        XCTAssertThrowsError(try result(total: huge, app: huge, categories: parts).validate())
    }

    // [07] Keep the original protection too. A matching sum does not make a negative or
    // unreadable component acceptable.
    func testNegativeAndNonfiniteComponentsRemainRejected() {
        for invalid in [-1.0, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertThrowsError(try result(total: invalid, app: invalid).validate())
            XCTAssertThrowsError(try result(categories: [category(device: invalid)]).validate())
        }
    }

    // [08] Decimal fractions do not always add up exactly on a computer. Ordinary rounding
    // should not make a good result look damaged.
    func testNormalFloatingPointSummationIsAccepted() {
        XCTAssertNoThrow(try result(total: 0.3, app: 0.1, display: 0.2,
                                   categories: [category(total: 0.1, device: 0.1)]).validate())
        XCTAssertNoThrow(try result(total: 0.3, app: 0.3,
            categories: [category(total: 0.3, device: 0.1, network: 0.2)]).validate())
    }

    // [09] A real zero is valid. Earlier total-only history also stays readable when its
    // top-level parts agree, even if it has no category list.
    func testZeroAndLegacyTotalOnlyHistoryRemainValid() {
        XCTAssertNoThrow(try result(total: 0, app: 0,
            categories: [category(total: 0, device: 0)]).validate())
        XCTAssertNoThrow(try result(total: 1, app: 0.75, display: 0.2, background: 0.05).validate())
    }

    // [10] Small estimates still count. The tolerance is only a rounding allowance, not
    // permission to replace a tiny result with a different amount.
    func testTinyValuesAndAbsoluteToleranceHaveAClearBoundary() {
        XCTAssertNoThrow(try result(total: 1e-15, app: 1e-15,
            categories: [category(total: 1e-15, device: 1e-15)]).validate())
        XCTAssertNoThrow(try result(total: 5e-13, app: 0).validate())
        XCTAssertThrowsError(try result(total: 2e-12, app: 0).validate())
    }

    // [11] The same rounding rule should work at another scale without accepting a
    // clearly different total.
    func testRelativeToleranceDoesNotAcceptAMaterialDifference() {
        XCTAssertNoThrow(try result(total: 1e9 + 0.05, app: 1e9).validate())
        XCTAssertThrowsError(try result(total: 1e9 + 0.2, app: 1e9).validate())
    }

    // [12] These answers were worked out separately from the shared code. They catch unit
    // or coefficient changes that a comparison against the same code could miss.
    func testSharedCalculationMatchesIndependentDecimalOracleCases() throws {
        let scenarios: [(String, FootprintInputs, [Double])] = [
            ("one hour of video", FootprintInputs(usages: [
                CategoryUsage(category: .video, minutes: 60, gigabytesPerHour: 1, wifiShare: 0.8)
            ], brightness: 0.5, gpsHours: 0.25, bluetoothHours: 2),
             [0.03251719658119658, 0.032493408547008544, 0.000013401709401709402, 0.000010386324786324786]),
            ("half an hour of audio on Wi-Fi", FootprintInputs(usages: [
                CategoryUsage(category: .audio, minutes: 30, gigabytesPerHour: 0.0432, wifiShare: 1)
            ], brightness: 1, gpsHours: 0, bluetoothHours: 0),
             [0.0006336146461538461, 0.0006202129367521368, 0.000013401709401709402, 0]),
            ("AI and social media", FootprintInputs(usages: [
                CategoryUsage(category: .ai, minutes: 30, gigabytesPerHour: 0.005, wifiShare: 0),
                CategoryUsage(category: .social, minutes: 90, gigabytesPerHour: 0.2, wifiShare: 1)
            ], brightness: 0.25, gpsHours: 1.125, bluetoothHours: 8.25),
             [0.009319878846153847, 0.009261748931623931, 0.000013401709401709402, 0.00004472820512820513]),
            ("genuine zero activity", FootprintInputs(usages: [
                CategoryUsage(category: .other, minutes: 0, gigabytesPerHour: 0.05, wifiShare: 0.8)
            ], brightness: 0.5, gpsHours: 0, bluetoothHours: 0), [0, 0, 0, 0]),
            ("a long calendar day", FootprintInputs(usages: [
                CategoryUsage(category: .video, minutes: 1450, gigabytesPerHour: 0.7, wifiShare: 0.8)
            ], brightness: 0.5, gpsHours: 24, bluetoothHours: 24, calendarDayMinutes: 1500),
             [0.5510366376068376, 0.5501659732193732, 0.00032387464387464385, 0.0005467897435897436]),
            ("fractional seconds", FootprintInputs(usages: [
                CategoryUsage(category: .video, minutes: 20.49 / 60, gigabytesPerHour: 0.7, wifiShare: 0.8),
                CategoryUsage(category: .ai, minutes: 3.2 / 60, gigabytesPerHour: 0.005, wifiShare: 0.8)
            ], brightness: 0.63, gpsHours: 0.1, bluetoothHours: 0.3),
             [0.00013050483439714, 0.00012758259160018992, 0.00000010788376068376068, 0.000002814359036266294])
        ]
        for (name, inputs, expected) in scenarios {
            let actual = try SharedFootprintCalculator().calculate(inputs)
            XCTAssertEqual(actual.totalKg, expected[0], accuracy: 1e-12, name)
            XCTAssertEqual(actual.appUsageKg, expected[1], accuracy: 1e-12, name)
            XCTAssertEqual(actual.displayKg, expected[2], accuracy: 1e-12, name)
            XCTAssertEqual(actual.backgroundKg, expected[3], accuracy: 1e-12, name)
            XCTAssertNoThrow(try actual.validate(), name)
        }
    }

    // [13] A damaged but readable history file must be kept for recovery. Opening it must
    // not allow setup or another save to quietly overwrite the evidence.
    @MainActor func testInvalidArchiveBalanceIsPreservedAndBlocksMutation() throws {
        let original = makeStore()
        let first = date("2026-10-07T10:00:00Z")
        let now = date("2026-10-08T10:00:00Z")
        let input = simpleInputs()
        try original.saveProfile(input, now: first)
        var archive = try XCTUnwrap(original.archive)
        archive.records[0].result = result(total: 1, app: 2)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let damaged = try encoder.encode(archive)
        try damaged.write(to: original.fileURL, options: .atomic)
        let reopened = FootprintStore(fileURL: original.fileURL,
            calculator: SharedFootprintCalculator(), calendar: calendar)
        XCTAssertNotNil(reopened.errorMessage)
        XCTAssertFalse(reopened.isConfigured)
        XCTAssertThrowsError(try reopened.saveProfile(input, now: now))
        XCTAssertThrowsError(try reopened.saveDay("2026-10-07", inputs: input, now: now))
        XCTAssertEqual(try Data(contentsOf: original.fileURL), damaged)
    }

    // [14] The same check belongs before a save too. A broken calculation must leave the
    // last good in-memory result and the file together.
    @MainActor func testInvalidCalculationCannotReplaceSavedHistory() throws {
        let calculator = BalanceProbeCalculator()
        let store = makeStore(calculator)
        let first = date("2026-10-07T10:00:00Z")
        try store.saveProfile(simpleInputs(), now: first)
        let original = store.archive
        let file = try Data(contentsOf: store.fileURL)
        calculator.returnBrokenTotal = true
        XCTAssertThrowsError(try store.saveDay("2026-10-07", inputs: simpleInputs(),
                                             now: date("2026-10-08T10:00:00Z")))
        XCTAssertEqual(store.archive, original)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), file)
    }

    // [15] Three hours can contain very different kinds of use. These separately worked-out
    // amounts check that the real iPhone defaults and the shared calculation keep the same units.
    func testThreeHourMixedUseMatchesIndependentDecimalOracleWithSharedDefaults() throws {
        let usages = [FootprintCategory.video, .audio, .messaging].map { category in
            var usage = SharedFootprintCalculator.exampleUsage(for: category)
            usage.minutes = 60
            return usage
        }
        let inputs = FootprintInputs(usages: usages, brightness: 0.5, gpsHours: 0, bluetoothHours: 0)
        let actual = try SharedFootprintCalculator().calculate(inputs)
        XCTAssertEqual(inputs.totalMinutes, 180)
        XCTAssertEqual(actual.totalKg, 0.024604487556923077, accuracy: 1e-12)
        XCTAssertEqual(actual.appUsageKg, 0.02456428242871795, accuracy: 1e-12)
        XCTAssertEqual(actual.displayKg, 0.000040205128205128205, accuracy: 1e-12)
        XCTAssertEqual(actual.backgroundKg, 0)
        XCTAssertEqual(actual.categories.count, 3)
        XCTAssertEqual(Set(actual.categories.map(\.category)), Set([.video, .audio, .messaging]))
        XCTAssertEqual(actual.categories.reduce(0) { $0 + $1.deviceKg }, 0.00014071794871794872, accuracy: 1e-12)
        XCTAssertEqual(actual.categories.reduce(0) { $0 + $1.networkKg }, 0.00545045648, accuracy: 1e-12)
        XCTAssertEqual(actual.categories.reduce(0) { $0 + $1.backendKg }, 0.018973108, accuracy: 1e-12)
        let expectedCategories: [(FootprintCategory, Double)] = [
            (.video, 0.022765488547008547),
            (.audio, 0.0014343247535042735),
            (.messaging, 0.0003644691282051282)
        ]
        for (category, expected) in expectedCategories {
            let saved = try XCTUnwrap(actual.categories.first { $0.category == category })
            XCTAssertEqual(saved.totalKg, expected, accuracy: 1e-12)
        }
        XCTAssertNoThrow(try actual.validate())
    }

    // [16] Equal time does not mean equal traffic. Fixed answers also show that changing
    // the connection assumption affects network energy without changing the device or server parts.
    func testThreeHourCategoryAndNetworkScenariosMatchIndependentDecimalAnswers() throws {
        func result(_ category: FootprintCategory, wifiShare: Double? = nil) throws -> FootprintResult {
            var usage = SharedFootprintCalculator.exampleUsage(for: category)
            usage.minutes = 180
            if let wifiShare { usage.wifiShare = wifiShare }
            return try SharedFootprintCalculator().calculate(FootprintInputs(usages: [usage],
                brightness: 0.5, gpsHours: 0, bluetoothHours: 0))
        }
        let video = try result(.video)
        let messaging = try result(.messaging)
        let allWiFi = try result(.video, wifiShare: 1)
        let allCellular = try result(.video, wifiShare: 0)
        XCTAssertEqual(video.totalKg, 0.06833667076923077, accuracy: 1e-12)
        XCTAssertEqual(messaging.totalKg, 0.0011336125128205128, accuracy: 1e-12)
        XCTAssertEqual(allWiFi.totalKg, 0.05891103076923077, accuracy: 1e-12)
        XCTAssertEqual(allCellular.totalKg, 0.10603923076923077, accuracy: 1e-12)
        for candidate in [video, messaging, allWiFi, allCellular] {
            XCTAssertEqual(candidate.displayKg, 0.000040205128205128205, accuracy: 1e-12)
            XCTAssertEqual(candidate.backgroundKg, 0)
            XCTAssertNoThrow(try candidate.validate())
        }
        let wifiParts = try XCTUnwrap(allWiFi.categories.first)
        let cellularParts = try XCTUnwrap(allCellular.categories.first)
        XCTAssertEqual(wifiParts.deviceKg, cellularParts.deviceKg, accuracy: 1e-12)
        XCTAssertEqual(wifiParts.backendKg, 0.052899, accuracy: 1e-12)
        XCTAssertEqual(cellularParts.backendKg, wifiParts.backendKg, accuracy: 1e-12)
        XCTAssertEqual(wifiParts.networkKg, 0.0057708, accuracy: 1e-12)
        XCTAssertEqual(cellularParts.networkKg, 0.052899, accuracy: 1e-12)
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return value
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func simpleInputs() -> FootprintInputs {
        FootprintInputs(usages: [CategoryUsage(category: .video, minutes: 60,
            gigabytesPerHour: 1, wifiShare: 0.8)], brightness: 0.5, gpsHours: 0, bluetoothHours: 0)
    }
    @MainActor private func makeStore(_ calculator: any FootprintCalculating = SharedFootprintCalculator()) -> FootprintStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return FootprintStore(fileURL: folder.appendingPathComponent("history.json"),
                              calculator: calculator, calendar: calendar)
    }
}

// [17] Return a balanced answer first, then a deliberately wrong total. This keeps the
// save-safety test independent from failures in Apple's activity service.
private final class BalanceProbeCalculator: FootprintCalculating {
    var returnBrokenTotal = false
    func calculate(_ inputs: FootprintInputs) throws -> FootprintResult {
        let good = try SharedFootprintCalculator().calculate(inputs)
        guard returnBrokenTotal else { return good }
        return FootprintResult(totalKg: good.totalKg + 1, appUsageKg: good.appUsageKg,
            displayKg: good.displayKg, backgroundKg: good.backgroundKg, categories: good.categories)
    }
}
