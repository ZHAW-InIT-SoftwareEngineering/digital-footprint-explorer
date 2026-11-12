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

#if DEBUG && os(watchOS)
import SwiftUI
import WidgetKit

enum WatchVisualPreviewFamily: String {
    case rectangular, circular, inline
    var widgetFamily: WidgetFamily {
        switch self {
        case .rectangular: .accessoryRectangular
        case .circular: .accessoryCircular
        case .inline: .accessoryInline
        }
    }
    var width: CGFloat {
        switch self {
        case .rectangular: 150
        case .circular: 58
        case .inline: 174
        }
    }
    var height: CGFloat {
        switch self {
        case .rectangular: 72
        case .circular: 58
        case .inline: 26
        }
    }
    static func requested(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
        guard let position = arguments.firstIndex(of: "-ui-watch-complication"),
              arguments.indices.contains(position + 1) else { return nil }
        return Self(rawValue: arguments[position + 1])
    }
}

// [01] Use the real complication content for a bounded layout check, without pretending this app screen is a watch-face host.
struct WatchComplicationVisualPreview: View {
    @ObservedObject var model: WatchGardenModel
    let family: WatchVisualPreviewFamily

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Complication preview").font(.headline)
                    .accessibilityIdentifier("watch.complication.preview")
                Text("Example · \(family.rawValue)").font(.caption2).foregroundStyle(.secondary)
                WatchGardenComplicationContent(
                    entry: WatchGardenEntry(date: Date(), envelope: model.envelope, isPreview: true),
                    family: family.widgetFamily,
                    privacyRedacted: ProcessInfo.processInfo.arguments.contains("-ui-watch-privacy-redacted"))
                    .frame(width: family.width, height: family.height)
                Text("Content layout only. Watch-face placement is checked separately.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 6)
        }
        .background(.black)
    }
}

struct WatchVisualTextSize: ViewModifier {
    let isPreviewing: Bool
    func body(content: Content) -> some View {
        if isPreviewing, let position = ProcessInfo.processInfo.arguments.firstIndex(of: "-ui-watch-text-size"),
           ProcessInfo.processInfo.arguments.indices.contains(position + 1) {
            switch ProcessInfo.processInfo.arguments[position + 1] {
            case "accessibility3": content.dynamicTypeSize(.accessibility3)
            case "accessibility5": content.dynamicTypeSize(.accessibility5)
            default: content
            }
        } else {
            content
        }
    }
}
#endif
