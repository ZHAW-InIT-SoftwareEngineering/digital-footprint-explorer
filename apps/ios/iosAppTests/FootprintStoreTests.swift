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

// [01] Daily results should save safely and use the same shared calculation as the Android
// reference

import XCTest
import Shared
@testable import DFE

// [02] Known test totals make it easier to see a failed save or an incorrect recent-day
// comparison.
private final class ControlledCalculator: FootprintCalculating {
    var calls = 0
    var failAt: Int?
    func calculate(_ inputs: FootprintInputs) throws -> FootprintResult {
        calls += 1
        if calls == failAt { throw FootprintError.invalidResult }
        let total = inputs.totalMinutes / 1_000
        return FootprintResult(totalKg: total, appUsageKg: total, displayKg: 0, backgroundKg: 0, categories: [])
    }
}

final class FootprintStoreTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return value
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func inputs(_ minutes: Double = 60) -> FootprintInputs {
        FootprintInputs(usages: [CategoryUsage(category: .video, minutes: minutes, gigabytesPerHour: 1, wifiShare: 0.8)], brightness: 0.5, gpsHours: 0.25, bluetoothHours: 2)
    }
    @MainActor private func store(_ calculator: ControlledCalculator = ControlledCalculator()) -> FootprintStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        return FootprintStore(fileURL: url, calculator: calculator, calendar: calendar)
    }

    // [03] Opening the app after several days should fill permitted gaps once, without duplicating
    // them on reopening.
    @MainActor func testCatchUpAfterDelayedLaunchAndRelaunchIsIdempotent() async throws {
        let store = store()
        try store.saveProfile(inputs(), now: date("2026-10-07T10:00:00Z"))
        try store.catchUp(now: date("2026-10-11T10:00:00Z"))
        XCTAssertEqual(store.records.map(\.day), ["2026-10-07", "2026-10-08", "2026-10-09", "2026-10-10"])
        XCTAssertTrue(store.records.allSatisfy(\.isCompleted))
        XCTAssertEqual(store.records.last?.source, .routineEstimate)
        let old = store.archive
        try store.catchUp(now: date("2026-10-11T10:00:00Z"))
        XCTAssertEqual(store.archive, old)
        let reopened = FootprintStore(fileURL: store.fileURL, calculator: ControlledCalculator(), calendar: calendar)
        try reopened.catchUp(now: date("2026-10-11T10:00:00Z"))
        XCTAssertEqual(reopened.archive, old)
    }

    // [04] A new routine applies from its change date; it should not rewrite the meaning of
    // earlier missing days.
    @MainActor func testRoutineRevisionDoesNotChangeEarlierMissingDays() async throws {
        let store = store()
        try store.saveProfile(inputs(15), now: date("2026-10-07T10:00:00Z"))
        try store.saveProfile(inputs(120), now: date("2026-10-09T10:00:00Z"))
        try store.catchUp(now: date("2026-10-11T10:00:00Z"))
        XCTAssertEqual(store.records.map { $0.inputs.totalMinutes }, [15, 15, 120, 120])
    }

    // [05] If catch-up is cancelled, the original file stays usable and a later attempt can start
    // again.
    @MainActor func testCancelledCatchUpLeavesArchiveUntouchedAndCanResume() async throws {
        let store = store()
        try store.saveProfile(inputs(), now: date("2026-10-07T10:00:00Z"))
        let old = store.archive
        let file = try Data(contentsOf: store.fileURL)
        var checks = 0
        XCTAssertThrowsError(try store.catchUp(now: date("2026-10-11T10:00:00Z"), shouldCancel: { checks += 1; return checks > 2 }))
        XCTAssertEqual(store.archive, old)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), file)
        try store.catchUp(now: date("2026-10-11T10:00:00Z"))
        XCTAssertEqual(store.records.count, 4)
    }

    // [06] A failed calculation must not leave half of a catch-up saved as though the whole pass
    // succeeded.
    @MainActor func testCalculationFailureDuringCatchUpDoesNotCommitPartialDays() async throws {
        let calculator = ControlledCalculator()
        let store = store(calculator)
        try store.saveProfile(inputs(), now: date("2026-10-07T10:00:00Z"))
        let old = store.archive
        calculator.failAt = 3
        XCTAssertThrowsError(try store.catchUp(now: date("2026-10-11T10:00:00Z")))
        XCTAssertEqual(store.archive, old)
        calculator.failAt = nil
        try store.catchUp(now: date("2026-10-11T10:00:00Z"))
        XCTAssertEqual(store.records.count, 4)
    }

    // [07] An earlier explicit correction should not be silently replaced by an automatic import.
    @MainActor func testExplicitManualEditWinsOverScreenTimeImport() async throws {
        let store = store()
        try store.saveProfile(inputs(), now: date("2026-10-07T10:00:00Z"))
        try store.catchUp(now: date("2026-10-10T10:00:00Z"))
        try store.saveDay("2026-10-08", inputs: inputs(90), now: date("2026-10-10T10:00:00Z"))
        try store.importAutomaticUsage(day: date("2026-10-08T10:00:00Z"), minutesByCategory: ["VIDEO_STREAMING": 20], now: date("2026-10-10T10:00:00Z"))
        XCTAssertEqual(store.records.first { $0.day == "2026-10-08" }?.inputs.totalMinutes, 90)
        XCTAssertEqual(Set(store.records.map(\.day)).count, store.records.count)
        XCTAssertEqual(store.records.first { $0.day == "2026-10-09" }?.baselineKg, 0.075)
    }

    // [08] Measured zero should replace an older time assumption while keeping the other model
    // assumptions visible.
    @MainActor func testMeasuredZeroUsageReplacesRoutineAndOtherAssumptionsRemain() async throws {
        let store = store()
        try store.saveProfile(inputs(), now: date("2026-10-07T10:00:00Z"))
        let now = date("2026-10-09T10:00:00Z")
        try store.importAutomaticUsage(day: date("2026-10-08T10:00:00Z"), minutesByCategory: ["VIDEO_STREAMING": 0], now: now)
        let record = try XCTUnwrap(store.records.last)
        XCTAssertEqual(record.inputs.totalMinutes, 0)
        XCTAssertEqual(record.inputs.brightness, 0.5)
        XCTAssertEqual(record.inputs.usages.first?.gigabytesPerHour, 1)
        XCTAssertEqual(record.source, .screenTimeWithEstimates)
        XCTAssertThrowsError(try store.importAutomaticUsage(day: date("2026-10-08T10:00:00Z"), minutesByCategory: ["INVALID": 1], now: now))
    }

    // [09] Daily history follows local dates, including the shorter and longer days around clock
    // changes.
    @MainActor func testDayBoundariesAcrossDaylightSavingTime() async throws {
        let store = store()
        try store.saveProfile(inputs(), now: date("2026-03-28T11:00:00Z"))
        try store.catchUp(now: date("2026-03-31T10:00:00Z"))
        XCTAssertEqual(store.records.map(\.day), ["2026-03-28", "2026-03-29", "2026-03-30"])
        let days = FootprintCalendar(calendar: calendar)
        XCTAssertEqual(days.next("2026-10-25"), "2026-10-26")
        XCTAssertNil(days.date("2026-02-30"))
    }

    // [10] Keeping a damaged file gives recovery a chance; running setup must not destroy that
    // evidence.
    @MainActor func testCorruptArchiveIsPreservedAndCannotBeOverwrittenBySetup() async throws {
        let original = store()
        try original.saveProfile(inputs(), now: date("2026-10-07T10:00:00Z"))
        let corrupt = Data("broken archive".utf8)
        try corrupt.write(to: original.fileURL)
        let reopened = FootprintStore(fileURL: original.fileURL, calculator: ControlledCalculator(), calendar: calendar)
        XCTAssertNotNil(reopened.errorMessage)
        XCTAssertThrowsError(try reopened.saveProfile(inputs()))
        XCTAssertEqual(try Data(contentsOf: original.fileURL), corrupt)
        try reopened.deleteAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.fileURL.path))
        XCTAssertFalse(reopened.isConfigured)
    }

    // [11] An impossible future day or invalid input should be refused without losing the existing
    // history.
    @MainActor func testFutureDayAndInvalidInputAreRejectedWithoutLosingHistory() async throws {
        let store = store()
        let now = date("2026-10-07T10:00:00Z")
        try store.saveProfile(inputs(), now: now)
        let old = store.archive
        XCTAssertThrowsError(try store.saveDay("2026-10-08", inputs: inputs(), now: now))
        XCTAssertThrowsError(try store.saveDay("2026-10-07", inputs: inputs(1441), now: now))
        var duplicate = inputs()
        duplicate.usages.append(duplicate.usages[0])
        XCTAssertThrowsError(try duplicate.validate())
        XCTAssertThrowsError(try inputs(.nan).validate())
        XCTAssertEqual(store.archive, old)
    }

    // [12] The garden compares recent days fairly and still has a sensible result when the
    // baseline is zero.
    func testGardenUsesRollingBaselineAndHandlesZero() {
        XCTAssertEqual(FootprintGarden.state(total: 0, baseline: 0), .stable)
        XCTAssertEqual(FootprintGarden.state(total: 1, baseline: 0), .withered)
        XCTAssertEqual(FootprintGarden.state(total: 0.6, baseline: 1), .flourishing)
        XCTAssertEqual(FootprintGarden.state(total: 0.85, baseline: 1), .growing)
        XCTAssertEqual(FootprintGarden.state(total: 1.05, baseline: 1), .stable)
        XCTAssertEqual(FootprintGarden.state(total: 1.3, baseline: 1), .wilting)
        XCTAssertEqual(FootprintGarden.state(total: 1.5, baseline: 1), .withered)
    }

    // [13] An independent reference case checks that iOS reaches the existing shared calculation
    // correctly.
    func testSwiftCallsSharedAndroidModelWithIndependentReferenceFixture() throws {
        let result = try SharedFootprintCalculator().calculate(inputs())
        XCTAssertEqual(result.totalKg, 0.03251719658119658, accuracy: 1e-12)
        XCTAssertEqual(result.appUsageKg, 0.03249340854700855, accuracy: 1e-12)
        XCTAssertEqual(result.displayKg, 0.000013401709401709404, accuracy: 1e-12)
        XCTAssertEqual(result.backgroundKg, 0.000010386324786324786, accuracy: 1e-12)
        XCTAssertEqual(result.categories.first?.category, .video)
        XCTAssertEqual(try XCTUnwrap(result.categories.first).networkKg, 0.0072364, accuracy: 1e-12)
    }
}
