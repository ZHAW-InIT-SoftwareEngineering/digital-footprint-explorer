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

enum WidgetGardenState: String, Codable, CaseIterable {
    case flourishing, growing, stable, wilting, withered
    var title: String { rawValue.capitalized }
    var imageName: String { "Garden" + title }
}

// [01] Keep the input source visible so a small widget does not turn an estimate into a claimed measurement.
enum WidgetEstimateSource: String, Codable {
    case manual, routineEstimate, screenTimeWithEstimates
    var title: String {
        switch self {
        case .manual: "Manual entry"
        case .routineEstimate: "Routine estimate"
        case .screenTimeWithEstimates: "Screen Time + estimates"
        }
    }
    var compactTitle: String {
        switch self {
        case .manual: "Manual entry"
        case .routineEstimate: "Routine estimate"
        case .screenTimeWithEstimates: "Screen Time"
        }
    }
}

/// [02] Share only the saved total and garden summary. Detailed inputs and history stay in the app.
struct GardenWidgetSnapshot: Codable, Equatable {
    let day: String
    let totalKg: Double
    let garden: WidgetGardenState
    let source: WidgetEstimateSource
    let calculatedAt: Date
    let isCompleted: Bool

    static let widgetKind = "FootprintGardenWidget"
    static let appURL = URL(string: "digitalfootprint://today")!

    // [03] Read the saved date in a fixed zone for formatting; travel must not change which day it names.
    var dayDate: Date? {
        let pieces = day.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3, day.count == 10 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: pieces[0], month: pieces[1], day: pieces[2], hour: 12)) else { return nil }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        guard String(format: "%04d-%02d-%02d", actual.year!, actual.month!, actual.day!) == day else { return nil }
        return date
    }

    // [04] Reject a bad date or impossible amount instead of showing a misleading garden.
    func validate() throws {
        guard dayDate != nil, totalKg.isFinite, totalKg >= 0,
              (totalKg * 1_000).isFinite, calculatedAt.timeIntervalSince1970.isFinite else {
            throw WidgetSnapshotError.invalidData
        }
    }

    func isStale(on date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> Bool {
        day < dayKey(on: date, timeZone: timeZone)
    }

    func isCurrentDay(on date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> Bool {
        day == dayKey(on: date, timeZone: timeZone)
    }

    private func dayKey(on date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", values.year!, values.month!, values.day!)
    }

    // [05] An older result stays useful, but it must say it is the last saved day rather than today.
    func statusLabel(on date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        if isCurrentDay(on: date, timeZone: timeZone) {
            return isCompleted ? "Completed day" : "In progress"
        }
        return "Last saved day"
    }

    func amountLabel(locale: Locale = .autoupdatingCurrent) -> String {
        let grams = totalKg * 1_000
        let formatter = NumberFormatter()
        formatter.locale = locale
        // [06] Keep a small positive estimate visible instead of rounding it down to a displayed zero.
        formatter.numberStyle = grams > 0 && (grams < 0.001 || grams >= 1_000_000) ? .scientific : .decimal
        formatter.usesSignificantDigits = true
        formatter.minimumSignificantDigits = 1
        formatter.maximumSignificantDigits = 3
        return formatter.string(from: NSNumber(value: grams)) ?? String(grams)
    }

    // [07] Read the date, source and saved status with the amount, giving VoiceOver the same context as the visual card.
    func accessibilitySummary(on date: Date, timeZone: TimeZone = .autoupdatingCurrent,
                              locale: Locale = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .long
        let savedDay = dayDate.map { formatter.string(from: $0) } ?? day
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let savedAt = formatter.string(from: calculatedAt)
        let completion = isCompleted ? "Completed day." : "Day in progress."
        let freshness = isCurrentDay(on: date, timeZone: timeZone) ? "" : " This is the last saved day, not today's estimate."
        return "Your garden: \(garden.title). Estimated footprint: \(amountLabel(locale: locale)) grams of carbon dioxide equivalent. Saved for \(savedDay). \(completion) \(source.title). Last saved \(savedAt).\(freshness)"
    }

    // [08] This fixed example is for the gallery only. It must never be saved as someone's activity.
    static func preview(on date: Date) -> GardenWidgetSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        return GardenWidgetSnapshot(day: String(format: "%04d-%02d-%02d", values.year!, values.month!, values.day!),
                                    totalKg: 0.06, garden: .growing, source: .screenTimeWithEstimates,
                                    calculatedAt: date, isCompleted: false)
    }

    var dateLabel: String {
        guard let date = dayDate else { return day }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter.string(from: date)
    }
}

enum WidgetSnapshotError: Error { case invalidData, unsupportedVersion }

// [09] Keep a format version beside the summary so a newer, unreadable file can be declined safely.
struct WidgetSnapshotEnvelope: Codable {
    let version: Int
    let snapshot: GardenWidgetSnapshot?
    init(snapshot: GardenWidgetSnapshot?) { version = 1; self.snapshot = snapshot }
}
