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

struct WatchGardenEntry: TimelineEntry {
    let date: Date
    let envelope: CompanionGardenEnvelope?
    let isPreview: Bool
}

// [01] The app preview and the real complication use this same content. Only WidgetKit supplies real watch-face placement.
struct WatchGardenComplicationContent: View {
    let entry: WatchGardenEntry
    let family: WidgetFamily
    let privacyRedacted: Bool

    var body: some View {
        Group {
            if privacyRedacted {
                if family == .accessoryInline {
                    Text("Phone garden · Unlock to view")
                } else {
                    Label("Phone garden", systemImage: "lock")
                        .font(.caption)
                }
            } else if let snapshot = entry.envelope?.snapshot {
                switch family {
                case .accessoryInline:
                    Text("Phone garden · \(snapshot.dateLabel) · \(snapshot.amountLabel()) g CO₂e")
                case .accessoryCircular:
                    VStack(spacing: 0) {
                        Image(snapshot.garden.imageName)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 32)
                        Text("\(snapshot.amountLabel()) g")
                            .font(.caption2.weight(.semibold))
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)
                        Text(snapshot.dateLabel)
                            .font(.system(size: 9))
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)
                    }
                default:
                    HStack(spacing: 7) {
                        Image(snapshot.garden.imageName)
                            .resizable().scaledToFit()
                            .frame(maxWidth: 58)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.isPreview ? "Phone garden preview" : "Phone garden · \(snapshot.dateLabel)")
                                .font(.caption2)
                                .lineLimit(1)
                            Text("\(snapshot.amountLabel()) g CO₂e")
                                .font(.headline)
                                .minimumScaleFactor(0.65)
                                .lineLimit(1)
                            Text(snapshot.isOlderThanLatestCompletedDay(now: entry.date) ? "Last saved estimate" : "Estimated phone footprint")
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                let status = entry.envelope?.availability ?? .sharingOff
                if family == .accessoryInline {
                    Text("DFE · \(status.title)")
                } else if family == .accessoryCircular {
                    VStack(spacing: 2) {
                        Image(systemName: "iphone")
                        Text("Open DFE").font(.caption2)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "iphone")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(status.title).font(.headline)
                            Text("Open DFE on your iPhone").font(.caption2)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("watch.complication.content")
    }

    private var accessibilitySummary: String {
        if privacyRedacted { return "Phone garden. Unlock your Watch to view your saved estimate." }
        guard let snapshot = entry.envelope?.snapshot else {
            return (entry.envelope?.availability ?? .sharingOff).explanation
        }
        let stale = snapshot.isOlderThanLatestCompletedDay(now: entry.date) ? " Last saved day; check your iPhone for a newer result." : ""
        return "Phone garden for \(snapshot.dateLabel): \(snapshot.garden.title). Estimated phone footprint: \(snapshot.amountLabel()) grams of carbon dioxide equivalent. \(snapshot.source.title).\(stale)"
    }
}

#endif
