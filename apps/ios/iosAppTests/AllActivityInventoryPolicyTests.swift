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

import XCTest
#if os(iOS) && canImport(FamilyControls)
import FamilyControls
#endif
@testable import DFE

final class AllActivityInventoryPolicyTests: XCTestCase {
    // [01] A refused inventory lookup can be skipped; the next public API still decides its own access.
    func testOnlyExactUnauthorizedInventoryErrorAllowsFallback() throws {
        #if os(iOS) && canImport(FamilyControls)
        if #available(iOS 26.4, *) {
            XCTAssertNoThrow(try AllActivityInventoryPolicy.continueWithoutInventory(after: FamilyControlsError.unauthorized))
            for error in [FamilyControlsError.restricted, .unavailable, .authorizationCanceled, .networkError] {
                XCTAssertThrowsError(try AllActivityInventoryPolicy.continueWithoutInventory(after: error)) { returned in
                    XCTAssertTrue(returned is FamilyControlsError)
                    XCTAssertEqual((returned as NSError).code, (error as NSError).code)
                }
            }
        } else {
            throw XCTSkip("The exact inventory error requires iOS 26.4 or later.")
        }
        #else
        throw XCTSkip("The exact Family Controls error is checked in the iOS test target.")
        #endif
    }

    func testCancellationAndAnUnrelatedErrorWithTheSameCodeStillPropagate() {
        XCTAssertThrowsError(try AllActivityInventoryPolicy.continueWithoutInventory(after: CancellationError())) {
            XCTAssertTrue($0 is CancellationError)
        }
        let error = NSError(domain: "synthetic.other", code: 8)
        XCTAssertThrowsError(try AllActivityInventoryPolicy.continueWithoutInventory(after: error)) {
            XCTAssertEqual(($0 as NSError).domain, error.domain)
            XCTAssertEqual(($0 as NSError).code, error.code)
        }
    }

    // [02] The live row must keep the same category as the host's ordinary identity mapping.
    func testFallbackUsesTheLiveRowIdentityForTheSameClassification() throws {
        let row = "com.google.ios.youtube"
        let bundle = try AllActivityInventoryPolicy.bundleIdentifier(row: row, known: "net.whatsapp.WhatsApp",
            seconds: 120, inventoryUnavailable: true)
        XCTAssertEqual(bundle, row)
        XCTAssertEqual(AutomaticActivityClassification.category(bundleIdentifier: bundle), .video)
        XCTAssertEqual(AutomaticActivityClassification.category(bundleIdentifier: bundle),
            AutomaticActivityClassification.category(bundleIdentifier: row))
    }

    // [03] Missing positive identity must fail, not turn a known streaming row into Other.
    func testFallbackRejectsMissingPositiveRowIdentityEvenWithAnOldAlias() {
        for row in [nil, ""] as [String?] {
            XCTAssertThrowsError(try AllActivityInventoryPolicy.bundleIdentifier(row: row,
                known: "com.google.ios.youtube", seconds: 60, inventoryUnavailable: true)) {
                guard case ScreenTimeImportError.unmappedSelection = $0 else {
                    return XCTFail("Expected missing activity identity")
                }
            }
        }
    }

    func testAnAvailableInventoryStillResolvesTokenOnlyRows() throws {
        let bundle = try AllActivityInventoryPolicy.bundleIdentifier(row: nil, known: "com.apple.Music",
            seconds: 60, inventoryUnavailable: false)
        XCTAssertEqual(bundle, "com.apple.Music")
        XCTAssertEqual(AutomaticActivityClassification.category(bundleIdentifier: bundle), .audio)
        XCTAssertNil(try AllActivityInventoryPolicy.bundleIdentifier(row: nil, known: "com.apple.Music",
            seconds: 0, inventoryUnavailable: true))
    }

    func testInvalidDurationsCannotUseTheZeroRowException() {
        for seconds in [Double.nan, .infinity, -1] {
            XCTAssertThrowsError(try AllActivityInventoryPolicy.bundleIdentifier(row: "synthetic.app",
                known: nil, seconds: seconds, inventoryUnavailable: true)) {
                guard case ScreenTimeImportError.invalidDuration = $0 else {
                    return XCTFail("Expected an invalid duration")
                }
            }
        }
    }
}
