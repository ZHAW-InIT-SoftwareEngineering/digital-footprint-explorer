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
import WidgetKit

struct WatchGardenProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchGardenEntry { preview() }

    func getSnapshot(in context: Context, completion: @escaping (WatchGardenEntry) -> Void) {
        completion(context.isPreview ? preview() : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchGardenEntry>) -> Void) {
        let entry = current()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: entry.date))
            ?? entry.date.addingTimeInterval(86_400)
        // [01] This check only updates the saved-day label. New phone results arrive through Watch Connectivity, not Screen Time on the Watch.
        completion(Timeline(entries: [entry], policy: .after(tomorrow.addingTimeInterval(900))))
    }

    private func current() -> WatchGardenEntry {
        let now = Date()
        let envelope = (try? CompanionGardenStorage.watchGroup())
            .flatMap { try? $0.load(now: now) }
        return WatchGardenEntry(date: now, envelope: envelope, isPreview: false)
    }

    private func preview() -> WatchGardenEntry {
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let day = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let snapshot = CompanionGardenSnapshot(day: CompanionGardenSnapshot.dayKey(day, calendar: calendar),
                                               totalKg: 0.06, garden: .growing, source: .screenTimeWithEstimates,
                                               calculatedAt: now, isCompleted: true)
        // [02] The gallery example stays in memory. It is never written as a person's phone activity.
        return WatchGardenEntry(date: now,
                                envelope: CompanionGardenEnvelope(producer: UUID(), sequence: 1, sentAt: now,
                                                                   availability: .available, snapshot: snapshot),
                                isPreview: true)
    }
}

struct WatchGardenWidgetView: View {
    let entry: WatchGardenEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        WatchGardenComplicationContent(entry: entry, family: family,
                                       privacyRedacted: redactionReasons.contains(.privacy))
            .containerBackground(.black, for: .widget)
            .widgetURL(URL(string: "dfe-watch://garden"))
            .privacySensitive()
    }
}

@main
struct DFEWatchGardenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CompanionGardenEnvelope.widgetKind, provider: WatchGardenProvider()) { entry in
            WatchGardenWidgetView(entry: entry)
        }
        .configurationDisplayName("Your phone garden")
        .description("Keep your latest saved iPhone footprint close. The Watch does not measure app activity.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
#endif
