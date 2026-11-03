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

enum FootprintTab: Hashable { case today, history, settings }

// [01] Changing the theme can redraw a screen. Keep the chosen tab for this app session.
@MainActor
final class AppNavigationState: ObservableObject {
    @Published var selectedTab: FootprintTab = .today
    @Published private(set) var todayRootID = UUID()

    func openWidgetURL(_ url: URL) {
        guard url.scheme == "digitalfootprint", url.host == "today" else { return }
        // [02] A widget opens the overview even when a saved day was left on screen.
        todayRootID = UUID()
        selectedTab = .today
    }
}

// [03] History and Settings share a rhythm, including their introduction and outer margins.
enum TabPageLayout {
    static let horizontal: CGFloat = 20
    // [04] Leave the first heading clear of the native pull-to-refresh indicator.
    static let top: CGFloat = 40
    // [05] Leave space above Today while the refresh spinner fades and the page settles back.
    static let todayTop: CGFloat = top + 16
    static let bottom: CGFloat = 24
    static let sectionSpacing: CGFloat = 32
    static let introSpacing: CGFloat = 8
    static let contentWidth: CGFloat = 680
}

// [06] Keep each tab's navigation separate, while sharing the same saved history and appearance.
struct ContentView: View {
    @EnvironmentObject private var navigation: AppNavigationState
    @EnvironmentObject private var store: FootprintStore
    @EnvironmentObject private var screenTime: ScreenTimeService
    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 18.0, *) {
            // [07] Name each tab clearly so tapping a control inside it cannot accidentally select another tab.
            TabView(selection: $navigation.selectedTab) {
                Tab("Today", systemImage: "leaf", value: FootprintTab.today) { todayNavigation }
                Tab("History", systemImage: "calendar", value: FootprintTab.history) {
                    NavigationStack { HistoryOverview(store: store) }
                }
                Tab("Settings", systemImage: "slider.horizontal.3", value: FootprintTab.settings) {
                    NavigationStack { SettingsScreen(store: store, screenTime: screenTime) }
                }
            }
        } else {
            TabView(selection: $navigation.selectedTab) {
                todayNavigation.tabItem { Label("Today", systemImage: "leaf") }.tag(FootprintTab.today)
                NavigationStack { HistoryOverview(store: store) }
                    .tabItem { Label("History", systemImage: "calendar") }.tag(FootprintTab.history)
                NavigationStack { SettingsScreen(store: store, screenTime: screenTime) }
                    .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }.tag(FootprintTab.settings)
            }
        }
    }

    // [08] A widget or notification returns to the main garden, even if a detail page was left open.
    private var todayNavigation: some View {
        NavigationStack {
            if store.isConfigured { TodayScreen(store: store, screenTime: screenTime) }
            else { WelcomeScreen(store: store, screenTime: screenTime) }
        }.id(navigation.todayRootID)
    }

    var body: some View {
        tabs
        .onOpenURL { url in
            navigation.openWidgetURL(url)
        }
        .tint(FootprintAppearance.accent)
        .withUITestTextSize()
        .background(FootprintAppearance.page.ignoresSafeArea())
        .alert("Could not save this change", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "Please try again.") }
    }
}

// [09] Only separate layout tests fix the text size. Normal screens follow the person's setting.
extension View {
    @ViewBuilder
    func withUITestTextSize() -> some View {
        #if DEBUG
        modifier(UITestTextSize())
        #else
        self
        #endif
    }
}

#if DEBUG
private struct UITestTextSize: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing"), arguments.contains("-ui-extra-large-text") {
            content.dynamicTypeSize(.accessibility5)
        } else if arguments.contains("-ui-testing"), arguments.contains("-ui-large-text") {
            content.dynamicTypeSize(.accessibility3)
        } else {
            content
        }
    }
}
#endif

// [10] Keep the garden prominent while giving the surrounding content a little more room.
private enum TodayGardenLayout {
    static let maximumWidth: CGFloat = 327 * 0.9
    static func height(in viewport: CGFloat) -> CGFloat {
        min(239, max(80, (viewport - 424) * 0.855)) * 0.9
    }
}

private struct WelcomeScreen: View {
    @ObservedObject var store: FootprintStore
    @ObservedObject var screenTime: ScreenTimeService
    @State private var automaticSetup = false
    @State private var widgetHelp = false
    var body: some View {
        GeometryReader { viewport in
            let gardenHeight = TodayGardenLayout.height(in: viewport.size.height)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TodayWelcome(title: "Welcome to your garden")
                    GardenArtwork(state: .stable, maximumWidth: TodayGardenLayout.maximumWidth)
                        .frame(height: gardenHeight).accessibilityHidden(true)
                    Text("Make yourself at home.").font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("A little space to notice your phone habits, one day at a time. Allow Screen Time once and let your garden take it from there.")
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    Button { automaticSetup = true } label: {
                        Label("Automatic setup", systemImage: "clock.badge.checkmark")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 28)
                            .fixedSize(horizontal: false, vertical: true)
                    }.modifier(TodayActionStyle()).controlSize(.large)
                        .accessibilityIdentifier("onboarding.automatic")
                    Text("Your first estimate waits for a completed day and usable Screen Time data. Carbon emissions and data traffic are estimates, not direct measurements.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { widgetHelp = true } label: {
                        Label("Set up a garden widget", systemImage: "square.grid.2x2")
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                            .fixedSize(horizontal: false, vertical: true)
                    }.accessibilityIdentifier("today.widgetHelp")
                    NavigationLink { PrivacyPolicyView(publicURL: ReleaseLinks.privacyPolicy) } label: {
                        Label("Privacy policy", systemImage: "hand.raised").frame(minHeight: 44)
                    }.accessibilityIdentifier("onboarding.privacy")
                }.padding(.horizontal, 20).padding(.top, TabPageLayout.todayTop).padding(.bottom, 24)
                    .frame(maxWidth: 600).frame(maxWidth: .infinity)
                    .frame(minHeight: viewport.size.height, alignment: .top)
            }.automaticRefresh()
                .accessibilityIdentifier("today.content")
                .background(FootprintAppearance.page)
                .navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
                .accessibilityHidden(automaticSetup || widgetHelp)
        }.sheet(isPresented: $automaticSetup, onDismiss: { Task { await AppServices.shared.refresh() } }) {
            AutomaticOnboardingView(store: store, service: screenTime).withUITestTextSize()
        }.sheet(isPresented: $widgetHelp) {
            WidgetHelpScreen().withUITestTextSize()
        }
    }
}

private struct TodayScreen: View {
    @ObservedObject var store: FootprintStore
    @ObservedObject var screenTime: ScreenTimeService
    @State private var automaticSetup = false
    @State private var widgetHelp = false
    private var todayRecord: FootprintRecord? { store.records.first { $0.day == store.today } }
    // [11] While today is unfinished, keep the latest saved garden visible with its actual date.
    private var displayedRecord: FootprintRecord? { todayRecord ?? store.latest }
    // [12] Waiting for the first usable day should not ask the person to complete setup again.
    private var needsAutomaticSetup: Bool { !screenTime.hasSavedAutomaticSetup(store: store) }

    var body: some View {
        GeometryReader { viewport in
            // [13] Leave the first action clear of the native floating tabs on small phones.
            let gardenHeight = TodayGardenLayout.height(in: viewport.size.height)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TodayWelcome()
                    if let record = displayedRecord {
                        VStack(spacing: 12) {
                            if todayRecord == nil {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 12) {
                                        Text("Latest completed day").foregroundStyle(.secondary)
                                        Spacer(minLength: 8)
                                        Text(dayLabel(record.day)).fontWeight(.semibold)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Latest completed day").foregroundStyle(.secondary)
                                        Text(dayLabel(record.day)).fontWeight(.semibold)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.font(.subheadline).padding(.bottom, 8)
                            }
                            FootprintSummary(record: record, gardenHeight: gardenHeight,
                                             showsComparison: false, gardenWidth: TodayGardenLayout.maximumWidth)
                        }
                        // [14] Group the summary as one container, so iOS 17 keeps its accessibility identity
                        // separate from the amount and garden state inside it.
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(todayRecord == nil ? "today.latestResult" : "today.currentResult")
                    } else {
                        VStack(spacing: 12) {
                            GardenArtwork(state: .stable, maximumWidth: TodayGardenLayout.maximumWidth)
                                .frame(height: gardenHeight).accessibilityHidden(true)
                            Text("Your garden starts here").font(.headline)
                                .multilineTextAlignment(.center)
                            Text("Your garden is waiting with you. Your first estimate needs a completed day and usable activity from Apple.")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity)
                    }
                    if needsAutomaticSetup {
                        Button { automaticSetup = true } label: {
                            Label("Automatic setup", systemImage: "clock.badge.checkmark")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 28)
                                .fixedSize(horizontal: false, vertical: true)
                        }.modifier(TodayActionStyle()).controlSize(.large)
                            .accessibilityIdentifier("today.automaticSetup")
                            .padding(.top, 12).padding(.bottom, 12)
                    }
                    if todayRecord == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(store.usesAutomaticInput ? "Let your next day take shape" : "Let your garden follow your day",
                                  systemImage: store.usesAutomaticInput ? "clock" : "leaf")
                                .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("today.automaticPending")
                            Text(store.usesAutomaticInput
                                 ? "Today's estimate waits until this day ends and Apple provides usable activity. Missing activity stays pending."
                                 : "Allow Screen Time once to start automatic estimates. No app-by-app selection or daily forms.")
                                .font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }.padding(.top, needsAutomaticSetup ? 0 : 12)
                    }
                    Spacer(minLength: 0)
                    Button { widgetHelp = true } label: {
                        Label("Set up a garden widget", systemImage: "square.grid.2x2")
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                            .fixedSize(horizontal: false, vertical: true)
                    }.accessibilityIdentifier("today.widgetHelp")
                    if let record = displayedRecord {
                        // [15] Today stays a short overview; the saved day holds the full explanation.
                        NavigationLink { RecordScreen(store: store, day: record.day) } label: {
                            HStack(spacing: 12) {
                                Text("View this day").font(.subheadline.weight(.semibold))
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            }.frame(minHeight: 44)
                        }.accessibilityIdentifier("today.dayDetails")
                    }
                }.padding(.horizontal, 20).padding(.top, TabPageLayout.todayTop).padding(.bottom, 24)
                    .frame(maxWidth: 600).frame(maxWidth: .infinity)
                    .frame(minHeight: viewport.size.height, alignment: .top)
            }.automaticRefresh()
                .accessibilityIdentifier("today.content")
                .background(FootprintAppearance.page)
                .accessibilityHidden(automaticSetup || widgetHelp)
                .navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
        }.sheet(isPresented: $automaticSetup, onDismiss: { Task { await AppServices.shared.refresh() } }) {
            AutomaticOnboardingView(store: store, service: screenTime).withUITestTextSize()
        }.sheet(isPresented: $widgetHelp) {
            WidgetHelpScreen().withUITestTextSize()
        }
    }
}

// [16] Keep the greeting and date together; the garden is the main visual below them.
private struct TodayWelcome: View {
    var title = "Good to have you here"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("today.welcome")
            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("today.date")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// [17] Let iOS draw the glass button and adapt it to accessibility settings.
struct TodayActionStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.foregroundStyle(FootprintAppearance.prominentText).buttonStyle(.glassProminent)
        } else {
            content.foregroundStyle(FootprintAppearance.prominentText).buttonStyle(.borderedProminent)
        }
    }
}

// [18] Open a saved day by date, so a later refresh shows its current saved explanation.
struct RecordScreen: View {
    @ObservedObject var store: FootprintStore
    let day: String
    private var record: FootprintRecord? { store.records.first { $0.day == day } }
    var body: some View {
        ScrollView {
            if let record {
                VStack(spacing: 20) {
                    FootprintSummary(record: record, showsGarden: false)
                    SourceCard(source: record.source, measuredCategories: record.automaticCategories ?? [])
                    CategoryBreakdownCard(record: record, initiallyExpanded: true)
                }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
        }
        .background(FootprintAppearance.page)
        .navigationTitle(dayLabel(day)).navigationBarTitleDisplayMode(.inline)
    }
}

private struct FootprintSummary: View {
    let record: FootprintRecord
    var gardenHeight: CGFloat = 160
    var showsComparison = true
    var gardenWidth: CGFloat = 320
    var showsGarden = true
    private var gardenMessage: String {
        GardenFeedback.message(state: record.garden, totalKg: record.result.totalKg,
                               baselineKg: record.baselineKg)
    }
    var body: some View {
        VStack(spacing: 8) {
            if showsGarden {
                GardenArtwork(state: record.garden, maximumWidth: gardenWidth).frame(height: gardenHeight)
                    .accessibilityHidden(true)
            }
            Text(summaryGrams(record.result.totalKg))
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit().multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(summaryGrams(record.result.totalKg))
                .accessibilityHint("Estimated carbon footprint for this day.")
                .accessibilityIdentifier("footprint.total")
            Text("Estimated carbon footprint").font(.subheadline).foregroundStyle(.primary)
                .accessibilityHidden(true)
            if record.source == .screenTimeWithEstimates {
                // [20] Show the app time behind this saved estimate, so a weekly Screen Time
                // average is not mistaken for the input to a different completed day.
                Group {
                    if let imported = importedActivityMinutes(record) {
                        Text("Imported app activity: \(summaryActivityTime(imported))")
                    } else {
                        Text("Activity used for this estimate: \(summaryActivityTime(record.inputs.totalMinutes))")
                    }
                }.font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("footprint.importedActivity")
            }
            Text(gardenMessage).font(.subheadline)
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Garden: \(record.garden.title). \(gardenMessage)")
                .accessibilityIdentifier("garden.state")
            if showsGarden, !showsComparison, record.baselineKg != nil {
                Text("Your garden follows changes in your own estimates.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("garden.comparisonBasis")
            }
            if showsComparison, let baseline = record.baselineKg {
                Text("Your earlier daily average: \(summaryGrams(baseline)).")
                    .font(.footnote).foregroundStyle(.primary).multilineTextAlignment(.center)
                Text("The garden compares this estimate with up to seven earlier days.")
                    .font(.footnote).foregroundStyle(.primary).multilineTextAlignment(.center)
            }
        }.fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity).padding(.bottom, 2)
    }
}

// [19] The model has uncertain inputs, so the main figure avoids false precision.
func summaryGrams(_ kg: Double) -> String {
    "\((kg * 1000).formatted(.number.precision(.significantDigits(1...3)))) g CO₂e"
}

// [22] Earlier selected-app records can also contain routine estimates. Count only the
// categories marked as imported; missing source information is not evidence of measured time.
func importedActivityMinutes(_ record: FootprintRecord) -> Double? {
    guard record.source == .screenTimeWithEstimates,
          let imported = record.automaticCategories, !imported.isEmpty else { return nil }
    let categories = Set(imported)
    let values = record.inputs.usages.filter { categories.contains($0.category) }
    guard values.count == categories.count, Set(values.map(\.category)) == categories,
          values.allSatisfy({ $0.minutes.isFinite && $0.minutes >= 0 }) else { return nil }
    let total = values.reduce(0) { $0 + $1.minutes }
    return total.isFinite ? total : nil
}

// [21] Keep the displayed activity readable without changing the saved minutes used by the model.
func summaryActivityTime(_ minutes: Double) -> String {
    guard minutes.isFinite, minutes >= 0, minutes < Double(Int.max) / 2 else { return "Unavailable" }
    if minutes == 0 { return "0 min" }
    let wholeMinutes = Int(minutes.rounded())
    if wholeMinutes == 0 { return "less than 1 min" }
    let hours = wholeMinutes / 60
    let remaining = wholeMinutes % 60
    if hours == 0 { return "\(remaining) min" }
    return remaining == 0 ? "\(hours) h" : "\(hours) h \(remaining) min"
}

private struct SourceCard: View {
    let source: FootprintSource
    var measuredCategories: [FootprintCategory] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(source.title, systemImage: source == .routineEstimate ? "clock.arrow.circlepath" : "info.circle")
                .font(.subheadline.weight(.semibold))
            Text(source.explanation).font(.footnote).foregroundStyle(.primary)
            if source == .screenTimeWithEstimates {
                Text("Apple's available app time can differ from the daily total in Screen Time. This estimate covers the app activity provided for the saved date on this iPhone.")
                    .font(.footnote).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("source.activityPeriod")
                Text("Traffic and power use follow saved category assumptions. Background listening, video quality and calls within an app may not be fully reflected.")
                    .font(.footnote).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("source.modelLimits")
            }
            if Set(measuredCategories) == Set(FootprintCategory.allCases) {
                Text("All model categories use imported app time. Apps without a local category rule stay under Other apps.")
                    .font(.caption).foregroundStyle(.primary)
            } else if !measuredCategories.isEmpty {
                Text("Usage time from Screen Time: " + measuredCategories.map(\.title).joined(separator: ", ") + ".")
                    .font(.caption).foregroundStyle(.primary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(FootprintAppearance.card, in: RoundedRectangle(cornerRadius: 16))
    }
}


enum FootprintAppearance {
    // [20] Dark green on light surfaces, pale green on dark ones; system colors follow contrast settings.
    static let accent = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.56, green: 0.85, blue: 0.66, alpha: 1)
        }
        return traits.accessibilityContrast == .high
            ? UIColor(red: 0.06, green: 0.30, blue: 0.16, alpha: 1)
            : UIColor(red: 0.10, green: 0.40, blue: 0.24, alpha: 1)
    })
    static let prominentText = Color(uiColor: .systemBackground)
    static let page = AppSurface.canvas
    static let card = AppSurface.card
}

// [21] Saved/shared results use kg; the interface uses g so small daily values are readable.
func grams(_ kg: Double) -> String {
    let amount = (kg * 1000).formatted(.number.precision(.fractionLength(0...3)))
    return "\(amount) g CO₂e"
}

// [22] Format the saved calendar date for the person reading it without moving that day across time zones.
func dayLabel(_ day: String) -> String {
    guard let date = FootprintCalendar().date(day) else { return day }
    return date.formatted(date: .abbreviated, time: .omitted)
}
