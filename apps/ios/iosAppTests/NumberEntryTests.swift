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

// [01] The older number editor must not quietly save a different value from the one someone typed

import XCTest
@testable import DFE

final class NumberEntryTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    // [02] People pause halfway through a number, so the editor must allow normal unfinished
    // typing.
    func testWholeDecimalEntryAcceptsSignsAndTrailingDecimalWhileTyping() throws {
        for (text, expected) in [("60", 60.0), ("60.", 60.0), (".5", 0.5),
                                 ("+12.5", 12.5), ("-3", -3.0), (" 60.5 ", 60.5), ("0", 0.0)] {
            XCTAssertEqual(try XCTUnwrap(LocalizedNumberEntry.parse(text, locale: english)), expected, accuracy: 1e-12)
        }
    }

    // [03] Pasted text may contain more than a number; accepting only its first part would save a
    // misleading value.
    func testInvalidPasteCannotBeReadAsItsNumericPrefix() {
        for text in ["", " ", "60abc", "12,34", "1,000", "1.2.3", "+", "-", ".", "+.",
                     "NaN", "inf", "∞", "1e3", "60 20", "60\n20"] {
            XCTAssertNil(LocalizedNumberEntry.parse(text, locale: english), text)
        }
        XCTAssertNil(LocalizedNumberEntry.parse(String(repeating: "9", count: 400), locale: english))
        XCTAssertNil(LocalizedNumberEntry.parse("0." + String(repeating: "0", count: 400) + "1", locale: english))
    }

    // [04] Someone's decimal separator should work naturally without changing the number they
    // meant.
    func testDecimalSeparatorMatchesThePersonsLocale() throws {
        let swiss = Locale(identifier: "de_CH")
        let german = Locale(identifier: "de_DE")
        XCTAssertEqual(try XCTUnwrap(LocalizedNumberEntry.parse("12.5", locale: swiss)), 12.5)
        XCTAssertNil(LocalizedNumberEntry.parse("12,5", locale: swiss))
        XCTAssertEqual(try XCTUnwrap(LocalizedNumberEntry.parse("12,5", locale: german)), 12.5)
        XCTAssertNil(LocalizedNumberEntry.parse("12.5", locale: german))
        XCTAssertEqual(LocalizedNumberEntry.format(12.5, fractionDigits: 2, locale: german), "12,5")
    }

    // [05] Local number symbols and very small values should survive editing instead of being
    // rounded away.
    func testLocalizedDecimalDigitsAndSmallPositiveValuesAreKept() throws {
        let arabic = Locale(identifier: "ar_EG")
        let separator = LocalizedNumberEntry.decimalSeparator(in: arabic)
        XCTAssertEqual(try XCTUnwrap(LocalizedNumberEntry.parse("١\(separator)٢", locale: arabic)), 1.2)
        let tiny = try XCTUnwrap(LocalizedNumberEntry.parse("0.0000001", locale: english))
        XCTAssertEqual(tiny, 0.0000001, accuracy: 1e-15)
        let display = LocalizedNumberEntry.format(tiny, fractionDigits: 3, locale: english)
        XCTAssertGreaterThan(try XCTUnwrap(LocalizedNumberEntry.parse(display, locale: english)), 0)
    }

    // [06] Being readable as a number does not make a negative estimate input acceptable to the
    // model.
    func testNegativeEntryStillHasToPassTheModelsRangeCheck() throws {
        let value = try XCTUnwrap(LocalizedNumberEntry.parse("-1", locale: english))
        var inputs = FootprintInputs.empty
        inputs.usages = [CategoryUsage(category: .video, minutes: value)]
        XCTAssertThrowsError(try inputs.validate())
    }

    // [07] Hiding a field must not hide its error and let an invalid value slip into a saved
    // result.
    @MainActor func testInvalidDraftBlocksSavingWhenItsFieldIsHiddenAndReopened() {
        let state = InputValidationState()
        let identifier = "input.data.VIDEO_STREAMING"
        XCTAssertNil(state.update("60abc", for: identifier, value: 60,
                                  accessibilityTitle: "Video streaming, data per hour", locale: english))
        XCTAssertNotNil(state.firstError)
        // [08] Hiding a field should not forget that its unfinished value still needs correction.
        state.synchronize(identifier, value: 60)
        XCTAssertEqual(state.text(for: identifier, value: 60, fractionDigits: 3, locale: english), "60abc")
        XCTAssertNotNil(state.firstError)
        XCTAssertEqual(state.update("12.5", for: identifier, value: 60,
                                    accessibilityTitle: "Video streaming, data per hour", locale: english), 12.5)
        XCTAssertNil(state.firstError)
    }

    // [09] Clearing a field is not a request to secretly put its old number back when saving.
    @MainActor func testEmptyDraftDoesNotRestoreTheOldValueOnSave() {
        let state = InputValidationState()
        let identifier = "input.gps"
        XCTAssertNil(state.update("", for: identifier, value: 2,
                                  accessibilityTitle: "GPS activity in hours", locale: english))
        XCTAssertNotNil(state.firstError)
        XCTAssertEqual(state.text(for: identifier, value: 2, fractionDigits: 2, locale: english), "")
    }

    // [10] Normal typing should keep its exact text, while a deliberate preset should replace an
    // older draft.
    @MainActor func testOrdinaryKeystrokesPreserveTheirTextAndExternalPresetsResetIt() {
        let state = InputValidationState()
        let identifier = "input.minutes.VIDEO_STREAMING"
        XCTAssertEqual(state.update("060.", for: identifier, value: 60,
                                    accessibilityTitle: "Video streaming, daily minutes", locale: english), 60)
        state.synchronize(identifier, value: 60)
        XCTAssertEqual(state.text(for: identifier, value: 60, fractionDigits: 1, locale: english), "060.")
        state.update("bad", for: identifier, value: 60,
                     accessibilityTitle: "Video streaming, daily minutes", locale: english)
        state.synchronize(identifier, value: 120)
        XCTAssertNil(state.firstError)
        XCTAssertEqual(state.text(for: identifier, value: 120, fractionDigits: 1, locale: english), "120")
        state.update("bad", for: identifier, value: 120,
                     accessibilityTitle: "Video streaming, daily minutes", locale: english)
        // [11] Choosing the old preset is still a deliberate reset, even when an invalid draft is
        // currently visible.
        state.clear(identifier)
        XCTAssertNil(state.firstError)
        XCTAssertEqual(state.text(for: identifier, value: 120, fractionDigits: 1, locale: english), "120")
    }

    // [12] Removing one category should not discard the person's unfinished changes in another
    // category.
    @MainActor func testRemovingACategoryOnlyClearsItsOwnDrafts() {
        let state = InputValidationState()
        for identifier in ["input.minutes.VIDEO_STREAMING", "input.data.VIDEO_STREAMING", "input.gps"] {
            state.update("bad", for: identifier, value: 1, accessibilityTitle: identifier, locale: english)
        }
        state.clearCategory("VIDEO_STREAMING")
        XCTAssertEqual(state.text(for: "input.minutes.VIDEO_STREAMING", value: 1, fractionDigits: 1, locale: english), "1")
        XCTAssertEqual(state.text(for: "input.data.VIDEO_STREAMING", value: 1, fractionDigits: 3, locale: english), "1")
        XCTAssertEqual(state.text(for: "input.gps", value: 1, fractionDigits: 2, locale: english), "bad")
        XCTAssertNotNil(state.firstError)
        state.clear("input.gps")
        XCTAssertNil(state.firstError)
    }
}
