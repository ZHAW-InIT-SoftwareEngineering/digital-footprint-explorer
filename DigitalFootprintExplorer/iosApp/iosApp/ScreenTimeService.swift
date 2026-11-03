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
import Combine
#if SCREEN_TIME_ENABLED
import SwiftUI
import FamilyControls
import DeviceActivity
import ManagedSettings
#endif

// [01] Keep earlier app selections readable, while the current setup can include all activity Apple permits.
enum ScreenTimeActivityScope: String {
    case selectedApps, allAuthorizedApps
}

#if DEBUG
/// [02] Interface previews use separate saved choices and do not request the person's Apple access.
struct UITestIsolation {
    let arguments: [String]
    var isActive: Bool { arguments.contains("-ui-testing") }
    var permitsAutomaticPreview: Bool { isActive && arguments.contains("-ui-automatic-preview") }

    func authorizationState(hasSavedSetup: Bool, previouslyAuthorized: Bool) -> ScreenTimeState {
        if hasSavedSetup { return .dataAccess }
        return previouslyAuthorized || arguments.contains("-ui-revoked-preview") ? .revoked : .notRequested
    }
}

/// [03] These local notes distinguish an app action from a status change reported by Apple.
enum ScreenTimeScopeMutation: String, Codable {
    case allActivitySetup = "all_activity_setup"
    case disconnectSucceeded = "disconnect_succeeded"
    case localReset = "local_reset"
    case legacySelectedSetup = "legacy_selected_setup"
}
#endif

/// [04] A broader opt-in never changes which earlier days the app may import.
struct ScreenTimeScopeStart {
    static func importStart(scope: ScreenTimeActivityScope, archiveStart: Date,
                            allActivityStartDay: String?, calendar: Calendar) -> Date? {
        let archiveStart = calendar.startOfDay(for: archiveStart)
        guard scope == .allAuthorizedApps else { return archiveStart }
        guard let key = allActivityStartDay,
              let scopeStart = FootprintCalendar(calendar: calendar).date(key) else { return nil }
        return max(archiveStart, scopeStart)
    }
}

// [05] Ordinary Screen Time approval and approval to read usage data are different.
// The calculation needs the latter; publishing the app does not grant it.
enum ScreenTimePermission: Equatable {
    case notDetermined, denied, approved, approvedWithDataAccess
}

enum ScreenTimeState: Equatable {
    case unavailable, notRequested, denied, reportOnly, dataAccess, revoked
    var canImport: Bool { self == .dataAccess }
    var title: String {
        switch self {
        case .unavailable: "Automatic access unavailable"
        case .notRequested: "Not connected"
        case .denied: "Permission not granted"
        case .reportOnly: "Report access only"
        case .dataAccess: "Usage import available"
        case .revoked: "Permission removed"
        }
    }
    var explanation: String {
        switch self {
        case .unavailable: "Automatic import is unavailable in this build. Saved days remain readable."
        case .notRequested: "Allow Screen Time to start automatic daily estimates. New days stay pending until access and complete data are available."
        case .denied: "Screen Time was not approved on this phone. New automatic days stay pending."
        case .reportOnly: "This permission allows Screen Time reports, but it does not allow usage time to be imported into the footprint calculation. New automatic days stay pending."
        case .dataAccess: "Screen Time can supply app usage time from this iPhone after you enable automatic input. Data use, brightness and background activity still use model assumptions."
        case .revoked: "Screen Time access has been removed. Your saved results remain available. You can reconnect Screen Time to resume automatic input."
        }
    }
}

struct ScreenTimeAuthorizationDecision {
    static func state(permission: ScreenTimePermission, previouslyAuthorized: Bool,
                      supportsDataAccess: Bool, enabled: Bool) -> ScreenTimeState {
        // [06] The build must support importing, and Apple must also allow data access on this phone.
        guard enabled else { return .unavailable }
        switch permission {
        case .notDetermined: return previouslyAuthorized ? .revoked : .notRequested
        case .denied: return previouslyAuthorized ? .revoked : .denied
        case .approved: return .reportOnly
        case .approvedWithDataAccess: return supportsDataAccess ? .dataAccess : .reportOnly
        }
    }
}

/// [07] For earlier selected-app setups, use an app ID only when it matches a chosen app.
/// A display name or an unrelated installed app is never enough.
struct ScreenTimeIdentityMapping {
    // [08] One app identity may belong to only one chosen category, otherwise its time could be counted twice.
    static func assign<Key: Hashable>(_ key: Key, to categoryID: String,
                                      in assignments: inout [Key: String]) throws {
        guard assignments[key] == nil || assignments[key] == categoryID else {
            throw ScreenTimeImportError.conflictingSelection
        }
        assignments[key] = categoryID
    }

    @discardableResult
    static func resolveSelectedApplication<Application: Hashable, Token: Hashable>(
        _ application: Application, token: Token?, bundleIdentifier: String?,
        tokenAssignments: [Token: String], resolvedApplications: inout [Application: String],
        bundleAssignments: inout [String: String]) throws -> Bool {
        // [09] Apple's list can include other apps. Keep only an exact match for a chosen app.
        guard let token, let id = tokenAssignments[token] else { return false }
        try assign(application, to: id, in: &resolvedApplications)
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            try assign(bundleIdentifier, to: id, in: &bundleAssignments)
        }
        return true
    }

    // [10] Use an exact Apple identity match. A similar app name is not evidence of the same activity.
    static func categoryID<Token: Hashable>(token: Token?, bundleIdentifier: String?,
        tokenAssignments: [Token: String], bundleAssignments: [String: String]) -> String? {
        if let token, let id = tokenAssignments[token] { return id }
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }
        return bundleAssignments[bundleIdentifier]
    }
}

/// [11] One unavailable old day should not block a later usable day.
/// Lost access, conflicting choices or damaged history stop the whole update.
struct ScreenTimeImportPolicy {
    static func shouldContinue(after error: Error) -> Bool {
        #if SCREEN_TIME_ENABLED
        if #available(iOS 26.4, *), let activityError = error as? DeviceActivityData.Error {
            // [12] An absent old record can be retried later; access failures cannot.
            switch activityError {
            case .missingData: return true
            case .unauthorized, .unavailable: return false
            @unknown default: return false
            }
        }
        #endif
        switch error {
        case ScreenTimeImportError.noData, ScreenTimeImportError.incompleteData,
             ScreenTimeImportError.unmappedSelection, ScreenTimeImportError.invalidDuration,
             ScreenTimeImportError.multipleDevices,
             FootprintError.invalidInput, FootprintError.invalidDay:
            return true
        default:
            return false
        }
    }
}

#if SCREEN_TIME_ENABLED
struct ScreenTimeQueryScope {
    static func filter(interval: DateInterval, applications: Set<ApplicationToken>,
                       categories: Set<ActivityCategoryToken>) -> DeviceActivityFilter {
        // [13] Use Apple's current-person and current-device defaults, without requesting another person's activity.
        DeviceActivityFilter(segment: .daily(during: interval), applications: applications, categories: categories)
    }
}
#endif

struct ScreenTimeImportScope {
    static func recognizedTokens<Token: Hashable>(token: Token?, bundleIdentifier: String?,
        selected: Set<Token>, bundleAliases: [String: Set<Token>]) throws -> Set<Token> {
        let tokenMatches = token.map { selected.contains($0) } ?? false
        let bundlePresent = bundleIdentifier?.isEmpty == false
        let aliases = bundleIdentifier.flatMap { bundleAliases[$0] } ?? []
        // [14] If Apple supplies two kinds of app ID, they must agree. A familiar name cannot replace a missing match.
        if let token, bundlePresent, (tokenMatches || !aliases.isEmpty), !aliases.contains(token) {
            throw ScreenTimeImportError.unmappedSelection
        }
        if let token, tokenMatches { return [token] }
        return aliases
    }

    static func usage(categoryID: String?, selectedGroupID: String?, hasIdentity: Bool,
                      seconds: () -> Double) throws -> ScreenTimeApplicationUsage? {
        guard hasIdentity else { throw ScreenTimeImportError.unmappedSelection }
        guard categoryID != nil || selectedGroupID != nil else { return nil }
        // [15] Skip unrelated activity before reading its duration.
        return ScreenTimeApplicationUsage(seconds: seconds(), categoryID: categoryID)
    }

    // [16] If unrelated activity appeared, all chosen apps and groups must still be accounted for.
    // A partial match should leave the day pending rather than quietly lose time.
    static func validateCoverage<App: Hashable, Group: Hashable>(selectedApps: Set<App>,
        coveredApps: Set<App>, selectedGroups: Set<Group>, coveredGroups: Set<Group>,
        foreignRowsSeen: Bool) throws {
        guard !foreignRowsSeen || (selectedApps.isSubset(of: coveredApps)
            && selectedGroups.isSubset(of: coveredGroups)) else {
            throw ScreenTimeImportError.unmappedSelection
        }
    }
}

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

#if DEBUG
// [70] These broad bands can locate missing coverage without saving a person's usage time.
enum ScreenTimeCoverageBand: String, Codable {
    case zero, underQuarter, underHalf, similar, over

    static func compare(appSeconds: Double, screenOnSeconds: Double) -> Self? {
        guard appSeconds.isFinite, appSeconds >= 0, screenOnSeconds.isFinite, screenOnSeconds >= 0 else { return nil }
        if appSeconds == 0 { return .zero }
        if screenOnSeconds == 0 { return .over }
        if appSeconds < screenOnSeconds / 4 { return .underQuarter }
        if appSeconds < screenOnSeconds / 2 { return .underHalf }
        return appSeconds <= screenOnSeconds + 0.001 ? .similar : .over
    }
}

// [71] Only fixed labels, dates, counts and yes/no checks can reach the local receipt.
// App identities, exact durations and calculation settings have no fields in this record.
struct ScreenTimeCoverageSnapshot: Codable {
    let queryId: String
    let capturedAt: Date
    let queryDay: String
    let queryTimeZone: String
    let activityScope: String
    var dataSource = "live"
    var deviceFilter = "not_built"
    var userFilter = "not_built"
    var applicationFilterEmpty: Bool?
    var categoryFilterEmpty: Bool?
    var webDomainFilterEmpty: Bool?
    var responseCount = 0
    var deviceCount = 0
    var segmentCount = 0
    var matchingSegmentCount = 0
    var applicationRowCount = 0
    var positiveApplicationRowCount = 0
    var uniqueContributionCount: Int?
    var sourceQueryDay: String?
    var sourceQueryDaysMatchRequested: Bool?
    var sourceFreshThroughDay: Bool?
    var matchingSegmentsComplete: Bool?
    var rawAppsVsScreenOn: ScreenTimeCoverageBand?
    var uniqueAppsVsScreenOn: ScreenTimeCoverageBand?
    var returnedAllModelCategories: Bool?
    var appSecondsToReturnedMinutesConserved: Bool?
    var savedInputsMatchReturned: Bool?
    var savedRecordDayMatchesQuery: Bool?
    var savedRecordSourceIsScreenTime: Bool?
    var savedRecordContainsAllModelCategories: Bool?
    var savedPositiveUsageHasZeroTrafficAssumption: Bool?
    var outcome = "started"
}

// [72] A matching overall total can hide time moving between categories.
// Compare those inputs here and keep only the answer in the technical note.
enum ScreenTimeCoverageConservation {
    static func secondsMatchMinutes(_ seconds: Double, minutes: [String: Double]) -> Bool {
        guard seconds.isFinite, seconds >= 0,
              minutes.values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return false }
        let total = minutes.values.reduce(0, +) * 60
        return total.isFinite && abs(total - seconds) <= max(0.001, seconds * 1e-10)
    }

    static func savedInputsMatch(_ returned: [String: Double], usages: [CategoryUsage]) -> Bool {
        guard Set(usages.map { $0.category.rawValue }).count == usages.count,
              Set(returned.keys) == Set(usages.map { $0.category.rawValue }) else { return false }
        return usages.allSatisfy { usage in
            guard let expected = returned[usage.category.rawValue], expected.isFinite, expected >= 0,
                  usage.minutes.isFinite, usage.minutes >= 0 else { return false }
            return abs(expected - usage.minutes) <= max(0.001 / 60, expected * 1e-10)
        }
    }
}

// [73] Exact sums exist only while this import is running. They are deliberately not Codable.
// Comparing the returned rows, unique apps and saved inputs shows where a discrepancy begins.
struct ScreenTimeCoverageAccumulator {
    private var report: ScreenTimeCoverageSnapshot
    private var rawAppSeconds = 0.0
    private var screenOnSeconds = 0.0
    private var uniqueAppSeconds: Double?
    private var validAppSeconds = true
    private var validScreenSeconds = true

    init(day: String, timeZone: String, scope: String, capturedAt: Date = Date(), queryId: String = UUID().uuidString) {
        report = ScreenTimeCoverageSnapshot(queryId: queryId, capturedAt: capturedAt,
            queryDay: day, queryTimeZone: timeZone, activityScope: scope)
    }

    mutating func describeFilter(currentDeviceDefault: Bool, defaultUser: Bool,
                                 applicationsEmpty: Bool, categoriesEmpty: Bool, webDomainsEmpty: Bool) {
        report.deviceFilter = currentDeviceDefault ? "current_device_default" : "explicit"
        report.userFilter = defaultUser ? "default" : "explicit"
        report.applicationFilterEmpty = applicationsEmpty
        report.categoryFilterEmpty = categoriesEmpty
        report.webDomainFilterEmpty = webDomainsEmpty
    }

    mutating func observeResponse(freshThroughDay: Bool, deviceCount: Int) {
        report.responseCount += 1
        report.deviceCount = deviceCount
        report.sourceFreshThroughDay = (report.sourceFreshThroughDay ?? true) && freshThroughDay
    }

    mutating func observeSegment(sourceDay: String, matchesRequestedDay: Bool,
                                 complete: Bool, activitySeconds: Double) {
        report.segmentCount += 1
        if report.sourceQueryDay == nil { report.sourceQueryDay = sourceDay }
        report.sourceQueryDaysMatchRequested = (report.sourceQueryDaysMatchRequested ?? true) && matchesRequestedDay
        guard matchesRequestedDay else { return }
        report.matchingSegmentCount += 1
        report.matchingSegmentsComplete = (report.matchingSegmentsComplete ?? true) && complete
        if activitySeconds.isFinite, activitySeconds >= 0 { screenOnSeconds += activitySeconds }
        else { validScreenSeconds = false }
    }

    mutating func observeApplication(seconds: Double) {
        report.applicationRowCount += 1
        guard seconds.isFinite, seconds >= 0 else { validAppSeconds = false; return }
        if seconds > 0 { report.positiveApplicationRowCount += 1 }
        rawAppSeconds += seconds
    }

    mutating func collected(uniqueSeconds: [Double], minutes: [String: Double]) {
        report.uniqueContributionCount = uniqueSeconds.count
        let uniqueTotal = uniqueSeconds.reduce(0, +)
        uniqueAppSeconds = uniqueTotal
        report.returnedAllModelCategories = Set(minutes.keys) == Set(FootprintCategory.allCases.map(\.rawValue))
        report.appSecondsToReturnedMinutesConserved = ScreenTimeCoverageConservation.secondsMatchMinutes(
            uniqueTotal, minutes: minutes)
        report.outcome = "collected"
    }

    mutating func stopped(_ error: Error) {
        switch error {
        case is CancellationError: report.outcome = "cancelled"
        case ScreenTimeImportError.permissionRequired: report.outcome = "permission_required"
        case ScreenTimeImportError.invalidDuration: report.outcome = "invalid_duration"
        case ScreenTimeImportError.noData: report.outcome = "no_data"
        case ScreenTimeImportError.multipleDevices: report.outcome = "multiple_devices"
        case ScreenTimeImportError.incompleteData: report.outcome = "incomplete_data"
        case ScreenTimeImportError.unmappedSelection: report.outcome = "unmapped_selection"
        case ScreenTimeImportError.conflictingSelection: report.outcome = "conflicting_selection"
        case ScreenTimeImportError.selectionChanged: report.outcome = "selection_changed"
        default: report.outcome = "system_error"
        }
    }

    func snapshot() -> ScreenTimeCoverageSnapshot {
        var result = report
        if report.matchingSegmentCount > 0, validAppSeconds, validScreenSeconds {
            result.rawAppsVsScreenOn = .compare(appSeconds: rawAppSeconds, screenOnSeconds: screenOnSeconds)
            if let uniqueAppSeconds {
                result.uniqueAppsVsScreenOn = .compare(appSeconds: uniqueAppSeconds, screenOnSeconds: screenOnSeconds)
            }
        }
        return result
    }
}

// [74] Update the same query after saving and keep only twenty recent attempts.
struct ScreenTimeCoverageJournal: Codable {
    var schemaVersion = 1
    var debugOnly = true
    var updatedAt: Date
    var receipts: [ScreenTimeCoverageSnapshot] = []

    mutating func append(_ receipt: ScreenTimeCoverageSnapshot) {
        receipts.removeAll { $0.queryId == receipt.queryId }
        receipts.append(receipt)
        if receipts.count > 20 { receipts.removeFirst(receipts.count - 20) }
        updatedAt = receipt.capturedAt
    }
}

// [77] Compare only Apple's official grouping and cache choices for the same completed day.
enum ScreenTimeCoverageProbeVariant: String, CaseIterable, Codable {
    case dailyCached = "daily_cached", hourlyCached = "hourly_cached"
    case dailyLive = "daily_live", hourlyLive = "hourly_live"
    case dailyLiveOriginalEndpoint = "daily_live_original_endpoint"
    var hourly: Bool { self == .hourlyCached || self == .hourlyLive }
    var cached: Bool { self == .dailyCached || self == .hourlyCached }
    var originalEndpoint: Bool { self == .dailyLiveOriginalEndpoint }
}

struct ScreenTimeProbeIntervalCoverage: Codable {
    let uniqueIntervalCount: Int
    let duplicateIntervalCount: Int
    let intervalsWithinRequestedDay: Bool
    let coversRequestedDay: Bool
    let overlappingIntervals: Bool

    // [78] Count the returned intervals rather than assuming every day has twenty-four hours.
    static func evaluate(_ intervals: [DateInterval], requested: DateInterval) -> Self {
        let unique = Array(Set(intervals)).sorted { $0.start < $1.start }
        let inside = unique.filter { interval in
            interval.duration.isFinite && interval.duration > 0
                && interval.start >= requested.start.addingTimeInterval(-0.001)
                && interval.end <= requested.end.addingTimeInterval(0.001)
        }
        let within = inside.count == unique.count
        var cursor = requested.start
        var gap = false
        var overlap = false
        for interval in inside {
            if interval.start.timeIntervalSince(cursor) > 0.001 { gap = true }
            if cursor.timeIntervalSince(interval.start) > 0.001 { overlap = true }
            cursor = max(cursor, interval.end)
        }
        return Self(uniqueIntervalCount: unique.count, duplicateIntervalCount: intervals.count - unique.count,
            intervalsWithinRequestedDay: within,
            coversRequestedDay: !inside.isEmpty && !gap && abs(cursor.timeIntervalSince(requested.end)) <= 0.001,
            overlappingIntervals: overlap)
    }
}

// [79] The same app can be used in several hours. Only repeated rows within the SAME
// interval are duplicates; merging different hours would throw away real time.
struct ScreenTimeSegmentedCoverageLedger<Token: Hashable> {
    private let knownBundles: [Token: String]
    private var segments: [DateInterval: ScreenTimeContributionLedger<Token>] = [:]
    init(knownBundles: [Token: String] = [:]) { self.knownBundles = knownBundles }
    mutating func record(interval: DateInterval, token: Token?, bundle: String?, seconds: Double) throws {
        var ledger = segments[interval] ?? ScreenTimeContributionLedger(knownBundles: knownBundles)
        try ledger.record(token: token, bundleIdentifier: bundle, categoryID: FootprintCategory.other.rawValue,
            seconds: seconds, isExplicit: true)
        segments[interval] = ledger
    }
    func durations() throws -> [Double] {
        try segments.values.flatMap { try $0.contributions().map(\.seconds) }
    }
}

struct ScreenTimeCoverageProbeVariantReport: Codable {
    let variant: ScreenTimeCoverageProbeVariant
    let coverage: ScreenTimeCoverageSnapshot
    let intervalCoverage: ScreenTimeProbeIntervalCoverage
    var screenOnReferenceDeduplicatedByInterval = true
}

struct ScreenTimeCoverageProbeReport: Codable {
    var schemaVersion = 1
    var debugOnly = true
    let capturedAt: Date
    let queryDay: String
    let queryTimeZone: String
    var cacheMayAlreadyBeWarm = true
    var productionHistorySaved = false
    var variants: [ScreenTimeCoverageProbeVariantReport] = []
    var dailyCachedMatchesDailyLive: Bool?
    var hourlyCachedMatchesHourlyLive: Bool?
    var hourlyLiveMatchesDailyLive: Bool?
    var hourlyLiveVsDailyLive: ScreenTimeCoverageBand?
    var originalEndpointMatchesAdjustedDailyLive: Bool?
    var sameDeviceAcrossVariants: Bool?
    var outcome = "running"
}

@MainActor
enum ScreenTimeCoverageDiagnostics {
    static let relativePath = "DFEScreenTimeCoverageDiagnostics/coverage-v1.json"
    static let alternativeLaunchArgument = "-dfe-coverage-alternatives"
    static let alternativesRelativePath = "DFEScreenTimeCoverageDiagnostics/alternatives-v1.json"

    // [80] This separate one-shot file cannot alter history, widget summaries or pending notices.
    static func recordAlternatives(_ report: ScreenTimeCoverageProbeReport) {
        guard BackgroundUpdateDiagnostics.isAllowed else { return }
        do {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let file = caches.appendingPathComponent(alternativesRelativePath)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = [.sortedKeys]
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(report).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { }
    }

    // [75] Normal development imports can leave a small technical trail. Tests cannot touch
    // this receipt, and a failed diagnostic must never change someone's imported result.
    static func record(_ receipt: ScreenTimeCoverageSnapshot) {
        guard BackgroundUpdateDiagnostics.isAllowed else { return }
        do {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let file = caches.appendingPathComponent(relativePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            var journal = (try? Data(contentsOf: file)).flatMap { try? decoder.decode(ScreenTimeCoverageJournal.self, from: $0) }
                ?? ScreenTimeCoverageJournal(updatedAt: receipt.capturedAt)
            if journal.schemaVersion != 1 || !journal.debugOnly {
                journal = ScreenTimeCoverageJournal(updatedAt: receipt.capturedAt)
            }
            journal.append(receipt)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = [.sortedKeys]
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(journal).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { }
    }

    // [76] Compare private values on the phone. Only pass/fail checks and the presence
    // of a saved zero traffic assumption leave this comparison.
    static func recordSave(_ receipt: ScreenTimeCoverageSnapshot?, returned: [String: Double],
                           record: FootprintRecord?, saveFailed: Bool = false) {
        guard var receipt else { return }
        receipt.outcome = saveFailed ? "save_failed" : (record == nil ? "no_saved_record" : "saved")
        if let record, !saveFailed {
            receipt.savedInputsMatchReturned = ScreenTimeCoverageConservation.savedInputsMatch(returned, usages: record.inputs.usages)
            receipt.savedRecordDayMatchesQuery = record.day == receipt.queryDay
            receipt.savedRecordSourceIsScreenTime = record.source == .screenTimeWithEstimates
            receipt.savedRecordContainsAllModelCategories = Set(record.automaticCategories ?? []) == Set(FootprintCategory.allCases)
            receipt.savedPositiveUsageHasZeroTrafficAssumption = record.inputs.usages.contains {
                $0.minutes > 0 && $0.gigabytesPerHour == 0
            }
        }
        self.record(receipt)
    }
}
#endif

struct ScreenTimeDailyUsage {
    let day: Date
    /// [24] Only confirmed categories appear here; a saved zero is different from missing activity.
    let minutesByCategory: [String: Double]
    #if DEBUG
    var coverageDiagnostic: ScreenTimeCoverageSnapshot? = nil
    #endif
}

struct ScreenTimeApplicationUsage {
    let seconds: Double
    let categoryID: String?
}

/// [25] A chosen app category wins over a broader group choice. Count app time only;
/// the rest of a group total may be website use, so do not invent app activity from it.
struct ScreenTimeAllocation {
    static let otherCategory = "MISCELLANEOUS"
    static func scale(categorySeconds: Double, applicationSeconds: Double) throws -> Double {
        guard categorySeconds.isFinite, categorySeconds >= 0,
              applicationSeconds.isFinite, applicationSeconds >= 0 else {
            throw ScreenTimeImportError.invalidDuration
        }
        // [26] The category total is the boundary if Apple reports overlapping app activity.
        return applicationSeconds > categorySeconds && applicationSeconds > 0
            ? categorySeconds / applicationSeconds : 1
    }

    // [27] Keep app durations inside the reported group total, without inventing app use from website time.
    static func minutes(categorySeconds: Double, categoryID: String?,
                        applications: [ScreenTimeApplicationUsage]) throws -> [String: Double] {
        guard categorySeconds.isFinite, categorySeconds >= 0,
              applications.allSatisfy({ $0.seconds.isFinite && $0.seconds >= 0 }) else {
            throw ScreenTimeImportError.invalidDuration
        }
        let applicationSeconds = applications.reduce(0) { $0 + $1.seconds }
        let scale = try scale(categorySeconds: categorySeconds, applicationSeconds: applicationSeconds)
        var result: [String: Double] = [:]
        for application in applications {
            let id = application.categoryID ?? categoryID ?? otherCategory
            result[id, default: 0] += application.seconds * scale / 60
        }
        return result
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

@MainActor
// [28] This is the only route from Apple activity to the app's daily inputs.
// Check live access, complete days and stable setup before any result reaches history.
final class ScreenTimeService: ObservableObject {
    @Published private(set) var state: ScreenTimeState = .unavailable
    @Published private(set) var isRequesting = false
    @Published private(set) var isImporting = false
    @Published private(set) var lastImportDate: Date?
    @Published private(set) var lastError: String?
    private let defaults: UserDefaults
    private let historyKey = "dfe.screenTime.wasAuthorized"
    private let selectionKey = "dfe.screenTime.categorySelections.v1"
    private let scopeKey = "dfe.screenTime.activityScope.v1"
    private let allActivityStartKey = "dfe.screenTime.allActivityStartDay.v1"
    private let backfillCursorKey = "dfe.screenTime.backfillCursorDay.v1"
    #if DEBUG
    private let uiTestIsolation: UITestIsolation
    private let scopeMutationKey = "dfe.screenTime.debug.lastScopeMutation.v1"
    private let scopeMutationAtKey = "dfe.screenTime.debug.lastScopeMutationAt.v1"

    var diagnosticScopeMutation: (reason: ScreenTimeScopeMutation, timestamp: Date)? {
        guard let value = defaults.string(forKey: scopeMutationKey),
              let reason = ScreenTimeScopeMutation(rawValue: value),
              let timestamp = defaults.object(forKey: scopeMutationAtKey) as? Date else { return nil }
        return (reason, timestamp)
    }

    private func recordScopeMutation(_ reason: ScreenTimeScopeMutation) {
        // [29] Save this development note beside this service's choices, so a test cannot alter normal saved choices.
        defaults.set(reason.rawValue, forKey: scopeMutationKey)
        defaults.set(Date(), forKey: scopeMutationAtKey)
    }
    #endif
    @Published private(set) var activityScope: ScreenTimeActivityScope = .selectedApps
    private var subscriptions = Set<AnyCancellable>()
    // [30] Reject an old response if the setup changed, disconnected or reset while Apple was answering.
    private var selectionRevision = 0
    private static let refreshCoordinator = RefreshCoordinator<ScreenTimeRefreshResult>()
    private let refreshKey = UUID()
    #if SCREEN_TIME_ENABLED
    @Published private(set) var selections: [String: FamilyActivitySelection] = [:]
    #endif

    // [31] This checks whether the build can offer setup, not whether Apple has granted access
    // or whether the person meets Apple's regional conditions.
    var supportsAutomaticSetup: Bool {
        #if DEBUG
        if uiTestIsolation.isActive { return uiTestIsolation.permitsAutomaticPreview }
        #endif
        #if SCREEN_TIME_ENABLED
        if #available(iOS 26.4, *) { return true }
        #endif
        return false
    }

    /// [32] A saved setup, current Apple permission and a complete first day are three different things.
    func hasSavedAutomaticSetup(store: FootprintStore) -> Bool {
        guard store.usesAutomaticInput, let archiveStart = store.automaticStartDate,
              activityScope == .allAuthorizedApps else { return false }
        return ScreenTimeScopeStart.importStart(scope: activityScope, archiveStart: archiveStart,
            allActivityStartDay: defaults.string(forKey: allActivityStartKey),
            calendar: store.aggregationCalendar) != nil
    }

    #if DEBUG
    /// [33] Test screens save a separate setup only. They cannot request or grant Apple access.
    func saveControlledAllActivitySetup(inputs: FootprintInputs, store: FootprintStore,
                                        now: Date = Date()) throws {
        guard uiTestIsolation.permitsAutomaticPreview else {
            throw FootprintError.invalidInput("Automatic previews are only available in isolated interface tests.")
        }
        let savedStart = defaults.string(forKey: allActivityStartKey)
        let validStart = savedStart.flatMap { FootprintCalendar(calendar: store.aggregationCalendar).date($0) }
        let keepsScope = activityScope == .allAuthorizedApps && validStart != nil
        let startDay = keepsScope ? savedStart! : store.dayKey(for: now)
        try store.saveAutomaticProfile(inputs, now: now)
        if !keepsScope { defaults.removeObject(forKey: backfillCursorKey) }
        defaults.set(startDay, forKey: allActivityStartKey)
        defaults.set(ScreenTimeActivityScope.allAuthorizedApps.rawValue, forKey: scopeKey)
        activityScope = .allAuthorizedApps
        selectionRevision &+= 1
        lastError = nil
        refreshAuthorization()
    }
    #endif

    convenience init(defaults suppliedDefaults: UserDefaults? = nil) {
        self.init(defaults: suppliedDefaults, launchArguments: ProcessInfo.processInfo.arguments)
    }

    #if DEBUG
    /// [34] Let controlled tests check a separate setup without changing how the rest of the app was launched.
    convenience init(isolatedUIArguments arguments: [String], defaults: UserDefaults) {
        precondition(UITestIsolation(arguments: arguments).isActive)
        self.init(defaults: defaults, launchArguments: arguments)
    }
    #endif

    // [35] Keep test choices in separate storage. A normal launch reads the saved setup
    // without treating an earlier approval as current permission.
    private init(defaults suppliedDefaults: UserDefaults?, launchArguments arguments: [String]) {
        #if DEBUG
        uiTestIsolation = UITestIsolation(arguments: arguments)
        #endif
        let defaults: UserDefaults
        #if DEBUG
        if let suppliedDefaults { defaults = suppliedDefaults }
        else if arguments.contains("-ui-testing") {
            let name = "dfe.isolated-ui-screen-time"
            let isolated = UserDefaults(suiteName: name)!
            if arguments.contains("-reset-ui-state") { isolated.removePersistentDomain(forName: name) }
            defaults = isolated
        } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
                    || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil {
            defaults = UserDefaults(suiteName: "dfe.isolated-unit-screen-time.\(UUID().uuidString)")!
        } else { defaults = .standard }
        #else
        defaults = suppliedDefaults ?? .standard
        #endif
        self.defaults = defaults
        // [36] Old installations keep their narrower scope until the person opts in.
        activityScope = ScreenTimeActivityScope(rawValue: defaults.string(forKey: scopeKey) ?? "") ?? .selectedApps
        #if SCREEN_TIME_ENABLED
        if let data = defaults.data(forKey: selectionKey) {
            do { selections = try JSONDecoder().decode([String: FamilyActivitySelection].self, from: data) }
            catch { lastError = "The previous Screen Time setup could not be read. Please enable automatic estimates again." }
        }
        #endif
        observeAuthorizationChanges()
        refreshAuthorization()
    }

    // [37] Follow Apple's status changes so Settings and future imports stop relying on an old connection state.
    private func observeAuthorizationChanges() {
        #if DEBUG
        guard !uiTestIsolation.isActive else { return }
        #endif
        #if SCREEN_TIME_ENABLED
        AuthorizationCenter.shared.$authorizationStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshAuthorization() }
            }.store(in: &subscriptions)
        #endif
    }

    // [38] Ask Apple for its current status. A previous successful connection helps explain a removal,
    // but it can never grant access by itself.
    func refreshAuthorization() {
        #if DEBUG
        if uiTestIsolation.isActive {
            let start = defaults.string(forKey: allActivityStartKey)
            let validStart = start.flatMap { FootprintCalendar(calendar: FootprintCalendar.localCalendar).date($0) } != nil
            state = uiTestIsolation.authorizationState(
                hasSavedSetup: activityScope == .allAuthorizedApps && validStart,
                previouslyAuthorized: defaults.bool(forKey: historyKey))
            return
        }
        #endif
        #if SCREEN_TIME_ENABLED
        let status = AuthorizationCenter.shared.authorizationStatus
        let permission: ScreenTimePermission
        if #available(iOS 26.4, *), status == .approvedWithDataAccess {
            permission = .approvedWithDataAccess
        } else if status == .approved {
            permission = .approved
        } else if status == .denied {
            permission = .denied
        } else {
            permission = .notDetermined
        }
        let supported: Bool
        if #available(iOS 26.4, *) { supported = true } else { supported = false }
        state = ScreenTimeAuthorizationDecision.state(permission: permission,
            previouslyAuthorized: defaults.bool(forKey: historyKey), supportsDataAccess: supported, enabled: true)
        if permission == .approved || permission == .approvedWithDataAccess {
            defaults.set(true, forKey: historyKey)
        }
        #else
        state = .unavailable
        #endif
    }

    /// [39] Called only by the person's Connect button, never automatically at launch.
    func requestAuthorization() async {
        #if DEBUG
        guard !uiTestIsolation.isActive else { return }
        #endif
        #if SCREEN_TIME_ENABLED
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false; refreshAuthorization() }
        lastError = nil
        do { try await AuthorizationCenter.shared.requestAuthorization(for: .individual) }
        catch { lastError = "Screen Time could not be connected. \(error.localizedDescription)" }
        #endif
    }

    // [40] Forget the import setup only after Apple confirms the disconnect.
    // Saved daily estimates belong to the person and are kept.
    func disconnect() async {
        #if DEBUG
        guard !uiTestIsolation.isActive else { return }
        #endif
        #if SCREEN_TIME_ENABLED
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                AuthorizationCenter.shared.revokeAuthorization { result in continuation.resume(with: result) }
            }
            selectionRevision &+= 1
            selections = [:]
            defaults.removeObject(forKey: selectionKey)
            defaults.removeObject(forKey: scopeKey)
            defaults.removeObject(forKey: allActivityStartKey)
            defaults.removeObject(forKey: backfillCursorKey)
            activityScope = .selectedApps
            lastImportDate = nil
            lastError = nil
            #if DEBUG
            recordScopeMutation(.disconnectSucceeded)
            #endif
        } catch { lastError = "Screen Time could not be disconnected. \(error.localizedDescription)" }
        refreshAuthorization()
        #endif
    }

    /// [41] Clears local app choices after the person's confirmed Delete action.
    /// System permission is removed only through the separate Disconnect action.
    func resetLocalData() {
        selectionRevision &+= 1
        defaults.removeObject(forKey: selectionKey)
        defaults.removeObject(forKey: historyKey)
        defaults.removeObject(forKey: scopeKey)
        defaults.removeObject(forKey: allActivityStartKey)
        defaults.removeObject(forKey: backfillCursorKey)
        activityScope = .selectedApps
        #if SCREEN_TIME_ENABLED
        selections = [:]
        #endif
        lastImportDate = nil
        lastError = nil
        #if DEBUG
        recordScopeMutation(.localReset)
        #endif
        refreshAuthorization()
    }

    #if SCREEN_TIME_ENABLED
    /// [42] One opt-in covers app activity Apple makes available on this phone.
    /// Starting here does not rewrite earlier history or invent today's result.
    func saveAllActivitySetup(inputs: FootprintInputs, store: FootprintStore, now: Date = Date()) throws {
        refreshAuthorization()
        guard state.canImport, supportsAutomaticSetup else { throw ScreenTimeImportError.permissionRequired }
        guard Set(inputs.usages.map(\.category)) == Set(FootprintCategory.allCases) else {
            throw FootprintError.invalidInput("All app activity needs estimate settings for every category.")
        }
        let savedStart = defaults.string(forKey: allActivityStartKey)
        let validStart = savedStart.flatMap { FootprintCalendar(calendar: store.aggregationCalendar).date($0) }
        let keepsScope = activityScope == .allAuthorizedApps && validStart != nil
        let startDay = keepsScope ? savedStart! : store.dayKey(for: now)
        try store.saveAutomaticProfile(inputs, now: now)
        if !keepsScope { defaults.removeObject(forKey: backfillCursorKey) }
        defaults.set(startDay, forKey: allActivityStartKey)
        defaults.set(ScreenTimeActivityScope.allAuthorizedApps.rawValue, forKey: scopeKey)
        activityScope = .allAuthorizedApps
        selectionRevision &+= 1
        lastError = nil
        #if DEBUG
        recordScopeMutation(.allActivitySetup)
        #endif
    }

    /// [43] Check all earlier app selections before saving the new setup.
    /// A failed setup keeps the old choices, and setup alone never creates a daily result.
    func saveAutomaticSetup(inputs: FootprintInputs,
                            choices: [String: FamilyActivitySelection], store: FootprintStore) throws {
        refreshAuthorization()
        guard state.canImport, supportsAutomaticSetup else { throw ScreenTimeImportError.permissionRequired }
        var cleaned = choices
        var appTokens = Set<ApplicationToken>()
        var groupTokens = Set<ActivityCategoryToken>()
        for key in cleaned.keys {
            guard FootprintCategory(rawValue: key) != nil else { throw ScreenTimeImportError.noSelection }
            cleaned[key]?.webDomainTokens = []
            guard let selection = cleaned[key] else { continue }
            guard appTokens.isDisjoint(with: selection.applicationTokens),
                  groupTokens.isDisjoint(with: selection.categoryTokens) else { throw ScreenTimeImportError.conflictingSelection }
            appTokens.formUnion(selection.applicationTokens)
            groupTokens.formUnion(selection.categoryTokens)
        }
        cleaned = cleaned.filter { !$0.value.applicationTokens.isEmpty || !$0.value.categoryTokens.isEmpty }
        guard !cleaned.isEmpty, Set(cleaned.keys) == Set(inputs.usages.map { $0.category.rawValue }) else {
            throw ScreenTimeImportError.noSelection
        }
        let encoded = try JSONEncoder().encode(cleaned)
        try store.saveAutomaticProfile(inputs)
        defaults.set(encoded, forKey: selectionKey)
        selections = cleaned
        defaults.set(ScreenTimeActivityScope.selectedApps.rawValue, forKey: scopeKey)
        defaults.removeObject(forKey: allActivityStartKey)
        defaults.removeObject(forKey: backfillCursorKey)
        activityScope = .selectedApps
        selectionRevision &+= 1
        lastError = nil
        #if DEBUG
        recordScopeMutation(.legacySelectedSetup)
        #endif
    }

    func selection(for categoryID: String) -> FamilyActivitySelection {
        selections[categoryID] ?? FamilyActivitySelection(includeEntireCategory: true)
    }

    // [44] For older selected-app setups, move a choice out of other categories before saving it.
    // That gives each chosen app or group one destination.
    func saveSelection(_ selection: FamilyActivitySelection, for categoryID: String) throws {
        guard FootprintCategory(rawValue: categoryID) != nil else { throw ScreenTimeImportError.noSelection }
        var next = selections
        var cleaned = selection
        // [45] Website history is outside this prototype's app-category input.
        cleaned.webDomainTokens = []
        for id in next.keys where id != categoryID {
            next[id]?.applicationTokens.subtract(cleaned.applicationTokens)
            next[id]?.categoryTokens.subtract(cleaned.categoryTokens)
        }
        next[categoryID] = cleaned
        let encoded = try JSONEncoder().encode(next)
        defaults.set(encoded, forKey: selectionKey)
        selections = next
        selectionRevision &+= 1
        lastError = nil
    }
    #endif

    /// [46] Every automatic update checks the same saved consent and live permission.
    /// An update can finish without importing anything when one of those is missing.
    @discardableResult
    func refreshAutomaticDays(store: FootprintStore, now: Date = Date(),
                              backfillLimit: Int = ScreenTimeImportPlan.foregroundBackfillLimit) async throws -> ScreenTimeRefreshResult {
        try Task.checkCancellation()
        refreshAuthorization()
        guard store.usesAutomaticInput else { return ScreenTimeRefreshResult() }
        guard hasSavedAutomaticSetup(store: store), state.canImport else {
            return ScreenTimeRefreshResult(stoppedForAccess: true)
        }
        return try await refreshCompletedDays(store: store, now: now, backfillLimit: backfillLimit)
    }

    /// [47] Share an update only for the same local day, time zone and setup.
    /// This comparison contains no app identities or activity amounts.
    func refreshContext(store: FootprintStore, now: Date = Date()) -> String {
        "\(store.dayKey(for: now))|\(store.aggregationCalendar.timeZone.identifier)|\(selectionRevision)"
    }

    /// [48] Unavailable days wait for another attempt. Save each complete day separately,
    /// so an interruption does not lose good days or overwrite earlier manual corrections.
    @discardableResult
    func refreshCompletedDays(store: FootprintStore, now: Date = Date(),
                              backfillLimit: Int = ScreenTimeImportPlan.foregroundBackfillLimit) async throws -> ScreenTimeRefreshResult {
        try await Self.refreshCoordinator.perform(key: refreshKey, context: refreshContext(store: store, now: now)) { [self] in
            try await performCompletedDays(store: store, now: now, backfillLimit: backfillLimit)
        }
    }

    // [49] Check whether a complete day falls after the saved consent date, without reading activity.
    func hasEligibleCompletedDay(store: FootprintStore, now: Date = Date()) -> Bool {
        guard activityScope == .allAuthorizedApps, store.usesAutomaticInput, let archiveStart = store.automaticStartDate,
              let start = ScreenTimeScopeStart.importStart(scope: activityScope, archiveStart: archiveStart,
                  allActivityStartDay: defaults.string(forKey: allActivityStartKey), calendar: store.aggregationCalendar)
        else { return false }
        return start < store.aggregationCalendar.startOfDay(for: now)
    }

    #if DEBUG
    // [50] Report only the saved start date and eligible-day count, without reading the person's activity.
    func diagnosticImportBoundary(store: FootprintStore, now: Date = Date()) -> (startDay: String?, completedDates: Int?) {
        guard activityScope == .allAuthorizedApps, store.usesAutomaticInput,
              let archiveStart = store.automaticStartDate,
              let start = ScreenTimeScopeStart.importStart(scope: activityScope, archiveStart: archiveStart,
                  allActivityStartDay: defaults.string(forKey: allActivityStartKey), calendar: store.aggregationCalendar)
        else { return (nil, nil) }
        let today = store.aggregationCalendar.startOfDay(for: now)
        let count = store.aggregationCalendar.dateComponents([.day], from: start, to: today).day
        return (store.dayKey(for: start), count.map { max(0, $0) })
    }
    #endif

    // [51] Take one view of the day and setup for the whole update, then check it again before saving.
    // This prevents a reconnect or time-zone change from accepting a response that belongs to the old setup.
    private func performCompletedDays(store: FootprintStore, now: Date, backfillLimit: Int) async throws -> ScreenTimeRefreshResult {
        #if DEBUG
        // [52] A test screen left open across midnight must still avoid reading real activity.
        if uiTestIsolation.isActive { return ScreenTimeRefreshResult() }
        #endif
        let aggregation = ScreenTimeCalendarSnapshot(store.aggregationCalendar)
        let calendar = aggregation.calendar
        let dayCalendar = FootprintCalendar(calendar: calendar)
        var result = ScreenTimeRefreshResult()
        refreshAuthorization()
        guard state.canImport else {
            result.stoppedForAccess = true
            return result
        }
        let firstDate: Date
        if store.usesAutomaticInput {
            guard let startKey = store.archive?.automaticStartDay,
                  let startDate = dayCalendar.date(startKey) else {
                let message = "Review automatic setup before importing usage. Its start date has not been saved."
                lastError = message
                throw FootprintError.invalidInput(message)
            }
            firstDate = startDate
        } else {
            guard let startKey = store.firstDay, let startDate = dayCalendar.date(startKey) else { return result }
            firstDate = startDate
        }
        isImporting = true
        defer { isImporting = false }
        let today = calendar.startOfDay(for: now)
        guard let firstDay = ScreenTimeScopeStart.importStart(scope: activityScope, archiveStart: firstDate,
            allActivityStartDay: defaults.string(forKey: allActivityStartKey), calendar: calendar) else {
            lastError = "Start automatic input again to confirm when all-app access begins."
            result.stoppedForError = true
            return result
        }
        lastError = nil
        let manualDays = Set(store.records.filter { $0.source == .manual }.map(\.day))
        let importedDays = Set(store.records.filter { $0.source == .screenTimeWithEstimates }.map(\.day))
        // [53] Earlier selected-app setups can still refresh a day after its category choices change.
        let reuseOlderImports = activityScope == .allAuthorizedApps
        let cursor = defaults.string(forKey: backfillCursorKey).flatMap { dayCalendar.date($0) }
        let plan = ScreenTimeImportPlan.make(start: firstDay, today: today, calendar: calendar,
            cursor: cursor, backfillLimit: backfillLimit,
            shouldRefreshLatest: { !manualDays.contains(dayCalendar.key($0)) },
            shouldBackfill: {
                let key = dayCalendar.key($0)
                return !manualDays.contains(key) && (!reuseOlderImports || !importedDays.contains(key))
            })
        let refreshed = try await ScreenTimeCompletedDayImporter.run(dates: plan.dates, today: today, calendar: calendar,
            shouldImport: { !manualDays.contains(dayCalendar.key($0)) },
            onAttempt: { [self] day in
                // [54] A failed or interrupted old query gives the next gap a turn.
                // The missing day itself remains available on a later cycle.
                if let next = plan.nextBackfillDay[day] {
                    defaults.set(dayCalendar.key(next), forKey: backfillCursorKey)
                }
            }, importDay: { [self] day in
                try aggregation.requireCurrent(store.aggregationCalendar)
                let revision = selectionRevision
                let usage = try await collectDay(day, calendar: calendar)
                try Task.checkCancellation()
                refreshAuthorization()
                guard state.canImport else { throw ScreenTimeImportError.permissionRequired }
                guard revision == selectionRevision else { throw ScreenTimeImportError.selectionChanged }
                try aggregation.requireCurrent(store.aggregationCalendar)
                guard calendar.isDate(usage.day, inSameDayAs: day) else { throw FootprintError.invalidDay }
                let wasMissing = !store.records.contains { $0.day == dayCalendar.key(day) }
                do {
                    try store.importAutomaticUsage(day: usage.day, minutesByCategory: usage.minutesByCategory, now: now)
                } catch {
                    #if DEBUG
                    ScreenTimeCoverageDiagnostics.recordSave(usage.coverageDiagnostic,
                        returned: usage.minutesByCategory, record: nil, saveFailed: true)
                    #endif
                    throw error
                }
                let savedRecord = store.records.first(where: { $0.day == dayCalendar.key(day) })
                #if DEBUG
                ScreenTimeCoverageDiagnostics.recordSave(usage.coverageDiagnostic,
                    returned: usage.minutesByCategory, record: savedRecord)
                #endif
                guard savedRecord?.source == .screenTimeWithEstimates else { return nil }
                lastImportDate = now
                return ScreenTimeDayImportReceipt(day: usage.day, created: wasMissing)
            }, onError: { [self] error in
                lastError = error.localizedDescription
                if ScreenTimeImportPolicy.shouldContinue(after: error) { return .pending }
                return state.canImport ? .error : .noAccess
            })
        // [55] Check the time zone again even if the last day was unavailable; an old-zone result must not look current.
        try aggregation.requireCurrent(store.aggregationCalendar)
        return refreshed
    }

    // [56] Read the chosen scope through Apple's official data access. Legacy selections still
    // need exact identity checks; the all-app route uses the saved broader consent.
    private func collectDay(_ date: Date, calendar: Calendar) async throws -> ScreenTimeDailyUsage {
        #if SCREEN_TIME_ENABLED
        guard state.canImport else { throw ScreenTimeImportError.permissionRequired }
        guard #available(iOS 26.4, *) else { throw ScreenTimeImportError.permissionRequired }
        let revision = selectionRevision
        try Task.checkCancellation()
        if activityScope == .allAuthorizedApps {
            return try await collectAllActivityDay(date, calendar: calendar, revision: revision)
        }
        var appMap: [ApplicationToken: String] = [:]
        var categoryMap: [ActivityCategoryToken: String] = [:]
        var bundleMap: [String: String] = [:]
        var knownBundles: [ApplicationToken: String] = [:]
        var resolvedApps: [Application: String] = [:]
        var resolvedCategories: [ActivityCategory: String] = [:]
        var appBundleAliases: [String: Set<ApplicationToken>] = [:]
        var appObjectAliases: [Application: Set<ApplicationToken>] = [:]
        var groupObjectAliases: [ActivityCategory: Set<ActivityCategoryToken>] = [:]
        var mappedIDs = Set<String>()
        for (id, selection) in selections {
            guard FootprintCategory(rawValue: id) != nil else { throw ScreenTimeImportError.conflictingSelection }
            if !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty { mappedIDs.insert(id) }
            for token in selection.applicationTokens { try ScreenTimeIdentityMapping.assign(token, to: id, in: &appMap) }
            for token in selection.categoryTokens { try ScreenTimeIdentityMapping.assign(token, to: id, in: &categoryMap) }
        }
        guard !mappedIDs.isEmpty else { throw ScreenTimeImportError.noSelection }
        // [57] Apple's picker hides ordinary app IDs. Link only the chosen Apple identities
        // in memory, so returned activity can still match those earlier choices.
        if !appMap.isEmpty {
            try Task.checkCancellation()
            var resolvedTokens = Set<ApplicationToken>()
            for application in try await FamilyActivityData.shared.installedApplications {
                try Task.checkCancellation()
                if try ScreenTimeIdentityMapping.resolveSelectedApplication(application,
                    token: application.token, bundleIdentifier: application.bundleIdentifier,
                    tokenAssignments: appMap, resolvedApplications: &resolvedApps, bundleAssignments: &bundleMap),
                   let token = application.token {
                    resolvedTokens.insert(token)
                    appObjectAliases[application, default: []].insert(token)
                    if let bundle = application.bundleIdentifier, !bundle.isEmpty {
                        appBundleAliases[bundle, default: []].insert(token)
                        knownBundles[token] = bundle
                    }
                }
            }
            // [58] After access is removed, earlier app choices may no longer match Apple's data.
            // Ask for fresh choices instead of turning unknown activity into a measured zero.
            guard resolvedTokens == Set(appMap.keys) else { throw ScreenTimeImportError.unmappedSelection }
        }
        if !categoryMap.isEmpty {
            try Task.checkCancellation()
            var resolvedTokens = Set<ActivityCategoryToken>()
            for category in try await FamilyActivityData.shared.activityCategories {
                try Task.checkCancellation()
                guard let token = category.token, let id = categoryMap[token] else { continue }
                try ScreenTimeIdentityMapping.assign(category, to: id, in: &resolvedCategories)
                groupObjectAliases[category, default: []].insert(token)
                resolvedTokens.insert(token)
            }
            guard resolvedTokens == Set(categoryMap.keys) else { throw ScreenTimeImportError.unmappedSelection }
        }
        try Task.checkCancellation()
        refreshAuthorization()
        guard state.canImport else { throw ScreenTimeImportError.permissionRequired }
        guard revision == selectionRevision else { throw ScreenTimeImportError.selectionChanged }
        guard let interval = calendar.dateInterval(of: .day, for: date) else { throw ScreenTimeImportError.noData }
        let filter = ScreenTimeQueryScope.filter(interval: interval,
            applications: Set(appMap.keys), categories: Set(categoryMap.keys))
        var devices = Set<DeviceActivityData.Device>()
        var sawSegment = false
        var contributions = ScreenTimeContributionLedger<ApplicationToken>(knownBundles: knownBundles)
        var coveredApps = Set<ApplicationToken>()
        var coveredGroups = Set<ActivityCategoryToken>()
        var foreignRowsSeen = false
        let selectedApps = Set(appMap.keys)
        let selectedGroups = Set(categoryMap.keys)
        for try await data in DeviceActivityData.activityData(filteredBy: filter, using: .live) {
            try Task.checkCancellation()
            devices.insert(data.device)
            guard devices.count == 1 else { throw ScreenTimeImportError.multipleDevices }
            // [59] Apple must have updated the source through the end of the day before we call that day complete.
            guard data.lastUpdatedDate >= interval.end else { throw ScreenTimeImportError.incompleteData }
            for await segment in data.activitySegments {
                try Task.checkCancellation()
                guard calendar.isDate(segment.dateInterval.start, inSameDayAs: interval.start) else { continue }
                guard ScreenTimeDayValidation.isCompleteSegment(segment.dateInterval, for: interval) else {
                    throw ScreenTimeImportError.incompleteData
                }
                sawSegment = true
                for await category in segment.categories {
                    try Task.checkCancellation()
                    let categoryID = category.category.token.flatMap { categoryMap[$0] } ?? resolvedCategories[category.category]
                    if let token = category.category.token, categoryMap[token] != nil { coveredGroups.insert(token) }
                    else { coveredGroups.formUnion(groupObjectAliases[category.category] ?? []) }
                    var categoryContributions = ScreenTimeContributionLedger<ApplicationToken>(knownBundles: knownBundles)
                    for await application in category.applications {
                        try Task.checkCancellation()
                        let id = ScreenTimeIdentityMapping.categoryID(token: application.application.token,
                            bundleIdentifier: application.application.bundleIdentifier,
                            tokenAssignments: appMap, bundleAssignments: bundleMap) ?? resolvedApps[application.application]
                        let recognized = try ScreenTimeImportScope.recognizedTokens(token: application.application.token,
                            bundleIdentifier: application.application.bundleIdentifier, selected: selectedApps,
                            bundleAliases: appBundleAliases)
                        let hasIdentity = application.application.token != nil
                            || application.application.bundleIdentifier?.isEmpty == false
                        guard let usage = try ScreenTimeImportScope.usage(categoryID: id,
                            selectedGroupID: categoryID, hasIdentity: hasIdentity,
                            seconds: { application.totalActivityDuration }) else {
                            foreignRowsSeen = true
                            continue
                        }
                        let chosenTokens = recognized.union(appObjectAliases[application.application] ?? [])
                        coveredApps.formUnion(chosenTokens)
                        guard let destination = usage.categoryID ?? categoryID else {
                            throw ScreenTimeImportError.unmappedSelection
                        }
                        try categoryContributions.record(token: application.application.token,
                            bundleIdentifier: application.application.bundleIdentifier, categoryID: destination,
                            seconds: usage.seconds, isExplicit: usage.categoryID != nil)
                    }
                    // [60] A group with only unrelated activity must add nothing to the chosen categories.
                    let rows = try categoryContributions.contributions(requireResolvedPartials: false)
                    guard !rows.isEmpty else { continue }
                    let scale = try ScreenTimeAllocation.scale(categorySeconds: category.totalActivityDuration,
                        applicationSeconds: rows.reduce(0) { $0 + $1.seconds })
                    for row in rows {
                        // [61] Keep the original duration beside the adjusted one, so conflicting repeated activity
                        // cannot quietly change the day's estimate.
                        if row.tokens.isEmpty {
                            try contributions.record(token: nil, bundleIdentifier: row.bundleIdentifier,
                                categoryID: row.categoryID, seconds: row.seconds * scale,
                                sourceSeconds: row.sourceSeconds, isExplicit: row.isExplicit)
                        } else {
                            for token in row.tokens {
                                try contributions.record(token: token, bundleIdentifier: row.bundleIdentifier,
                                    categoryID: row.categoryID, seconds: row.seconds * scale,
                                    sourceSeconds: row.sourceSeconds, isExplicit: row.isExplicit)
                            }
                        }
                    }
                }
            }
        }
        // [62] If Apple returns no activity, the result is unknown; it is not proof that the phone was unused.
        guard sawSegment else { throw ScreenTimeImportError.noData }
        try ScreenTimeImportScope.validateCoverage(selectedApps: selectedApps, coveredApps: coveredApps,
            selectedGroups: selectedGroups, coveredGroups: coveredGroups, foreignRowsSeen: foreignRowsSeen)
        var minutes = Dictionary(uniqueKeysWithValues: mappedIDs.map { ($0, 0.0) })
        for contribution in try contributions.contributions() {
            minutes[contribution.categoryID, default: 0] += contribution.seconds / 60
        }
        let totalMinutes = minutes.values.reduce(0, +)
        guard totalMinutes.isFinite, totalMinutes <= interval.duration / 60 + 0.001 else {
            throw ScreenTimeImportError.invalidDuration
        }
        return ScreenTimeDailyUsage(day: interval.start, minutesByCategory: minutes)
        #else
        throw ScreenTimeImportError.permissionRequired
        #endif
    }
    #if SCREEN_TIME_ENABLED
    @available(iOS 26.4, *)
    // [63] An empty app filter asks for the activity Apple makes available under the granted scope.
    // It does not bypass Apple's permission, device or regional restrictions.
    private func collectAllActivityDay(_ date: Date, calendar: Calendar, revision: Int) async throws -> ScreenTimeDailyUsage {
        guard let interval = calendar.dateInterval(of: .day, for: date) else { throw ScreenTimeImportError.noData }
        #if DEBUG
        var coverageAudit = ScreenTimeCoverageAccumulator(day: FootprintCalendar(calendar: calendar).key(interval.start),
            timeZone: calendar.timeZone.identifier, scope: activityScope.rawValue)
        #endif
        do {
            var knownBundles: [ApplicationToken: String] = [:]
            // [64] With expanded permission, Apple allows this local app-ID lookup.
            // Do not save or send the installed-app list, or guess what happened inside an app.
            for app in try await FamilyActivityData.shared.installedApplications {
                try Task.checkCancellation()
                guard let token = app.token, let bundle = app.bundleIdentifier, !bundle.isEmpty else { continue }
                guard knownBundles[token] == nil || knownBundles[token] == bundle else {
                    throw ScreenTimeImportError.unmappedSelection
                }
                knownBundles[token] = bundle
            }
            try Task.checkCancellation()
            refreshAuthorization()
            guard state.canImport else { throw ScreenTimeImportError.permissionRequired }
            guard revision == selectionRevision else { throw ScreenTimeImportError.selectionChanged }
            let filter = ScreenTimeQueryScope.filter(interval: interval, applications: [], categories: [])
            #if DEBUG
            coverageAudit.describeFilter(currentDeviceDefault: filter.devices == nil, defaultUser: filter.users == nil,
                applicationsEmpty: filter.applications.isEmpty, categoriesEmpty: filter.categories.isEmpty,
                webDomainsEmpty: filter.webDomains.isEmpty)
            #endif
            var ledger = ScreenTimeContributionLedger<ApplicationToken>(knownBundles: knownBundles)
            var devices = Set<DeviceActivityData.Device>()
            var sawSegment = false
            for try await data in DeviceActivityData.activityData(filteredBy: filter, using: .live) {
                try Task.checkCancellation()
                devices.insert(data.device)
                #if DEBUG
                coverageAudit.observeResponse(freshThroughDay: data.lastUpdatedDate >= interval.end,
                    deviceCount: devices.count)
                #endif
                guard devices.count == 1 else { throw ScreenTimeImportError.multipleDevices }
                // [65] Apple must have updated the source through the end of the day before we call that day complete.
                guard data.lastUpdatedDate >= interval.end else { throw ScreenTimeImportError.incompleteData }
                for await segment in data.activitySegments {
                    try Task.checkCancellation()
                    let matchesRequestedDay = calendar.isDate(segment.dateInterval.start, inSameDayAs: interval.start)
                    #if DEBUG
                    coverageAudit.observeSegment(sourceDay: FootprintCalendar(calendar: calendar).key(segment.dateInterval.start),
                        matchesRequestedDay: matchesRequestedDay,
                        complete: ScreenTimeDayValidation.isCompleteSegment(segment.dateInterval, for: interval),
                        activitySeconds: segment.totalActivityDuration)
                    #endif
                    guard matchesRequestedDay else { continue }
                    var applicationRowCount = 0
                    var hasPositiveApplicationDuration = false
                    for await group in segment.categories {
                        for await activity in group.applications {
                            try Task.checkCancellation()
                            applicationRowCount += 1
                            let token = activity.application.token
                            let bundle = activity.application.bundleIdentifier.flatMap { $0.isEmpty ? nil : $0 }
                                ?? token.flatMap { knownBundles[$0] }
                            let category = AutomaticActivityClassification.category(bundleIdentifier: bundle)
                            // [66] Use individual app durations only. Adding group totals or website rows would count some activity twice.
                            let seconds = activity.totalActivityDuration
                            #if DEBUG
                            coverageAudit.observeApplication(seconds: seconds)
                            #endif
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
            // [67] Start every category at zero only after a complete segment was returned.
            // Before that point, missing activity remains unknown.
            var minutes = Dictionary(uniqueKeysWithValues: FootprintCategory.allCases.map { ($0.rawValue, 0.0) })
            let contributions = try ledger.contributions()
            for row in contributions { minutes[row.categoryID, default: 0] += row.seconds / 60 }
            let total = minutes.values.reduce(0, +)
            guard total.isFinite, total <= interval.duration / 60 + 0.001 else {
                throw ScreenTimeImportError.invalidDuration
            }
            #if DEBUG
            coverageAudit.collected(uniqueSeconds: contributions.map(\.seconds), minutes: minutes)
            let diagnostic = coverageAudit.snapshot()
            ScreenTimeCoverageDiagnostics.record(diagnostic)
            return ScreenTimeDailyUsage(day: interval.start, minutesByCategory: minutes, coverageDiagnostic: diagnostic)
            #else
            return ScreenTimeDailyUsage(day: interval.start, minutesByCategory: minutes)
            #endif
        } catch {
            #if DEBUG
            coverageAudit.stopped(error)
            ScreenTimeCoverageDiagnostics.record(coverageAudit.snapshot())
            #endif
            throw error
        }
    }
    #endif

    #if DEBUG
    // [81] An explicit development launch compares authorized API answers without saving
    // activity or changing permission. Ordinary launches never take this path.
    func captureAlternativeCoverage(store: FootprintStore, now: Date = Date()) async {
        guard BackgroundUpdateDiagnostics.isAllowed else { return }
        let calendar = store.aggregationCalendar
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let interval = calendar.dateInterval(of: .day, for: yesterday) else { return }
        var report = ScreenTimeCoverageProbeReport(capturedAt: now,
            queryDay: FootprintCalendar(calendar: calendar).key(yesterday), queryTimeZone: calendar.timeZone.identifier)
        refreshAuthorization()
        guard activityScope == .allAuthorizedApps, state.canImport, store.usesAutomaticInput,
              let archiveStart = store.automaticStartDate,
              let optInStart = ScreenTimeScopeStart.importStart(scope: activityScope, archiveStart: archiveStart,
                allActivityStartDay: defaults.string(forKey: allActivityStartKey), calendar: calendar),
              optInStart <= yesterday else {
            report.outcome = "no_eligible_authorized_day"
            ScreenTimeCoverageDiagnostics.recordAlternatives(report)
            return
        }
        #if SCREEN_TIME_ENABLED
        guard #available(iOS 26.4, *) else { return }
        do {
            var knownBundles: [ApplicationToken: String] = [:]
            for app in try await FamilyActivityData.shared.installedApplications {
                try Task.checkCancellation()
                guard let token = app.token, let bundle = app.bundleIdentifier, !bundle.isEmpty else { continue }
                guard knownBundles[token] == nil || knownBundles[token] == bundle else {
                    throw ScreenTimeImportError.unmappedSelection
                }
                knownBundles[token] = bundle
            }
            var results: [ScreenTimeCoverageProbeVariant: (seconds: Double?, device: DeviceActivityData.Device?)] = [:]
            // [82] Cached answers come first. Earlier normal imports may already have warmed
            // Apple's cache, so this comparison is not presented as a clean-cache experiment.
            for variant in ScreenTimeCoverageProbeVariant.allCases {
                try Task.checkCancellation()
                let result = await readCoverageVariant(variant, interval: interval, calendar: calendar, knownBundles: knownBundles)
                report.variants.append(result.report)
                results[variant] = (result.seconds, result.device)
                ScreenTimeCoverageDiagnostics.recordAlternatives(report)
            }
            func equal(_ lhs: ScreenTimeCoverageProbeVariant, _ rhs: ScreenTimeCoverageProbeVariant) -> Bool? {
                guard let left = results[lhs]?.seconds, let right = results[rhs]?.seconds else { return nil }
                return abs(left - right) <= max(0.001, max(left, right) * 1e-10)
            }
            report.dailyCachedMatchesDailyLive = equal(.dailyCached, .dailyLive)
            report.hourlyCachedMatchesHourlyLive = equal(.hourlyCached, .hourlyLive)
            report.hourlyLiveMatchesDailyLive = equal(.hourlyLive, .dailyLive)
            report.originalEndpointMatchesAdjustedDailyLive = equal(.dailyLiveOriginalEndpoint, .dailyLive)
            if let hourly = results[.hourlyLive]?.seconds, let daily = results[.dailyLive]?.seconds {
                report.hourlyLiveVsDailyLive = .compare(appSeconds: hourly, screenOnSeconds: daily)
            }
            let devices = results.values.compactMap(\.device)
            report.sameDeviceAcrossVariants = devices.count == ScreenTimeCoverageProbeVariant.allCases.count
                ? Set(devices).count == 1 : nil
            report.outcome = report.variants.allSatisfy { $0.coverage.outcome == "collected" } ? "completed" : "partial"
        } catch is CancellationError { report.outcome = "cancelled" }
        catch { report.outcome = "identity_lookup_or_query_setup_failed" }
        #else
        report.outcome = "unsupported_build"
        #endif
        ScreenTimeCoverageDiagnostics.recordAlternatives(report)
    }

    #if SCREEN_TIME_ENABLED
    @available(iOS 26.4, *)
    private func readCoverageVariant(_ variant: ScreenTimeCoverageProbeVariant, interval: DateInterval,
                                     calendar: Calendar, knownBundles: [ApplicationToken: String]) async
        -> (report: ScreenTimeCoverageProbeVariantReport, seconds: Double?, device: DeviceActivityData.Device?) {
        var audit = ScreenTimeCoverageAccumulator(day: FootprintCalendar(calendar: calendar).key(interval.start),
            timeZone: calendar.timeZone.identifier, scope: activityScope.rawValue)
        var intervals: [DateInterval] = []
        var screenByInterval: [DateInterval: Double] = [:]
        var ledger = ScreenTimeSegmentedCoverageLedger<ApplicationToken>(knownBundles: knownBundles)
        var devices = Set<DeviceActivityData.Device>()
        var total: Double?
        do {
            // [83] Apple rounds hourly/daily filter endpoints to the requested unit.
            // Compare the last instant of yesterday with a separate original-endpoint control.
            let query = variant.originalEndpoint ? interval
                : DateInterval(start: interval.start, end: interval.end.addingTimeInterval(-0.001))
            let filter = DeviceActivityFilter(segment: variant.hourly ? .hourly(during: query) : .daily(during: query))
            audit.describeFilter(currentDeviceDefault: filter.devices == nil, defaultUser: filter.users == nil,
                applicationsEmpty: filter.applications.isEmpty, categoriesEmpty: filter.categories.isEmpty,
                webDomainsEmpty: filter.webDomains.isEmpty)
            for try await data in DeviceActivityData.activityData(filteredBy: filter, using: variant.cached ? .cached : .live) {
                try Task.checkCancellation()
                devices.insert(data.device)
                audit.observeResponse(freshThroughDay: data.lastUpdatedDate >= interval.end, deviceCount: devices.count)
                guard devices.count == 1 else { throw ScreenTimeImportError.multipleDevices }
                for await segment in data.activitySegments {
                    try Task.checkCancellation()
                    let part = segment.dateInterval
                    let within = part.duration > 0 && part.start >= interval.start.addingTimeInterval(-0.001)
                        && part.end <= interval.end.addingTimeInterval(0.001)
                    let seconds = segment.totalActivityDuration
                    guard seconds.isFinite, seconds >= 0 else { throw ScreenTimeImportError.invalidDuration }
                    let previous = screenByInterval[part]
                    audit.observeSegment(sourceDay: FootprintCalendar(calendar: calendar).key(part.start),
                        matchesRequestedDay: within, complete: within,
                        activitySeconds: previous == nil ? seconds : 0)
                    intervals.append(part)
                    guard within else { continue }
                    if let previous, abs(previous - seconds) > 0.001 { throw ScreenTimeImportError.invalidDuration }
                    screenByInterval[part] = seconds
                    for await group in segment.categories {
                        for await activity in group.applications {
                            try Task.checkCancellation()
                            let duration = activity.totalActivityDuration
                            audit.observeApplication(seconds: duration)
                            try ledger.record(interval: part, token: activity.application.token,
                                bundle: activity.application.bundleIdentifier, seconds: duration)
                        }
                    }
                }
            }
            // [84] Keep the observed app rows available for this diagnostic comparison,
            // even when empty or missing hours prevent us from proving full-day coverage.
            let unique = try ledger.durations()
            let sum = unique.reduce(0, +)
            guard sum.isFinite else { throw ScreenTimeImportError.invalidDuration }
            audit.collected(uniqueSeconds: unique, minutes: [FootprintCategory.other.rawValue: sum / 60])
            total = sum
            let coverage = ScreenTimeProbeIntervalCoverage.evaluate(intervals, requested: interval)
            guard coverage.coversRequestedDay, !coverage.overlappingIntervals else {
                throw ScreenTimeImportError.incompleteData
            }
        } catch {
            audit.stopped(error)
        }
        var snapshot = audit.snapshot()
        snapshot.dataSource = variant.cached ? "cached" : "live"
        let coverage = ScreenTimeProbeIntervalCoverage.evaluate(intervals, requested: interval)
        return (ScreenTimeCoverageProbeVariantReport(variant: variant, coverage: snapshot, intervalCoverage: coverage),
            total, devices.count == 1 ? devices.first : nil)
    }
    #endif
    #endif

}
