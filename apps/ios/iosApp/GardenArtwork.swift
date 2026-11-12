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

/// [01] The same five transparent garden pictures used by the Android app.
struct GardenArtwork: View {
    let state: FootprintGarden
    var maximumWidth: CGFloat = 320

    // [02] Choose the picture from the saved garden state, so the app and widget tell the same story.
    static func imageName(for state: FootprintGarden) -> String {
        switch state {
        case .flourishing: "GardenFlourishing"
        case .growing: "GardenGrowing"
        case .stable: "GardenStable"
        case .wilting: "GardenWilting"
        case .withered: "GardenWithered"
        }
    }

    var body: some View {
        // [03] Fit the complete original image; keep its colors and transparency.
        Image(Self.imageName(for: state))
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: maximumWidth)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Garden: \(state.title)")
            .accessibilityIdentifier("garden.artwork")
    }
}
