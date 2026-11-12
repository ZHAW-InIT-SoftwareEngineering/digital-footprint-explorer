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
import CryptoKit

// [01] These development notes show whether the steps ran, without copying app names or usage amounts.
struct BackgroundDiagnosticState: Codable {
    let authorization: String
    let allScopeSaved: Bool
    let automaticEnabled: Bool
    let eligibleCompletedDay: Bool
    let normalOptInStartDay: String?
    let completedDatesEligible: Int?
    let applicationState: String
    let widgetMatchesLatest: Bool?
    var scopeMutationReason: ScreenTimeScopeMutation? = nil
    var scopeMutationAt: Date? = nil
    var archiveFingerprint: String? = nil
}

struct BackgroundDiagnosticEvent: Codable {
    let timestamp: Date
    let event: String
    let source: String
    let trigger: String
    let taskCompleted: Bool?
    let taskSuccess: Bool?
    let outcome: String?
    let attemptedDays: Int?
    let importedDays: Int?
    let pendingDays: Int?
    let newRecords: Int?
    let state: BackgroundDiagnosticState
    let probe: BackgroundProbeReceipt?
}

struct BackgroundDiagnosticLog: Codable {
    var schemaVersion = 1
    var debugOnly = true
    var updatedAt: Date
    var events: [BackgroundDiagnosticEvent] = []

    // [02] Keep only a short recent trail, so a local check does not become an unlimited log.
    mutating func append(_ event: BackgroundDiagnosticEvent) {
        updatedAt = event.timestamp
        events.append(event)
        if events.count > 60 { events.removeFirst(events.count - 60) }
    }
}

enum BackgroundWidgetComparison {
    // [03] Compare the same saved date format on both sides.
    // A fraction of a second lost during saving should not look like an outdated widget.
    static func matches(expected: GardenWidgetSnapshot?, actual: WidgetSnapshotReadResult) -> Bool? {
        switch actual {
        case .unavailable, .unreadable: return nil
        case .empty: return expected == nil
        case .saved(let saved):
            guard let expected else { return false }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            guard let lhs = try? encoder.encode(expected), let rhs = try? encoder.encode(saved) else { return nil }
            return lhs == rhs
        }
    }
}

/// [04] Compare a file fingerprint without copying the history into a test receipt.
/// A missing or protected file stays unknown; this check never creates or repairs it.
enum BackgroundArchiveFingerprint {
    static func read(fileURL: URL) -> String? {
        guard let bytes = try? Data(contentsOf: fileURL) else { return nil }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

/// [05] Local development receipts only. No usage values or app identities enter this file.
@MainActor
enum BackgroundUpdateDiagnostics {
    static let relativePath = "DFEBackgroundDiagnostics/background-update-v1.json"
    private static var launchArm = BackgroundDiagnosticArm()

    private static var isIsolatedTest: Bool {
        let environment = ProcessInfo.processInfo.environment
        return ProcessInfo.processInfo.arguments.contains("-ui-testing")
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }

    static var isAllowed: Bool { !isIsolatedTest }

    // [06] Mark an intentional debugger check clearly; it must not look like a naturally scheduled update.
    static func markNextLaunchAsSimulated(probe: Bool = false, now: Date = Date()) -> Bool {
        guard isAllowed else { return false }
        launchArm.mark(probe: probe, now: now)
        return true
    }

    static func nextLaunchContext(now: Date = Date()) -> (trigger: String, probe: Bool) {
        launchArm.consume(now: now)
    }

    // [07] Record readiness and save outcomes separately. A callback can finish even when
    // Apple has not supplied a usable day, so completion alone is not proof of an import.
    static func record(event: String, source: String, trigger: String,
                       store: FootprintStore, service: ScreenTimeService?,
                       result: ScreenTimeRefreshResult? = nil, outcome: String? = nil,
                       taskCompleted: Bool? = nil, taskSuccess: Bool? = nil,
                       probe: BackgroundProbeReceipt? = nil, now: Date = Date()) {
        guard !isIsolatedTest else { return }
        service?.refreshAuthorization()
        let authorization: String
        switch service?.state {
        case .dataAccess: authorization = "data_access"
        case .reportOnly: authorization = "report_only"
        case .notRequested: authorization = "not_requested"
        case .denied: authorization = "denied"
        case .revoked: authorization = "revoked"
        case .unavailable, .none: authorization = "unavailable"
        }
        let applicationState: String
        switch UIApplication.shared.applicationState {
        case .active: applicationState = "active"
        case .inactive: applicationState = "inactive"
        case .background: applicationState = "background"
        @unknown default: applicationState = "unknown"
        }
        let boundary = service?.diagnosticImportBoundary(store: store, now: now)
        let scopeMutation = service?.diagnosticScopeMutation
        let state = BackgroundDiagnosticState(authorization: authorization,
            allScopeSaved: service?.activityScope == .allAuthorizedApps,
            automaticEnabled: store.usesAutomaticInput,
            eligibleCompletedDay: service?.hasEligibleCompletedDay(store: store, now: now) ?? false,
            normalOptInStartDay: boundary?.startDay, completedDatesEligible: boundary?.completedDates,
            applicationState: applicationState,
            widgetMatchesLatest: BackgroundWidgetComparison.matches(
                expected: store.latest.map { GardenWidgetSnapshot(record: $0) },
                actual: WidgetSnapshotStorage.configured().read()),
            scopeMutationReason: scopeMutation?.reason, scopeMutationAt: scopeMutation?.timestamp,
            archiveFingerprint: BackgroundArchiveFingerprint.read(fileURL: store.fileURL))
        let entry = BackgroundDiagnosticEvent(timestamp: now, event: event, source: source, trigger: trigger,
            taskCompleted: taskCompleted, taskSuccess: taskSuccess, outcome: outcome ?? result?.outcome.rawValue,
            attemptedDays: result?.attemptedDays, importedDays: result?.importedDays,
            pendingDays: result?.pendingDays, newRecords: result?.newRecords, state: state, probe: probe)
        do {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let file = caches.appendingPathComponent(relativePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            var log = (try? Data(contentsOf: file)).flatMap { try? decoder.decode(BackgroundDiagnosticLog.self, from: $0) }
                ?? BackgroundDiagnosticLog(updatedAt: now)
            if log.schemaVersion != 1 || !log.debugOnly { log = BackgroundDiagnosticLog(updatedAt: now) }
            log.append(entry)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = [.sortedKeys]
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(log).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // [08] A diagnostic must never change the result of saving or importing.
        }
    }
}

/// [09] Development tools can label a simulated run or read a technical snapshot.
/// This bridge neither grants Screen Time access nor launches background work by itself.
@MainActor
@objc(DFEBackgroundDebugBridge)
final class DFEBackgroundDebugBridge: NSObject {
    @objc static func markNextLaunchAsSimulated() -> Bool {
        guard Thread.isMainThread else { return false }
        return BackgroundUpdateDiagnostics.markNextLaunchAsSimulated()
    }

    @objc static func markNextLaunchAsSimulatedAndProbe() -> Bool {
        guard Thread.isMainThread else { return false }
        return BackgroundUpdateDiagnostics.markNextLaunchAsSimulated(probe: true)
    }

    @objc static func captureNotificationState() -> Bool {
        guard Thread.isMainThread, BackgroundUpdateDiagnostics.isAllowed else { return false }
        Task { @MainActor in await AppServices.shared.notifications.captureTechnicalState() }
        return true
    }

    @objc static func captureState() -> Bool {
        guard Thread.isMainThread, BackgroundUpdateDiagnostics.isAllowed else { return false }
        let app = AppServices.shared
        BackgroundUpdateDiagnostics.record(event: "snapshot", source: "debugger", trigger: "explicit_state_check",
                                            store: app.store, service: app.screenTime)
        return true
    }
}
#endif
