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

// [01] Both widgets should follow the latest saved garden, using a small daily summary rather than
// private app details

import XCTest
import SwiftUI
import WidgetKit
@testable import DFE

private final class WidgetTestCalculator: FootprintCalculating {
    var shouldFail = false
    func calculate(_ inputs: FootprintInputs) throws -> FootprintResult {
        if shouldFail { throw FootprintError.invalidResult }
        let total = inputs.totalMinutes / 1_000
        return FootprintResult(totalKg: total, appUsageKg: total, displayKg: 0, backgroundKg: 0, categories: [])
    }
}

private final class ClearFailingWidgetPublisher: WidgetSnapshotPublishing {
    func publish(_ snapshot: GardenWidgetSnapshot?) throws {
        if snapshot == nil { throw CocoaError(.fileWriteNoPermission) }
    }
}

@MainActor
final class WidgetSnapshotTests: XCTestCase {
    private func directory() -> URL {
        let result = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: result) }
        return result
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func inputs(_ minutes: Double) -> FootprintInputs {
        FootprintInputs(usages: [CategoryUsage(category: .video, minutes: minutes, gigabytesPerHour: 1, wifiShare: 0.8)], brightness: 0.5, gpsHours: 0, bluetoothHours: 0)
    }
    private func snapshot(_ total: Double = 0.06, day: String = "2026-10-07") -> GardenWidgetSnapshot {
        GardenWidgetSnapshot(day: day, totalKg: total, garden: .stable, source: .manual,
                             calculatedAt: date("2026-10-07T10:00:00Z"), isCompleted: false)
    }

    // [02] The shared summary should survive saving without exposing individual apps, and zero
    // must remain a real value.
    func testSnapshotRoundTripSharesOnlySavedAggregateAndPreservesZero() throws {
        let storage = WidgetSnapshotStorage(directory: directory())
        XCTAssertTrue(try storage.write(snapshot(0)))
        XCTAssertEqual(storage.read().snapshot, snapshot(0))
        let data = try Data(contentsOf: XCTUnwrap(storage.fileURL))
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let value = try XCTUnwrap(encoded["snapshot"] as? [String: Any])
        XCTAssertEqual(Set(value.keys), ["day", "totalKg", "garden", "source", "calculatedAt", "isCompleted"])
        XCTAssertEqual(value["source"] as? String, "manual")
    }

    // [03] Widgets need a reload when their content changes, without repeatedly asking iOS to
    // redraw the same result.
    func testPublisherReloadsOnlyWhenSavedContentChangesAndClearsData() throws {
        let storage = WidgetSnapshotStorage(directory: directory())
        var reloads = 0
        let publisher = FootprintWidgetPublisher(storage: storage, reload: { reloads += 1 })
        try publisher.publish(snapshot())
        try publisher.publish(snapshot())
        XCTAssertEqual(reloads, 1)
        try publisher.publish(nil)
        XCTAssertNil(storage.read().snapshot)
        if case .empty = storage.read() {} else { XCTFail("Deleted data must become an empty widget") }
        XCTAssertEqual(reloads, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(storage.fileURL).path))
        try publisher.publish(nil)
        XCTAssertEqual(reloads, 2)
    }

    // [17] Checking the same day again updates its saved time, but it should not spend another
    // widget refresh on the same garden. VoiceOver can still read the newer time from the file.
    func testPublisherSavesNewCheckTimeWithoutReloadingTheSameGarden() throws {
        let storage = WidgetSnapshotStorage(directory: directory())
        var reloads = 0
        let publisher = FootprintWidgetPublisher(storage: storage, reload: { reloads += 1 })
        let original = snapshot()
        let checkedAgain = GardenWidgetSnapshot(day: original.day, totalKg: original.totalKg,
            garden: original.garden, source: original.source,
            calculatedAt: date("2026-10-07T11:00:00Z"), isCompleted: original.isCompleted)

        try publisher.publish(original)
        try publisher.publish(checkedAgain)

        XCTAssertEqual(reloads, 1, "A later check alone does not change the garden")
        XCTAssertEqual(storage.read().snapshot, checkedAgain, "Keep the latest saved time for the next widget read")
        let zone = TimeZone(secondsFromGMT: 0)!
        let locale = Locale(identifier: "en_US")
        XCTAssertNotEqual(original.accessibilitySummary(on: checkedAgain.calculatedAt, timeZone: zone, locale: locale),
                          storage.read().snapshot?.accessibilitySummary(on: checkedAgain.calculatedAt, timeZone: zone, locale: locale))
    }

    // [18] Automatic imports can check yesterday more than once. The full save path must treat
    // unchanged usage like the same result, while a real correction still reaches both widgets.
    func testRepeatedAutomaticImportDoesNotReloadUntilItsSavedResultChanges() throws {
        let folder = directory()
        let storage = WidgetSnapshotStorage(directory: folder.appendingPathComponent("widget"))
        var reloads = 0
        let publisher = FootprintWidgetPublisher(storage: storage, reload: { reloads += 1 })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let store = FootprintStore(fileURL: folder.appendingPathComponent("history.json"),
                                  calculator: WidgetTestCalculator(), calendar: calendar, widgetPublisher: publisher)
        let day = date("2026-10-07T10:00:00Z")
        let firstCheck = date("2026-10-08T08:00:00Z")
        let laterCheck = date("2026-10-08T08:10:00Z")
        try store.saveAutomaticProfile(inputs(0), now: day)
        try store.importAutomaticUsage(day: day, minutesByCategory: [FootprintCategory.video.rawValue: 30], now: firstCheck)
        let first = try XCTUnwrap(storage.read().snapshot)
        XCTAssertEqual(reloads, 1)

        try store.importAutomaticUsage(day: day, minutesByCategory: [FootprintCategory.video.rawValue: 30], now: laterCheck)
        let repeated = try XCTUnwrap(storage.read().snapshot)
        XCTAssertEqual(repeated.totalKg, first.totalKg)
        XCTAssertEqual(repeated.garden, first.garden)
        XCTAssertEqual(repeated.calculatedAt, laterCheck)
        XCTAssertEqual(store.latest?.calculatedAt, laterCheck)
        XCTAssertEqual(reloads, 1, "An unchanged automatic import should keep its earlier reload request")

        try store.importAutomaticUsage(day: day, minutesByCategory: [FootprintCategory.video.rawValue: 40],
                                       now: date("2026-10-08T08:20:00Z"))
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(storage.read().snapshot, store.latest.map(GardenWidgetSnapshot.init(record:)))
    }

    // [19] A new date, amount, garden, source or completion changes the story the widget tells.
    // Check each part separately so one correct comparison cannot hide another missing one.
    func testPublisherReloadsForEveryMeaningfulGardenChange() throws {
        let original = snapshot()
        let changes: [(String, GardenWidgetSnapshot)] = [
            ("day", GardenWidgetSnapshot(day: "2026-10-08", totalKg: original.totalKg, garden: original.garden,
                source: original.source, calculatedAt: original.calculatedAt, isCompleted: original.isCompleted)),
            ("amount", GardenWidgetSnapshot(day: original.day, totalKg: 0.08, garden: original.garden,
                source: original.source, calculatedAt: original.calculatedAt, isCompleted: original.isCompleted)),
            ("garden", GardenWidgetSnapshot(day: original.day, totalKg: original.totalKg, garden: .growing,
                source: original.source, calculatedAt: original.calculatedAt, isCompleted: original.isCompleted)),
            ("source", GardenWidgetSnapshot(day: original.day, totalKg: original.totalKg, garden: original.garden,
                source: .screenTimeWithEstimates, calculatedAt: original.calculatedAt, isCompleted: original.isCompleted)),
            ("completion", GardenWidgetSnapshot(day: original.day, totalKg: original.totalKg, garden: original.garden,
                source: original.source, calculatedAt: original.calculatedAt, isCompleted: true))
        ]
        for (name, changed) in changes {
            let storage = WidgetSnapshotStorage(directory: directory())
            var reloads = 0
            let publisher = FootprintWidgetPublisher(storage: storage, reload: { reloads += 1 })
            try publisher.publish(original)
            try publisher.publish(changed)
            XCTAssertEqual(reloads, 2, "A changed \(name) needs a new widget timeline")
            XCTAssertEqual(storage.read().snapshot, changed)
        }
    }

    // [20] A summary can disappear or become unreadable between checks. Repairing it needs a
    // reload even when the app's result has not changed since the last successful save.
    func testPublisherReloadsAfterRepairingAMissingOrDamagedSummary() throws {
        let storage = WidgetSnapshotStorage(directory: directory())
        var reloads = 0
        let publisher = FootprintWidgetPublisher(storage: storage, reload: { reloads += 1 })
        let value = snapshot()
        try publisher.publish(value)
        let file = try XCTUnwrap(storage.fileURL)
        try FileManager.default.removeItem(at: file)
        try publisher.publish(value)
        XCTAssertEqual(reloads, 2)
        try Data("damaged summary".utf8).write(to: file)
        try publisher.publish(value)
        XCTAssertEqual(reloads, 3)
        XCTAssertEqual(storage.read().snapshot, value)
        try publisher.publish(value)
        XCTAssertEqual(reloads, 3)
    }

    // [04] A damaged or unfamiliar summary should stay hidden rather than show a convincing but
    // invalid footprint.
    func testInvalidDatesNonfiniteTotalsCorruptionAndNewVersionsAreNotDisplayed() throws {
        let storage = WidgetSnapshotStorage(directory: directory())
        XCTAssertThrowsError(try storage.write(snapshot(.nan)))
        XCTAssertThrowsError(try storage.write(snapshot(-1)))
        XCTAssertThrowsError(try storage.write(snapshot(day: "2026-02-30")))
        try FileManager.default.createDirectory(at: XCTUnwrap(storage.directory), withIntermediateDirectories: true)
        let url = try XCTUnwrap(storage.fileURL)
        try Data("invalid json".utf8).write(to: url)
        if case .unreadable = storage.read() {} else { XCTFail("Corrupt data cannot appear as a valid zero") }
        try Data("{\"version\":2,\"snapshot\":null}".utf8).write(to: url)
        if case .unreadable = storage.read() {} else { XCTFail("Newer formats must not be misread") }
    }

    // [05] Missing shared storage is not a zero-use day, so an empty widget must not invent an
    // estimate.
    func testMissingGroupAndEmptyStorageDoNotInventAnEstimate() throws {
        let unavailable = WidgetSnapshotStorage(directory: nil)
        XCTAssertFalse(try unavailable.write(snapshot()))
        if case .unavailable = unavailable.read() {} else { XCTFail("No container means unavailable") }
        let empty = WidgetSnapshotStorage(directory: directory())
        if case .empty = empty.read() {} else { XCTFail("A new widget has no saved estimate") }
    }

    // [06] Travel should not change a saved day's identity, and a stale garden should still show
    // its original date.
    func testSavedDayKeepsItsIdentityAcrossTimeZonesAndBecomesStaleAfterMidnight() throws {
        let value = snapshot()
        XCTAssertFalse(value.isStale(on: date("2026-10-07T21:59:00Z"), timeZone: TimeZone(identifier: "Europe/Zurich")!))
        XCTAssertTrue(value.isStale(on: date("2026-10-07T22:01:00Z"), timeZone: TimeZone(identifier: "Europe/Zurich")!))
        XCTAssertFalse(value.isStale(on: date("2026-10-07T22:01:00Z"), timeZone: TimeZone(identifier: "America/Los_Angeles")!))
        // [07] A clock rollback keeps the original date; a future saved day is not today.
        XCTAssertFalse(value.isStale(on: date("2026-10-06T10:00:00Z"), timeZone: TimeZone(secondsFromGMT: 0)!))
        XCTAssertEqual(value.day, "2026-10-07")
        XCTAssertNotNil(value.dayDate)
    }

    // [08] Every successful history change should publish the newest saved garden, including after
    // an older edit.
    func testStoreCommitCatchUpAndHistoricalEditPublishItsLatestSavedGarden() throws {
        let folder = directory()
        let storage = WidgetSnapshotStorage(directory: folder.appendingPathComponent("widget"))
        let publisher = FootprintWidgetPublisher(storage: storage, reload: {})
        let store = FootprintStore(fileURL: folder.appendingPathComponent("history.json"), calculator: WidgetTestCalculator(), widgetPublisher: publisher)
        try store.saveProfile(inputs(60), now: date("2026-10-07T10:00:00Z"))
        XCTAssertEqual(storage.read().snapshot?.source, .manual)
        try store.catchUp(now: date("2026-10-10T10:00:00Z"))
        XCTAssertEqual(storage.read().snapshot?.day, "2026-10-09")
        XCTAssertEqual(storage.read().snapshot?.source, .routineEstimate)
        XCTAssertEqual(storage.read().snapshot?.isCompleted, true)
        try store.saveDay("2026-10-08", inputs: inputs(0), now: date("2026-10-10T10:00:00Z"))
        let latest = try XCTUnwrap(store.latest)
        XCTAssertEqual(storage.read().snapshot, GardenWidgetSnapshot(record: latest))
        XCTAssertEqual(latest.garden, .withered)
    }

    // [09] Reopening should restore the widget summary, while deleting history must leave
    // unrelated files untouched.
    func testReloadRestoresSnapshotAndDeleteClearsItWithoutErasingOtherFiles() throws {
        let folder = directory()
        let storage = WidgetSnapshotStorage(directory: folder.appendingPathComponent("widget"))
        let publisher = FootprintWidgetPublisher(storage: storage, reload: {})
        let url = folder.appendingPathComponent("history.json")
        let store = FootprintStore(fileURL: url, calculator: WidgetTestCalculator(), widgetPublisher: publisher)
        try store.saveProfile(inputs(0), now: date("2026-10-07T10:00:00Z"))
        try publisher.publish(nil)
        let reopened = FootprintStore(fileURL: url, calculator: WidgetTestCalculator(), widgetPublisher: publisher)
        XCTAssertEqual(storage.read().snapshot?.totalKg, 0)
        try reopened.deleteAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        if case .empty = storage.read() {} else { XCTFail("A deletion must clear shared data") }
    }

    // [10] A calculation failure keeps the last valid garden, but a damaged source file cannot
    // support a derived summary.
    func testFailedCalculationKeepsPreviousWidgetAndCorruptArchiveClearsDerivedSnapshot() throws {
        let folder = directory()
        let storage = WidgetSnapshotStorage(directory: folder.appendingPathComponent("widget"))
        let calculator = WidgetTestCalculator()
        let publisher = FootprintWidgetPublisher(storage: storage, reload: {})
        let url = folder.appendingPathComponent("history.json")
        let store = FootprintStore(fileURL: url, calculator: calculator, widgetPublisher: publisher)
        try store.saveProfile(inputs(60), now: date("2026-10-07T10:00:00Z"))
        let old = storage.read().snapshot
        calculator.shouldFail = true
        XCTAssertThrowsError(try store.saveDay("2026-10-07", inputs: inputs(120), now: date("2026-10-07T11:00:00Z")))
        XCTAssertEqual(storage.read().snapshot, old)
        try Data("broken archive".utf8).write(to: url)
        XCTAssertThrowsError(try store.reload())
        XCTAssertNil(storage.read().snapshot)
        XCTAssertEqual(try Data(contentsOf: url), Data("broken archive".utf8))
    }

    // [11] A widget save can fail separately; it must not undo daily history that was already
    // saved successfully.
    func testWidgetWriteFailureDoesNotRollBackACommittedArchive() throws {
        let folder = directory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let obstruction = folder.appendingPathComponent("not-a-directory")
        try Data("keep".utf8).write(to: obstruction)
        let publisher = FootprintWidgetPublisher(storage: WidgetSnapshotStorage(directory: obstruction), reload: {})
        let url = folder.appendingPathComponent("history.json")
        let store = FootprintStore(fileURL: url, calculator: WidgetTestCalculator(), widgetPublisher: publisher)
        try store.saveProfile(inputs(60), now: date("2026-10-07T10:00:00Z"))
        XCTAssertEqual(store.latest?.result.totalKg, 0.06)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(store.errorMessage)
        let reopened = FootprintStore(fileURL: url, calculator: WidgetTestCalculator(),
                                      widgetPublisher: ClearFailingWidgetPublisher())
        let oldArchive = reopened.archive
        let oldData = try Data(contentsOf: url)
        XCTAssertThrowsError(try reopened.deleteAll())
        XCTAssertEqual(reopened.archive, oldArchive)
        XCTAssertEqual(try Data(contentsOf: url), oldData)
    }

    // [12] Both widget sizes need honest empty and zero states, with rendered examples for visual
    // review.
    func testSharedWidgetViewRendersBothFamiliesAndHonestEmptyZeroStates() throws {
        let now = date("2026-10-07T10:00:00Z")
        let completed = GardenWidgetSnapshot(day: "2026-10-07", totalKg: 0.06, garden: .flourishing,
                                             source: .screenTimeWithEstimates, calculatedAt: now, isCompleted: true)
        let stale = GardenWidgetSnapshot(day: "2026-10-06", totalKg: 0.013 / 1_000, garden: .withered,
                                        source: .routineEstimate, calculatedAt: now, isCompleted: true)
        var samples: [(String, WidgetSnapshotReadResult, ColorScheme, WidgetRenderingMode, DynamicTypeSize)] = [
            ("light", .saved(snapshot()), .light, .fullColor, .large),
            ("dark", .saved(snapshot()), .dark, .fullColor, .large),
            ("accented", .saved(completed), .light, .accented, .large),
            ("empty", .empty, .light, .fullColor, .large),
            ("unavailable", .unavailable, .light, .fullColor, .large),
            ("unreadable", .unreadable, .light, .fullColor, .large),
            ("zero", .saved(snapshot(0)), .light, .fullColor, .large),
            ("tiny positive", .saved(snapshot(0.013 / 1_000)), .light, .fullColor, .large),
            ("completed today", .saved(completed), .light, .fullColor, .large),
            ("last saved day", .saved(stale), .light, .fullColor, .large),
            ("XXX Large", .saved(completed), .light, .fullColor, .xxxLarge),
            ("AX3", .saved(completed), .light, .fullColor, .accessibility3),
            ("AX5", .saved(completed), .light, .fullColor, .accessibility5),
            ("AX5 last saved day", .saved(stale), .light, .fullColor, .accessibility5),
            ("AX5 empty", .empty, .light, .fullColor, .accessibility5),
            ("preview", .saved(.preview(on: now)), .light, .fullColor, .large),
            ("preview XXX Large", .saved(.preview(on: now)), .light, .fullColor, .xxxLarge),
            ("preview AX5", .saved(.preview(on: now)), .light, .fullColor, .accessibility5),
            ("privacy redaction", .saved(completed), .light, .fullColor, .large)
        ]
        for state in WidgetGardenState.allCases {
            let saved = GardenWidgetSnapshot(day: completed.day, totalKg: completed.totalKg, garden: state,
                                              source: completed.source, calculatedAt: now, isCompleted: true)
            for (name, mode) in [("full color", WidgetRenderingMode.fullColor),
                                 ("accented", .accented), ("vibrant", .vibrant)] {
                samples.append(("\(state.title) \(name)", .saved(saved), .light, mode, .large))
            }
        }
        for family in [WidgetFamily.systemSmall, .systemMedium] {
            let canvases: [(CGFloat, CGFloat)] = family == .systemSmall ? [(148, 148), (164, 164)] : [(321, 148), (360, 164)]
            for (width, height) in canvases {
              for (name, data, appearance, mode, typeSize) in samples {
                let view = GardenWidgetView(data: data, family: family, date: now, isPreview: name.hasPrefix("preview"))
                    .padding(16).frame(width: width, height: height)
                    .background(Color(uiColor: .systemBackground))
                    .environment(\.colorScheme, appearance)
                    .environment(\.widgetRenderingMode, mode)
                    .environment(\.dynamicTypeSize, typeSize)
                    .redacted(reason: name == "privacy redaction" ? .privacy : [])
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.uiImage)
                // [13] These attachments are for visual review; frame size alone cannot prove no clipping.
                let attachment = XCTAttachment(image: image)
                attachment.name = "Isolated widget \(family == .systemSmall ? "small" : "medium") \(Int(width))x\(Int(height)) pt \(name); synthetic saved input"
                attachment.lifetime = .keepAlways
                add(attachment)
              }
            }
        }
    }

    // [14] The widget should use the same garden art as Today, so its visual story matches the
    // saved estimate.
    func testPublishedGardenUsesTheAppArtworkForEveryEmissionState() throws {
        var artwork = Set<Data>()
        for total in [0.06, 0.08, 0.1, 0.12, 0.15] {
            let state = FootprintGarden.state(total: total, baseline: 0.1)
            let result = FootprintResult(totalKg: total, appUsageKg: total, displayKg: 0,
                                         backgroundKg: 0, categories: [])
            let record = FootprintRecord(day: "2026-10-07", inputs: inputs(60), result: result,
                                         source: .screenTimeWithEstimates, calculatedAt: date("2026-10-07T10:00:00Z"),
                                         isCompleted: true, garden: state, baselineKg: 0.1)
            let published = GardenWidgetSnapshot(record: record)
            let appImage = try XCTUnwrap(UIImage(named: GardenArtwork.imageName(for: record.garden)))
            let widgetImage = try XCTUnwrap(UIImage(named: published.garden.imageName))
            let appData = try XCTUnwrap(appImage.pngData())
            let widgetData = try XCTUnwrap(widgetImage.pngData())
            XCTAssertEqual(widgetData, appData, "The saved widget must show the same garden as Today")
            artwork.insert(widgetData)
        }
        XCTAssertEqual(artwork.count, WidgetGardenState.allCases.count,
                       "Each emission state must keep its own garden picture")
    }

    // [15] Small positive estimates must not look like zero, and the date must identify the day
    // the widget describes.
    func testPresentationKeepsSmallPositiveValuesAndDistinguishesTheSavedDay() {
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(snapshot(0).amountLabel(locale: locale), "0")
        XCTAssertEqual(snapshot(0.013 / 1_000).amountLabel(locale: locale), "0.013")
        XCTAssertEqual(snapshot(12.3456 / 1_000).amountLabel(locale: locale), "12.3")
        XCTAssertNotEqual(snapshot(0.0000001 / 1_000).amountLabel(locale: locale), "0")
        let value = snapshot()
        let zone = TimeZone(identifier: "Europe/Zurich")!
        XCTAssertEqual(value.statusLabel(on: date("2026-10-07T21:59:00Z"), timeZone: zone), "In progress")
        XCTAssertEqual(value.statusLabel(on: date("2026-10-07T22:01:00Z"), timeZone: zone), "Last saved day")
        XCTAssertFalse(value.isCurrentDay(on: date("2026-10-06T10:00:00Z"), timeZone: zone))
        let completed = GardenWidgetSnapshot(day: value.day, totalKg: value.totalKg, garden: value.garden,
                                             source: value.source, calculatedAt: value.calculatedAt, isCompleted: true)
        XCTAssertEqual(completed.statusLabel(on: date("2026-10-07T10:00:00Z"), timeZone: zone), "Completed day")
    }

    // [16] Someone using VoiceOver needs the date, unit and stale warning that a sighted person
    // can read.
    func testVoiceOverSummaryPreservesUnitDateSourceCompletionAndStaleWarning() {
        let value = GardenWidgetSnapshot(day: "2026-10-07", totalKg: 0.013 / 1_000, garden: .wilting,
                                        source: .screenTimeWithEstimates,
                                        calculatedAt: date("2026-10-07T10:00:00Z"), isCompleted: false)
        let summary = value.accessibilitySummary(on: date("2026-10-08T10:00:00Z"),
                                                 timeZone: TimeZone(secondsFromGMT: 0)!,
                                                 locale: Locale(identifier: "en_US"))
        XCTAssertTrue(summary.contains("Wilting"))
        XCTAssertTrue(summary.contains("0.013 grams of carbon dioxide equivalent"))
        XCTAssertTrue(summary.contains("October 7, 2026"))
        XCTAssertTrue(summary.contains("Day in progress"))
        XCTAssertTrue(summary.contains("Screen Time + estimates"))
        XCTAssertTrue(summary.contains("not today's estimate"))
        let currentSummary = value.accessibilitySummary(on: date("2026-10-07T10:00:00Z"),
                                                        timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertFalse(currentSummary.contains("not today's estimate"))
    }
}
