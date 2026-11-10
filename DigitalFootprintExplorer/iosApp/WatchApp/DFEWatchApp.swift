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

#if os(watchOS)
import SwiftUI

@main
@MainActor
struct DFEWatchApp: App {
    @StateObject private var model: WatchGardenModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let shared = WatchGardenModel.shared
        _model = StateObject(wrappedValue: shared)
        // [01] The session also needs a delegate on a cold background launch, before any screen appears.
        shared.start()
    }

    var body: some Scene {
        WindowGroup {
            rootContent
                .tint(Color(red: 0.16, green: 0.78, blue: 0.46))
                .onChange(of: scenePhase, initial: true) { _, phase in
                    model.setSceneActive(phase == .active)
                }
                #if DEBUG
                .modifier(WatchVisualTextSize(isPreviewing: model.isPreviewing))
                #endif
        }
        .backgroundTask(.watchConnectivity) {
            await WatchGardenModel.shared.handleConnectivityBackground()
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        #if DEBUG
        if model.isPreviewing, let family = WatchVisualPreviewFamily.requested() {
            WatchComplicationVisualPreview(model: model, family: family)
        } else {
            WatchGardenView(model: model)
        }
        #else
        WatchGardenView(model: model)
        #endif
    }
}
#endif
