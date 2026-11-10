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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import XCTest
@testable import DFE

@MainActor
final class WidgetPendingPublicationTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-07T09:00:00Z")!

    private func pendingFixture() throws -> (URL, FootprintRecord) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let inputs = FootprintInputs(usages: [CategoryUsage(category: .video, gigabytesPerHour: 0.5)],
            brightness: 0.5, gpsHours: 0, bluetoothHours: 0)
        var archive = FootprintArchive(firstDay: "2026-11-04",
            revisions: [RoutineRevision(effectiveDay: "2026-11-04", savedAt: now, inputs: inputs)], records: [])
        archive.inputPreference = .automatic
        archive.automaticStartDay = "2026-11-04"
        let exchange = WidgetAutomaticExchange(directory: folder)
        try exchange.publishContext(from: archive, enabled: true, calendar: calendar,
            classificationRevision: "fixture", now: now)
        let request = try XCTUnwrap(exchange.contextForYesterday(now: now, calendar: calendar))
        var measured = inputs
        measured.usages[0].minutes = 30
        measured.calendarDayMinutes = 1440
        let result = FootprintResult(totalKg: 0.012, appUsageKg: 0.012, displayKg: 0, backgroundKg: 0,
            categories: [CategoryFootprint(category: .video, totalKg: 0.012,
                deviceKg: 0.004, networkKg: 0.004, backendKg: 0.004)])
        let record = FootprintRecord(day: request.day, inputs: measured, result: result,
            source: .screenTimeWithEstimates, calculatedAt: now, isCompleted: true,
            garden: .stable, baselineKg: nil, automaticCategories: [.video])
        XCTAssertTrue(try exchange.commit(record, expected: request, at: now, calendar: calendar))
        return (folder, record)
    }

    // [01] Opening an older private archive must not push the widget back to the previous day.
    func testAnOlderHostPublicationKeepsTheDurableWidgetDay() throws {
        let (folder, record) = try pendingFixture()
        let publisher = FootprintWidgetPublisher(storage: WidgetSnapshotStorage(directory: folder), reload: {})
        let older = GardenWidgetSnapshot(day: "2026-11-05", totalKg: 0.008, garden: .stable,
            source: .screenTimeWithEstimates, calculatedAt: now.addingTimeInterval(-86_400), isCompleted: true)
        try publisher.publish(older)
        XCTAssertEqual(WidgetSnapshotStorage(directory: folder).read().snapshot, GardenWidgetSnapshot(record: record))
        XCTAssertEqual(publisher.verification?.day, record.day)
    }

    // [02] A person's earlier manual correction has priority over an automatic result for the same date.
    func testAManualResultKeepsPriorityForTheSameDay() throws {
        let (folder, record) = try pendingFixture()
        let publisher = FootprintWidgetPublisher(storage: WidgetSnapshotStorage(directory: folder), reload: {})
        let manual = GardenWidgetSnapshot(day: record.day, totalKg: 0.007, garden: .stable,
            source: .manual, calculatedAt: now.addingTimeInterval(-10), isCompleted: true)
        try publisher.publish(manual)
        XCTAssertEqual(WidgetSnapshotStorage(directory: folder).read().snapshot, manual)
        let exchange = WidgetAutomaticExchange(directory: folder)
        XCTAssertEqual(try exchange.recoverPendingSnapshot(now: now.addingTimeInterval(86_400)), manual)
        XCTAssertEqual(WidgetSnapshotStorage(directory: folder).read().snapshot, manual)
    }

    // [03] If the shared handoff is damaged, keep the last picture instead of overwriting it blindly.
    func testAnUnreadableMailboxDoesNotReplaceTheLastValidSnapshot() throws {
        let (folder, record) = try pendingFixture()
        try Data("damaged".utf8).write(to: folder.appendingPathComponent(WidgetAutomaticExchange.fileName))
        let publisher = FootprintWidgetPublisher(storage: WidgetSnapshotStorage(directory: folder), reload: {})
        XCTAssertThrowsError(try publisher.publish(nil))
        XCTAssertEqual(WidgetSnapshotStorage(directory: folder).read().snapshot, GardenWidgetSnapshot(record: record))
    }
}
