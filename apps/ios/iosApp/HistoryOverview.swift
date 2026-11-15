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

// [01] Group real saved days into months, keeping the latest ones easy to find.
struct HistoryOverview: View {
    @ObservedObject var store: FootprintStore
    @Environment(\.appLanguage) private var appLanguage

    private var months: [HistoryMonth] {
        // [02] Saved dates use one calendar format, so grouping by their month also keeps date order.
        let grouped = Dictionary(grouping: store.records) { String($0.day.prefix(7)) }
        return grouped.keys.sorted(by: >).map { month in
            HistoryMonth(id: month, records: (grouped[month] ?? []).sorted { $0.day > $1.day })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TabPageLayout.sectionSpacing) {
                VStack(alignment: .leading, spacing: TabPageLayout.introSpacing) {
                    Text("Your garden, day by day")
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("history.intro")
                    Text("Look back at your saved estimates. Open a day to see its details.")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("history.introExplanation")
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)

                HistoryTips(records: store.records, calendar: store.aggregationCalendar)

                if store.records.isEmpty {
                    emptyHistory
                } else {
                    LazyVStack(alignment: .leading, spacing: TabPageLayout.sectionSpacing) {
                        ForEach(months) { month in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(monthTitle(month.id))
                                    .font(.headline)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityAddTraits(.isHeader)
                                    .accessibilityIdentifier("history.month.\(month.id)")

                                ForEach(month.records) { record in
                                    NavigationLink {
                                        RecordScreen(store: store, day: record.day)
                                    } label: {
                                        HStack(alignment: .top, spacing: 12) {
                                            HistoryDayRow(record: record)
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                                .padding(.top, 3)
                                                .accessibilityHidden(true)
                                        }
                                        .padding(16)
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        .contentShape(Rectangle())
                                        .background(FootprintAppearance.card, in: RoundedRectangle(cornerRadius: 18))
                                    }
                                    // [03] VoiceOver reads each saved day once, with the same context as its card.
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityLabel(Text(verbatim: dayAccessibilityLabel(record)))
                                    .accessibilityHint("Opens the saved day's details")
                                    .accessibilityIdentifier("history.day.\(record.day)")
                                }
                            }
                        }
                    }

                    Text("Missing activity stays pending. Earlier saved entries are kept for reference and cannot be edited here.")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, TabPageLayout.horizontal)
            .padding(.top, TabPageLayout.top)
            .padding(.bottom, TabPageLayout.bottom)
            .frame(maxWidth: TabPageLayout.contentWidth)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .automaticRefresh()
        .accessibilityIdentifier("history.content")
        .background(FootprintAppearance.page)
        .navigationTitle(appLanguage.text("History"))
    }

    // [04] Explain why history is empty without filling the list with made-up days.
    private var emptyHistory: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("No saved days yet")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("history.empty")
                Text("Connect Screen Time from Today. Completed days appear here when data is available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("history.empty.guidance")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        // [05] Keep both text labels available to VoiceOver, even when the list creates a row only as it comes into view.
        .accessibilityElement(children: .contain)
    }

    // [06] Translate the saved month into a familiar label while keeping the underlying date unchanged.
    private func monthTitle(_ month: String) -> String {
        guard let date = store.date(for: month + "-01") else { return month }
        let formatter = DateFormatter()
        formatter.calendar = store.aggregationCalendar
        formatter.locale = appLanguage.locale
        formatter.timeZone = store.aggregationCalendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: date)
    }

    private func dayAccessibilityLabel(_ record: FootprintRecord) -> String {
        appLanguage.format(
            "%@, Estimated carbon footprint: %@, %@, %@, Garden: %@",
            dayLabel(record.day, locale: appLanguage.locale),
            summaryGrams(record.result.totalKg, locale: appLanguage.locale),
            appLanguage.text(record.source.title),
            appLanguage.text(record.isCompleted ? "Completed" : "In progress"),
            appLanguage.text(record.garden.title)
        )
    }
}

private struct HistoryMonth: Identifiable {
    let id: String
    let records: [FootprintRecord]
}

private struct HistoryDayRow: View {
    let record: FootprintRecord
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if textSize.isAccessibilitySize {
                dateAndEstimate
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    dateLabel.fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    estimateLabel.fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(appLanguage.text(record.source.title) + " · " + appLanguage.text(record.isCompleted ? "Completed" : "In progress"))
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Label(appLanguage.format("Garden: %@", appLanguage.text(record.garden.title)), systemImage: "leaf")
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private var dateLabel: some View {
        Text(dayLabel(record.day, locale: appLanguage.locale)).font(.headline)
    }

    private var estimateLabel: some View {
        Text(summaryGrams(record.result.totalKg, locale: appLanguage.locale))
            .font(.headline)
            .monospacedDigit()

    }

    private var dateAndEstimate: some View {
        VStack(alignment: .leading, spacing: 4) {
            dateLabel
            estimateLabel
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
