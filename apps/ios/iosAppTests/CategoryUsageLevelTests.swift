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

// [01] Category colors and labels should explain the day's available use without judging missing
// data

import XCTest
@testable import DFE

final class CategoryUsageLevelTests: XCTestCase {
    // [02] Shorter and longer use need readable labels as well as color, so the comparison remains
    // accessible.
    func testShortMiddleAndLongestCategoryTimesHaveReadableRelativeLabels() {
        let day = [10.0, 20, 30]
        XCTAssertEqual(CategoryUsageLevel(minutes: 10, dayMinutes: day).label, "Less use")
        XCTAssertEqual(CategoryUsageLevel(minutes: 20, dayMinutes: day).label, "Moderate use")
        XCTAssertEqual(CategoryUsageLevel(minutes: 30, dayMinutes: day).label, "More use")
    }

    // [03] The scale should explain this day's pattern, rather than suggest a fixed healthy daily
    // limit.
    func testComparisonsFollowTheDayRatherThanAFixedDailyLimit() {
        let first = [10.0, 20, 30]
        let scaled = first.map { $0 * 10 }
        for (minutes, longerMinutes) in zip(first, scaled) {
            XCTAssertEqual(CategoryUsageLevel(minutes: minutes, dayMinutes: first),
                           CategoryUsageLevel(minutes: longerMinutes, dayMinutes: scaled))
        }
        XCTAssertEqual(CategoryUsageLevel(minutes: 20, dayMinutes: [20]).band, .more)
        XCTAssertEqual(CategoryUsageLevel(minutes: 20, dayMinutes: [20, 90]).band, .less)
    }

    // [04] Missing time and measured zero tell different stories; the screen must not treat them
    // as the same.
    func testMissingTimeIsNotPresentedAsRecordedZero() {
        let zero = CategoryUsageLevel(minutes: 0, dayMinutes: [0, 30])
        XCTAssertEqual(zero.band, .noUse)
        XCTAssertEqual(zero.label, "No recorded use")
        XCTAssertEqual(zero.fraction, 0)
        let missingValues: [Double?] = [nil, .nan, .infinity, -1]
        for value in missingValues {
            let missing = CategoryUsageLevel(minutes: value, dayMinutes: [0, 30])
            XCTAssertEqual(missing.band, .unavailable)
            XCTAssertNil(missing.fraction)
        }
    }

    // [05] Broken time values must not stretch the scale or create a comparison the data cannot
    // support.
    func testInvalidComparisonTimesCannotDistortOrInventTheScale() {
        XCTAssertEqual(CategoryUsageLevel(minutes: 10, dayMinutes: [10, 30, .nan, .infinity, -5]).band, .less)
        XCTAssertEqual(CategoryUsageLevel(minutes: 0, dayMinutes: [0, .nan]).band, .noUse)
        XCTAssertEqual(CategoryUsageLevel(minutes: 10, dayMinutes: [0, .nan]).band, .unavailable)
        XCTAssertEqual(CategoryUsageLevel(minutes: 60, dayMinutes: [10, 30]).fraction, 1)
    }
}
