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

struct WatchGardenView: View {
    @ObservedObject var model: WatchGardenModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 14) {
                    if let snapshot = model.envelope?.snapshot {
                        garden(snapshot, imageHeight: WatchGardenLayoutPolicy.gardenHeight(
                            availableHeight: Double(geometry.size.height), accessibilityText: dynamicTypeSize.isAccessibilitySize))
                    } else {
                        emptyState
                    }
                    refreshButton
                    Text(model.connectionNote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("watch.connectionNote")
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            // [02] Keep scrolled text inside the app's viewport so it cannot run behind the system clock.
            .clipped()
            .background(Color.black)
            .navigationTitle("DFE")
            .accessibilityIdentifier("watch.scroll")
        }
    }

    private var refreshButton: some View {
        Button(action: model.refresh) {
            if model.isRefreshing {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Checking…")
                    }
                    Text("Checking…")
                }
            } else {
                // [03] A short title leaves space for large text. VoiceOver still names the device the action checks.
                ViewThatFits(in: .horizontal) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                    Text("Refresh")
                }
            }
        }
        .font(.callout.weight(.medium))
        .buttonStyle(.bordered)
        .disabled(model.isRefreshing || model.isPreviewing)
        .accessibilityLabel(model.isRefreshing ? "Checking iPhone" : "Refresh from iPhone")
        .accessibilityHint("Checks for the latest saved estimate on your paired iPhone.")
        .accessibilityIdentifier("watch.refresh")
    }

    private func garden(_ snapshot: CompanionGardenSnapshot, imageHeight: Double) -> some View {
        VStack(spacing: 6) {
            ViewThatFits(in: .horizontal) {
                Text(gardenHeading)
                    .fixedSize()
                    .accessibilityIdentifier("watch.heading")
                Text(shortGardenHeading)
                    .accessibilityLabel(gardenHeading)
                    .accessibilityIdentifier("watch.heading")
            }
            .font(.headline)
            .multilineTextAlignment(.center)
            Text(snapshot.dateLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("watch.day")
            // [01] Reuse the phone's garden states so the Watch remains a familiar window into the same estimate.
            Image(snapshot.garden.imageName)
                .resizable()
                .scaledToFit()
                .frame(height: CGFloat(imageHeight))
                .accessibilityLabel("Garden state: \(snapshot.garden.title)")
                .accessibilityIdentifier("watch.garden")
            Text("\(snapshot.amountLabel()) g CO₂e")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("watch.estimate")
            Text("Estimated phone footprint")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(snapshot.garden.title)
                .font(.caption.weight(.medium))
                .accessibilityIdentifier("watch.state")
            if snapshot.isOlderThanLatestCompletedDay(now: Date()) {
                Label("Last saved day", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .accessibilityIdentifier("watch.stale")
            } else if !snapshot.isCompleted {
                Text("Day in progress").font(.caption2).foregroundStyle(.secondary)
            }
            Text(snapshot.source.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("watch.source")
            VStack(spacing: 3) {
                Text("Last saved")
                    .fontWeight(.medium)
                Text(snapshot.calculatedAt.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("watch.savedAt")
        }
    }

    private var gardenHeading: String {
        #if DEBUG
        if model.isPreviewing { return "Example preview" }
        #endif
        return "Your phone garden"
    }

    private var shortGardenHeading: String {
        #if DEBUG
        if model.isPreviewing { return "Example" }
        #endif
        return "Garden"
    }

    private var emptyState: some View {
        let availability = model.envelope?.availability ?? .sharingOff
        return VStack(spacing: 12) {
            Image(systemName: "iphone.and.arrow.right.inward")
                .font(.largeTitle)
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(availability.title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("watch.status.title")
            Text(availability.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("This Watch does not measure app activity.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 12)
    }
}
#endif
