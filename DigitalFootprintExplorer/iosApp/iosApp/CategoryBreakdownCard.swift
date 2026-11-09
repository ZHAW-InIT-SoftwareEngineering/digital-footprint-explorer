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
import UIKit

// [01] Compare category time within this day, without setting a "safe" usage limit.
struct CategoryUsageLevel: Equatable {
    enum Band: Equatable { case noUse, less, moderate, more, unavailable }
    let fraction: Double?

    // [02] Compare valid times with the most-used category in this day.
    // Missing time gets no score, because unknown use is different from no use.
    init(minutes: Double?, dayMinutes: [Double]) {
        guard let minutes, minutes.isFinite, minutes >= 0 else {
            fraction = nil
            return
        }
        if minutes == 0 {
            fraction = 0
        } else if let maximum = dayMinutes.filter({ $0.isFinite && $0 > 0 }).max() {
            fraction = max(Double.leastNonzeroMagnitude, min(1, minutes / maximum))
        } else {
            fraction = nil
        }
    }

    var band: Band {
        guard let fraction else { return .unavailable }
        if fraction == 0 { return .noUse }
        if fraction <= 1.0 / 3 { return .less }
        if fraction <= 2.0 / 3 { return .moderate }
        return .more
    }

    var label: String {
        switch band {
        case .noUse: "No recorded use"
        case .less: "Less use"
        case .moderate: "Moderate use"
        case .more: "More use"
        case .unavailable: "Time unavailable"
        }
    }
}

// [03] Keep a category's usage time and estimate together in the saved-day detail.
struct CategoryBreakdownCard: View {
    let record: FootprintRecord
    @State private var showsCategories: Bool
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .subheadline) private var iconColumnWidth: CGFloat = 24

    init(record: FootprintRecord, initiallyExpanded: Bool = false) {
        self.record = record
        _showsCategories = State(initialValue: initiallyExpanded)
    }

    // [04] Show the largest estimated contributors first so the explanation is easier to scan.
    private var categories: [CategoryFootprint] {
        record.result.categories.sorted {
            $0.totalKg == $1.totalKg
                ? $0.category.title < $1.category.title
                : $0.totalKg > $1.totalKg
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Where the estimate comes from").font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 20) {
                sourceRow("App use", kg: record.result.appUsageKg,
                          symbol: UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone", identifier: "breakdown.app")
                sourceRow("Screen", kg: record.result.displayKg,
                          symbol: "sun.max", identifier: "breakdown.screen")
                sourceRow("Background", kg: record.result.backgroundKg,
                          symbol: "arrow.triangle.2.circlepath", identifier: "breakdown.background")
            }
            if !categories.isEmpty {
                Divider()
                Button { showsCategories.toggle() } label: {
                    HStack(spacing: 12) {
                        Text("By app category").font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Image(systemName: showsCategories ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold)).accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("By app category")
                .accessibilityValue(showsCategories ? "Expanded" : "Collapsed")
                .accessibilityHint(showsCategories ? "Hide usage time and emission estimates" : "Show usage time and emission estimates")
                .accessibilityIdentifier("breakdown.categories")
                if showsCategories {
                    categoryDetails
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FootprintAppearance.card, in: RoundedRectangle(cornerRadius: 18))
    }

    // [05] Keep time, estimated emissions and their sources together for each category.
    // The bars and colours answer different questions, which the short note explains.
    private var categoryDetails: some View {
        VStack(spacing: 20) {
            Text("Colours compare usage time within this day, from green to amber to red. Bar length shows each category's share of app-use emissions.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(categories) { category in
                VStack(alignment: .leading, spacing: 8) {
                    categoryHeading(category)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("breakdown.category.\(category.id)")
                    GeometryReader { proxy in
                        let width = proxy.size.width.isFinite ? max(0, proxy.size.width) : 0
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.12))
                            Capsule().fill(usageColor(for: category.category))
                                .frame(width: width * share(of: category))
                        }
                    }
                    .frame(height: 5).accessibilityHidden(true)
                    Text("Device \(grams(category.deviceKg)) · Network \(grams(category.networkKg)) · Servers \(grams(category.backendKg))")
                        .font(.caption).foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 12)
                        .accessibilityIdentifier("breakdown.sources.\(category.id)")
                }
                .accessibilityElement(children: .contain)
                if category.id != categories.last?.id { Divider() }
            }
            Text("Brightness \(Int(record.inputs.brightness * 100))% · GPS \(record.inputs.gpsHours.formatted()) h · Bluetooth \(record.inputs.bluetoothHours.formatted()) h")
                .font(.caption).foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier("record.assumptions")
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    // [06] At larger text sizes, let the amount move below the category instead of squeezing either label.
    private func categoryHeading(_ category: CategoryFootprint) -> some View {
        if textSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                categoryNameAndTime(category)
                emissionAmount(category)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    categoryNameAndTime(category)
                    Spacer(minLength: 8)
                    emissionAmount(category).fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    categoryNameAndTime(category)
                    emissionAmount(category)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func categoryNameAndTime(_ category: CategoryFootprint) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: category.category.symbol)
                .font(.subheadline).frame(width: iconColumnWidth, alignment: .center)
                .foregroundStyle(usageColor(for: category.category))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(category.category.title).font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(usageTime(for: category.category))
                    .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func emissionAmount(_ category: CategoryFootprint) -> some View {
        Text(grams(category.totalKg)).font(.subheadline.weight(.semibold)).monospacedDigit()
            .foregroundStyle(usageColor(for: category.category))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func sourceRow(_ title: String, kg: Double, symbol: String, identifier: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Label(title, systemImage: symbol).fixedSize()
                Spacer(minLength: 12)
                Text(grams(kg)).monospacedDigit().fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol)
                Text(grams(kg)).monospacedDigit()
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine).accessibilityIdentifier(identifier)
    }

    // [07] Use the saved time for this exact day; a later setup change must not rewrite this label.
    private func usageTime(for category: FootprintCategory) -> String {
        guard let usage = record.inputs.usages.first(where: { $0.category == category }),
              usage.minutes.isFinite, usage.minutes >= 0 else {
            return "Usage time not recorded"
        }
        return "\(usage.minutes.formatted(.number.precision(.fractionLength(0...1)))) min · \(usageLevel(for: category).label)"
    }

    // [08] Keep every bar within its track, including a day with no estimated app emissions.
    private func share(of category: CategoryFootprint) -> Double {
        guard record.result.appUsageKg > 0 else { return 0 }
        return min(1, max(0, category.totalKg / record.result.appUsageKg))
    }

    private func usageLevel(for category: FootprintCategory) -> CategoryUsageLevel {
        CategoryUsageLevel(minutes: record.inputs.usages.first(where: { $0.category == category })?.minutes,
                           dayMinutes: record.inputs.usages.map(\.minutes))
    }

    // [09] The colour is a relative guide for this day, not a medical or environmental safety rating.
    private func usageColor(for category: FootprintCategory) -> Color {
        guard let fraction = usageLevel(for: category).fraction, fraction > 0 else { return .secondary }
        return Color(uiColor: UIColor { traits in
            let palette: [(CGFloat, CGFloat, CGFloat)]
            if traits.userInterfaceStyle == .dark {
                palette = [(0.63, 0.89, 0.68), (1, 0.78, 0.25), (1, 0.59, 0.59)]
            } else if traits.accessibilityContrast == .high {
                palette = [(0.06, 0.30, 0.16), (0.38, 0.22, 0), (0.57, 0.08, 0.10)]
            } else {
                palette = [(0.13, 0.44, 0.23), (0.52, 0.32, 0), (0.70, 0.12, 0.15)]
            }
            // [10] Keep short use green, then blend through amber towards the day's maximum.
            let position = min(2, max(0, (fraction - 1.0 / 3) * 3))
            let segment = position <= 1 ? 0 : 1
            let amount = CGFloat(position - Double(segment))
            let start = palette[segment], end = palette[segment + 1]
            return UIColor(red: start.0 + (end.0 - start.0) * amount,
                           green: start.1 + (end.1 - start.1) * amount,
                           blue: start.2 + (end.2 - start.2) * amount, alpha: 1)
        })
    }
}
