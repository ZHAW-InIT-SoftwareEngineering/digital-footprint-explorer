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

import Foundation
#if os(iOS) && canImport(DeviceActivity) && canImport(FamilyControls)
import SwiftUI
import DeviceActivity
import FamilyControls
import ManagedSettings
#endif

#if os(iOS) && canImport(DeviceActivity) && canImport(FamilyControls)
struct ScreenTimeQueryScope {
    static func filter(interval: DateInterval, applications: Set<ApplicationToken>,
                       categories: Set<ActivityCategoryToken>) -> DeviceActivityFilter {
        // [13] Use Apple's current-person and current-device defaults, without requesting another person's activity.
        DeviceActivityFilter(segment: .daily(during: interval), applications: applications, categories: categories)
    }
}
#endif

/// [17] Count an app once, even if it appears in several chosen groups.
/// Only Apple-provided identities can connect those rows; matching names are not enough.
struct ScreenTimeContributionLedger<Token: Hashable> {
    struct Contribution {
        let tokens: Set<Token>
        let bundleIdentifier: String?
        let categoryID: String
        let seconds: Double
        let sourceSeconds: Double
        let isExplicit: Bool
    }

    private enum Alias: Hashable {
        case token(Token), bundle(String)
    }
    private struct Entry {
        var tokens: Set<Token>
        var bundleIdentifier: String?
        var groupDestinations: Set<String>
        var explicitDestinations: Set<String>
        var seconds: Double
        var sourceSeconds: Double
        var minimumSeconds: Double
        var minimumSourceSeconds: Double
    }
    private let knownBundles: [Token: String]
    private var entries: [Int: Entry] = [:]
    private var aliases: [Alias: Int] = [:]
    private var nextID = 0

    init(knownBundles: [Token: String] = [:]) {
        self.knownBundles = knownBundles.filter { !$0.value.isEmpty }
    }

    // [18] Join rows only when Apple gives a matching identity, like checking two tickets
    // belong to the same booking. Conflicting times stop the import instead of choosing a guess.
    mutating func record(token: Token?, bundleIdentifier: String?, categoryID: String,
                         seconds: Double, sourceSeconds: Double? = nil, isExplicit: Bool) throws {
        let sourceSeconds = sourceSeconds ?? seconds
        guard seconds.isFinite, seconds >= 0, sourceSeconds.isFinite, sourceSeconds >= 0 else {
            throw ScreenTimeImportError.invalidDuration
        }
        let suppliedBundle = bundleIdentifier.flatMap { $0.isEmpty ? nil : $0 }
        let knownBundle = token.flatMap { knownBundles[$0] }
        if let suppliedBundle, let knownBundle, suppliedBundle != knownBundle {
            throw ScreenTimeImportError.unmappedSelection
        }
        let bundle = suppliedBundle ?? knownBundle
        guard token != nil || bundle != nil else { throw ScreenTimeImportError.unmappedSelection }
        var incomingAliases = Set<Alias>()
        if let token { incomingAliases.insert(.token(token)) }
        if let bundle { incomingAliases.insert(.bundle(bundle)) }
        let matchingIDs = Set(incomingAliases.compactMap { aliases[$0] })
        var merged = Entry(tokens: Set(token.map { [$0] } ?? []), bundleIdentifier: bundle,
            groupDestinations: isExplicit ? [] : [categoryID],
            explicitDestinations: isExplicit ? [categoryID] : [],
            seconds: seconds, sourceSeconds: sourceSeconds,
            minimumSeconds: seconds, minimumSourceSeconds: sourceSeconds)
        for id in matchingIDs {
            guard let previous = entries[id] else { throw ScreenTimeImportError.unmappedSelection }
            guard max(previous.sourceSeconds, merged.sourceSeconds) - min(previous.minimumSourceSeconds, merged.minimumSourceSeconds) <= 0.001,
                  max(previous.seconds, merged.seconds) - min(previous.minimumSeconds, merged.minimumSeconds) <= 0.001 else {
                throw ScreenTimeImportError.invalidDuration
            }
            if let previousBundle = previous.bundleIdentifier, let bundle, previousBundle != bundle {
                throw ScreenTimeImportError.unmappedSelection
            }
            merged.tokens.formUnion(previous.tokens)
            merged.bundleIdentifier = merged.bundleIdentifier ?? previous.bundleIdentifier
            merged.groupDestinations.formUnion(previous.groupDestinations)
            merged.explicitDestinations.formUnion(previous.explicitDestinations)
            merged.seconds = max(merged.seconds, previous.seconds)
            merged.sourceSeconds = max(merged.sourceSeconds, previous.sourceSeconds)
            merged.minimumSeconds = min(merged.minimumSeconds, previous.minimumSeconds)
            merged.minimumSourceSeconds = min(merged.minimumSourceSeconds, previous.minimumSourceSeconds)
        }
        // [19] Wait for all rows before choosing a category.
        // An explicit app choice then wins over a group choice, whichever arrived first.
        let id = matchingIDs.min() ?? nextID
        if matchingIDs.isEmpty { nextID += 1 }
        for oldID in matchingIDs { entries.removeValue(forKey: oldID) }
        entries[id] = merged
        for token in merged.tokens { aliases[.token(token)] = id }
        if let bundle = merged.bundleIdentifier { aliases[.bundle(bundle)] = id }
    }

    func contributions(requireResolvedPartials: Bool = true) throws -> [Contribution] {
        if requireResolvedPartials,
           entries.values.contains(where: { $0.bundleIdentifier == nil }),
           entries.values.contains(where: { $0.bundleIdentifier != nil }) {
            // [20] Two different kinds of app ID may describe the same app.
            // Without Apple's link between them, leave the day pending rather than risk counting it twice.
            throw ScreenTimeImportError.unmappedSelection
        }
        return try entries.values.map { entry in
            let destinations = entry.explicitDestinations.isEmpty
                ? entry.groupDestinations : entry.explicitDestinations
            guard destinations.count == 1, let categoryID = destinations.first else {
                throw ScreenTimeImportError.conflictingSelection
            }
            return Contribution(tokens: entry.tokens, bundleIdentifier: entry.bundleIdentifier,
                categoryID: categoryID, seconds: entry.seconds, sourceSeconds: entry.sourceSeconds,
                isExplicit: !entry.explicitDestinations.isEmpty)
        }.sorted {
            if $0.categoryID != $1.categoryID { return $0.categoryID < $1.categoryID }
            if $0.seconds != $1.seconds { return $0.seconds < $1.seconds }
            return $0.sourceSeconds < $1.sourceSeconds
        }
    }

    // [21] Add only the checked, non-repeated app contributions, so group overlap does not inflate a category.
    func secondsByCategory() throws -> [String: Double] {
        var result: [String: Double] = [:]
        for contribution in try contributions() {
            result[contribution.categoryID, default: 0] += contribution.seconds
        }
        return result
    }
}

// [22] A complete daily estimate needs the exact requested day, including a clock-change day.
struct ScreenTimeDayValidation {
    static func isCompleteSegment(_ segment: DateInterval, for requested: DateInterval) -> Bool {
        // [23] Reject activity that crosses the requested day; guessing how to split it could distort the estimate.
        abs(segment.start.timeIntervalSince(requested.start)) <= 0.001
            && abs(segment.end.timeIntervalSince(requested.end)) <= 0.001
    }
}

// [68] A full date is not enough when Apple reports activity but no usable app time.
// Keep that day pending; filling every category with zero would hide the missing coverage.
struct ScreenTimeAllActivityCoverage {
    static func requireUsableSegment(_ segment: DateInterval, for requested: DateInterval,
                                     activitySeconds: Double, applicationRowCount: Int,
                                     hasPositiveApplicationDuration: Bool) throws {
        guard ScreenTimeDayValidation.isCompleteSegment(segment, for: requested) else {
            throw ScreenTimeImportError.incompleteData
        }
        guard activitySeconds.isFinite, activitySeconds >= 0,
              activitySeconds <= requested.duration + 0.001, applicationRowCount >= 0 else {
            throw ScreenTimeImportError.invalidDuration
        }
        // [69] Screen-on time may include websites or system activity. Do not spread any
        // remainder across apps; only explicit app rows or a genuine zero support this input.
        guard activitySeconds == 0 || (applicationRowCount > 0 && hasPositiveApplicationDuration) else {
            throw ScreenTimeImportError.incompleteData
        }
    }
}


enum ScreenTimeImportError: LocalizedError {
    case permissionRequired, noSelection, invalidDuration, noData, multipleDevices, incompleteData, unmappedSelection, conflictingSelection, selectionChanged
    var errorDescription: String? {
        switch self {
        case .permissionRequired: "Usage import needs Screen Time data access. New automatic days stay pending."
        case .noSelection: "Complete automatic setup before importing usage time."
        case .invalidDuration: "Screen Time returned an invalid usage duration. Your saved entries have been kept."
        case .noData: "Screen Time has not returned a complete record for this day. Your saved entries have been kept."
        case .multipleDevices: "Screen Time returned more than one phone. These times were not combined; your saved entries have been kept."
        case .incompleteData: "Screen Time's data has not been updated through the end of this day. Your saved entries have been kept."
        case .unmappedSelection: "Screen Time could not confirm the identity of some app activity. This day stays pending and your saved entries have been kept."
        case .conflictingSelection: "Some activity has conflicting categories. This day stays pending and your saved entries have been kept."
        case .selectionChanged: "Automatic setup changed during the import. The earlier response was not saved; the app can try again."
        }
    }
}
