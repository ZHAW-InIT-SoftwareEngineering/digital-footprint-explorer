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

private final class WidgetReconciliationCalculator: FootprintCalculating {
    var shouldFail = false
    func calculate(_ inputs: FootprintInputs) throws -> FootprintResult {
        if shouldFail { throw FootprintError.invalidResult }
        let total = inputs.totalMinutes / 1_000
        return FootprintResult(totalKg: total, appUsageKg: total, displayKg: 0,
            backgroundKg: 0, categories: [])
    }
}

@MainActor
final class WidgetHostReconciliationTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return value
    }
    private func fixture(enableWidget: Bool = true) throws -> (FootprintStore, WidgetAutomaticExchange, WidgetReconciliationCalculator, Date) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let exchange = WidgetAutomaticExchange(directory: folder.appendingPathComponent("group"))
        let calculator = WidgetReconciliationCalculator()
        let store = FootprintStore(fileURL: folder.appendingPathComponent("private/history.json"),
            calculator: calculator, calendar: calendar, automaticWidgetExchange: exchange,
            automaticWidgetReceiptDirectory: folder.appendingPathComponent("documents"))
        let now = Date()
        let begin = calendar.date(byAdding: .day, value: -3, to: calendar.startOfDay(for: now))!
        let inputs = FootprintInputs(usages: [CategoryUsage(category: .video, gigabytesPerHour: 1, wifiShare: 0.8)],
            brightness: 0.5, gpsHours: 0, bluetoothHours: 0)
        try store.saveAutomaticProfile(inputs, now: begin)
        if enableWidget {
            try store.configureWidgetAutomaticInput(enabled: true, earliestDay: store.dayKey(for: begin),
                allowResumingAfterWithdrawal: true)
        }
        return (store, exchange, calculator, now)
    }
    @discardableResult
    private func pending(_ exchange: WidgetAutomaticExchange, calculator: WidgetReconciliationCalculator,
                         now: Date, allowExistingAutomaticDay: Bool = false) throws -> WidgetAutomaticPendingRecord {
        let request = try XCTUnwrap(exchange.contextForYesterday(now: now, calendar: calendar,
            allowExistingAutomaticDay: allowExistingAutomaticDay))
        var inputs = request.inputs
        inputs.usages[0].minutes = 30
        inputs.calendarDayMinutes = request.interval.duration / 60
        let result = try calculator.calculate(inputs)
        let record = FootprintRecord(day: request.day, inputs: inputs, result: result,
            source: .screenTimeWithEstimates, calculatedAt: now, isCompleted: true,
            garden: .state(total: result.totalKg, baseline: request.baselineKg),
            baselineKg: request.baselineKg, automaticCategories: [.video])
        XCTAssertTrue(try exchange.commit(record, expected: request, at: now, calendar: calendar))
        return try XCTUnwrap(exchange.pendingRecords().first)
    }
    private func reopen(_ store: FootprintStore, exchange: WidgetAutomaticExchange,
                        calculator: WidgetReconciliationCalculator) -> FootprintStore {
        FootprintStore(fileURL: store.fileURL, calculator: calculator, calendar: calendar,
            automaticWidgetExchange: exchange)
    }

    // [16] Delete covers both the shared day check and its two support copies, even if an old task answers later.
    func testDeleteClearsWidgetAutomaticChecksAndTheirExactDocumentCopies() throws {
        #if DFE_WIDGET_AUTOMATIC_IMPORT
        let (store, exchange, calculator, now) = try fixture()
        let saved = try pending(exchange, calculator: calculator, now: now)
        let receipt = WidgetAutomaticReceipt(day: saved.record.day, queryStartedAt: now.addingTimeInterval(-1),
            finishedAt: now, savedAt: now, status: .pendingSaved, calculationSucceeded: true,
            pendingSaved: true, elapsedMillis: 1_000, error: nil)
        let checks = WidgetAutomaticReceiptStore(directory: exchange.directory)
        XCTAssertTrue(try checks.save(receipt))
        let documents = store.fileURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        for name in [WidgetAutomaticReceipt.fileName, WidgetAutomaticReceiptMirror.storageCheckFileName, "unrelated.txt"] {
            try Data("synthetic technical copy".utf8).write(to: documents.appendingPathComponent(name))
        }
        let reconciliation = store.fileURL.deletingPathExtension().appendingPathExtension("widget-import-reconciliation.json")
        try Data("[]".utf8).write(to: reconciliation)
        let storage = WidgetSnapshotStorage(directory: exchange.directory)
        for family in ["small", "medium"] {
            _ = try WidgetStorageVerificationStore(directory: exchange.directory)
                .recordTimelineRead(family: family, result: storage.read(), at: now, isPreview: false)
        }

        try store.deleteAll()

        XCTAssertNil(store.archive)
        XCTAssertTrue(try exchange.pendingRecords().isEmpty)
        XCTAssertTrue(try exchange.newQueriesAreBlocked())
        XCTAssertNil(try checks.latest())
        XCTAssertFalse(try checks.save(receipt))
        XCTAssertNil(try checks.latest())
        XCTAssertNil(storage.read().snapshot)
        XCTAssertTrue(WidgetStorageVerificationStore(directory: exchange.directory).timelineReads().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reconciliation.path))
        for name in [WidgetAutomaticReceipt.fileName, WidgetAutomaticReceiptMirror.storageCheckFileName] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: documents.appendingPathComponent(name).path))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: documents.appendingPathComponent("unrelated.txt").path))
        #else
        throw XCTSkip("The automatic widget route is not enabled in this build.")
        #endif
    }

    // [17] Missing shared-group access must not stop deletion of the app's own technical copies.
    func testDeleteWithoutSharedGroupStillRemovesOnlyItsDocumentChecks() throws {
        #if DFE_WIDGET_AUTOMATIC_IMPORT
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let documents = root.appendingPathComponent("documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        for name in [WidgetAutomaticReceipt.fileName, WidgetAutomaticReceiptMirror.storageCheckFileName, "unrelated.txt"] {
            try Data("synthetic technical copy".utf8).write(to: documents.appendingPathComponent(name))
        }
        let store = FootprintStore(fileURL: root.appendingPathComponent("history.json"),
            calculator: WidgetReconciliationCalculator(), automaticWidgetReceiptDirectory: documents)
        try store.deleteAll()
        for name in [WidgetAutomaticReceipt.fileName, WidgetAutomaticReceiptMirror.storageCheckFileName] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: documents.appendingPathComponent(name).path))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: documents.appendingPathComponent("unrelated.txt").path))
        #else
        throw XCTSkip("The automatic widget route is not enabled in this build.")
        #endif
    }

    // [19] Restarting automatic updates must not let an older query restore an erased result or note.
    func testDeleteWithSavedConsentResumesWidgetWithFreshTicketAndNoEarlierDays() throws {
        let (store, exchange, calculator, now) = try fixture()
        let consentDay = try XCTUnwrap(store.firstDay)
        let request = try XCTUnwrap(exchange.contextForYesterday(now: now, calendar: calendar))
        let saved = try pending(exchange, calculator: calculator, now: now)
        let receipt = WidgetAutomaticReceipt(day: saved.record.day, queryStartedAt: now.addingTimeInterval(-1),
            finishedAt: now, savedAt: now, status: .pendingSaved, calculationSucceeded: true,
            pendingSaved: true, elapsedMillis: 1_000, error: nil)
        let checks = WidgetAutomaticReceiptStore(directory: exchange.directory)
        XCTAssertTrue(try checks.save(receipt, contextEpoch: request.context.epoch))

        try store.deleteAll(keepingAutomaticConsentFrom: consentDay, widgetAccess: true, now: now)

        XCTAssertTrue(store.usesAutomaticInput)
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertTrue(try exchange.pendingRecords().isEmpty)
        XCTAssertNil(WidgetSnapshotStorage(directory: exchange.directory).read().snapshot)
        XCTAssertNil(try checks.latest())
        XCTAssertFalse(try exchange.newQueriesAreBlocked())
        let context = try XCTUnwrap(exchange.currentContext())
        XCTAssertNotEqual(context.epoch, request.context.epoch)
        XCTAssertEqual(context.configuration.eligibleStartDay, store.dayKey(for: now))
        XCTAssertNil(try exchange.contextForYesterday(now: now, calendar: calendar))
        XCTAssertFalse(try exchange.validateRequest(request, now: now, calendar: calendar))
        XCTAssertThrowsError(try exchange.commit(saved.record, expected: request, at: now, calendar: calendar))
        XCTAssertFalse(try checks.save(receipt, contextEpoch: request.context.epoch))
        XCTAssertNil(try checks.latest())

        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        let next = try XCTUnwrap(exchange.contextForYesterday(now: tomorrow, calendar: calendar))
        XCTAssertEqual(next.day, store.dayKey(for: now))
        XCTAssertNil(next.baselineKg)
    }

    // [20] An earlier withdrawal still takes priority even if Apple's status has yet to change.
    func testDeleteWithSavedConsentKeepsEarlierWidgetWithdrawal() throws {
        let (store, exchange, _, now) = try fixture()
        let consentDay = try XCTUnwrap(store.firstDay)
        try exchange.blockNewQueries()
        try store.deleteAll(keepingAutomaticConsentFrom: consentDay, widgetAccess: true, now: now)

        XCTAssertTrue(store.usesAutomaticInput)
        XCTAssertTrue(try exchange.newQueriesAreBlocked())
        XCTAssertFalse(try exchange.currentContext()?.enabled ?? true)
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        XCTAssertNil(try exchange.contextForYesterday(now: tomorrow, calendar: calendar))
    }

    // [01] A widget day must enter private history before the app publishes that older history again.
    func testReopenMergesPendingBeforePublishingAndKeepsWidgetSaveTime() throws {
        let (store, exchange, calculator, now) = try fixture()
        let saved = try pending(exchange, calculator: calculator, now: now)
        let reopened = reopen(store, exchange: exchange, calculator: calculator)
        XCTAssertEqual(reopened.records.map(\.day), [saved.record.day])
        XCTAssertEqual(reopened.latest?.calculatedAt, saved.record.calculatedAt)
        XCTAssertEqual(reopened.latest?.result, saved.record.result)
        XCTAssertNil(reopened.latestVerifiedAutomaticSave)
        XCTAssertTrue(try exchange.pendingRecords().isEmpty)
        let receiptURL = store.fileURL.deletingPathExtension().appendingPathExtension("widget-import-reconciliation.json")
        let bytes = try Data(contentsOf: receiptURL)
        let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [[String: Any]])
        XCTAssertEqual(entries.first?["day"] as? String, saved.record.day)
        let formatter = ISO8601DateFormatter()
        XCTAssertEqual((entries.first?["widgetSavedAt"] as? String).flatMap(formatter.date), saved.originSavedAt)
        XCTAssertNotNil(entries.first?["hostReconciledAt"])
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("minutes"))
        try reopened.reload()
        XCTAssertEqual(reopened.records.count, 1)
    }

    // [02] A failed recheck must keep the durable handoff and the original private file for a later retry.
    func testCalculationFailureDoesNotAcknowledgeOrDamagePrivateHistory() throws {
        let (store, exchange, calculator, now) = try fixture()
        _ = try pending(exchange, calculator: calculator, now: now)
        let previous = try Data(contentsOf: store.fileURL)
        calculator.shouldFail = true
        let reopened = reopen(store, exchange: exchange, calculator: calculator)
        XCTAssertTrue(reopened.isConfigured)
        XCTAssertNotNil(reopened.errorMessage)
        XCTAssertTrue(reopened.records.isEmpty)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), previous)
        XCTAssertEqual(try exchange.pendingRecords().count, 1)
        calculator.shouldFail = false
        try reopened.reload()
        XCTAssertEqual(reopened.records.count, 1)
        XCTAssertTrue(try exchange.pendingRecords().isEmpty)
    }

    // [03] A person's saved correction wins over an automatic handoff for the same date.
    func testManualRecordWinsAndPendingReplayIsAcknowledged() throws {
        let (store, exchange, calculator, now) = try fixture()
        let saved = try pending(exchange, calculator: calculator, now: now)
        var manual = saved.record.inputs
        manual.usages[0].minutes = 10
        try store.saveDay(saved.record.day, inputs: manual, now: now)
        let reopened = reopen(store, exchange: exchange, calculator: calculator)
        XCTAssertEqual(reopened.latest?.source, .manual)
        XCTAssertEqual(reopened.latest?.inputs.totalMinutes, 10)
        XCTAssertTrue(try exchange.pendingRecords().isEmpty)
    }

    // [04] A new all-app opt-in cannot silently include days from an older selected-app routine.
    func testLaterAllAppConsentBoundaryPreventsEarlierWidgetImport() throws {
        let (store, exchange, _, now) = try fixture()
        try store.configureWidgetAutomaticInput(enabled: true, earliestDay: store.dayKey(for: now))
        XCTAssertNil(try exchange.contextForYesterday(now: now, calendar: calendar))
    }

    // [05] Disconnect stops a running old ticket, while a day already saved remains readable.
    func testSuspendingImportMergesCompletedWorkAndRejectsOldTicket() throws {
        let (store, exchange, calculator, now) = try fixture()
        let request = try XCTUnwrap(exchange.contextForYesterday(now: now, calendar: calendar))
        _ = try pending(exchange, calculator: calculator, now: now)
        try store.configureWidgetAutomaticInput(enabled: false)
        XCTAssertFalse(try XCTUnwrap(exchange.currentContext()).enabled)
        XCTAssertFalse(try exchange.validateRequest(request, now: now, calendar: calendar))
        XCTAssertEqual(store.records.count, 1)
        XCTAssertTrue(try exchange.pendingRecords().isEmpty)
    }

    // [06] An unsettled process status is not a second consent decision.
    func testUnsettledAuthorizationKeepsExplicitSharedChoice() throws {
        let (store, exchange, _, _) = try fixture()
        let before = try XCTUnwrap(exchange.currentContext())
        try store.configureWidgetAutomaticInput(enabled: nil)
        XCTAssertEqual(try exchange.currentContext(), before)
    }

    // [07] Deleting entries invalidates the saved ticket before a late query can restore a result.
    func testDeleteInvalidatesWidgetTicketAndKeepsTombstone() throws {
        let (store, exchange, calculator, now) = try fixture()
        let request = try XCTUnwrap(exchange.contextForYesterday(now: now, calendar: calendar))
        let saved = try pending(exchange, calculator: calculator, now: now)
        try store.deleteAll()
        XCTAssertFalse(store.isConfigured)
        XCTAssertTrue(try exchange.pendingRecords().isEmpty)
        XCTAssertFalse(try XCTUnwrap(exchange.currentContext()).enabled)
        XCTAssertThrowsError(try exchange.commit(saved.record, expected: request, at: now, calendar: calendar))
    }

    // [09] A successful later widget reading can update an older automatic result for the same day.
    func testNewerAutomaticPendingReplacesEarlierHostCalculation() throws {
        let (store, exchange, calculator, now) = try fixture()
        let day = calendar.date(byAdding: .day, value: -1, to: now)!
        try store.importAutomaticUsage(day: day, minutesByCategory: [FootprintCategory.video.rawValue: 10],
            now: now.addingTimeInterval(-60))
        let saved = try pending(exchange, calculator: calculator, now: now, allowExistingAutomaticDay: true)
        let reopened = reopen(store, exchange: exchange, calculator: calculator)
        XCTAssertEqual(reopened.latest?.inputs.totalMinutes, 30)
        XCTAssertEqual(reopened.latest?.calculatedAt, saved.record.calculatedAt)
        XCTAssertTrue(try exchange.pendingRecords().isEmpty)
    }

    // [10] A late handoff cannot overwrite a newer result already saved by the host.
    func testOlderAutomaticPendingDoesNotRegressNewerHostCalculation() throws {
        let (store, exchange, calculator, now) = try fixture()
        let day = calendar.date(byAdding: .day, value: -1, to: now)!
        try store.importAutomaticUsage(day: day, minutesByCategory: [FootprintCategory.video.rawValue: 10],
            now: now.addingTimeInterval(-60))
        _ = try pending(exchange, calculator: calculator, now: now.addingTimeInterval(-30),
            allowExistingAutomaticDay: true)
        try store.importAutomaticUsage(day: day, minutesByCategory: [FootprintCategory.video.rawValue: 20], now: now)
        let reopened = reopen(store, exchange: exchange, calculator: calculator)
        XCTAssertEqual(reopened.latest?.inputs.totalMinutes, 20)
        XCTAssertTrue(try exchange.pendingRecords().isEmpty)
    }

    // [11] Withdrawing access must still block new widget queries when the shared handoff cannot be decoded.
    func testWithdrawalWritesDenyMarkerWithoutReadingDamagedMailbox() throws {
        let (store, exchange, _, _) = try fixture()
        let previous = try Data(contentsOf: store.fileURL)
        let shared = exchange.directory!.appendingPathComponent(WidgetAutomaticExchange.fileName)
        try Data("{}".utf8).write(to: shared)
        store.blockWidgetAutomaticInput()
        XCTAssertTrue(store.isConfigured)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), previous)
        XCTAssertEqual(try Data(contentsOf: shared), Data("{}".utf8))
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(try exchange.newQueriesAreBlocked())
        XCTAssertNil(try exchange.contextForYesterday(now: Date(), calendar: calendar))
    }

    // [12] A fresh process or old preferences cannot undo withdrawal; an explicit new setup gets a fresh ticket.
    func testOrdinaryRefreshDoesNotUnblockWithdrawalButExplicitSetupCan() throws {
        let (store, exchange, _, now) = try fixture()
        let request = try XCTUnwrap(exchange.contextForYesterday(now: now, calendar: calendar))
        try exchange.blockNewQueries()
        try store.configureWidgetAutomaticInput(enabled: true)
        XCTAssertTrue(try exchange.newQueriesAreBlocked())
        XCTAssertNil(try exchange.contextForYesterday(now: now, calendar: calendar))
        try store.configureWidgetAutomaticInput(enabled: true, allowResumingAfterWithdrawal: true)
        XCTAssertFalse(try exchange.newQueriesAreBlocked())
        XCTAssertNotEqual(try XCTUnwrap(exchange.currentContext()).epoch, request.context.epoch)
        XCTAssertFalse(try exchange.validateRequest(request, now: now, calendar: calendar))
        XCTAssertNotNil(try exchange.contextForYesterday(now: now, calendar: calendar))
    }

    // [13] An earlier all-app setup can adopt the new widget path without asking the person to repeat setup.
    func testFirstSaveAndUnsettledMigrationDoNotCreateWithdrawalMarker() throws {
        let (store, exchange, _, now) = try fixture(enableWidget: false)
        XCTAssertNil(try exchange.currentContext())
        XCTAssertFalse(try exchange.newQueriesAreBlocked())
        XCTAssertFalse(store.widgetAutomaticUpdatesPaused)
        try store.configureWidgetAutomaticInput(enabled: nil)
        XCTAssertNil(try exchange.currentContext())
        XCTAssertFalse(try exchange.newQueriesAreBlocked())
        try store.configureWidgetAutomaticInput(enabled: true)
        XCTAssertTrue(try XCTUnwrap(exchange.currentContext()).enabled)
        XCTAssertFalse(try exchange.newQueriesAreBlocked())
        XCTAssertNotNil(try exchange.contextForYesterday(now: now, calendar: calendar))
    }

    // [14] A cached Connected state cannot widen the widget's scope after its all-app start date is missing or damaged.
    func testMissingOrInvalidBroaderConsentBoundaryCannotEnableWidget() throws {
        let suite = "dfe-widget-boundary-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set(ScreenTimeActivityScope.allAuthorizedApps.rawValue, forKey: "dfe.screenTime.activityScope.v1")
        defaults.set("2026-10-07", forKey: "dfe.screenTime.allActivityStartDay.v1")
        let service = ScreenTimeService(isolatedUIArguments: ["-ui-testing", "-ui-automatic-preview"], defaults: defaults)
        XCTAssertEqual(service.state, .dataAccess)
        defaults.removeObject(forKey: "dfe.screenTime.allActivityStartDay.v1")
        XCTAssertEqual(service.state, .dataAccess)
        XCTAssertNil(service.widgetAutomaticStartDay)
        XCTAssertEqual(service.widgetAutomaticAccessDecision, false)
        defaults.set("not-a-date", forKey: "dfe.screenTime.allActivityStartDay.v1")
        XCTAssertNil(service.widgetAutomaticStartDay)
        XCTAssertEqual(service.widgetAutomaticAccessDecision, false)
    }

    // [08] An unreadable shared file must not make the separate, valid history look corrupted.
    func testUnreadableMailboxKeepsValidPrivateArchive() throws {
        let (store, exchange, calculator, _) = try fixture()
        let previous = try Data(contentsOf: store.fileURL)
        try Data("{}".utf8).write(to: exchange.directory!.appendingPathComponent(WidgetAutomaticExchange.fileName))
        let reopened = reopen(store, exchange: exchange, calculator: calculator)
        XCTAssertTrue(reopened.isConfigured)
        XCTAssertNotNil(reopened.errorMessage)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), previous)
    }
}
