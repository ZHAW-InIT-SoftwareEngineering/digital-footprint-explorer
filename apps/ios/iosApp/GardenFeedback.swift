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

// [01] The garden reflects a saved estimate, never a measured change in the environment.
enum GardenFeedback {
    static func message(state: FootprintGarden, totalKg: Double, baselineKg: Double?) -> String {
        // [02] Without a valid earlier average, a welcome message is more honest than claiming improvement.
        guard let baseline = baselineKg, baseline.isFinite, baseline >= 0,
              totalKg.isFinite, totalKg >= 0 else {
            return "Your garden starts here. This estimate is a starting point."
        }
        // [03] A zero starting average needs words of its own; a percentage comparison would be misleading.
        if baseline == 0 {
            return totalKg == 0
                ? "Another zero estimate. A quiet day for your garden."
                : "Above your earlier zero estimate. One day is only part of the picture."
        }
        // [04] Use the same saved state as the artwork; do not invent another scoring system.
        switch state {
        case .flourishing:
            return "Your estimate is well below your recent average. Your garden is in full bloom."
        case .growing:
            return "Your estimate is below your recent average. Your garden is growing."
        case .stable:
            return "Your estimate is close to your recent average. A steady day for your garden."
        case .wilting:
            return "Your estimate is above your recent average. One day is only part of the picture."
        case .withered:
            return "Your estimate is well above your recent average. One day is only part of the picture."
        }
    }
}
