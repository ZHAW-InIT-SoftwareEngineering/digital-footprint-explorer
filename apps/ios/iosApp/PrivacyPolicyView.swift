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

/// [01] The local copy stays readable even when the phone has no internet connection.
struct PrivacyPolicyView: View {
    var publicURL: URL? = nil

    // [02] Offer an online copy only for a complete secure web address; the local policy is still available.
    private var securePublicURL: URL? {
        guard let publicURL, publicURL.scheme?.lowercased() == "https",
              let host = publicURL.host, !host.isEmpty else { return nil }
        return publicURL
    }

    var body: some View {
        Form {
            Section {
                Text(PrivacyPolicyContent.appName).font(.headline)
                Text(PrivacyPolicyContent.updatedText)
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(PrivacyPolicyContent.introduction, id: \.self) { paragraph in
                    Text(paragraph).fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                Link(destination: PrivacyPolicyContent.contactURL) {
                    Label("Email the DFE team", systemImage: "envelope")
                        .frame(minHeight: 44)
                        .fixedSize(horizontal: false, vertical: true)
                }.accessibilityIdentifier("privacy.contact")
                if let securePublicURL {
                    Link(destination: securePublicURL) {
                        Label("Open online policy", systemImage: "safari")
                            .frame(minHeight: 44)
                            .fixedSize(horizontal: false, vertical: true)
                    }.accessibilityIdentifier("privacy.online")
                }
            }
            ForEach(PrivacyPolicyContent.sections) { section in
                Section {
                    ForEach(section.paragraphs, id: \.self) { paragraph in
                        Text(paragraph).fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text(section.title)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(FootprintAppearance.page)
        .navigationTitle(PrivacyPolicyContent.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("privacy.policy")
    }
}
