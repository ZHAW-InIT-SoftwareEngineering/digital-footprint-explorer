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

/// [01] Show the saved result without calculating a new footprint in the widget.
/// Use system text colours so small labels stay readable in light and dark appearances.
struct GardenWidgetView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.redactionReasons) private var redactionReasons
    @ScaledMetric(relativeTo: .caption2) private var compactTextSize: CGFloat = 11
    let data: WidgetSnapshotReadResult
    let family: WidgetFamily
    let date: Date
    var isPreview = false

    // [02] Choose a layout for the widget size and text setting, keeping the saved amount readable.
    // The whole widget opens Today and gives VoiceOver one complete summary.
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let snapshot = data.snapshot {
                    if typeSize.isAccessibilitySize {
                        accessibleContent(snapshot, size: geometry.size)
                    } else if family == .systemMedium {
                        mediumContent(snapshot, size: geometry.size)
                    } else if typeSize >= .xxLarge {
                        largeSmallContent(snapshot, size: geometry.size)
                    } else {
                        smallContent(snapshot, size: geometry.size)
                    }
                } else {
                    emptyContent(size: geometry.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .privacySensitive(data.snapshot != nil && !isPreview)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Opens Today in Digital Footprint Explorer")
        .widgetURL(GardenWidgetSnapshot.appURL)
        .containerBackground(.background, for: .widget)
    }

    private func smallContent(_ snapshot: GardenWidgetSnapshot, size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(snapshot.garden.title).font(.caption2.weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Text(isPreview ? "Preview" : "Estimate").font(.caption2).foregroundStyle(.primary)
            }
            artwork(snapshot).frame(maxWidth: .infinity, maxHeight: min(64, max(0, size.height - 62)))
            amount(snapshot, style: .title3)
            Text(smallDateLabel(snapshot)).font(.caption2)
                .lineLimit(1).minimumScaleFactor(0.85)
        }
        .privacySensitive()
    }

    // [03] Reduce decoration before shrinking useful text when a small widget has larger type.
    private func largeSmallContent(_ snapshot: GardenWidgetSnapshot, size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(isPreview ? "Preview" : "Estimate").font(.caption2).foregroundStyle(.primary)
            if size.height >= 125 {
                artwork(snapshot).frame(maxWidth: .infinity, maxHeight: min(42, max(0, size.height - 90)))
            }
            amount(snapshot, style: .caption2)
            Text(snapshot.isCurrentDay(on: date) ? snapshot.dateLabel : "Saved \(snapshot.dateLabel)")
                .font(.caption2)
            Text(snapshot.garden.title).font(.caption2.weight(.semibold))
        }
        .privacySensitive()
    }

    private func mediumContent(_ snapshot: GardenWidgetSnapshot, size: CGSize) -> some View {
        HStack(spacing: 16) {
            artwork(snapshot).frame(maxWidth: .infinity, maxHeight: 110)
            VStack(alignment: .leading, spacing: 5) {
                if typeSize < .xxLarge && size.height >= 125 {
                    Text(isPreview ? "Your garden · Preview" : "Your garden").font(.caption).foregroundStyle(.primary)
                }
                Text(snapshot.garden.title).font(.headline)
                amount(snapshot, style: .title3)
                Text("\(isPreview ? "Preview" : "Estimate") · \(snapshot.dateLabel)").font(.caption2)
                if typeSize < .xxLarge || size.height >= 125 {
                    Text(snapshot.statusLabel(on: date)).font(.caption2).foregroundStyle(.primary)
                }
                Text(typeSize >= .xxLarge ? snapshot.source.compactTitle : snapshot.source.title)
                    .font(.caption2).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .privacySensitive()
    }

    private func accessibleContent(_ snapshot: GardenWidgetSnapshot, size: CGSize) -> some View {
        let font = compactFont(size: size)
        // [04] In a fixed widget frame, keep the result readable before decorative artwork.
        return VStack(alignment: .leading, spacing: 4) {
            Text(isPreview ? "Preview" : "Estimate").font(font).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            amount(snapshot, style: font, unitStyle: font)
            Text(family == .systemSmall || snapshot.isCurrentDay(on: date) ? snapshot.dateLabel : "Saved \(snapshot.dateLabel)")
                .font(font).fixedSize(horizontal: false, vertical: true)
        }
        .privacySensitive()
    }

    private func compactFont(size: CGSize) -> Font {
        // [05] Text grows with the setting, within a budget for four lines in the small frame.
        let budget = size.height / (family == .systemSmall ? 5.25 : 4.1)
        return .system(size: max(11, min(compactTextSize, budget)))
    }

    private func amount(_ snapshot: GardenWidgetSnapshot, style: Font, unitStyle: Font? = nil) -> some View {
        let value = Text(snapshot.amountLabel()).font(style.weight(.semibold))
        let unit = Text(" g CO₂e").font((unitStyle ?? .caption2).weight(.medium))
        return Text("\(value)\(unit)")
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }

    private func smallDateLabel(_ snapshot: GardenWidgetSnapshot) -> String {
        if !snapshot.isCurrentDay(on: date) { return "\(snapshot.dateLabel) · Saved" }
        return "\(snapshot.dateLabel) · \(snapshot.isCompleted ? "Complete" : "In progress")"
    }

    // [06] When iOS hides private content, show a neutral garden instead of revealing the saved state.
    private func artwork(_ snapshot: GardenWidgetSnapshot) -> some View {
        gardenImage(redactionReasons.contains(.privacy) ? .stable : snapshot.garden)
            .opacity(redactionReasons.contains(.privacy) ? 0.45 : 1)
    }

    @ViewBuilder private func gardenImage(_ state: WidgetGardenState) -> some View {
        let image = Image(state.imageName).renderingMode(.original).resizable()
        if #available(iOS 18.0, *) {
            // [07] Keep the app's garden when the Home Screen uses tinted widgets.
            image.widgetAccentedRenderingMode(.fullColor).scaledToFit()
                .accessibilityHidden(true)
        } else {
            image.scaledToFit().accessibilityHidden(true)
        }
    }

    // [08] Explain an unavailable summary in the space we have, without creating a pretend footprint.
    @ViewBuilder private func emptyContent(size: CGSize) -> some View {
        if typeSize.isAccessibilitySize {
            Text("Open the app").font(compactFont(size: size).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        } else if typeSize >= .xxLarge {
            Text(emptyMessage).font(.caption2).fixedSize(horizontal: false, vertical: true)
        } else if family == .systemMedium {
            HStack(spacing: 16) {
                waitingGarden.frame(maxWidth: .infinity, maxHeight: 110)
                emptyMessageContent.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                waitingGarden.frame(maxWidth: .infinity, maxHeight: min(46, max(0, size.height - 70)))
                emptyMessageContent
            }
        }
    }

    private var waitingGarden: some View {
        // [09] This muted garden is a waiting illustration, never a calculated result.
        gardenImage(.stable).opacity(0.55)
    }

    private var emptyMessageContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your garden").font(.headline)
            Text(family == .systemSmall ? compactEmptyMessage : emptyMessage)
                .font(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var compactEmptyMessage: String {
        switch data {
        case .empty: "Open the app to check your garden."
        case .unavailable: "Garden unavailable. Open the app."
        case .unreadable: "Open the app to refresh your garden."
        case .saved: ""
        }
    }

    private var emptyMessage: String {
        switch data {
        case .empty: "Open the app to check your garden."
        case .unavailable: "Your saved garden is not available yet. Open the app to check."
        case .unreadable: "Open the app to refresh your saved garden."
        case .saved: ""
        }
    }

    // [10] Respect the same privacy hiding for spoken text as for the picture and amount.
    private var accessibilitySummary: String {
        if redactionReasons.contains(.privacy) {
            return "Your garden. Open the app to see your saved estimate."
        }
        if let snapshot = data.snapshot {
            return (isPreview ? "Widget preview. " : "") + snapshot.accessibilitySummary(on: date)
        }
        return "Your garden. \(emptyMessage)"
    }
}
