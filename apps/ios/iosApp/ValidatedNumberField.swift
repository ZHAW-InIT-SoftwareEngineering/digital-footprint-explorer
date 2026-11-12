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

import SwiftUI
import Foundation

/// [01] Decimal entry is checked in full, so pasted text cannot silently keep an old value.
enum LocalizedNumberEntry {
    // [02] Accept the decimal mark familiar to the person typing, rather than assuming every language uses a dot.
    static func decimalSeparator(in locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        return formatter.decimalSeparator ?? "."
    }

    // [03] Read the whole entry. A pasted unit or stray letter should show an error,
    // not silently keep part of a number and save an unintended assumption.
    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let separator = decimalSeparator(in: locale)
        let localized = trimmed.replacingOccurrences(of: separator, with: ".")
        var normalized = ""
        var hasDecimal = false
        var hasDigit = false
        for (index, character) in localized.enumerated() {
            if index == 0, character == "+" || character == "-" {
                normalized.append(character)
            } else if character == ".", !hasDecimal {
                // [04] A dot is only a decimal separator in locales that use it.
                guard separator == "." || !trimmed.contains(".") else { return nil }
                hasDecimal = true
                normalized.append(".")
            } else if character.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }),
                      let digit = character.wholeNumberValue, (0...9).contains(digit) {
                normalized.append(String(digit))
                hasDigit = true
            } else {
                return nil
            }
        }
        guard hasDigit else { return nil }
        // [05] Keep a trailing decimal while typing; it still names the entered number.
        if normalized.last == "." { normalized.append("0") }
        guard let value = Double(normalized), value.isFinite else { return nil }
        // [06] Values below Double's range must not quietly become a saved zero.
        guard value != 0 || !normalized.contains(where: { "123456789".contains($0) }) else { return nil }
        return value
    }

    static func format(_ value: Double, fractionDigits: Int, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        var precision = max(0, fractionDigits)
        // [07] Do not display a small positive assumption as zero when reopening its field.
        if value.isFinite, value != 0, abs(value) < pow(10, -Double(precision)) {
            precision = min(324, max(precision, Int(ceil(-log10(abs(value)))) + 2))
        }
        formatter.maximumFractionDigits = precision
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

@MainActor
// [08] Keep unfinished text separate from the last valid value, so typing a decimal
// does not suddenly erase the field or save a bad number.
final class InputValidationState: ObservableObject {
    private struct Draft {
        var text: String
        var boundValue: Double
        var error: String?
    }
    @Published private var drafts: [String: Draft] = [:]

    var firstError: String? {
        drafts.keys.sorted().compactMap { drafts[$0]?.error }.first
    }

    func text(for identifier: String, value: Double, fractionDigits: Int, locale: Locale = .current) -> String {
        drafts[identifier]?.text ?? LocalizedNumberEntry.format(value, fractionDigits: fractionDigits, locale: locale)
    }

    @discardableResult
    func update(_ text: String, for identifier: String, value: Double,
                accessibilityTitle: String, locale: Locale = .current) -> Double? {
        let parsed = LocalizedNumberEntry.parse(text, locale: locale)
        drafts[identifier] = Draft(text: text, boundValue: parsed ?? value,
                                  error: parsed == nil ? "Enter a valid number for \(accessibilityTitle)." : nil)
        return parsed
    }

    func synchronize(_ identifier: String, value: Double) {
        // [09] A valid keystroke also updates the numeric input. Keep the person's text while they finish typing.
        guard let draft = drafts[identifier], draft.boundValue != value else { return }
        drafts.removeValue(forKey: identifier)
    }

    func clear(_ identifier: String) {
        drafts.removeValue(forKey: identifier)
    }

    func clearCategory(_ rawValue: String) {
        // [10] Removed categories should no longer prevent the remaining routine from saving.
        for identifier in Array(drafts.keys) where identifier.hasSuffix(".\(rawValue)") {
            drafts.removeValue(forKey: identifier)
        }
    }
}

// [11] Reuse the same number checks and accessible label wherever an assumption can be reviewed.
struct ValidatedNumberField: View {
    let placeholder: String
    @Binding var value: Double
    let fractionDigits: Int
    let identifier: String
    let accessibilityTitle: String
    let focus: FocusState<String?>.Binding
    @EnvironmentObject private var validation: InputValidationState
    @Environment(\.locale) private var locale

    var body: some View {
        TextField(placeholder, text: Binding(
            get: { validation.text(for: identifier, value: value, fractionDigits: fractionDigits, locale: locale) },
            set: { text in
                if let parsed = validation.update(text, for: identifier, value: value,
                                                  accessibilityTitle: accessibilityTitle, locale: locale) {
                    value = parsed
                }
            }
        ))
        .multilineTextAlignment(.trailing)
        .keyboardType(.decimalPad)
        .focused(focus, equals: identifier)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityIdentifier(identifier)
        .onAppear { validation.synchronize(identifier, value: value) }
        .onChange(of: value) { _, newValue in validation.synchronize(identifier, value: newValue) }
    }
}
