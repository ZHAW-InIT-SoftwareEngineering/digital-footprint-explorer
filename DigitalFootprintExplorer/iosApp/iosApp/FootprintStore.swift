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
#if os(iOS)
import UIKit
#endif
import Combine

/// [01] Save history as one complete replacement. If the app stops during a calculation,
/// the previous file remains, and a later launch can try the missing days again.
@MainActor
final class FootprintStore: ObservableObject {
    @Published private(set) var archive: FootprintArchive?
    @Published var errorMessage: String?
    @Published private(set) var widgetVerification: WidgetPublicationVerification?
    @Published private(set) var widgetCheckSaveFailed = false
    let importVerification: AutomaticUpdateVerification
    private let calculator: any FootprintCalculating
    private let widgetPublisher: (any WidgetSnapshotPublishing)?
    private let automaticWidgetExchange: WidgetAutomaticExchange?
    private let automaticWidgetReceiptDirectory: URL?
    private var widgetImportStartDay: String?
    let fileURL: URL
    private let days: FootprintCalendar
    private var unreadableArchive = false
    private let verificationCompletionState: @MainActor () -> AutomaticUpdateCompletionState

    var widgetReadChecks: [WidgetTimelineReadCheck] { widgetPublisher?.timelineReadChecks ?? [] }
    var widgetStorageAvailable: Bool { widgetPublisher != nil }
    var widgetAutomaticUpdatesPaused: Bool {
        (try? automaticWidgetExchange?.newQueriesAreBlocked()) ?? false
    }
    private var widgetCheckFileURL: URL {
        fileURL.deletingPathExtension().appendingPathExtension("widget-verification.json")
    }
    private var widgetReconciliationFileURL: URL {
        fileURL.deletingPathExtension().appendingPathExtension("widget-import-reconciliation.json")
    }

    private struct WidgetImportReconciliationCheck: Codable {
        let pendingID: UUID
        let day: String
        let widgetSavedAt: Date
        let widgetCalculatedAt: Date
        let hostReconciledAt: Date
        let widgetProducer: WidgetVerificationProducer
        let hostProducer: WidgetVerificationProducer
    }

    var isConfigured: Bool { archive != nil }
    var usesAutomaticInput: Bool { archive?.usesAutomaticInput == true }
    // [02] Export only history whose local origin can be checked.
    var canExportHistory: Bool {
        !unreadableArchive && archive.map { !$0.containsScreenTimeDerivedData } == true
    }
    var profile: FootprintInputs? { archive?.revisions.last(where: { $0.effectiveDay <= today })?.inputs }
    var aggregationCalendar: Calendar { days.calendar }
    var records: [FootprintRecord] { archive?.records ?? [] }
    var latest: FootprintRecord? { records.last }
    // [33] An old import check cannot describe a day that was later replaced by manual input.
    var latestVerifiedAutomaticSave: VerifiedAutomaticSave? {
        guard let latest, latest.source == .screenTimeWithEstimates, latest.isCompleted else { return nil }
        return importVerification.record(for: latest.day)
    }
    var firstDay: String? { archive?.firstDay }
    var firstDate: Date? { firstDay.flatMap { days.date($0) } }
    var automaticStartDate: Date? { archive?.automaticStartDay.flatMap { days.date($0) } }
    var today: String { days.key(Date()) }
    func date(for day: String) -> Date? { days.date(day) }
    func dayKey(for date: Date) -> String { days.key(date) }
    // [03] A saved day keeps its own inputs. A missing day uses the assumptions that applied at that time.
    func inputs(for day: String) -> FootprintInputs? {
        records.first { $0.day == day }?.inputs ?? archive?.revisions.last { $0.effectiveDay <= day }?.inputs
    }

    convenience init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DigitalFootprintExplorer", isDirectory: true)
        #if DEBUG
        // [04] Keep test archives and reset flags out of the shipped app.
        let arguments = ProcessInfo.processInfo.arguments
        let isUITest = arguments.contains("-ui-testing")
        let environment = ProcessInfo.processInfo.environment
        let isUnitTestHost = environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
        let url: URL
        if isUITest {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("dfe-ui-testing.json")
        } else if isUnitTestHost {
            // [05] Hosted tests must not read history or publish a real widget.
            url = FileManager.default.temporaryDirectory.appendingPathComponent("dfe-unit-host-\(UUID().uuidString).json")
        } else {
            url = directory.appendingPathComponent("daily-footprints.json")
        }
        if isUITest && arguments.contains("-reset-ui-state") {
            for target in [url, url.deletingPathExtension().appendingPathExtension("import-verification.json"),
                           url.deletingPathExtension().appendingPathExtension("widget-verification.json")] {
                try? FileManager.default.removeItem(at: target)
            }
        }
        #if DFE_WIDGET_AUTOMATIC_IMPORT
        let exchange = isUITest || isUnitTestHost ? nil : Self.availableAutomaticWidgetExchange()
        #else
        let exchange: WidgetAutomaticExchange? = nil
        #endif
        self.init(fileURL: url, calculator: SharedFootprintCalculator(),
                  widgetPublisher: isUITest || isUnitTestHost ? nil : FootprintWidgetPublisher.availablePublisher(),
                  automaticWidgetExchange: exchange,
                  automaticWidgetReceiptDirectory: isUITest || isUnitTestHost ? nil
                    : FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        #else
        #if DFE_WIDGET_AUTOMATIC_IMPORT
        let exchange = Self.availableAutomaticWidgetExchange()
        #else
        let exchange: WidgetAutomaticExchange? = nil
        #endif
        self.init(fileURL: directory.appendingPathComponent("daily-footprints.json"),
                  calculator: SharedFootprintCalculator(),
                  widgetPublisher: FootprintWidgetPublisher.availablePublisher(), automaticWidgetExchange: exchange,
                  automaticWidgetReceiptDirectory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        #endif
        #if DEBUG
        if isUITest, arguments.contains("-ui-example-history"), !isConfigured {
            // [06] Fixed examples live only in the isolated UI archive, never on a person's history.
            let now = Date()
            if let yesterday = days.calendar.date(byAdding: .day, value: -1, to: days.calendar.startOfDay(for: now)) {
                do {
                    let inputs = AutomaticActivityClassification.assumptions(preserving: nil)
                    try saveAutomaticProfile(inputs, now: yesterday)
                    var minutes = Dictionary(uniqueKeysWithValues: FootprintCategory.allCases.map { ($0.rawValue, 0.0) })
                    minutes[FootprintCategory.video.rawValue] = 30
                    minutes[FootprintCategory.audio.rawValue] = 20
                    minutes[FootprintCategory.other.rawValue] = 10
                    try importAutomaticUsage(day: yesterday, minutesByCategory: minutes, now: now)
                    if arguments.contains("-ui-legacy-today") {
                        var legacy = inputs
                        legacy.usages[0].minutes = 60
                        try saveDay(today, inputs: legacy, now: now)
                    }
                } catch { report(error) }
            }
        }
        #endif
    }

    init(fileURL: URL, calculator: any FootprintCalculating, calendar: Calendar = FootprintCalendar.localCalendar,
         widgetPublisher: (any WidgetSnapshotPublishing)? = nil,
         automaticWidgetExchange: WidgetAutomaticExchange? = nil,
         automaticWidgetReceiptDirectory: URL? = nil,
         verificationClock: @escaping () -> Date = Date.init,
         verificationCompletionState: (@MainActor () -> AutomaticUpdateCompletionState)? = nil) {
        self.fileURL = fileURL
        self.calculator = calculator
        self.widgetPublisher = widgetPublisher
        self.automaticWidgetExchange = automaticWidgetExchange
        self.automaticWidgetReceiptDirectory = automaticWidgetReceiptDirectory
        self.days = FootprintCalendar(calendar: calendar)
        self.verificationCompletionState = verificationCompletionState ?? {
            #if os(iOS)
            switch UIApplication.shared.applicationState {
            case .active: return .active
            case .inactive: return .inactive
            case .background: return .background
            @unknown default: return .unknown
            }
            #else
            return .unknown
            #endif
        }
        self.importVerification = AutomaticUpdateVerification(
            fileURL: fileURL.deletingPathExtension().appendingPathExtension("import-verification.json"),
            clock: verificationClock)
        do { try load() }
        catch { unreadableArchive = true; errorMessage = error.localizedDescription }
    }

    /// [07] Read saved history again before updating the open app.
    /// This gives a real import priority over filling gaps from an older manual routine.
    func reload() throws {
        try load()
        unreadableArchive = false
    }

    // [08] Start from the saved file before filling gaps, because another update may already have saved work.
    func refresh(now: Date = Date()) throws {
        try reload()
        try catchUp(now: now)
    }

    func saveProfile(_ inputs: FootprintInputs, now: Date = Date()) throws {
        // [09] Editing assumptions must not quietly change an automatic routine to manual.
        if usesAutomaticInput {
            guard archive?.automaticStartDay != nil else {
                throw FootprintError.invalidInput("Review automatic setup before saving new assumptions or importing usage.")
            }
            try saveAutomaticProfile(inputs, now: now)
            return
        }
        try inputs.validate()
        guard !unreadableArchive else { throw FootprintError.damagedArchive }
        if archive == nil {
            let key = days.key(now)
            var next = FootprintArchive(firstDay: key, revisions: [RoutineRevision(effectiveDay: key, savedAt: now, inputs: inputs)], records: [])
            next.records = [try makeRecord(day: key, inputs: inputs, source: .manual, now: now)]
            recomputeGardens(&next, now: now)
            try commit(next)
        } else {
            guard days.key(now) >= archive!.firstDay else { throw FootprintError.invalidDay }
            // [10] Complete the earlier dates with their original routine before adding a revision.
            try catchUp(now: now)
            var next = archive!
            next.revisions.append(RoutineRevision(effectiveDay: days.key(now), savedAt: now, inputs: inputs))
            // [11] Array order records the actual edit sequence. A clock correction
            // must not make a newer same-day edit lose to an older timestamp.
            next.revisions = next.revisions.enumerated().sorted { lhs, rhs in
                lhs.element.effectiveDay == rhs.element.effectiveDay
                    ? lhs.offset < rhs.offset
                    : lhs.element.effectiveDay < rhs.element.effectiveDay
            }.map(\.element)
            try commit(next)
        }
    }

    /// [12] Save the calculation assumptions, then wait for a complete day from Apple.
    /// Zero here leaves room for imported time; it is not a saved zero-use result.
    func saveAutomaticProfile(_ inputs: FootprintInputs, now: Date = Date()) throws {
        try inputs.validate()
        guard !unreadableArchive else { throw FootprintError.damagedArchive }
        let key = days.key(now)
        var assumptions = inputs
        assumptions.calendarDayMinutes = nil
        for index in assumptions.usages.indices { assumptions.usages[index].minutes = 0 }
        var next: FootprintArchive
        if let current = archive {
            guard key >= current.firstDay,
                  current.automaticStartDay.map({ key >= $0 }) ?? true else { throw FootprintError.invalidDay }
            next = current
            next.revisions.append(RoutineRevision(effectiveDay: key, savedAt: now, inputs: assumptions))
            next.revisions = next.revisions.enumerated().sorted { lhs, rhs in
                lhs.element.effectiveDay == rhs.element.effectiveDay
                    ? lhs.offset < rhs.offset
                    : lhs.element.effectiveDay < rhs.element.effectiveDay
            }.map(\.element)
        } else {
            next = FootprintArchive(firstDay: key,
                revisions: [RoutineRevision(effectiveDay: key, savedAt: now, inputs: assumptions)], records: [])
        }
        // [13] A review can repair an older automatic file with no recorded opt-in day.
        // Later assumption edits keep the already confirmed boundary.
        if !next.usesAutomaticInput || next.automaticStartDay == nil { next.automaticStartDay = key }
        next.inputPreference = .automatic
        recomputeGardens(&next, now: now)
        try commit(next)
    }

    // [14] Validate a replacement before touching history, then update the later garden comparisons too.
    func saveDay(_ day: String, inputs: FootprintInputs, source: FootprintSource = .manual, measuredCategories: [FootprintCategory] = [], now: Date = Date()) throws {
        try inputs.validate()
        guard !unreadableArchive else { throw FootprintError.damagedArchive }
        guard var next = archive else { throw FootprintError.notConfigured }
        guard days.date(day) != nil, day >= next.firstDay, day <= days.key(now) else { throw FootprintError.invalidDay }
        let replacement = try makeRecord(day: day, inputs: inputs, source: source, measuredCategories: measuredCategories, now: now)
        // [15] A date is the record's identity, so an edit replaces rather than adds.
        next.records.removeAll { $0.day == day }
        next.records.append(replacement)
        next.records.sort { $0.day < $1.day }
        recomputeGardens(&next, now: now)
        try commit(next)
    }

    /// [16] Manual routines fill missing completed dates using the assumptions saved then.
    /// Automatic routines wait for measured time; neither mode invents today's input.
    func catchUp(now: Date = Date(), shouldCancel: () -> Bool = { false }) throws {
        guard !unreadableArchive else { throw FootprintError.damagedArchive }
        guard var next = archive else { return }
        if next.usesAutomaticInput {
            if shouldCancel() { throw CancellationError() }
            // [17] Missing Screen Time data stays missing; it is never a zero-use estimate.
            recomputeGardens(&next, now: now)
            if next != archive { try commit(next) }
            return
        }
        let today = days.key(now)
        var day = next.firstDay
        var recorded = Set(next.records.map(\.day))
        while day < today {
            if shouldCancel() { throw CancellationError() }
            if !recorded.contains(day) {
                guard let routine = next.revisions.last(where: { $0.effectiveDay <= day }) else { throw FootprintError.damagedArchive }
                next.records.append(try makeRecord(day: day, inputs: routine.inputs, source: .routineEstimate, now: now))
                recorded.insert(day)
            }
            guard let following = days.next(day), following > day else { throw FootprintError.invalidDay }
            day = following
        }
        if shouldCancel() { throw CancellationError() }
        next.records.sort { $0.day < $1.day }
        recomputeGardens(&next, now: now)
        if next != archive { try commit(next) }
    }

    /// [18] Screen Time supplies usage time only. Keep the other calculation assumptions
    /// visible in the saved record rather than presenting them as measurements.
    func importAutomaticUsage(day date: Date, minutesByCategory: [String: Double], now: Date = Date(),
                              origin: AutomaticUpdateOrigin = .foreground) throws {
        guard !unreadableArchive else { throw FootprintError.damagedArchive }
        let day = days.key(date)
        guard day < days.key(now), let base = inputs(for: day) else { throw FootprintError.invalidDay }
        if usesAutomaticInput {
            guard let startDay = archive?.automaticStartDay else {
                throw FootprintError.invalidInput("Review automatic setup before importing usage. Its start date has not been saved.")
            }
            guard day >= startDay else { throw FootprintError.invalidDay }
        }
        guard let interval = days.calendar.dateInterval(of: .day, for: date) else { throw FootprintError.invalidDay }
        let capacity = interval.duration / 60
        guard FootprintInputs.isValidCalendarDayCapacity(capacity),
              !minutesByCategory.isEmpty,
              minutesByCategory.values.allSatisfy({ $0.isFinite && (0...capacity).contains($0) }),
              minutesByCategory.values.reduce(0, +) <= capacity else {
            throw FootprintError.invalidInput("Screen Time did not return valid usage times for the selected categories.")
        }
        guard minutesByCategory.keys.allSatisfy({ FootprintCategory(rawValue: $0) != nil }) else {
            throw FootprintError.invalidInput("Screen Time returned an unknown category.")
        }
        // [19] A manual entry keeps the person's input even if they later map a
        // category that was not part of this day's entry.
        if records.first(where: { $0.day == day })?.source == .manual { return }
        guard minutesByCategory.keys.allSatisfy({ id in base.usages.contains(where: { $0.category.rawValue == id }) }) else {
            throw FootprintError.invalidInput("The returned activity does not match this day's saved setup. This day has been kept.")
        }
        if usesAutomaticInput {
            let expected = Set(base.usages.map { $0.category.rawValue })
            guard Set(minutesByCategory.keys) == expected else {
                throw FootprintError.invalidInput("Screen Time has not returned a complete day for all selected categories yet.")
            }
        }
        var inputs = base
        // [20] Keep the queried day's capacity with its record. Reopening while
        // travelling must not reinterpret a valid 25-hour day as 24 hours.
        inputs.calendarDayMinutes = capacity
        if let previous = records.first(where: { $0.day == day && $0.source == .screenTimeWithEstimates }) {
            guard let routine = archive?.revisions.last(where: { $0.effectiveDay <= day })?.inputs else {
                throw FootprintError.damagedArchive
            }
            // [21] A new mapping replaces the previous import. Old measured values
            // outside that mapping go back to the routine for this date.
            let previouslyMeasured = Set(previous.automaticCategories ?? previous.inputs.usages.map(\.category))
            for index in inputs.usages.indices {
                let category = inputs.usages[index].category
                if previouslyMeasured.contains(category), minutesByCategory[category.rawValue] == nil {
                    guard let original = routine.usages.first(where: { $0.category == category }) else {
                        throw FootprintError.invalidInput("This day's saved settings do not match the new automatic input. Your earlier estimate has been kept.")
                    }
                    inputs.usages[index].minutes = original.minutes
                }
            }
        }
        // [22] Update only the categories returned for this day's saved setup.
        // Do not silently move another category's time into a different one.
        inputs.usages = inputs.usages.map { usage in
            var changed = usage
            if let measured = minutesByCategory[usage.category.rawValue] { changed.minutes = measured }
            return changed
        }
        let measured = FootprintCategory.allCases.filter { minutesByCategory[$0.rawValue] != nil }
        let wasAlreadyImported = records.contains { $0.day == day && $0.source == .screenTimeWithEstimates }
        try saveDay(day, inputs: inputs, source: .screenTimeWithEstimates, measuredCategories: measured, now: now)
        // [32] The history has reached disk now. Record this real completion separately from the
        // date used to plan the calculation; a failed check must not undo a good saved day.
        importVerification.recordSuccessfulSave(day: day, wasAlreadyImported: wasAlreadyImported, origin: origin,
                                               completionState: verificationCompletionState())
    }

    func deleteAll() throws {
        // [35] Invalidate the shared ticket first, so an older widget query cannot restore a deleted day.
        try automaticWidgetExchange?.disableAndClear()
        // [23] Clear the widget summary first. If that fails, do not claim everything was deleted
        // while an old saved amount is still available to the widget.
        try widgetPublisher?.publish(nil)
        try importVerification.clear()
        try WidgetVerificationMirror.clear(at: widgetCheckFileURL)
        if FileManager.default.fileExists(atPath: widgetReconciliationFileURL.path) {
            try FileManager.default.removeItem(at: widgetReconciliationFileURL)
        }
        #if DFE_WIDGET_AUTOMATIC_IMPORT
        if let automaticWidgetReceiptDirectory {
            try WidgetAutomaticReceiptMirror.clearCopies(in: automaticWidgetReceiptDirectory)
        }
        #endif
        if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
        archive = nil
        unreadableArchive = false
        errorMessage = nil
        publishWidgetSnapshot()
        // [45] Clearing the shared file first may leave no later publisher change to trigger a reload.
        if automaticWidgetExchange != nil { widgetPublisher?.reloadAfterClearing() }
    }

    func report(_ error: Error) { errorMessage = error.localizedDescription }

    // [37] The shared ticket is available only to the normal app, never to an isolated test host.
    private static func availableAutomaticWidgetExchange() -> WidgetAutomaticExchange? {
        let storage = WidgetSnapshotStorage.configured()
        guard storage.directory != nil else { return nil }
        return WidgetAutomaticExchange(directory: storage.directory)
    }

    /// [38] Share the confirmed scope, not merely the presence of an old automatic archive.
    /// A later all-app opt-in must not silently include days from an earlier selected-app setup.
    func configureWidgetAutomaticInput(enabled: Bool?, earliestDay: String? = nil,
                                       allowResumingAfterWithdrawal: Bool = false) throws {
        guard let automaticWidgetExchange else { return }
        if let earliestDay { widgetImportStartDay = earliestDay }
        let previous = try automaticWidgetExchange.currentContext()
        // [49] Installing this feature over an earlier automatic setup is not a withdrawal.
        // Wait for the real decision before creating either a shared ticket or a deny marker.
        if enabled == nil && previous == nil {
            try reconcileWidgetPendingRecords()
            return
        }
        // [43] A fresh process can have an unsettled Apple status. Keep the explicit saved choice;
        // only Apple's data API can decide whether the next query is allowed.
        let effectiveEnabled = enabled ?? previous?.enabled ?? false
        if !effectiveEnabled {
            // [39] Rotate the ticket before draining saved work. Calls already running can no longer commit.
            _ = try automaticWidgetExchange.publishContext(from: archive, enabled: false,
                calendar: aggregationCalendar, classificationRevision: AutomaticActivityClassification.revision,
                eligibleStartDay: widgetContextStartDay())
        }
        try reconcileWidgetPendingRecords()
        // [48] Old preferences cannot undo a withdrawal after a crash or a failed system call.
        // Only a new, explicit successful setup may reopen this gate.
        if effectiveEnabled && !allowResumingAfterWithdrawal {
            if try automaticWidgetExchange.newQueriesAreBlocked() { return }
        }
        _ = try automaticWidgetExchange.publishContext(from: archive, enabled: effectiveEnabled,
            calendar: aggregationCalendar, classificationRevision: AutomaticActivityClassification.revision,
            eligibleStartDay: widgetContextStartDay())
    }

    // [46] Withdrawal must not depend on decoding a possibly damaged shared file.
    // Pause new queries first, then keep completed work when it can still be checked.
    func blockWidgetAutomaticInput() {
        guard let automaticWidgetExchange else { return }
        do { try automaticWidgetExchange.blockNewQueries() }
        catch { errorMessage = "The widget pause could not be saved. Screen Time can still be disconnected." }
        do { try configureWidgetAutomaticInput(enabled: false) }
        catch { errorMessage = "The widget update could not be checked. Your saved history is kept." }
    }

    private func widgetContextStartDay() -> String? {
        if let widgetImportStartDay { return widgetImportStartDay }
        return (try? automaticWidgetExchange?.currentContext())?.configuration.eligibleStartDay
    }

    private func refreshAutomaticWidgetContext() throws {
        guard let automaticWidgetExchange else { return }
        guard let current = try automaticWidgetExchange.currentContext() else { return }
        let wasEnabled = current.enabled
        let blocked = try automaticWidgetExchange.newQueriesAreBlocked()
        let enabled = wasEnabled && !blocked
        _ = try automaticWidgetExchange.publishContext(from: archive, enabled: enabled,
            calendar: aggregationCalendar, classificationRevision: AutomaticActivityClassification.revision,
            eligibleStartDay: widgetContextStartDay())
    }

    // [40] A widget first saves a complete pending day. Merge it before publishing from private history,
    // then acknowledge its ID only after that history has reached disk.
    private func reconcileWidgetPendingRecords() throws {
        guard let automaticWidgetExchange else { return }
        let pending = try automaticWidgetExchange.pendingRecords()
        guard !pending.isEmpty else { return }
        guard var next = archive, next.usesAutomaticInput, let start = next.automaticStartDay else {
            throw WidgetAutomaticExchangeError.invalidData
        }
        var accepted = Set<UUID>()
        var changed = false
        for item in pending.sorted(by: { $0.record.day < $1.record.day }) {
            let record = item.record
            if next.records.contains(where: { $0.day == record.day && $0.source == .manual }) {
                accepted.insert(item.id)
                continue
            }
            guard item.classificationRevision == AutomaticActivityClassification.revision,
                  item.modelRevision == "shared-ios-v1", record.day >= start,
                  days.date(record.day) != nil, record.day < today,
                  item.originSavedAt <= Date().addingTimeInterval(5),
                  record.calculatedAt <= item.originSavedAt.addingTimeInterval(5),
                  let sourceCalendar = calendarForWidgetReceipt(item),
                  let sourceDate = FootprintCalendar(calendar: sourceCalendar).date(record.day),
                  let interval = sourceCalendar.dateInterval(of: .day, for: sourceDate),
                  record.inputs.calendarDayMinutes == interval.duration / 60,
                  let routine = next.revisions.last(where: { $0.effectiveDay <= record.day })?.inputs else {
                throw WidgetAutomaticExchangeError.invalidData
            }
            // [41] The host checks the same assumptions and calculator again. A pending file cannot choose new inputs.
            var normalized = record.inputs
            normalized.calendarDayMinutes = nil
            for index in normalized.usages.indices { normalized.usages[index].minutes = 0 }
            var expected = routine
            expected.calendarDayMinutes = nil
            for index in expected.usages.indices { expected.usages[index].minutes = 0 }
            guard normalized == expected,
                  Set(record.automaticCategories ?? []) == Set(record.inputs.usages.map(\.category)),
                  try calculator.calculate(record.inputs) == record.result else {
                throw WidgetAutomaticExchangeError.invalidData
            }
            // [42] Manual corrections always win. For automatic days, a later valid calculation may
            // replace an older one, while replaying an equal or older handoff changes nothing.
            if let index = next.records.firstIndex(where: { $0.day == record.day }) {
                let existing = next.records[index]
                if existing.source == .routineEstimate
                    || (existing.source == .screenTimeWithEstimates && record.calculatedAt > existing.calculatedAt) {
                    next.records[index] = record
                    changed = true
                }
            } else {
                next.records.append(record)
                changed = true
            }
            accepted.insert(item.id)
        }
        if changed {
            next.records.sort { $0.day < $1.day }
            recomputeGardens(&next, now: Date())
            try commit(next)
        }
        // [47] Keep the widget's original clock separate from this later host reconciliation.
        // A technical receipt failure must not undo a valid saved day.
        do { try recordWidgetReconciliation(pending.filter { accepted.contains($0.id) }) }
        catch { errorMessage = "The widget check could not be saved. Your history is kept." }
        try automaticWidgetExchange.acknowledge(ids: accepted)
    }

    private func recordWidgetReconciliation(_ pending: [WidgetAutomaticPendingRecord]) throws {
        guard !pending.isEmpty else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var previous = (try? decoder.decode([WidgetImportReconciliationCheck].self,
            from: Data(contentsOf: widgetReconciliationFileURL))) ?? []
        let identifiers = Set(pending.map(\.id))
        previous.removeAll { identifiers.contains($0.pendingID) }
        let now = Date()
        previous.append(contentsOf: pending.map {
            WidgetImportReconciliationCheck(pendingID: $0.id, day: $0.record.day,
                widgetSavedAt: $0.originSavedAt, widgetCalculatedAt: $0.record.calculatedAt,
                hostReconciledAt: now, widgetProducer: $0.producer, hostProducer: .current)
        })
        previous = Array(previous.sorted { $0.hostReconciledAt < $1.hostReconciledAt }.suffix(32))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(previous).write(to: widgetReconciliationFileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func calendarForWidgetReceipt(_ item: WidgetAutomaticPendingRecord) -> Calendar? {
        guard let zone = TimeZone(identifier: item.timeZoneIdentifier) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private func load() throws {
        do { try readArchive() }
        catch {
            // [24] Keep both the unreadable disk file and the last known in-memory
            // state. Every mutation stays blocked until an explicit recovery.
            unreadableArchive = true
            try? widgetPublisher?.publish(nil)
            throw error
        }
        do { try reconcileWidgetPendingRecords() }
        catch {
            // [44] A bad handoff is not a damaged private history. Keep both saved files,
            // and avoid publishing an older garden over work that has not been checked yet.
            errorMessage = "The widget update could not be checked. Your saved history is kept."
            return
        }
        publishWidgetSnapshot()
    }

    // [25] Treat the saved file as untrusted input. Invalid dates, repeated days or an unknown
    // file version must not be accepted as a good history.
    private func readArchive() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { archive = nil; return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded: FootprintArchive
        do { loaded = try decoder.decode(FootprintArchive.self, from: Data(contentsOf: fileURL)) }
        catch { throw FootprintError.damagedArchive }
        guard loaded.version == 1 else { throw FootprintError.unsupportedArchive }
        guard days.date(loaded.firstDay) != nil, !loaded.revisions.isEmpty,
              loaded.revisions.first?.effectiveDay == loaded.firstDay,
              loaded.records.map(\.day) == loaded.records.map(\.day).sorted(),
              loaded.revisions.map(\.effectiveDay) == loaded.revisions.map(\.effectiveDay).sorted(),
              Set(loaded.records.map(\.day)).count == loaded.records.count,
              loaded.records.allSatisfy({ days.date($0.day) != nil && $0.day >= loaded.firstDay }),
              loaded.revisions.allSatisfy({ days.date($0.effectiveDay) != nil && $0.effectiveDay >= loaded.firstDay }) else {
            throw FootprintError.damagedArchive
        }
        if let startDay = loaded.automaticStartDay {
            guard loaded.usesAutomaticInput, days.date(startDay) != nil, startDay >= loaded.firstDay,
                  loaded.revisions.contains(where: { $0.effectiveDay == startDay }) else {
                throw FootprintError.damagedArchive
            }
        }
        for record in loaded.records { try record.inputs.validate(); try record.result.validate() }
        for revision in loaded.revisions { try revision.inputs.validate() }
        archive = loaded
    }

    // [26] Keep the source beside the calculation so a future screen can distinguish imported time from assumptions.
    private func makeRecord(day: String, inputs: FootprintInputs, source: FootprintSource, measuredCategories: [FootprintCategory] = [], now: Date) throws -> FootprintRecord {
        let result = try calculator.calculate(inputs)
        try result.validate()
        return FootprintRecord(day: day, inputs: inputs, result: result, source: source, calculatedAt: now,
                               isCompleted: day < days.key(now), garden: .stable, baselineKg: nil,
                               automaticCategories: measuredCategories.isEmpty ? nil : measuredCategories)
    }

    private func recomputeGardens(_ next: inout FootprintArchive, now: Date) {
        // [27] Rebuild every later baseline after a past-day correction. A day's own
        // result is excluded from its comparison, as in the Android garden.
        for index in next.records.indices {
            let previous = next.records[..<index].suffix(7)
            let baseline = previous.isEmpty ? nil : previous.reduce(0) { $0 + $1.result.totalKg } / Double(previous.count)
            next.records[index].baselineKg = baseline
            next.records[index].garden = .state(total: next.records[index].result.totalKg, baseline: baseline)
            next.records[index].isCompleted = next.records[index].day < days.key(now)
        }
    }

    private func commit(_ next: FootprintArchive) throws {
        var committed = next
        // [28] A manual correction must not remove an earlier import's origin.
        committed.screenTimeDataImported = next.containsScreenTimeDerivedData
            || archive?.containsScreenTimeDerivedData == true
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(committed)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // [29] Apply file protection during the complete replacement, rather than leaving an unprotected copy.
        // After the phone's first unlock, later background updates can use the saved file.
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
        // [30] Update the screen and widget only after the protected history file has been saved successfully.
        archive = committed
        errorMessage = nil
        // [36] The private save comes first. Sharing the updated setup must not undo it on a storage error.
        do { try refreshAutomaticWidgetContext() }
        catch { errorMessage = "The widget setup could not be updated. Your saved day is kept." }
        publishWidgetSnapshot()
    }

    private func publishWidgetSnapshot() {
        // [31] Share only from saved history. If the widget summary fails, keep the successful
        // history save and give a later refresh another chance to publish it.
        do { try widgetPublisher?.publish(latest.map { GardenWidgetSnapshot(record: $0) }) }
        catch { /* [33] The publisher keeps the failed check; the saved history stays available. */ }
        widgetVerification = widgetPublisher?.verification ?? WidgetPublicationVerification(
            status: .unavailable, day: latest?.day, checkedAt: Date(), publishedAt: nil,
            producer: .current, receiptStored: false)
        do {
            // [34] Mirror only the safe check, so a local test can confirm shared storage
            // without copying the garden's values out of its container.
            if latest == nil { try WidgetVerificationMirror.clear(at: widgetCheckFileURL) }
            else {
                try WidgetVerificationMirror.write(to: widgetCheckFileURL,
                    publication: widgetVerification, timelineReads: widgetReadChecks)
            }
            widgetCheckSaveFailed = false
        } catch { widgetCheckSaveFailed = true }
    }
}
