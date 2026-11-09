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

// [01] Offer one practical next step, linked to a category the person can recognise.
struct HistoryTip: Equatable {
    let day: String?
    let category: FootprintCategory?

    var action: String {
        switch category ?? .other {
        case .video:
            "Try turning off autoplay, if your video app offers it. Take a short break before choosing another video."
        case .audio:
            "Choose what you want to listen to, then pause when you are finished instead of letting playback continue."
        case .social:
            "Choose one reason to open the app, then put your device aside when you are done. Quiet notifications that pull you back in."
        case .messaging:
            "Check messages at times that work for you. Quiet non-urgent chats so each alert does not start another session."
        case .ai:
            "Save useful answers so you can return to them without starting the same task again."
        case .email:
            "Set aside a short time to check email, then leave the inbox until you need it again."
        case .calls:
            "Decide what you want to cover before a video call. When the call is finished, take a break from the screen."
        case .gaming:
            "Choose a stopping point before you start, such as the end of one round. Take a short break before playing again."
        case .navigation:
            "Plan the route before you leave. Once you know the way, put your device away when you no longer need directions."
        case .other:
            "Finish one task, then take a short screen break before opening another app. A small change is enough to start."
        }
    }
}

enum HistoryTipSelector {
    // [02] Use recent completed estimates to pick a relevant suggestion.
    // With no suitable result, offer a general idea instead of claiming to know the person's habits.
    static func tip(records: [FootprintRecord], calendar: Calendar = FootprintCalendar.localCalendar) -> HistoryTip {
        let days = FootprintCalendar(calendar: calendar)
        let latest = records.filter { $0.isCompleted && days.date($0.day) != nil }
            .max { $0.day < $1.day }
        guard let record = latest, record.result.totalKg.isFinite, record.result.totalKg > 0,
              (try? record.inputs.validate()) != nil else {
            return HistoryTip(day: nil, category: nil)
        }
        // [03] Rank the saved estimate, not minutes. A missing or invalid category cannot guide a tip.
        let category = record.result.categories.filter { value in
            let values = [value.totalKg, value.deviceKg, value.networkKg, value.backendKg]
            return values.allSatisfy { $0.isFinite && $0 >= 0 } && value.totalKg > 0
                && record.inputs.usages.contains {
                    $0.category == value.category && $0.minutes.isFinite && $0.minutes > 0 && $0.minutes <= record.inputs.usageCapacityMinutes
                }
        }.sorted {
            if $0.totalKg == $1.totalKg { return $0.category.rawValue < $1.category.rawValue }
            return $0.totalKg > $1.totalKg
        }.first?.category
        guard let category else { return HistoryTip(day: nil, category: nil) }
        return HistoryTip(day: record.day, category: category)
    }
}

// [04] Present a small choice the person can try today, with more detail only when they want it.
struct HistoryTips: View {
    let records: [FootprintRecord]
    let calendar: Calendar
    @Environment(\.dynamicTypeSize) private var textSize

    private var tip: HistoryTip { HistoryTipSelector.tip(records: records, calendar: calendar) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tips for your next day")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("history.tips.heading")

            VStack(alignment: .leading, spacing: 12) {
                suggestionHeader
                Text(tip.action)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("history.tips.action")

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 24) {
                        idea("Choose a daily time limit", symbol: "timer",
                             detail: "In Settings, open Screen Time and choose an optional daily time limit. Pick an amount that feels useful to you.",
                             guide: "Apple's Screen Time guide", id: "limit",
                             url: DeviceHelpLinks.screenTime)
                        idea("Quiet alerts you do not need", symbol: "bell.slash",
                             detail: "Open Settings, then Notifications. Choose which apps can interrupt you, while keeping the alerts that matter.",
                             guide: "Apple's notification guide", id: "notifications",
                             url: DeviceHelpLinks.notifications)
                        idea("Make room for a screen break", symbol: "moon",
                             detail: "Open Settings, then Focus. Choose the people and apps that can reach you while you take some time away.",
                             guide: "Apple's Focus guide", id: "focus",
                             url: DeviceHelpLinks.focus)
                        Text("Shorter app sessions can lower the time used by the estimate. Actual carbon savings are not measured.")
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 12)
                } label: {
                    Text("More ideas")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("history.tips.more")
                }
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 24).fill(FootprintAppearance.card)
                RoundedRectangle(cornerRadius: 24).fill(FootprintAppearance.accent.opacity(0.07))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(FootprintAppearance.accent.opacity(0.12), lineWidth: 1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.tips")
    }

    @ViewBuilder
    private var suggestionHeader: some View {
        if textSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                categorySymbol
                suggestionTitle
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                categorySymbol
                suggestionTitle
            }
        }
    }

    private var categorySymbol: some View {
        Image(systemName: tip.category?.symbol ?? "leaf")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(FootprintAppearance.accent)
            .frame(width: 44, height: 44)
            .background(FootprintAppearance.accent.opacity(0.10), in: Circle())
            .accessibilityHidden(true)
    }

    private var suggestionTitle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("One small step")
                .font(.system(.headline, design: .rounded, weight: .semibold))
            Text(context)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("history.tips.context")
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // [05] Say what the suggestion is based on, so advice is not mistaken for a guaranteed carbon saving.
    private var context: String {
        guard let day = tip.day, let category = tip.category else {
            return "A few general ideas to try at your own pace."
        }
        return "From your saved estimate for \(dayLabel(day)): \(category.title) contributed the most."
    }

    @ViewBuilder
    private func idea(_ title: String, symbol: String, detail: String, guide: String,
                      id: String, url: String) -> some View {
        if textSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                ideaSymbol(symbol)
                ideaContent(title, detail: detail, guide: guide, id: id, url: url)
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                ideaSymbol(symbol)
                ideaContent(title, detail: detail, guide: guide, id: id, url: url)
            }
        }
    }

    private func ideaSymbol(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(FootprintAppearance.accent)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }

    private func ideaContent(_ title: String, detail: String, guide: String,
                             id: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.subheadline)
            if let url = URL(string: url) {
                Link(destination: url) {
                    Label(guide, systemImage: "arrow.up.right")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(FootprintAppearance.accent)
                .accessibilityHint("Opens Apple's guide in your browser.")
                .accessibilityIdentifier("history.tips.guide.\(id)")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
