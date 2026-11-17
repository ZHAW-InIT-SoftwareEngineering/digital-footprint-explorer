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

/// [01] Share matching updates, but wait when the day or setup is different.
/// If iOS ends background work, the open app can share one recovery attempt.
@MainActor
final class RefreshCoordinator<Value: Sendable> {
    @MainActor
    private final class Flight {
        let key: UUID
        let context: String?
        let task: Task<Value, Error>
        var recovery: Flight?
        init(key: UUID, context: String?, task: Task<Value, Error>) {
            self.key = key; self.context = context; self.task = task
        }
        func matches(key: UUID, context: String?) -> Bool {
            self.key == key && self.context == context
        }
    }
    private var active: Flight?
    private(set) var waitingRequests = 0

    // [02] Treat matching requests like people sharing one order: wait for the same work
    // instead of asking Apple for the same day several times at once.
    func perform(key: UUID, context: String? = nil, _ operation: @escaping @MainActor @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        guard let running = active else { return try await own(makeFlight(key: key, context: context, operation)) }
        waitingRequests += 1
        defer { waitingRequests -= 1 }
        if !running.matches(key: key, context: context) {
            // [03] A new day, zone or setup must not reuse another refresh's result.
            // Wait without cancelling another owner's job, then run this one.
            do { _ = try await running.task.value } catch { }
            if active === running { active = nil }
            try Task.checkCancellation()
            return try await perform(key: key, context: context, operation)
        }
        do {
            let value = try await running.task.value
            try Task.checkCancellation()
            return value
        } catch is CancellationError {
            try Task.checkCancellation()
            return try await recover(after: running, operation: operation)
        }
    }

    private func makeFlight(key: UUID, context: String?, _ operation: @escaping @MainActor @Sendable () async throws -> Value) -> Flight {
        let flight = Flight(key: key, context: context, task: Task { @MainActor in try await operation() })
        active = flight
        return flight
    }

    // [04] When the request that started this work stops, cancel its work too.
    // A waiting foreground request can then use the shared recovery path.
    private func own(_ flight: Flight) async throws -> Value {
        defer { if active === flight { active = nil } }
        let task = flight.task
        let value = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        try Task.checkCancellation()
        return value
    }

    // [05] Keep one shared retry after background time expires, rather than letting each waiting screen start another.
    private func recover(after cancelled: Flight,
                         operation: @escaping @MainActor @Sendable () async throws -> Value) async throws -> Value {
        if let recovery = cancelled.recovery {
            let value = try await recovery.task.value
            try Task.checkCancellation()
            return value
        }
        if let running = active, running !== cancelled {
            if running.matches(key: cancelled.key, context: cancelled.context) {
                cancelled.recovery = running
                let value = try await running.task.value
                try Task.checkCancellation()
                return value
            }
            do { _ = try await running.task.value } catch { }
            if active === running { active = nil }
            try Task.checkCancellation()
            return try await recover(after: cancelled, operation: operation)
        }
        let retry = makeFlight(key: cancelled.key, context: cancelled.context, operation)
        cancelled.recovery = retry
        return try await own(retry)
    }
}

enum ScreenTimeRefreshOutcome: String, Sendable {
    case imported, pending, noAccess = "no_access", error, noNewRecord = "no_new_record"
}

/// [06] Finishing an update is not the same as saving a usable day. Keep both outcomes clear.
struct ScreenTimeRefreshResult: Equatable, Sendable {
    var attemptedDays = 0
    var importedDays = 0
    var pendingDays = 0
    var newRecords = 0
    var stoppedForAccess = false
    var stoppedForError = false
    var latestCompletedDayRefreshed = false

    var outcome: ScreenTimeRefreshOutcome {
        if stoppedForAccess { return .noAccess }
        if stoppedForError { return .error }
        if importedDays > 0 { return .imported }
        if pendingDays > 0 { return .pending }
        return .noNewRecord
    }
    var completedWithoutFatalError: Bool { !stoppedForAccess && !stoppedForError }
}


// [07] A receipt names a day that was actually saved; an attempted query is not a completed import.
struct ScreenTimeDayImportReceipt {
    let day: Date
    let created: Bool
}

enum ScreenTimeDayImportFailure { case pending, noAccess, error }

enum ScreenTimeRefreshContextError: LocalizedError {
    case timeZoneChanged
    var errorDescription: String? {
        "Your time zone changed during the update. Existing results are safe. The app can try again in your current time zone."
    }
}

/// [08] Keep this query on the day and time zone it started with.
/// A named time zone keeps its clock-change rules while the phone's settings may move on.
struct ScreenTimeCalendarSnapshot {
    let calendar: Calendar
    private let timeZoneIdentifier: String

    init(_ source: Calendar) {
        timeZoneIdentifier = source.timeZone.identifier
        var frozen = source
        frozen.timeZone = TimeZone(identifier: timeZoneIdentifier)
            ?? TimeZone(secondsFromGMT: source.timeZone.secondsFromGMT())!
        calendar = frozen
    }

    // [09] If travel changes the time zone during a query, try again instead of saving a day under the wrong boundary.
    func requireCurrent(_ current: Calendar) throws {
        guard current.timeZone.identifier == timeZoneIdentifier else {
            throw ScreenTimeRefreshContextError.timeZoneChanged
        }
    }
}

/// [10] Opening in the background can also create screens. Older gaps should be added
/// only when the app is actively open, leaving background time for yesterday.
struct AppRefreshBackfillPolicy {
    static func limit(isApplicationActive: Bool) -> Int {
        isApplicationActive ? ScreenTimeImportPlan.foregroundBackfillLimit : 0
    }
}

/// [11] Try yesterday first, then give older missing days a turn.
/// The saved place only changes retry order; it is not proof that a day was imported.
struct ScreenTimeImportPlan {
    static let foregroundBackfillLimit = 6
    let dates: [Date]
    let nextBackfillDay: [Date: Date]

    // [12] Give yesterday the first chance, then rotate through a few older gaps.
    // This keeps a long history from using up every background opportunity.
    static func make(start: Date, today: Date, calendar: Calendar, cursor: Date?,
                     backfillLimit: Int = foregroundBackfillLimit,
                     shouldRefreshLatest: (Date) -> Bool,
                     shouldBackfill: (Date) -> Bool) -> ScreenTimeImportPlan {
        let start = calendar.startOfDay(for: start)
        let today = calendar.startOfDay(for: today)
        guard let latest = calendar.date(byAdding: .day, value: -1, to: today), start <= latest else {
            return ScreenTimeImportPlan(dates: [], nextBackfillDay: [:])
        }
        var dates = shouldRefreshLatest(latest) ? [latest] : []
        var successors: [Date: Date] = [:]
        let limit = max(0, min(backfillLimit, foregroundBackfillLimit))
        guard start < latest, limit > 0 else {
            return ScreenTimeImportPlan(dates: dates, nextBackfillDay: successors)
        }
        let candidate = cursor.map { calendar.startOfDay(for: $0) }
        let first = candidate.flatMap { $0 >= start && $0 < latest ? $0 : nil } ?? start
        var day = first
        var backfilled = 0
        repeat {
            guard let following = calendar.date(byAdding: .day, value: 1, to: day), following > day else { break }
            let next = following < latest ? following : start
            if shouldBackfill(day) {
                dates.append(day)
                successors[day] = next
                backfilled += 1
                if backfilled == limit { break }
            }
            day = next
        } while day != first
        return ScreenTimeImportPlan(dates: dates, nextBackfillDay: successors)
    }
}

/// [13] The service checks Apple access and validates each day before saving it.
/// Count saved days separately from attempts, even while an older day is still missing.
@MainActor
enum ScreenTimeCompletedDayImporter {
    static func run(start: Date, today: Date, calendar: Calendar,
                    shouldImport: (Date) -> Bool,
                    importDay: (Date) async throws -> ScreenTimeDayImportReceipt?,
                    onError: (Error) -> ScreenTimeDayImportFailure) async throws -> ScreenTimeRefreshResult {
        var dates: [Date] = []
        var day = start
        while day < today {
            try Task.checkCancellation()
            dates.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return try await run(dates: dates, today: today, calendar: calendar,
            shouldImport: shouldImport, importDay: importDay, onError: onError)
    }

    // [14] Save completed days one by one. A missing older day can wait, while loss of permission
    // stops further reading and leaves earlier saved days intact.
    static func run(dates: [Date], today: Date, calendar: Calendar,
                    shouldImport: (Date) -> Bool,
                    onAttempt: (Date) -> Void = { _ in },
                    importDay: (Date) async throws -> ScreenTimeDayImportReceipt?,
                    onError: (Error) -> ScreenTimeDayImportFailure) async throws -> ScreenTimeRefreshResult {
        var result = ScreenTimeRefreshResult()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        for day in dates where day < today {
            try Task.checkCancellation()
            if shouldImport(day) {
                do {
                    result.attemptedDays += 1
                    onAttempt(day)
                    if let receipt = try await importDay(day) {
                        try Task.checkCancellation()
                        result.importedDays += 1
                        if receipt.created { result.newRecords += 1 }
                        if let yesterday, calendar.isDate(receipt.day, inSameDayAs: yesterday) {
                            result.latestCompletedDayRefreshed = true
                        }
                    }
                } catch is CancellationError { throw CancellationError() }
                catch let error as ScreenTimeRefreshContextError {
                    // [15] A day checked in the old time zone must not trigger a notice using the new zone.
                    throw error
                }
                catch {
                    switch onError(error) {
                    case .pending: result.pendingDays += 1
                    case .noAccess: result.stoppedForAccess = true; return result
                    case .error: result.stoppedForError = true; return result
                    }
                }
            }
        }
        return result
    }
}
