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

enum WatchGardenLayoutPolicy {
    static let primaryContentReserve: Double = 140
    static let accessibilityContentReserve: Double = 110

    // [01] Give the date and amount room before making the garden larger. The screen size matters, rather than a particular Watch model.
    static func gardenHeight(availableHeight: Double, accessibilityText: Bool) -> Double {
        let minimum: Double = accessibilityText ? 88 : 64
        guard availableHeight.isFinite, availableHeight > 0 else { return minimum }
        let reserve = accessibilityText ? accessibilityContentReserve : primaryContentReserve
        // [02] At larger text sizes the Crown makes room for the details, so the garden can stay large enough to recognise.
        let limit: Double = 108
        return min(limit, max(minimum, availableHeight - reserve))
    }
}
