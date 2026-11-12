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

// [01] The garden should connect the actual calculation, recent history and the correct bundled
// image

import XCTest
import UIKit
import SwiftUI
@testable import DFE

final class GardenBehaviorTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return calendar
    }

    private func date(_ day: String) -> Date {
        ISO8601DateFormatter().date(from: day + "T10:00:00Z")!
    }

    private func inputs(minutes: Double) -> FootprintInputs {
        FootprintInputs(
            usages: [CategoryUsage(category: .video, minutes: minutes, gigabytesPerHour: 0.7, wifiShare: 0.8)],
            brightness: 0.5, gpsHours: 0, bluetoothHours: 0
        )
    }

    private func fileURL() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("history.json")
    }

    // [02] Values just beside a boundary matter: rounding must not put the same day in the wrong
    // garden state.
    func testExactGardenThresholdsAndValuesOnBothSidesAtDifferentScales() {
        let cases: [(Double, FootprintGarden)] = [
            (0.699999, .flourishing), (0.7, .flourishing), (0.700001, .growing),
            (0.899999, .growing), (0.9, .growing), (0.900001, .stable),
            (1.099999, .stable), (1.1, .wilting), (1.100001, .wilting),
            (1.399999, .wilting), (1.4, .wilting), (1.400001, .withered)
        ]
        for baseline in [1.0, 100.0, 0.000001] {
            for (ratio, expected) in cases {
                XCTAssertEqual(FootprintGarden.state(total: baseline * ratio, baseline: baseline), expected,
                               "Total/baseline ratio \(ratio), baseline \(baseline)")
            }
        }
        // [03] Use exact examples near each boundary to catch rounding that could show the wrong
        // garden.
        XCTAssertEqual(FootprintGarden.state(total: 90, baseline: 100), .growing)
        XCTAssertEqual(FootprintGarden.state(total: 110, baseline: 100), .wilting)
        XCTAssertEqual(FootprintGarden.state(total: 140, baseline: 100), .wilting)
    }

    // [04] The actual shared calculation should be able to reach every garden state, rather than
    // only a test substitute.
    @MainActor func testRealSharedEmissionsFromUsageProduceAllFiveGardenStates() async throws {
        let cases: [(Double, FootprintGarden)] = [
            (30, .flourishing), (48, .growing), (60, .stable), (72, .wilting), (90, .withered)
        ]
        for (minutes, expected) in cases {
            let store = FootprintStore(fileURL: fileURL(), calculator: SharedFootprintCalculator(), calendar: calendar)
            try store.saveProfile(inputs(minutes: 60), now: date("2026-10-07"))
            let first = try XCTUnwrap(store.latest)
            XCTAssertNil(first.baselineKg)
            XCTAssertEqual(first.garden, .stable)
            try store.saveDay("2026-10-08", inputs: inputs(minutes: minutes), now: date("2026-10-08"))
            let next = try XCTUnwrap(store.latest)
            XCTAssertEqual(try XCTUnwrap(next.baselineKg), first.result.totalKg, accuracy: 1e-14)
            // [05] With unchanged assumptions and no background use, this model scales with minutes.
            XCTAssertEqual(next.result.totalKg / first.result.totalKg, minutes / 60, accuracy: 1e-12)
            XCTAssertEqual(next.garden, expected, "Saved use: \(minutes) minutes")
        }
    }

    // [06] Only the seven earlier records belong in a day's comparison, and correcting one must
    // update later gardens.
    @MainActor func testOnlySevenEarlierRecordsSetBaselineAndPastEditsRebuildIt() async throws {
        let url = fileURL()
        let store = FootprintStore(fileURL: url, calculator: SharedFootprintCalculator(), calendar: calendar)
        let now = date("2026-10-16")
        try store.saveProfile(inputs(minutes: 1200), now: date("2026-10-07"))
        for day in 8...15 {
            try store.saveDay(String(format: "2026-10-%02d", day), inputs: inputs(minutes: 60), now: now)
        }
        let latest = try XCTUnwrap(store.latest)
        let unitTotal = latest.result.totalKg
        XCTAssertEqual(try XCTUnwrap(latest.baselineKg), unitTotal, accuracy: 1e-14)
        XCTAssertEqual(latest.garden, .stable)
        XCTAssertTrue(latest.isCompleted)

        // [07] The first day's much larger result is now outside the seven-record window.
        try store.saveDay("2026-10-07", inputs: inputs(minutes: 0), now: now)
        XCTAssertEqual(try XCTUnwrap(store.latest).baselineKg, latest.baselineKg)
        XCTAssertEqual(store.latest?.garden, .stable)

        try store.saveDay("2026-10-14", inputs: inputs(minutes: 300), now: now)
        let corrected = try XCTUnwrap(store.latest)
        XCTAssertEqual(try XCTUnwrap(corrected.baselineKg), (6 * unitTotal + 5 * unitTotal) / 7, accuracy: 1e-14)
        XCTAssertEqual(corrected.garden, .flourishing)
        XCTAssertEqual(Set(store.records.map(\.day)).count, store.records.count)
        let reopened = FootprintStore(fileURL: url, calculator: SharedFootprintCalculator(), calendar: calendar)
        XCTAssertNil(reopened.errorMessage)
        XCTAssertEqual(reopened.latest, corrected)
    }

    // [08] A run of zero-use days and the first positive day should save a usable garden without
    // invalid numbers.
    @MainActor func testZeroUseHistoryAndFirstPositiveDayRemainFiniteAndPersist() async throws {
        let url = fileURL()
        let store = FootprintStore(fileURL: url, calculator: SharedFootprintCalculator(), calendar: calendar)
        try store.saveProfile(inputs(minutes: 0), now: date("2026-10-07"))
        XCTAssertNil(store.latest?.baselineKg)
        XCTAssertEqual(store.latest?.garden, .stable)
        try store.catchUp(now: date("2026-10-10"))
        XCTAssertEqual(store.records.map(\.garden), [.stable, .stable, .stable])
        XCTAssertEqual(store.records.dropFirst().map(\.baselineKg), [0, 0])
        XCTAssertTrue(store.records.allSatisfy { $0.result.totalKg == 0 })
        try store.saveDay("2026-10-10", inputs: inputs(minutes: 60), now: date("2026-10-10"))
        let positive = try XCTUnwrap(store.latest)
        XCTAssertGreaterThan(positive.result.totalKg, 0)
        XCTAssertEqual(positive.baselineKg, 0)
        XCTAssertEqual(positive.garden, .withered)
        let reopened = FootprintStore(fileURL: url, calculator: SharedFootprintCalculator(), calendar: calendar)
        XCTAssertNil(reopened.errorMessage)
        XCTAssertEqual(reopened.latest, positive)
    }

    // [09] Each state should render its own bundled garden, so a changed result is visible as well
    // as readable.
    @MainActor func testEachGardenUsesItsOwnBundledOriginalImage() async throws {
        let images: [(FootprintGarden, String)] = [
            (.flourishing, "GardenFlourishing"), (.growing, "GardenGrowing"),
            (.stable, "GardenStable"), (.wilting, "GardenWilting"), (.withered, "GardenWithered")
        ]
        for (state, name) in images {
            XCTAssertEqual(GardenArtwork.imageName(for: state), name)
            XCTAssertNotNil(UIImage(named: name), "Missing garden image: \(name)")
            // [10] Render the real component, without adding a made-up history to the app.
            let renderer = ImageRenderer(content: GardenArtwork(state: state)
                .frame(width: 320, height: 240)
                .background(Color(uiColor: .systemBackground)))
            renderer.scale = 2
            let rendered = try XCTUnwrap(renderer.uiImage, "Could not render garden: \(state.title)")
            let attachment = XCTAttachment(image: rendered)
            attachment.name = "Original garden: \(state.title) (320×240 pt, 2×)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
