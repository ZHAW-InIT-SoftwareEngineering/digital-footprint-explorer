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

import Foundation
#if os(iOS)
import os
#endif
#if os(iOS) && canImport(DeviceActivity)
import DeviceActivity
import FamilyControls
#endif

struct WidgetAutomaticReceipt: Codable {
    enum Status: String, Codable {
        case contextUnavailable, timedOut, queryFailed, commitRejected, pendingSaved, pendingSavedSnapshotPending, superseded
    }
    static let fileName = "widget-automatic-import-check-v1.json"
    let formatVersion: Int
    let day: String?
    let queryStartedAt: Date?
    let finishedAt: Date
    let savedAt: Date?
    let status: Status
    let calculationSucceeded: Bool
    let pendingSaved: Bool
    let elapsedMillis: Int
    let error: WidgetAutomaticFixedError?
    let sourceRevision: String
    let build: String
    let configuration: String
    let runtime: String
    let availableMemoryBytes: UInt64?
    let isSimulator: Bool

    init(day: String?, queryStartedAt: Date?, finishedAt: Date, savedAt: Date?, status: Status,
         calculationSucceeded: Bool, pendingSaved: Bool, elapsedMillis: Int, error: WidgetAutomaticFixedError?) {
        self.formatVersion = 1
        self.day = day
        self.queryStartedAt = queryStartedAt
        self.finishedAt = finishedAt
        self.savedAt = savedAt
        self.status = status
        self.calculationSucceeded = calculationSucceeded
        self.pendingSaved = pendingSaved
        self.elapsedMillis = elapsedMillis
        self.error = error
        self.sourceRevision = WidgetAutomaticBuildIdentity.sourceRevision
        self.build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        self.configuration = WidgetVerificationProducer.current.configuration
        self.runtime = ProcessInfo.processInfo.operatingSystemVersionString
        #if os(iOS)
        self.availableMemoryBytes = UInt64(os_proc_available_memory())
        #else
        self.availableMemoryBytes = nil
        #endif
        #if targetEnvironment(simulator)
        self.isSimulator = true
        #else
        self.isSimulator = false
        #endif
    }

}

// [08] A missing build identity stays unknown. It must not borrow an earlier experiment's label.
enum WidgetAutomaticBuildIdentity {
    static var sourceRevision: String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "DFESourceRevision") as? String,
              !value.isEmpty, value != "unavailable", !value.contains("$("), !value.contains("${") else {
            return "unavailable"
        }
        return value
    }
}

// [07] Public error families and numeric codes are enough to diagnose a failure.
// No app names, usage values or system error text enter this file.
struct WidgetAutomaticFixedError: Codable {
    enum Kind: String, Codable { case cancelled, deviceActivity, familyControls, importValidation, other }
    let kind: Kind
    let code: Int
    static func fixed(_ error: Error) -> Self {
        if error is CancellationError { return .init(kind: .cancelled, code: 0) }
        #if os(iOS) && canImport(DeviceActivity)
        if #available(iOS 26.4, *), error is DeviceActivityData.Error {
            return .init(kind: .deviceActivity, code: (error as NSError).code)
        }
        if error is FamilyControlsError {
            return .init(kind: .familyControls, code: (error as NSError).code)
        }
        #endif
        if let error = error as? ScreenTimeImportError {
            let code: Int = switch error {
            case .permissionRequired: 1
            case .noSelection: 2
            case .invalidDuration: 3
            case .noData: 4
            case .multipleDevices: 5
            case .incompleteData: 6
            case .unmappedSelection: 7
            case .conflictingSelection: 8
            case .selectionChanged: 9
            }
            return .init(kind: .importValidation, code: code)
        }
        return .init(kind: .other, code: (error as NSError).code)
    }
}
