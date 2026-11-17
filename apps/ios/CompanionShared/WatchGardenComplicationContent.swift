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
    @Environment(\.appLanguage) private var language

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
                let date = snapshot.dateLabel(locale: language.locale)
                let amount = snapshot.amountLabel(locale: language.locale)
                switch family {
                case .accessoryInline:
                    Text(language.format("Phone garden · %@ · %@ g CO₂e", date, amount))
                case .accessoryCircular:
                    VStack(spacing: 0) {
                        Image(snapshot.garden.imageName)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 32)
                        Text(language.format("%@ g", amount))
                            .font(.caption2.weight(.semibold))
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)
                        Text(date)
                            .font(.system(size: 9))
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)
                    }
                default:
                    let isOlder = snapshot.isOlderThanLatestCompletedDay(now: entry.date)
                    HStack(spacing: 7) {
                        Image(snapshot.garden.imageName)
                            .resizable().scaledToFit()
                            .frame(maxWidth: 58)
                        VStack(alignment: .leading, spacing: 2) {
                            // [02] Keep the date readable on narrow faces, even if the longer German title does not fit.
                            ViewThatFits(in: .horizontal) {
                                Text(entry.isPreview ? language.text("Phone garden preview") :
                                    language.format("Phone garden · %@", date)).fixedSize(horizontal: true, vertical: false)
                                Text(entry.isPreview ? language.text("Preview") : date)
                            }
                            .font(.caption2)
                            .lineLimit(1)
                            Text(language.format("%@ g CO₂e", amount))
                                .font(.headline)
                                .minimumScaleFactor(0.65)
                                .lineLimit(1)
                            ViewThatFits(in: .horizontal) {
                                Text(language.text(isOlder ? "Last saved estimate" : "Estimated phone footprint"))
                                    .fixedSize(horizontal: true, vertical: false)
                                Text(language.text(isOlder ? "Saved" : "Estimate"))
                            }
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                let status = entry.envelope?.availability ?? .sharingOff
                if family == .accessoryInline {
                    Text(language.format("DFE · %@", language.text(status.title)))
                } else if family == .accessoryCircular {
                    VStack(spacing: 2) {
                        Image(systemName: "iphone")
                        Text("Open DFE").font(.caption2)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "iphone")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(language.text(status.title)).font(.headline)
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
        if privacyRedacted { return language.text("Phone garden. Unlock your Watch to view your saved estimate.") }
        guard let snapshot = entry.envelope?.snapshot else {
            return language.text((entry.envelope?.availability ?? .sharingOff).explanation)
        }
        let summary = language.format("Phone garden for %@: %@. Estimated phone footprint: %@ grams of carbon dioxide equivalent. %@.",
                                      snapshot.dateLabel(locale: language.locale), language.text(snapshot.garden.title),
                                      snapshot.amountLabel(locale: language.locale), language.text(snapshot.source.title))
        if snapshot.isOlderThanLatestCompletedDay(now: entry.date) {
            return summary + " " + language.text("Last saved day; check your iPhone for a newer result.")
        }
        return summary
    }
}

#endif
