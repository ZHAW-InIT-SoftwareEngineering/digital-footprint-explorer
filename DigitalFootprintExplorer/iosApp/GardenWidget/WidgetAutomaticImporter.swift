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

#if DFE_WIDGET_AUTOMATIC_IMPORT
import Foundation
import DeviceActivity
import WidgetKit
import os

// [01] The widget reads Apple's live data using the person's saved automatic opt-in.
// Its result uses the same calculation as DFE, then waits in a protected mailbox for the app.
enum WidgetAutomaticImporter {
    @MainActor private static var queryInFlight = false

    static func run(completion: @escaping () -> Void) {
        Task { @MainActor in
            // [02] A cancelled Apple call may still be finishing. Do not pile another query onto it.
            guard !queryInFlight else { completion(); return }
            guard #available(iOS 26.4, *),
                  let directory = WidgetSnapshotStorage.configured().directory else {
                completion()
                return
            }
            let exchange = WidgetAutomaticExchange(directory: directory)
            var calendar = FootprintCalendar.localCalendar
            // [12] Freeze the zone for this query, so travelling cannot move its day halfway through.
            calendar.timeZone = TimeZone(identifier: calendar.timeZone.identifier) ?? .current
            let request: WidgetAutomaticRequest
            do {
                // [10] A previous interrupted write may already have saved the day in the mailbox.
                // Repair its picture before deciding whether another query is needed.
                _ = try exchange.recoverPendingSnapshot()
                let eligible = try exchange.contextForYesterday(now: Date(), calendar: calendar)
                guard let eligible else {
                    completion()
                    return
                }
                request = eligible
            } catch {
                saveReceipt(.init(day: nil, queryStartedAt: nil, finishedAt: Date(), savedAt: nil,
                    status: .contextUnavailable, calculationSucceeded: false, pendingSaved: false,
                    elapsedMillis: 0, error: .fixed(error)), directory: directory)
                completion()
                return
            }

            queryInFlight = true
            let startedAt = Date()
            let startedUptime = ProcessInfo.processInfo.systemUptime
            let terminal = WidgetAutomaticTerminal(
                deadlineUptime: startedUptime + 8,
                timeout: { calculated in
                    saveReceipt(.init(day: request.day, queryStartedAt: startedAt,
                        finishedAt: Date(), savedAt: nil, status: .timedOut,
                        calculationSucceeded: calculated, pendingSaved: false,
                        elapsedMillis: elapsedMillis(since: startedUptime), error: nil), directory: directory,
                        contextEpoch: request.context.epoch)
                }, completion: completion)
            terminal.arm()
            let query = Task { @MainActor in
                // [03] Only the real end of the query frees its place. A timeout alone cannot do that.
                defer { queryInFlight = false }
                do {
                    let usage = try await AllActivityDayReader.collect(request.date, calendar: calendar) {
                        try validate(request, exchange: exchange, initialCalendar: calendar)
                    }
                    try Task.checkCancellation()
                    try validate(request, exchange: exchange, initialCalendar: calendar)
                    let inputs = try importedInputs(usage, request: request)
                    let result = try SharedFootprintCalculator().calculate(inputs)
                    try result.validate()
                    terminal.noteCalculationSucceeded()
                    // [04] Calculation has no file effects. Only the winning, still-current request may save.
                    terminal.finishQuery {
                        do {
                            try validate(request, exchange: exchange, initialCalendar: calendar)
                            let now = Date()
                            let record = FootprintRecord(day: request.day, inputs: inputs, result: result,
                                source: .screenTimeWithEstimates, calculatedAt: now, isCompleted: true,
                                garden: .state(total: result.totalKg, baseline: request.baselineKg),
                                baselineKg: request.baselineKg, automaticCategories: FootprintCategory.allCases)
                            let saved = try exchange.commit(record, expected: request, at: now,
                                calendar: FootprintCalendar.localCalendar)
                            // [14] The other widget size may still hold its previous timeline.
                            // Ask it to read this same saved day; the pending record prevents another import loop.
                            if saved { WidgetCenter.shared.reloadTimelines(ofKind: GardenWidgetSnapshot.widgetKind) }
                            saveReceipt(.init(day: request.day, queryStartedAt: startedAt, finishedAt: Date(),
                                savedAt: saved ? Date() : nil, status: saved ? .pendingSaved : .superseded,
                                calculationSucceeded: true, pendingSaved: saved,
                                elapsedMillis: elapsedMillis(since: startedUptime), error: nil), directory: directory,
                                contextEpoch: request.context.epoch)
                        } catch {
                            // [13] A snapshot error can happen after the pending day reached disk.
                            // Check that saved handoff before describing the whole attempt as a failed save.
                            let durable = (try? exchange.pendingRecords())?.contains {
                                $0.contextEpoch == request.context.epoch && $0.record.day == request.day
                                    && $0.record.inputs == inputs && $0.record.result == result
                            } == true
                            saveReceipt(.init(day: request.day, queryStartedAt: startedAt, finishedAt: Date(),
                                savedAt: durable ? Date() : nil,
                                status: durable ? .pendingSavedSnapshotPending : .commitRejected,
                                calculationSucceeded: true, pendingSaved: durable,
                                elapsedMillis: elapsedMillis(since: startedUptime), error: .fixed(error)), directory: directory,
                                contextEpoch: request.context.epoch)
                        }
                    }
                } catch {
                    terminal.finishQuery {
                        saveReceipt(.init(day: request.day, queryStartedAt: startedAt,
                            finishedAt: Date(), savedAt: nil, status: .queryFailed,
                            calculationSucceeded: false, pendingSaved: false,
                            elapsedMillis: elapsedMillis(since: startedUptime), error: .fixed(error)), directory: directory,
                            contextEpoch: request.context.epoch)
                    }
                }
            }
            terminal.setTask(query)
        }
    }

    // [11] These are scheduling requests, not an alarm. WidgetKit chooses the actual reload time.
    // Missing data gets a later retry; a saved day waits for the next useful morning.
    static func nextRefreshDate(now: Date = Date(), calendar: Calendar = FootprintCalendar.localCalendar) -> Date {
        let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now.addingTimeInterval(86_400)
        let nextMorning = morning > now ? morning
            : calendar.date(byAdding: .day, value: 1, to: morning) ?? now.addingTimeInterval(86_400)
        guard let directory = WidgetSnapshotStorage.configured().directory else { return nextMorning }
        do {
            let exchange = WidgetAutomaticExchange(directory: directory)
            if try exchange.contextForYesterday(now: now, calendar: calendar) != nil {
                let retry = now.addingTimeInterval(45 * 60)
                return morning > now ? max(retry, morning) : retry
            }
        } catch {
            return max(now.addingTimeInterval(45 * 60), morning > now ? morning : now)
        }
        return nextMorning
    }

    @MainActor
    private static func validate(_ request: WidgetAutomaticRequest, exchange: WidgetAutomaticExchange,
                                 initialCalendar: Calendar) throws {
        try Task.checkCancellation()
        let current = FootprintCalendar.localCalendar
        guard current.timeZone.identifier == initialCalendar.timeZone.identifier,
              try exchange.validateRequest(request, now: Date(), calendar: current) else {
            throw ScreenTimeImportError.selectionChanged
        }
    }

    // [05] The same daily limits used by the host apply here, including 23-hour and 25-hour days.
    private static func importedInputs(_ usage: AllActivityDayUsage,
                                       request: WidgetAutomaticRequest) throws -> FootprintInputs {
        let capacity = request.interval.duration / 60
        let expected = Set(FootprintCategory.allCases.map(\.rawValue))
        guard abs(usage.day.timeIntervalSince(request.interval.start)) <= 0.001,
              FootprintInputs.isValidCalendarDayCapacity(capacity),
              Set(usage.minutesByCategory.keys) == expected,
              Set(request.inputs.usages.map { $0.category.rawValue }) == expected,
              usage.minutesByCategory.values.allSatisfy({ $0.isFinite && (0...capacity).contains($0) }),
              usage.minutesByCategory.values.reduce(0, +) <= capacity else {
            throw ScreenTimeImportError.invalidDuration
        }
        var inputs = request.inputs
        inputs.calendarDayMinutes = capacity
        inputs.usages = inputs.usages.map { original in
            var changed = original
            changed.minutes = usage.minutesByCategory[original.category.rawValue]!
            return changed
        }
        try inputs.validate()
        return inputs
    }

    private static func elapsedMillis(since started: TimeInterval) -> Int {
        Int(max(0, (ProcessInfo.processInfo.systemUptime - started) * 1_000))
    }

    private static func saveReceipt(_ receipt: WidgetAutomaticReceipt, directory: URL, contextEpoch: UUID? = nil) {
        do {
            _ = try WidgetAutomaticReceiptStore(directory: directory).save(receipt, contextEpoch: contextEpoch)
        } catch {
            // [06] A failed technical note must not replace a valid garden or hold up WidgetKit.
        }
    }
}

#endif
