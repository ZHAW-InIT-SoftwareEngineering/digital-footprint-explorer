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

// [01] Refresh connects history, the widget and morning notices; these examples keep that work in
// disposable data

import XCTest
@testable import DFE

private final class AppRefreshCalculator: FootprintCalculating {
    var calls = 0

    func calculate(_ inputs: FootprintInputs) throws -> FootprintResult {
        calls += 1
        let total = inputs.totalMinutes / 1_000
        return FootprintResult(totalKg: total, appUsageKg: total, displayKg: 0, backgroundKg: 0, categories: [])
    }
}

private final class AppRefreshWidgetPublisher: WidgetSnapshotPublishing {
    var snapshots: [GardenWidgetSnapshot?] = []

    func publish(_ snapshot: GardenWidgetSnapshot?) throws {
        snapshots.append(snapshot)
    }
}

@MainActor
final class AppRefreshTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return calendar
    }

    private func historyURL() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("history.json")
    }

    private func screenTime() -> ScreenTimeService {
        let suite = "dfe.app-refresh-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return ScreenTimeService(defaults: defaults)
    }

    private func inputs(_ minutes: Double) -> FootprintInputs {
        FootprintInputs(usages: [CategoryUsage(category: .video, minutes: minutes, gigabytesPerHour: 1, wifiShare: 0.8)],
                        brightness: 0.5, gpsHours: 0, bluetoothHours: 0)
    }

    // [02] An abandoned refresh should stop before it reads or changes history. A later pull can
    // try again.
    func testCancelledForegroundWorkThrowsBeforeReloadOrImport() async throws {
        let calculator = AppRefreshCalculator()
        let publisher = AppRefreshWidgetPublisher()
        let store = FootprintStore(fileURL: historyURL(), calculator: calculator, calendar: calendar, widgetPublisher: publisher)
        let now = ISO8601DateFormatter().date(from: "2026-10-07T10:00:00Z")!
        try store.saveProfile(inputs(60), now: now)
        let savedArchive = store.archive
        let calculationCount = calculator.calls
        publisher.snapshots.removeAll()
        // [03] A reload would expose this damaged file, so cancellation must stop first.
        let damagedFile = Data("damaged archive".utf8)
        try damagedFile.write(to: store.fileURL)
        let service = screenTime()
        XCTAssertFalse(service.hasSavedAutomaticSetup(store: store))
        let services = AppServices(store: store, screenTime: service)

        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try await services.performRefresh(trigger: .pullToRefresh)
        }
        do {
            try await task.value
            XCTFail("Cancelled foreground work must reach the refresh coordinator as cancellation")
        } catch is CancellationError {
            // [04] Another person-requested pull is still waiting, so it should get its own chance
            // to finish.
        }

        XCTAssertEqual(store.archive, savedArchive)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(calculator.calls, calculationCount)
        XCTAssertTrue(publisher.snapshots.isEmpty)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), damagedFile)
    }

    // [05] A screen can be out of date even when the file is current, so refresh must read the
    // saved result again.
    func testForegroundRefreshReloadsSavedHistoryWithoutCreatingAnImport() async throws {
        let calculator = AppRefreshCalculator()
        let publisher = AppRefreshWidgetPublisher()
        let store = FootprintStore(fileURL: historyURL(), calculator: calculator, calendar: calendar, widgetPublisher: publisher)
        let now = ISO8601DateFormatter().date(from: "2026-10-07T10:00:00Z")!
        try store.saveProfile(inputs(60), now: now)
        let originalArchive = store.archive
        // [06] Another store represents a committed update that this screen has not read yet.
        let writer = FootprintStore(fileURL: store.fileURL, calculator: AppRefreshCalculator(), calendar: calendar)
        try writer.saveDay("2026-10-07", inputs: inputs(90), now: now)
        XCTAssertNotEqual(originalArchive, writer.archive)
        let savedFile = try Data(contentsOf: store.fileURL)
        let calculationCount = calculator.calls
        publisher.snapshots.removeAll()
        let service = screenTime()
        XCTAssertFalse(service.hasSavedAutomaticSetup(store: store))
        let services = AppServices(store: store, screenTime: service)

        try await services.performRefresh(trigger: .pullToRefresh)

        XCTAssertEqual(store.archive, writer.archive)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.usesAutomaticInput)
        XCTAssertEqual(calculator.calls, calculationCount)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), savedFile)
        XCTAssertEqual(publisher.snapshots, [GardenWidgetSnapshot(record: try XCTUnwrap(writer.latest))])
    }

    // [07] Without valid access, yesterday stays pending. An older garden is better than a made-up
    // new result.
    func testBlockedAutomaticRefreshKeepsEarlierDayAndWidgetWithoutInventingInput() async throws {
        for boundary in [nil, "not-a-date"] {
            let calculator = AppRefreshCalculator()
            let publisher = AppRefreshWidgetPublisher()
            let store = FootprintStore(fileURL: historyURL(), calculator: calculator,
                calendar: calendar, widgetPublisher: publisher)
            let first = ISO8601DateFormatter().date(from: "2026-10-07T10:00:00Z")!
            let next = ISO8601DateFormatter().date(from: "2026-10-08T10:00:00Z")!
            let later = ISO8601DateFormatter().date(from: "2026-10-10T10:00:00Z")!
            try store.saveAutomaticProfile(inputs(0), now: first)
            try store.importAutomaticUsage(day: first, minutesByCategory: ["VIDEO_STREAMING": 20], now: next)
            let suite = "dfe.blocked-refresh-tests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            if let boundary {
                defaults.set(ScreenTimeActivityScope.allAuthorizedApps.rawValue,
                    forKey: "dfe.screenTime.activityScope.v1")
                defaults.set(boundary, forKey: "dfe.screenTime.allActivityStartDay.v1")
            }
            let service = ScreenTimeService(defaults: defaults)
            let saved = store.archive
            let bytes = try Data(contentsOf: store.fileURL)
            let calculationCount = calculator.calls
            publisher.snapshots.removeAll()

            // [08] An older access choice or broken start date must stop before any real activity
            // is requested.
            let result = try await service.refreshAutomaticDays(store: store, now: later)

            XCTAssertEqual(result.outcome, .noAccess)
            XCTAssertFalse(result.completedWithoutFatalError)
            XCTAssertEqual(result.attemptedDays, 0)
            XCTAssertEqual(result.importedDays, 0)
            XCTAssertEqual(result.newRecords, 0)
            XCTAssertEqual(store.archive, saved)
            XCTAssertEqual(try Data(contentsOf: store.fileURL), bytes)
            XCTAssertEqual(calculator.calls, calculationCount)
            XCTAssertTrue(publisher.snapshots.isEmpty)
            XCTAssertFalse(service.isImporting)
            XCTAssertNil(service.lastImportDate)
            XCTAssertEqual(defaults.string(forKey: "dfe.screenTime.allActivityStartDay.v1"), boundary)
        }
    }

    // [09] An inactive automatic setup must not quietly change older manual history or the widget.
    func testInactiveAutomaticRefreshDoesNotChangeManualHistoryOrWidget() async throws {
        let calculator = AppRefreshCalculator()
        let publisher = AppRefreshWidgetPublisher()
        let store = FootprintStore(fileURL: historyURL(), calculator: calculator,
            calendar: calendar, widgetPublisher: publisher)
        let now = ISO8601DateFormatter().date(from: "2026-10-07T10:00:00Z")!
        try store.saveProfile(inputs(60), now: now)
        let saved = store.archive
        let bytes = try Data(contentsOf: store.fileURL)
        let calculationCount = calculator.calls
        publisher.snapshots.removeAll()

        let result = try await screenTime().refreshAutomaticDays(store: store, now: now.addingTimeInterval(172_800))

        XCTAssertEqual(result, ScreenTimeRefreshResult())
        XCTAssertEqual(store.archive, saved)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), bytes)
        XCTAssertEqual(calculator.calls, calculationCount)
        XCTAssertTrue(publisher.snapshots.isEmpty)
    }

    // [10] Reopening the app must keep unavailable days empty rather than filling them with
    // guessed activity.
    func testForegroundRefreshPreservesBlockedAutomaticHistoryAndMissingDays() async throws {
        let calculator = AppRefreshCalculator()
        let publisher = AppRefreshWidgetPublisher()
        let store = FootprintStore(fileURL: historyURL(), calculator: calculator,
            calendar: calendar, widgetPublisher: publisher)
        let first = ISO8601DateFormatter().date(from: "2026-10-07T10:00:00Z")!
        let next = ISO8601DateFormatter().date(from: "2026-10-08T10:00:00Z")!
        try store.saveAutomaticProfile(inputs(0), now: first)
        try store.importAutomaticUsage(day: first, minutesByCategory: ["VIDEO_STREAMING": 20], now: next)
        let service = screenTime()
        XCTAssertFalse(service.hasSavedAutomaticSetup(store: store))
        let savedBytes = try Data(contentsOf: store.fileURL)
        let calculationCount = calculator.calls
        // [11] Read the saved file first so the comparison uses the time format that history
        // actually keeps.
        try store.reload()
        let saved = store.archive
        publisher.snapshots.removeAll()
        let services = AppServices(store: store, screenTime: service)

        try await services.performRefresh(trigger: .pullToRefresh)

        XCTAssertEqual(store.archive, saved)
        XCTAssertEqual(store.records.map(\.day), ["2026-10-07"])
        XCTAssertEqual(try Data(contentsOf: store.fileURL), savedBytes)
        XCTAssertEqual(calculator.calls, calculationCount)
        XCTAssertNil(store.errorMessage)
        XCTAssertNil(service.lastImportDate)
        XCTAssertEqual(publisher.snapshots, [GardenWidgetSnapshot(record: try XCTUnwrap(store.latest))])
    }

    // [12] One unavailable older day should not hide a valid result that was just saved for
    // yesterday.
    func testPendingOlderDayDoesNotHideAFreshlyCommittedLatestDay() async throws {
        let store = FootprintStore(fileURL: historyURL(), calculator: AppRefreshCalculator(), calendar: calendar)
        let start = ISO8601DateFormatter().date(from: "2026-10-19T10:00:00Z")!
        let now = ISO8601DateFormatter().date(from: "2026-10-21T07:00:00Z")!
        try store.saveAutomaticProfile(inputs(0), now: start)
        let result = try await ScreenTimeCompletedDayImporter.run(start: calendar.startOfDay(for: start),
            today: calendar.startOfDay(for: now), calendar: calendar, shouldImport: { _ in true },
            importDay: { day in
                if store.dayKey(for: day) == "2026-10-19" { throw ScreenTimeImportError.noData }
                try store.importAutomaticUsage(day: day, minutesByCategory: ["VIDEO_STREAMING": 20], now: now)
                return ScreenTimeDayImportReceipt(day: day, created: true)
            }, onError: { error in ScreenTimeImportPolicy.shouldContinue(after: error) ? .pending : .error })

        XCTAssertEqual(result.pendingDays, 1)
        XCTAssertEqual(result.importedDays, 1)
        XCTAssertTrue(result.completedWithoutFatalError)
        XCTAssertTrue(result.latestCompletedDayRefreshed)
        XCTAssertEqual(store.records.map(\.day), ["2026-10-20"])
        XCTAssertEqual(try XCTUnwrap(store.latest).inputs.totalMinutes, 20)
        XCTAssertNotNil(DailyGardenNotificationPlan.make(records: store.records, automaticAccessReady: true,
            now: now, recordCalendar: calendar, deliveryCalendar: calendar))
    }

    // [13] A saved result alone does not prove today's import worked, so it cannot trigger another
    // morning notice.
    func testMissingLatestOrFatalRefreshCannotSendAnOldSavedYesterdayAgain() async throws {
        let store = FootprintStore(fileURL: historyURL(), calculator: AppRefreshCalculator(), calendar: calendar)
        let start = ISO8601DateFormatter().date(from: "2026-10-19T10:00:00Z")!
        let yesterday = ISO8601DateFormatter().date(from: "2026-10-20T10:00:00Z")!
        let now = ISO8601DateFormatter().date(from: "2026-10-21T07:00:00Z")!
        try store.saveAutomaticProfile(inputs(0), now: start)
        try store.importAutomaticUsage(day: yesterday, minutesByCategory: ["VIDEO_STREAMING": 60], now: now)
        let result = try await ScreenTimeCompletedDayImporter.run(start: calendar.startOfDay(for: start),
            today: calendar.startOfDay(for: now), calendar: calendar, shouldImport: { _ in true },
            importDay: { day in
                if store.dayKey(for: day) == "2026-10-20" { throw ScreenTimeImportError.noData }
                try store.importAutomaticUsage(day: day, minutesByCategory: ["VIDEO_STREAMING": 20], now: now)
                return ScreenTimeDayImportReceipt(day: day, created: true)
            }, onError: { error in ScreenTimeImportPolicy.shouldContinue(after: error) ? .pending : .error })

        XCTAssertEqual(result.importedDays, 1)
        XCTAssertEqual(result.pendingDays, 1)
        XCTAssertFalse(result.latestCompletedDayRefreshed)
        XCTAssertEqual(store.records.first(where: { $0.day == "2026-10-20" })?.inputs.totalMinutes, 60)
        // [14] The old day looks ready, but only a fresh successful import may make it eligible
        // for a notice.
        XCTAssertNotNil(DailyGardenNotificationPlan.make(records: store.records, automaticAccessReady: true,
            now: now, recordCalendar: calendar, deliveryCalendar: calendar))

        let bytes = try Data(contentsOf: store.fileURL)
        let fatal = try await ScreenTimeCompletedDayImporter.run(start: calendar.startOfDay(for: start),
            today: calendar.startOfDay(for: now), calendar: calendar, shouldImport: { _ in true },
            importDay: { _ in throw FootprintError.damagedArchive }, onError: { _ in .error })
        XCTAssertFalse(fatal.completedWithoutFatalError)
        XCTAssertFalse(fatal.latestCompletedDayRefreshed)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), bytes)
    }

}
