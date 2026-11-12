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

enum CompanionGardenState: String, Codable, CaseIterable, Sendable {
    case flourishing, growing, stable, wilting, withered
    var title: String { rawValue.capitalized }
    var imageName: String { "Garden" + title }
}

enum CompanionEstimateSource: String, Codable, Sendable {
    case manual, routineEstimate, screenTimeWithEstimates
    var title: String {
        switch self {
        case .manual: "Manual entry"
        case .routineEstimate: "Routine estimate"
        case .screenTimeWithEstimates: "Screen Time + estimates"
        }
    }
}

// [01] The Watch shows one result from the phone. It never receives the apps, their usage or the saved history.
struct CompanionGardenSnapshot: Codable, Equatable, Sendable {
    let day: String
    let totalKg: Double
    let garden: CompanionGardenState
    let source: CompanionEstimateSource
    let calculatedAt: Date
    let isCompleted: Bool

    var dayDate: Date? { Self.date(for: day) }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // [02] A day is a label, not a moment in another time zone. Noon in UTC keeps that label steady while travelling.
    static func date(for day: String) -> Date? {
        guard day.count == 10 else { return nil }
        let pieces = day.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces[0].count == 4, pieces[1].count == 2, pieces[2].count == 2,
              pieces.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let year = Int(pieces[0]), let month = Int(pieces[1]), let number = Int(pieces[2]),
              year >= 2000 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let value = calendar.date(from: DateComponents(year: year, month: month, day: number, hour: 12)),
              dayKey(value, calendar: calendar) == day else { return nil }
        return value
    }

    func validate(now: Date) throws {
        // [03] Allow the world's furthest-ahead time zone, but do not turn a bad future date into a real garden.
        var furthestZone = Calendar(identifier: .gregorian)
        furthestZone.timeZone = TimeZone(secondsFromGMT: 14 * 3_600)!
        guard dayDate != nil, day <= Self.dayKey(now, calendar: furthestZone),
              totalKg.isFinite, totalKg >= 0, (totalKg * 1_000).isFinite,
              calculatedAt.timeIntervalSince1970.isFinite,
              calculatedAt >= Date(timeIntervalSince1970: 0),
              calculatedAt <= now.addingTimeInterval(300) else {
            throw CompanionGardenError.invalidSnapshot
        }
    }

    func isOlderThanLatestCompletedDay(now: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        guard let yesterday = gregorian.date(byAdding: .day, value: -1, to: now) else { return true }
        return day < Self.dayKey(yesterday, calendar: gregorian)
    }

    var dateLabel: String {
        guard let date = dayDate else { return day }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter.string(from: date)
    }

    func amountLabel(locale: Locale = .autoupdatingCurrent) -> String {
        let grams = totalKg * 1_000
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = grams > 0 && (grams < 0.001 || grams >= 1_000_000) ? .scientific : .decimal
        formatter.usesSignificantDigits = true
        formatter.minimumSignificantDigits = 1
        formatter.maximumSignificantDigits = 3
        return formatter.string(from: NSNumber(value: grams)) ?? String(grams)
    }
}

enum CompanionGardenAvailability: String, Codable, Sendable {
    case available, empty, disconnected, sharingOff, unavailable
    var title: String {
        switch self {
        case .available: "Your phone garden"
        case .empty: "Your garden is on its way"
        case .disconnected: "Screen Time is disconnected"
        case .sharingOff: "Watch sharing is off"
        case .unavailable: "Your phone result is unavailable"
        }
    }
    var explanation: String {
        switch self {
        case .available: "This estimate comes from your iPhone."
        case .empty: "A saved phone estimate will appear here after it is ready."
        case .disconnected: "Reconnect Screen Time in DFE on your iPhone to resume automatic estimates."
        case .sharingOff: "Turn on Apple Watch sharing in DFE Settings on your iPhone."
        case .unavailable: "Open DFE on your iPhone to check the latest result."
        }
    }
}

enum CompanionGardenError: Error, Equatable {
    case invalidSnapshot, invalidEnvelope, unsupportedVersion, oversizedPayload, storageUnavailable
}

struct CompanionGardenEnvelope: Codable, Equatable, Sendable {
    static let version = 1
    static let maximumBytes = 16_384
    static let contextKey = "dfePhoneGardenV1"
    static let refreshRequestKey = "dfeRefreshPhoneGardenV1"
    static let widgetKind = "DFEWatchGardenWidget"

    let version: Int
    let producer: UUID
    let sequence: UInt64
    let sentAt: Date
    let availability: CompanionGardenAvailability
    let snapshot: CompanionGardenSnapshot?

    init(producer: UUID, sequence: UInt64, sentAt: Date, availability: CompanionGardenAvailability,
         snapshot: CompanionGardenSnapshot?) {
        self.version = Self.version
        self.producer = producer
        self.sequence = sequence
        self.sentAt = sentAt
        self.availability = availability
        self.snapshot = snapshot
    }

    func validate(now: Date) throws {
        guard version == Self.version else { throw CompanionGardenError.unsupportedVersion }
        guard sequence > 0, sentAt.timeIntervalSince1970.isFinite,
              sentAt >= Date(timeIntervalSince1970: 0), sentAt <= now.addingTimeInterval(300),
              (availability == .available) == (snapshot != nil) else {
            throw CompanionGardenError.invalidEnvelope
        }
        try snapshot?.validate(now: now)
    }

    func encoded(now: Date = Date()) throws -> Data {
        try validate(now: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw CompanionGardenError.oversizedPayload }
        return data
    }

    static func decode(_ data: Data, now: Date = Date()) throws -> Self {
        guard data.count <= maximumBytes else { throw CompanionGardenError.oversizedPayload }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let envelope = try decoder.decode(Self.self, from: data)
        try envelope.validate(now: now)
        return envelope
    }

    // [04] Delayed messages must not bring back a garden after sharing was stopped or the result was cleared.
    func canReplace(_ previous: Self?, allowProducerChange: Bool = false) -> Bool {
        guard let previous else { return true }
        // [06] A new phone installation may withdraw sharing before the Watch has seen its new sender.
        // Accept that clear immediately; a result from an unknown sender still needs a current direct reply.
        guard producer == previous.producer else { return snapshot == nil || allowProducerChange }
        guard sequence >= previous.sequence else { return false }
        return sequence > previous.sequence || self == previous
    }
}

// [05] Keep the privacy decision separate from connection status. A request from the Watch cannot turn sharing on.
struct CompanionSharingPolicy: Equatable, Sendable {
    private(set) var isEnabled = false
    mutating func setEnabled(_ enabled: Bool) { isEnabled = enabled }
    func responseAvailability(for requested: CompanionGardenAvailability) -> CompanionGardenAvailability {
        isEnabled ? requested : .sharingOff
    }
    func allowedSnapshot(_ snapshot: CompanionGardenSnapshot?) -> CompanionGardenSnapshot? {
        isEnabled ? snapshot : nil
    }
}
