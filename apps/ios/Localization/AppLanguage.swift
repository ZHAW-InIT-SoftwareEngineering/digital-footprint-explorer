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

// [01] Keep the language choice separate from the saved garden, dates and calculation inputs.
enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case english = "en"
    case swissGerman = "de-CH"

    static let storageKey = "dfe.language"
    var id: String { rawValue }
    var locale: Locale { Locale(identifier: self == .swissGerman ? "de_CH" : "en_GB") }

    var displayName: String {
        switch self {
        case .english: "English"
        case .swissGerman: "Deutsch (Schweiz)"
        }
    }

    // [02] Use Swiss spelling for German devices, with English for other device languages.
    static var system: AppLanguage {
        preferred(for: Locale.preferredLanguages.first)
    }

    static func preferred(for languageTag: String?) -> AppLanguage {
        let language = languageTag.flatMap { Locale(identifier: $0).language.languageCode?.identifier }
        return language == "de" ? .swissGerman : .english
    }

    #if os(iOS)
    static let preferenceStore: UserDefaults = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing"), let testStore = UserDefaults(suiteName: "dfe.language.ui-testing") {
            if !arguments.contains("-ui-keep-language") || arguments.contains("-ui-reset-language") {
                testStore.removeObject(forKey: storageKey)
            }
            return testStore
        }
        #endif
        return .standard
    }()

    static var current: AppLanguage {
        preferenceStore.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .english
    }

    private static var widgetDefaults: UserDefaults? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") { return nil }
        #endif
        guard let group = WidgetSnapshotStorage.appGroupIdentifier(),
              FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil else { return nil }
        return UserDefaults(suiteName: group)
    }

    static var widgetPreference: AppLanguage {
        widgetDefaults?.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .system
    }

    // [03] Share only the choice with the widget so it can translate even when the app is closed.
    @discardableResult
    func updateWidgetPreference() -> Bool {
        guard let defaults = Self.widgetDefaults, defaults.string(forKey: Self.storageKey) != rawValue else { return false }
        defaults.set(rawValue, forKey: Self.storageKey)
        return true
    }
    #endif

    // [04] Look up runtime text in the same resources that SwiftUI uses for its view labels.
    private static let swissGermanBundle = Bundle.main.url(forResource: AppLanguage.swissGerman.rawValue, withExtension: "lproj")
        .flatMap { Bundle(url: $0) }

    func text(_ key: String) -> String {
        guard self == .swissGerman else { return key }
        return Self.swissGermanBundle?.localizedString(forKey: key, value: key, table: nil) ?? key
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }
}

private struct AppLanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppLanguage.english
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageEnvironmentKey.self] }
        set { self[AppLanguageEnvironmentKey.self] = newValue }
    }
}
