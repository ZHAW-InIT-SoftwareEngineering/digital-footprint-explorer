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

final class TodayPresentationTests: XCTestCase {
    private let today = "2026-10-20"
    private let gardens: [FootprintGarden] = [.flourishing, .growing, .stable, .wilting, .withered]
    private func record(day: String = "2026-10-19", completed: Bool = true,
                        garden: FootprintGarden, source: FootprintSource = .screenTimeWithEstimates) -> FootprintRecord {
        FootprintRecord(day: day,
            inputs: FootprintInputs(usages: [CategoryUsage(category: .video)], brightness: 0.5, gpsHours: 0, bluetoothHours: 0),
            result: FootprintResult(totalKg: 0.01, appUsageKg: 0.01, displayKg: 0, backgroundKg: 0, categories: []),
            source: source, calculatedAt: Date(timeIntervalSince1970: 1_792_400_000),
            isCompleted: completed, garden: garden, baselineKg: nil)
    }

    // [01] Every garden keeps the same waiting status while today's automatic activity is unfinished.
    func testAutomaticPendingMessageRemainsForEveryGardenAndSavedPeriod() {
        for garden in gardens {
            for saved in [record(garden: garden), record(day: today, completed: false, garden: garden, source: .manual),
                          record(day: "2026-10-19", completed: false, garden: garden)] {
                let presentation = TodayPresentation(record: saved, today: today, usesAutomaticInput: true)
                XCTAssertTrue(presentation.showsPendingMessage, "Missing waiting message for \(garden) on \(saved.day)")
                XCTAssertNotNil(presentation.periodTitle)
            }
        }
    }

    // [02] A saved legacy entry for today is still readable, but it is not a completed automatic day.
    func testCurrentLegacyDateIsLabelledHonestlyForEveryGarden() {
        for garden in gardens {
            let saved = record(day: today, completed: false, garden: garden, source: .manual)
            let presentation = TodayPresentation(record: saved, today: today, usesAutomaticInput: true)
            XCTAssertEqual(presentation.periodTitle, "Saved today")
            XCTAssertTrue(presentation.showsPendingMessage)
        }
    }

    // [03] A completed older day keeps its own date label, independent of whether the garden is lush or dry.
    func testCompletedPastDateIsLabelledForEveryGarden() {
        for garden in gardens {
            XCTAssertEqual(TodayPresentation(record: record(garden: garden), today: today,
                usesAutomaticInput: true).periodTitle, "Latest completed day")
        }
    }

    // [04] No saved day needs a waiting explanation; the older manual mode keeps its original current-day rule.
    func testEmptyAndManualStatesKeepTheirExistingWaitingRules() {
        let empty = TodayPresentation(record: nil, today: today, usesAutomaticInput: false)
        XCTAssertTrue(empty.showsPendingMessage)
        XCTAssertNil(empty.periodTitle)
        XCTAssertFalse(TodayPresentation(record: record(day: today, completed: false, garden: .stable, source: .manual),
            today: today, usesAutomaticInput: false).showsPendingMessage)
        XCTAssertTrue(TodayPresentation(record: record(garden: .stable), today: today,
            usesAutomaticInput: false).showsPendingMessage)
    }

    // [05] A clock correction must not turn a saved future or incomplete day into a completed result.
    func testFutureAndIncompleteDatesAreNotPresentedAsCompleted() {
        for garden in gardens {
            XCTAssertEqual(TodayPresentation(record: record(day: "2026-10-21", garden: garden),
                today: today, usesAutomaticInput: true).periodTitle, "Saved day")
            XCTAssertEqual(TodayPresentation(record: record(completed: false, garden: garden),
                today: today, usesAutomaticInput: true).periodTitle, "Saved day")
            XCTAssertEqual(TodayPresentation(record: record(day: today, garden: garden),
                today: today, usesAutomaticInput: true).periodTitle, "Saved today")
        }
    }
}
