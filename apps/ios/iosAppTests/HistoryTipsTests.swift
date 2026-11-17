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

// [01] Useful advice starts with a valid completed estimate. When that evidence is missing, keep
// the advice general

import XCTest
@testable import DFE

final class HistoryTipsTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return value
    }

    private func record(day: String = "2026-10-20", completed: Bool = true,
                        total: Double = 1, categories: [CategoryFootprint],
                        usages: [CategoryUsage]? = nil) -> FootprintRecord {
        let inputs = FootprintInputs(usages: usages ?? categories.map {
            CategoryUsage(category: $0.category, minutes: 30, gigabytesPerHour: 1, wifiShare: 0.8)
        }, brightness: 0.5, gpsHours: 0, bluetoothHours: 0)
        return FootprintRecord(day: day, inputs: inputs,
            result: FootprintResult(totalKg: total, appUsageKg: total, displayKg: 0,
                                    backgroundKg: 0, categories: categories),
            source: .screenTimeWithEstimates, calculatedAt: Date(timeIntervalSince1970: 0),
            isCompleted: completed, garden: .stable, baselineKg: nil)
    }

    private func category(_ category: FootprintCategory, amount: Double) -> CategoryFootprint {
        CategoryFootprint(category: category, totalKg: amount, deviceKg: 0,
                          networkKg: amount, backendKg: 0)
    }

    // [02] Advice should match the latest completed day, not an older result or today's unfinished
    // activity.
    func testLatestCompletedDayWinsWithoutUsingAPendingOrOlderDay() {
        let older = record(day: "2026-10-18", categories: [category(.video, amount: 1)])
        let latest = record(categories: [category(.social, amount: 1)])
        let pending = record(day: "2026-10-21", completed: false, categories: [category(.gaming, amount: 1)])
        for records in [[pending, older, latest], [latest, pending, older]] {
            let tip = HistoryTipSelector.tip(records: records, calendar: calendar)
            XCTAssertEqual(tip.day, latest.day)
            XCTAssertEqual(tip.category, .social)
        }
    }

    // [03] The most useful footprint tip may concern a short but heavier category, rather than the
    // longest use.
    func testLargestEstimatedCategoryIsChosenRatherThanLongestUse() {
        let value = record(categories: [category(.social, amount: 0.1), category(.video, amount: 0.9)],
            usages: [CategoryUsage(category: .social, minutes: 90), CategoryUsage(category: .video, minutes: 5)])
        let tip = HistoryTipSelector.tip(records: [value], calendar: calendar)
        XCTAssertEqual(tip.category, .video)
        XCTAssertEqual(tip.day, value.day)
    }

    // [04] When two estimates match, reopening the screen should not randomly suggest a different
    // category.
    func testEqualEstimatesChooseTheSameCategoryRegardlessOfArrayOrder() {
        let audio = category(.audio, amount: 0.5)
        let video = category(.video, amount: 0.5)
        for categories in [[audio, video], [video, audio]] {
            XCTAssertEqual(HistoryTipSelector.tip(records: [record(categories: categories)], calendar: calendar).category,
                           .audio)
        }
    }

    // [05] Without a usable completed result, a general suggestion is more honest than
    // personalized advice.
    func testEmptyPendingZeroAndInvalidDatesKeepAdviceGeneral() {
        let video = category(.video, amount: 1)
        let cases: [[FootprintRecord]] = [[],
            [record(completed: false, categories: [video])],
            [record(total: 0, categories: [category(.video, amount: 0)])],
            [record(day: "2026-02-30", categories: [video])]]
        for records in cases {
            XCTAssertEqual(HistoryTipSelector.tip(records: records, calendar: calendar), HistoryTip(day: nil, category: nil))
        }
        for invalid in [Double.nan, .infinity, -1] {
            let value = record(total: invalid, categories: [video])
            XCTAssertNil(HistoryTipSelector.tip(records: [value], calendar: calendar).category)
        }
    }

    // [06] One broken category should not hide a different category that still supports a useful
    // tip.
    func testInvalidCategoryValuesAreSkippedWithoutHidingAValidCategory() {
        for invalid in [Double.nan, .infinity, -1, 0] {
            let value = record(categories: [category(.video, amount: invalid), category(.audio, amount: 0.2)])
            XCTAssertEqual(HistoryTipSelector.tip(records: [value], calendar: calendar).category, .audio)
        }
    }

    // [07] A category total without believable activity time is too weak a basis for a personal
    // recommendation.
    func testMissingOrUnusableDurationCannotSupportAPersonalizedTip() {
        let video = category(.video, amount: 1)
        let values: [[CategoryUsage]] = [[], [CategoryUsage(category: .audio, minutes: 30)]]
            + [Double.nan, .infinity, -1, 0, 1441].map { [CategoryUsage(category: .video, minutes: $0)] }
        for usages in values {
            let value = record(categories: [video], usages: usages)
            XCTAssertEqual(HistoryTipSelector.tip(records: [value], calendar: calendar), HistoryTip(day: nil, category: nil))
        }
    }
}
