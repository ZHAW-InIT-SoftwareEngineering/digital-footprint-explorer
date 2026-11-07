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

/// [01] The IDs match the shared Android calculation model.
enum FootprintCategory: String, Codable, CaseIterable, Identifiable {
    case video = "VIDEO_STREAMING"
    case audio = "AUDIO_STREAMING"
    case social = "SOCIAL_MEDIA"
    case messaging = "MESSAGING"
    case ai = "ARTIFICIAL_INTELLIGENCE"
    case email = "E_MAIL"
    case calls = "VIDEO_CALL"
    case gaming = "GAMING"
    case navigation = "NAVIGATION"
    case other = "MISCELLANEOUS"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .video: "Video streaming"
        case .audio: "Music and podcasts"
        case .social: "Social media"
        case .messaging: "Messaging"
        case .ai: "AI tools"
        case .email: "Email"
        case .calls: "Video calls"
        case .gaming: "Games"
        case .navigation: "Maps and navigation"
        case .other: "Other apps"
        }
    }
    var symbol: String {
        switch self {
        case .video: "play.rectangle"
        case .audio: "headphones"
        case .social: "person.2"
        case .messaging: "bubble.left.and.bubble.right"
        case .ai: "sparkles"
        case .email: "envelope"
        case .calls: "video"
        case .gaming: "gamecontroller"
        case .navigation: "map"
        case .other: "square.grid.2x2"
        }
    }

}

// [02] Keep usage time separate from the traffic and connection assumptions used to estimate emissions.
struct CategoryUsage: Codable, Equatable, Identifiable {
    var category: FootprintCategory
    /// [03] Foreground minutes, counted once across the selected categories.
    var minutes: Double
    /// [04] Decimal GB of estimated traffic per hour of category use.
    var gigabytesPerHour: Double
    /// [05] A fraction between 0 and 1, rather than a percentage.
    var wifiShare: Double
    var id: String { category.rawValue }
    init(category: FootprintCategory, minutes: Double = 0, gigabytesPerHour: Double = 0, wifiShare: Double = 1) {
        self.category = category
        self.minutes = minutes
        self.gigabytesPerHour = gigabytesPerHour
        self.wifiShare = wifiShare
    }
}

// [06] Screen Time supplies available usage durations, while the remaining values describe
// the calculation assumptions. They are not measurements of the phone's emissions.
struct FootprintInputs: Codable, Equatable {
    var usages: [CategoryUsage]
    /// [07] Average normalized brightness during the entered foreground time.
    var brightness: Double
    // [08] Background durations are independent; GPS and Bluetooth can overlap.
    var gpsHours: Double
    var bluetoothHours: Double
    /// [09] Only an imported record stores this value. A civil day may be 23 or 25 hours.
    /// Missing metadata keeps the original 24-hour contract for older history.
    var calendarDayMinutes: Double? = nil
    var usageCapacityMinutes: Double { calendarDayMinutes ?? 1440 }

    static func isValidCalendarDayCapacity(_ minutes: Double) -> Bool {
        // [10] Some time-zone changes are larger than one hour. Reject impossible day lengths,
        // and let the import also check the exact day that Apple returned.
        minutes.isFinite && minutes > 0 && minutes <= 2880
            && minutes.rounded(.towardZero) == minutes
    }
    static let empty = FootprintInputs(usages: [], brightness: 0.5, gpsHours: 0, bluetoothHours: 0)
    var totalMinutes: Double { usages.reduce(0) { $0 + $1.minutes } }

    // [11] Stop impossible or incomplete values before they can change the saved garden.
    func validate() throws {
        guard Self.isValidCalendarDayCapacity(usageCapacityMinutes) else {
            throw FootprintError.invalidInput("This day's saved duration is not valid.")
        }
        guard !usages.isEmpty else { throw FootprintError.invalidInput("Choose at least one category.") }
        guard Set(usages.map(\.category)).count == usages.count else {
            throw FootprintError.invalidInput("Each category can only be entered once.")
        }
        guard brightness.isFinite, (0...1).contains(brightness),
              gpsHours.isFinite, (0...24).contains(gpsHours),
              bluetoothHours.isFinite, (0...24).contains(bluetoothHours) else {
            throw FootprintError.invalidInput("Brightness must be between 0 and 100%. Background use must be between 0 and 24 hours.")
        }
        for usage in usages {
            guard usage.minutes.isFinite, (0...usageCapacityMinutes).contains(usage.minutes),
                  usage.gigabytesPerHour.isFinite, (0...100).contains(usage.gigabytesPerHour),
                  usage.wifiShare.isFinite, (0...1).contains(usage.wifiShare) else {
                throw FootprintError.invalidInput("Check the minutes, data rate and Wi-Fi share for \(usage.category.title).")
            }
        }
        // [12] Reject excess daily time instead of clipping the person's input.
        guard totalMinutes <= usageCapacityMinutes else {
            let message = usageCapacityMinutes == 1440
                ? "The category times add up to more than 24 hours. Enter time spent in the foreground once, even if audio plays in the background."
                : "The category times exceed this calendar day's duration. Your saved entries have been kept."
            throw FootprintError.invalidInput(message)
        }
    }
}

// [13] Keep the estimated device, network and server parts, so a total can be explained later.
struct CategoryFootprint: Codable, Equatable, Identifiable {
    let category: FootprintCategory
    let totalKg: Double
    let deviceKg: Double
    let networkKg: Double
    let backendKg: Double
    var id: String { category.rawValue }
}

// [14] Store both the total and its parts; the interface can explain where the estimate comes from.
struct FootprintResult: Codable, Equatable {
    let totalKg: Double
    let appUsageKg: Double
    let displayKg: Double
    let backgroundKg: Double
    let categories: [CategoryFootprint]
    // [15] A saved estimate must add up, not just contain readable numbers. Allow tiny rounding
    // differences and keep older total-only history, but stop broken parts before they reach the garden.
    func validate() throws {
        let values = [totalKg, appUsageKg, displayKg, backgroundKg] + categories.flatMap {
            [$0.totalKg, $0.deviceKg, $0.networkKg, $0.backendKg]
        }
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw FootprintError.invalidResult
        }
        func matches(_ actual: Double, _ expected: Double) -> Bool {
            guard expected.isFinite else { return false }
            let tolerance = max(1e-12, max(abs(actual), abs(expected)) * 1e-10)
            return abs(actual - expected) <= tolerance
        }
        guard matches(totalKg, appUsageKg + displayKg + backgroundKg),
              Set(categories.map(\.category)).count == categories.count,
              categories.allSatisfy({ matches($0.totalKg, $0.deviceKg + $0.networkKg + $0.backendKg) }) else {
            throw FootprintError.invalidResult
        }
        if !categories.isEmpty {
            guard matches(appUsageKg, categories.reduce(0) { $0 + $1.totalKg }) else {
                throw FootprintError.invalidResult
            }
        }
    }
}

protocol FootprintCalculating {
    func calculate(_ inputs: FootprintInputs) throws -> FootprintResult
}

// [16] Older manual entries remain readable, but an imported time must still be labelled
// as Screen Time with estimates rather than measured carbon emissions.
enum FootprintSource: String, Codable {
    case manual
    case routineEstimate
    case screenTimeWithEstimates
    var title: String {
        switch self {
        case .manual: "Manual entry"
        case .routineEstimate: "Routine estimate"
        case .screenTimeWithEstimates: "Screen Time with estimates"
        }
    }
    var explanation: String {
        switch self {
        case .manual: "You entered the usage time. Data use, brightness and background use are estimates from your settings."
        case .routineEstimate: "This earlier estimate uses the routine that was active on that date. It is kept as read-only history."
        case .screenTimeWithEstimates: "Screen Time supplied app usage time for the recorded categories. App grouping, data use, brightness and background use remain estimates."
        }
    }
}

// [17] The garden compares a day with earlier saved estimates, so it reflects a personal trend
// rather than claiming that a certain amount of phone use is safe.
enum FootprintGarden: String, Codable {
    case flourishing, growing, stable, wilting, withered
    var title: String { rawValue.capitalized }
    static func state(total: Double, baseline: Double?) -> FootprintGarden {
        guard let baseline, baseline > 0 else {
            // [18] Zero-use days should not produce a division by zero.
            return baseline == 0 && total > 0 ? .withered : .stable
        }
        // [19] Computer rounding should not push a value into the next garden state
        // when it is meant to sit exactly on a comparison limit.
        func atLimit(_ limit: Double) -> Bool {
            abs(total - limit) <= max(total.ulp, limit.ulp) * 4
        }
        let flourishingLimit = baseline * 0.7
        let growingLimit = baseline * 0.9
        let wiltingLimit = baseline * 1.1
        let witheredLimit = baseline * 1.4
        if total < flourishingLimit || atLimit(flourishingLimit) { return .flourishing }
        if total < growingLimit || atLimit(growingLimit) { return .growing }
        if total < wiltingLimit && !atLimit(wiltingLimit) { return .stable }
        if total < witheredLimit || atLimit(witheredLimit) { return .wilting }
        return .withered
    }
}

// [20] Keep the inputs, result and source together. Later explanations should describe
// what was actually saved for this date, not the person's newest settings.
struct FootprintRecord: Codable, Equatable, Identifiable {
    let day: String
    var inputs: FootprintInputs
    var result: FootprintResult
    var source: FootprintSource
    var calculatedAt: Date
    var isCompleted: Bool
    var garden: FootprintGarden
    var baselineKg: Double?
    /// [21] Keep which categories came from Apple for this date.
    /// Older history and manual entries may not have this information.
    var automaticCategories: [FootprintCategory]? = nil
    var id: String { day }
}

/// [22] A later routine change must not silently rewrite missing days in the past.
struct RoutineRevision: Codable, Equatable {
    let effectiveDay: String
    let savedAt: Date
    let inputs: FootprintInputs
}

enum FootprintInputPreference: String, Codable {
    case manual
    case automatic
}

// [23] One history file keeps the starting date, setting changes and saved days together.
struct FootprintArchive: Codable, Equatable {
    var version: Int = 1
    var firstDay: String
    var revisions: [RoutineRevision]
    var records: [FootprintRecord]
    // [24] Older files lack this flag. Existing imported records still identify them.
    var screenTimeDataImported: Bool? = nil
    // [25] Missing in older files, which keep their original manual routine.
    var inputPreference: FootprintInputPreference? = nil
    // [26] Switching from manual input starts a new measured period, not older history.
    var automaticStartDay: String? = nil
    var usesAutomaticInput: Bool { inputPreference == .automatic }
    var containsScreenTimeDerivedData: Bool {
        screenTimeDataImported == true || records.contains { $0.source == .screenTimeWithEstimates }
    }
}

enum FootprintError: LocalizedError {
    case invalidInput(String)
    case invalidResult
    case notConfigured
    case invalidDay
    case unsupportedArchive
    case damagedArchive
    var errorDescription: String? {
        switch self {
        case .invalidInput(let message): message
        case .invalidResult: "The calculation did not return a valid result. Your saved entries have been kept."
        case .notConfigured: "Enable automatic input first."
        case .invalidDay: "Choose a date between your first day and today."
        case .unsupportedArchive: "This history was saved by a newer version of the app. Your file has been kept."
        case .damagedArchive: "The saved history could not be read. Your file has been kept. You can try again or delete the saved file to start again."
        }
    }
}

/// [27] Calendar arithmetic preserves calendar days across daylight-saving changes.
struct FootprintCalendar {
    var calendar: Calendar
    /// [28] Day IDs always use Gregorian dates. A phone's language or preferred
    /// calendar cannot reinterpret saved keys; its current time zone defines midnight.
    static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }
    init(calendar: Calendar = FootprintCalendar.localCalendar) { self.calendar = calendar }
    func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    // [29] Reject dates that only look valid, such as a day beyond the end of a month.
    func date(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        guard let value = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])), self.key(value) == key else { return nil }
        return value
    }
    func next(_ key: String) -> String? {
        guard let date = date(key), let next = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
        return self.key(next)
    }
}
