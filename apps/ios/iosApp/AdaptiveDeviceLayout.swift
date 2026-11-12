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

import CoreGraphics
import SwiftUI
#if DEBUG
import UIKit
#endif

// [01] Use the space the app has now, rather than guessing from a device name.
// A narrow window or larger accessibility text keeps the familiar single column.
struct AdaptiveDeviceLayout: Equatable {
    static let wideThreshold: CGFloat = 760
    static let maximumContentWidth: CGFloat = 1_120
    static let columnGap: CGFloat = 32

    // [03] A wider screen does not make the existing phone model a measured iPad result.
    static func modelScopeNote(isPad: Bool) -> String? {
        isPad ? "On iPad, this estimate uses the app's phone reference model. It is not a measurement of iPad energy use." : nil
    }

    let width: CGFloat
    let height: CGFloat
    let regularWidth: Bool
    let accessibilityText: Bool

    init(width: CGFloat, height: CGFloat = .infinity, regularWidth: Bool, accessibilityText: Bool) {
        self.width = width
        self.height = height
        self.regularWidth = regularWidth
        self.accessibilityText = accessibilityText
    }

    var usesColumns: Bool {
        width.isFinite && width >= Self.wideThreshold && regularWidth && !accessibilityText
    }

    // [07] A short reading area has room beside the garden. A very shallow window keeps the usual layout.
    var usesSideBySideEstimate: Bool {
        usesColumns && height.isFinite && (430...640).contains(height)
    }

    var horizontalPadding: CGFloat { usesColumns ? 32 : TabPageLayout.horizontal }

    var contentWidth: CGFloat {
        usesColumns ? Self.maximumContentWidth : 600
    }

    private var innerWidth: CGFloat {
        max(0, min(width.isFinite ? width : 0, contentWidth) - horizontalPadding * 2)
    }

    // [02] The side column stays readable while the garden gets the larger share of a wide window.
    var detailWidth: CGFloat {
        let readingShare: CGFloat = usesSideBySideEstimate ? 0.44 : 0.38
        return min(360, max(260, (innerWidth - Self.columnGap) * readingShare))
    }
    var gardenWidth: CGFloat { min(400, max(0, innerWidth - detailWidth - Self.columnGap)) }
    var gardenHeight: CGFloat { min(300, gardenWidth * 0.76) }
}

extension View {
    // [04] UI tests read the space this page really has, rather than guessing from a phone's pose.
    // Release builds keep the original view and never create this test-only accessibility receipt.
    @ViewBuilder
    func withUITestAdaptiveGeometry(viewport: CGSize, regularWidth: Bool,
                                    accessibilityText: Bool) -> some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            overlay(alignment: .topLeading) {
                UITestAdaptiveGeometryReceipt(viewport: viewport, regularWidth: regularWidth,
                                              accessibilityText: accessibilityText)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
            }
        } else {
            self
        }
#else
        self
#endif
    }
}

#if DEBUG
// [05] This small, noninteractive view belongs to the actual page window.
// Its receipt contains geometry only; it never reads a saved day, usage time or carbon estimate.
private struct UITestAdaptiveGeometryReceipt: UIViewRepresentable {
    let viewport: CGSize
    let regularWidth: Bool
    let accessibilityText: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UITestAdaptiveGeometryView()
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "today.layoutGeometry"
        view.accessibilityLabel = "UI test layout geometry"
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let view = uiView as? UITestAdaptiveGeometryView else { return }
        view.viewport = viewport
        view.regularWidth = regularWidth
        view.accessibilityText = accessibilityText
    }
}

private final class UITestAdaptiveGeometryView: UIView {
    var viewport = CGSize.zero
    var regularWidth = false
    var accessibilityText = false

    // [06] Read UIKit again for every accessibility snapshot, including after a window moves or rotates.
    override var accessibilityValue: String? {
        get {
            guard let window, let scene = window.windowScene,
                  viewport.width > 0, viewport.height > 0 else { return nil }
            func rectangle(_ frame: CGRect) -> [String: CGFloat] {
                ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
            }
            let orientation: UIInterfaceOrientation
            if #available(iOS 16, *) { orientation = scene.effectiveGeometry.interfaceOrientation }
            else { orientation = scene.interfaceOrientation }
            let locked: Bool
            let resizing: Bool
            if #available(iOS 26, *) {
                locked = scene.effectiveGeometry.isInterfaceOrientationLocked
                resizing = scene.effectiveGeometry.isInteractivelyResizing
            } else {
                locked = false
                resizing = false
            }
            let value: [String: Any] = [
                "version": 1,
                "viewportWidth": viewport.width,
                "viewportHeight": viewport.height,
                "regularWidth": regularWidth,
                "accessibilityText": accessibilityText,
                "interfaceOrientation": orientation.rawValue,
                "orientationLocked": locked,
                "supportedOrientations": window.rootViewController?.supportedInterfaceOrientations.rawValue ?? 0,
                "interactivelyResizing": resizing,
                "windowFrame": rectangle(UIAccessibility.convertToScreenCoordinates(window.bounds, in: window)),
                "safeFrame": rectangle(UIAccessibility.convertToScreenCoordinates(
                    window.safeAreaLayoutGuide.layoutFrame, in: window))
            ]
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set { super.accessibilityValue = newValue }
    }
}
#endif
