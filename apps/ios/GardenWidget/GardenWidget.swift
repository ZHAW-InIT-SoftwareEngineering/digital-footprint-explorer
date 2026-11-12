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
import WidgetKit

// [01] A widget entry is a view of a saved result at a given time, not a new Screen Time reading.
struct GardenWidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetSnapshotReadResult
    var isPreview = false
}

struct GardenWidgetProvider: TimelineProvider {
    // [02] The gallery needs a sample garden before a real entry exists. It stays labelled as a preview.
    func placeholder(in context: Context) -> GardenWidgetEntry {
        let now = Date()
        return GardenWidgetEntry(date: now, data: .saved(.preview(on: now)), isPreview: true)
    }
    func getSnapshot(in context: Context, completion: @escaping (GardenWidgetEntry) -> Void) {
        let now = Date()
        // [03] Gallery examples never enter shared storage or replace a person's saved result.
        let data: WidgetSnapshotReadResult = context.isPreview ? .saved(.preview(on: now)) : WidgetSnapshotStorage.configured().read()
        completion(GardenWidgetEntry(date: now, data: data, isPreview: context.isPreview))
    }
    // [04] Real timelines may import a completed day; gallery previews only read a saved summary.
    func getTimeline(in context: Context, completion: @escaping (Timeline<GardenWidgetEntry>) -> Void) {
        #if DFE_WIDGET_AUTOMATIC_IMPORT
        // [09] A widget can collect its own completed day without starting the main app.
        // Publish only after the shared mailbox has kept a valid, still-authorised result.
        if !context.isPreview {
            WidgetAutomaticImporter.run {
                completeTimeline(in: context, completion: completion)
            }
            return
        }
        #endif
        completeTimeline(in: context, completion: completion)
    }

    private func completeTimeline(in context: Context, completion: @escaping (Timeline<GardenWidgetEntry>) -> Void) {
        let now = Date()
        let storage = WidgetSnapshotStorage.configured()
        let data = storage.read()
        let family: String? = switch context.family {
        case .systemSmall: "small"
        case .systemMedium: "medium"
        default: nil
        }
        // [07] This proves only that a real timeline request read the shared data, not when iOS displayed it.
        if let family {
            _ = try? WidgetStorageVerificationStore(directory: storage.directory)
                .recordTimelineRead(family: family, result: data, at: Date(), isPreview: context.isPreview)
        }
        let entry = GardenWidgetEntry(date: now, data: data)
        // [05] Ask for the next useful check. WidgetKit chooses when it actually runs.
        #if DFE_WIDGET_AUTOMATIC_IMPORT
        let nextDay = WidgetAutomaticImporter.nextRefreshDate(now: now)
        #else
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        #endif
        completion(Timeline(entries: [entry], policy: .after(nextDay)))
    }
}

@main
// [06] Offer the two supported sizes, both opening the same Today route.
struct FootprintGardenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GardenWidgetSnapshot.widgetKind, provider: GardenWidgetProvider()) { entry in
            GardenWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Your garden")
        .description("Keep your garden nearby. See your last saved estimate, then tap to review your day.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct GardenWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GardenWidgetEntry
    var body: some View {
        GardenWidgetView(data: entry.data, family: family, date: entry.date, isPreview: entry.isPreview)
    }
}
