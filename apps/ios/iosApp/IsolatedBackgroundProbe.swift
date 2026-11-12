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

#if DEBUG
import Foundation
import UIKit

// [01] Keep pass or fail facts from a development check, without keeping the activity values it read.
struct BackgroundProbeReceipt: Codable {
    var outcome = "not_run"
    var executedInBackground = false
    var positiveUsage: Bool?
    var calculationValid: Bool?
    var saved: Bool?
    var reloaded: Bool?
    var widgetMatchesIsolated: Bool?
    var normalHistoryUnchanged: Bool?
    var normalWidgetUnchanged: Bool?
    var temporaryFilesRemoved: Bool?
}

struct BackgroundDiagnosticArm {
    private var markedAt: Date?
    private var probeRequested = false
    mutating func mark(probe: Bool, now: Date) { markedAt = now; probeRequested = probe }
    // [02] Use a short-lived, one-time mark so an old debugger request cannot label a later natural run.
    mutating func consume(now: Date) -> (trigger: String, probe: Bool) {
        defer { markedAt = nil; probeRequested = false }
        guard let markedAt, (0...60).contains(now.timeIntervalSince(markedAt)) else {
            return ("system_callback_observed", false)
        }
        return ("simulated_debugger", probeRequested)
    }
}

/// [03] The optional developer probe uses the real import core with a separate
/// archive and widget file. Its temporary data never replaces normal history.
@MainActor
enum IsolatedBackgroundProbe {
    private enum FileState: Equatable {
        case missing, bytes(Data), unreadable
        static func read(_ url: URL?) -> FileState {
            guard let url else { return .unreadable }
            guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
            guard let data = try? Data(contentsOf: url) else { return .unreadable }
            return .bytes(data)
        }
        func unchanged(comparedWith other: FileState) -> Bool? {
            if self == .unreadable || other == .unreadable { return nil }
            return self == other
        }
    }

    // [04] Run only while the app is truly in the background. Separate files let the check
    // exercise importing and saving without replacing the person's normal garden.
    static func run(normalStore: FootprintStore, now: Date = Date()) async -> BackgroundProbeReceipt {
        var receipt = BackgroundProbeReceipt()
        guard BackgroundUpdateDiagnostics.isAllowed, UIApplication.shared.applicationState == .background else {
            receipt.outcome = "not_background"
            return receipt
        }
        receipt.executedInBackground = true
        let normalWidget = WidgetSnapshotStorage.configured().fileURL
        let historyBefore = FileState.read(normalStore.fileURL)
        let widgetBefore = FileState.read(normalWidget)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dfe-background-probe-" + UUID().uuidString)
        let suite = "dfe.isolated-background-probe." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        do {
            try Task.checkCancellation()
            #if SCREEN_TIME_ENABLED
            let calendar = normalStore.aggregationCalendar
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else {
                throw FootprintError.invalidDay
            }
            let storage = WidgetSnapshotStorage(directory: folder.appendingPathComponent("widget"))
            let publisher = FootprintWidgetPublisher(storage: storage, reload: {})
            let calculator = SharedFootprintCalculator()
            let isolated = FootprintStore(fileURL: folder.appendingPathComponent("history.json"),
                calculator: calculator, calendar: calendar, widgetPublisher: publisher)
            let service = ScreenTimeService(defaults: defaults)
            try service.saveAllActivitySetup(inputs: AutomaticActivityClassification.assumptions(preserving: nil),
                                            store: isolated, now: yesterday)
            let result = try await service.refreshCompletedDays(store: isolated, now: now)
            try Task.checkCancellation()
            guard UIApplication.shared.applicationState == .background else { throw CancellationError() }
            receipt.outcome = result.outcome.rawValue
            if let record = isolated.latest, record.source == .screenTimeWithEstimates {
                receipt.positiveUsage = record.inputs.totalMinutes > 0
                try record.result.validate()
                receipt.calculationValid = true
                receipt.saved = FileManager.default.fileExists(atPath: isolated.fileURL.path)
                let reopened = FootprintStore(fileURL: isolated.fileURL, calculator: calculator,
                    calendar: calendar, widgetPublisher: publisher)
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.sortedKeys]
                receipt.reloaded = try encoder.encode(reopened.latest) == encoder.encode(isolated.latest)
                receipt.widgetMatchesIsolated = BackgroundWidgetComparison.matches(
                    expected: GardenWidgetSnapshot(record: record), actual: storage.read())
                if receipt.positiveUsage == true, receipt.calculationValid == true,
                   receipt.saved == true, receipt.reloaded == true, receipt.widgetMatchesIsolated == true {
                    receipt.outcome = "passed"
                }
            }
            #else
            receipt.outcome = "unsupported_build"
            #endif
        } catch is CancellationError { receipt.outcome = "cancelled" }
        catch { receipt.outcome = "error" }
        // [05] A successful import is not enough: also check that the real history and widget were left alone.
        receipt.normalHistoryUnchanged = historyBefore.unchanged(comparedWith: .read(normalStore.fileURL))
        receipt.normalWidgetUnchanged = widgetBefore.unchanged(comparedWith: .read(normalWidget))
        do { if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) } }
        catch { receipt.temporaryFilesRemoved = false }
        if receipt.temporaryFilesRemoved == nil {
            receipt.temporaryFilesRemoved = !FileManager.default.fileExists(atPath: folder.path)
        }
        if receipt.outcome == "passed", receipt.normalHistoryUnchanged != true
            || receipt.normalWidgetUnchanged != true || receipt.temporaryFilesRemoved != true {
            receipt.outcome = "isolation_unconfirmed"
        }
        return receipt
    }
}
#endif
