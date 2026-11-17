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

// [01] Only category minutes leave this reader. App identities stay in memory and are discarded.
// The calculation still labels carbon, traffic and other model inputs as estimates.
struct AllActivityDayUsage {
    let day: Date
    let minutesByCategory: [String: Double]
}

#if os(iOS) && canImport(DeviceActivity) && canImport(FamilyControls)
import SwiftUI
import DeviceActivity
import FamilyControls
import ManagedSettings

@available(iOS 26.4, *)
@MainActor
enum AllActivityDayReader {
    // [02] The caller checks the current saved opt-in and setup generation. Reading through
    // Apple's public API still requires permission; an earlier setup cannot grant that permission.
    static func collect(_ date: Date, calendar: Calendar,
                        validateContext: @MainActor () throws -> Void) async throws -> AllActivityDayUsage {
        try Task.checkCancellation()
        try validateContext()
        guard let interval = calendar.dateInterval(of: .day, for: date) else {
            throw ScreenTimeImportError.noData
        }
        var knownBundles: [ApplicationToken: String] = [:]
        var inventoryUnavailable = false
        // [03] Apple's local identity lookup joins repeated rows without saving an installed-app list.
        do {
            for app in try await FamilyActivityData.shared.installedApplications {
                try Task.checkCancellation()
                try validateContext()
                guard let token = app.token, let bundle = app.bundleIdentifier, !bundle.isEmpty else { continue }
                guard knownBundles[token] == nil || knownBundles[token] == bundle else {
                    throw ScreenTimeImportError.unmappedSelection
                }
                knownBundles[token] = bundle
            }
        } catch {
            try AllActivityInventoryPolicy.continueWithoutInventory(after: error)
            // [07] A widget may receive activity rows while Apple's separate inventory lookup is refused.
            // Discard any partial lookup and let the live API decide access to its own identified rows.
            knownBundles.removeAll()
            inventoryUnavailable = true
        }
        try Task.checkCancellation()
        try validateContext()
        let filter = ScreenTimeQueryScope.filter(interval: interval, applications: [], categories: [])
        var ledger = ScreenTimeContributionLedger<ApplicationToken>(knownBundles: knownBundles)
        var devices = Set<DeviceActivityData.Device>()
        var sawSegment = false
        for try await data in DeviceActivityData.activityData(filteredBy: filter, using: .live) {
            try Task.checkCancellation()
            try validateContext()
            devices.insert(data.device)
            guard devices.count == 1 else { throw ScreenTimeImportError.multipleDevices }
            // [04] A source not updated through the requested day must leave that day pending.
            guard data.lastUpdatedDate >= interval.end else { throw ScreenTimeImportError.incompleteData }
            for await segment in data.activitySegments {
                try Task.checkCancellation()
                try validateContext()
                guard calendar.isDate(segment.dateInterval.start, inSameDayAs: interval.start) else { continue }
                var applicationRowCount = 0
                var hasPositiveApplicationDuration = false
                for await group in segment.categories {
                    try Task.checkCancellation()
                    try validateContext()
                    for await activity in group.applications {
                        try Task.checkCancellation()
                        try validateContext()
                        applicationRowCount += 1
                        let token = activity.application.token
                        let seconds = activity.totalActivityDuration
                        let bundle = try AllActivityInventoryPolicy.bundleIdentifier(
                            row: activity.application.bundleIdentifier,
                            known: token.flatMap { knownBundles[$0] }, seconds: seconds,
                            inventoryUnavailable: inventoryUnavailable)
                        let category = AutomaticActivityClassification.category(bundleIdentifier: bundle)
                        // [05] Count individual app rows once. Adding website or group totals would count some activity twice.
                        try ledger.record(token: token, bundleIdentifier: bundle,
                            categoryID: category.rawValue, seconds: seconds, isExplicit: true)
                        hasPositiveApplicationDuration = hasPositiveApplicationDuration || seconds > 0
                    }
                }
                try ScreenTimeAllActivityCoverage.requireUsableSegment(segment.dateInterval, for: interval,
                    activitySeconds: segment.totalActivityDuration, applicationRowCount: applicationRowCount,
                    hasPositiveApplicationDuration: hasPositiveApplicationDuration)
                sawSegment = true
            }
        }
        guard sawSegment else { throw ScreenTimeImportError.noData }
        // [06] Zero categories are allowed only after Apple supplies a usable complete segment.
        // No response stays unknown instead of becoming a zero-impact day.
        var minutes = Dictionary(uniqueKeysWithValues: FootprintCategory.allCases.map { ($0.rawValue, 0.0) })
        for row in try ledger.contributions() { minutes[row.categoryID, default: 0] += row.seconds / 60 }
        let total = minutes.values.reduce(0, +)
        guard total.isFinite, total <= interval.duration / 60 + 0.001 else {
            throw ScreenTimeImportError.invalidDuration
        }
        try Task.checkCancellation()
        try validateContext()
        return AllActivityDayUsage(day: interval.start, minutesByCategory: minutes)
    }
}
#endif
