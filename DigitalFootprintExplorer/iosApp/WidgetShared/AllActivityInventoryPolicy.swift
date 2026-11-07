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
#if os(iOS) && canImport(FamilyControls)
import FamilyControls
#endif

enum AllActivityInventoryPolicy {
    // [01] The installed-app lookup and live activity query have separate system checks.
    // Only this exact lookup refusal allows us to try identities supplied by the live query itself.
    static func continueWithoutInventory(after error: Error) throws {
        #if os(iOS) && canImport(FamilyControls)
        if #available(iOS 26.4, *), let familyError = error as? FamilyControlsError,
           case .unauthorized = familyError { return }
        #endif
        throw error
    }

    // [02] Without the lookup, each positive app row must identify itself. Otherwise grouping
    // everything under Other would quietly change the calculation instead of explaining missing access.
    static func bundleIdentifier(row: String?, known: String?, seconds: Double,
                                 inventoryUnavailable: Bool) throws -> String? {
        guard seconds.isFinite, seconds >= 0 else { throw ScreenTimeImportError.invalidDuration }
        let row = row.flatMap { $0.isEmpty ? nil : $0 }
        if inventoryUnavailable {
            guard seconds == 0 || row != nil else { throw ScreenTimeImportError.unmappedSelection }
            return row
        }
        return row ?? known.flatMap { $0.isEmpty ? nil : $0 }
    }
}
