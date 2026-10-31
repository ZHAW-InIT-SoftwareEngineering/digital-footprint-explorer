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

// [01] Activity identities and category totals need careful local checks; Apple approval still
// needs a real-device test

import XCTest
#if SCREEN_TIME_ENABLED
import DeviceActivity
#endif
@testable import DFE

// [02] Apple's matching rules can be checked locally; actual approval still needs a separate phone
// test.
final class ScreenTimeTests: XCTestCase {
    // [03] An activity request should stay with this person and phone, rather than combine other
    // devices.
    func testUsageQueryStaysOnTheCurrentDeviceAndUser() {
        #if SCREEN_TIME_ENABLED
        let day = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 86400)
        // [04] Building this request description does not read private activity.
        let filter = ScreenTimeQueryScope.filter(interval: day, applications: [], categories: [])
        XCTAssertNil(filter.devices)
        XCTAssertNil(filter.users)
        XCTAssertTrue(filter.webDomains.isEmpty)
        #endif
    }

    // [05] Unselected rows should not hide a complete response for the choices the person actually
    // made.
    func testCompleteChosenCoverageAllowsIdentifiedForeignRows() throws {
        try ScreenTimeImportScope.validateCoverage(selectedApps: ["app"], coveredApps: ["app"],
            selectedGroups: Set<String>(), coveredGroups: [], foreignRowsSeen: true)
        // [06] A complete empty answer can mean real zero use; missing chosen activity is a
        // different case.
        try ScreenTimeImportScope.validateCoverage(selectedApps: ["app"], coveredApps: [],
            selectedGroups: Set<String>(), coveredGroups: [], foreignRowsSeen: false)
    }

    // [07] Activity from elsewhere cannot fill the gap when a chosen app or group is missing.
    func testForeignRowsCannotReplaceMissingChosenAppsOrGroups() {
        XCTAssertThrowsError(try ScreenTimeImportScope.validateCoverage(selectedApps: ["app"], coveredApps: [],
            selectedGroups: Set<String>(), coveredGroups: [], foreignRowsSeen: true))
        // [08] Sharing a footprint category does not prove that both chosen apps were included in
        // Apple's answer.
        XCTAssertThrowsError(try ScreenTimeImportScope.validateCoverage(selectedApps: ["first", "second"], coveredApps: ["first"],
            selectedGroups: Set<String>(), coveredGroups: [], foreignRowsSeen: true))
        XCTAssertThrowsError(try ScreenTimeImportScope.validateCoverage(selectedApps: ["app"], coveredApps: ["app"],
            selectedGroups: ["group"], coveredGroups: [], foreignRowsSeen: true))
    }

    // [09] Anonymous activity is not enough to tell whether an app belongs in the chosen group.
    func testAnonymousRowsCannotBecomeUsageEvenInsideAChosenGroup() {
        var durationRead = false
        XCTAssertThrowsError(try ScreenTimeImportScope.usage(categoryID: nil, selectedGroupID: "SOCIAL_MEDIA",
            hasIdentity: false, seconds: { durationRead = true; return 60 }))
        XCTAssertFalse(durationRead)
    }

    // [10] The importer should read only relevant activity, including identified apps inside a
    // chosen group.
    func testForeignRowsDoNotReadDurationButChosenGroupChildrenDo() throws {
        var durationRead = false
        XCTAssertNil(try ScreenTimeImportScope.usage(categoryID: nil, selectedGroupID: nil,
            hasIdentity: true, seconds: { durationRead = true; return 60 }))
        XCTAssertFalse(durationRead)
        let child = try ScreenTimeImportScope.usage(categoryID: nil, selectedGroupID: "SOCIAL_MEDIA",
            hasIdentity: true, seconds: { durationRead = true; return 60 })
        XCTAssertTrue(durationRead)
        XCTAssertEqual(child?.seconds, 60)
    }

    // [11] Conflicting identities can join unrelated activity, so a contradiction needs to stop
    // the import.
    func testCanonicalAliasesRejectContradictoryReportedIdentities() throws {
        let chosen: Set<String> = ["first", "second"]
        let aliases: [String: Set<String>] = ["example.first": ["first"], "example.second": ["second"]]
        XCTAssertEqual(try ScreenTimeImportScope.recognizedTokens(token: Optional<String>.none,
            bundleIdentifier: "example.first", selected: chosen, bundleAliases: aliases), ["first"])
        XCTAssertEqual(try ScreenTimeImportScope.recognizedTokens(token: "first",
            bundleIdentifier: nil, selected: chosen, bundleAliases: aliases), ["first"])
        for pair in [("first", "example.second"), ("foreign", "example.first"), ("first", "example.foreign")] {
            XCTAssertThrowsError(try ScreenTimeImportScope.recognizedTokens(token: pair.0,
                bundleIdentifier: pair.1, selected: chosen, bundleAliases: aliases))
        }
    }

    // [12] Apple can describe one app in two ways; it should count once, and conflicting versions
    // must be rejected.
    func testCanonicalTokenAndBundleRowsAreCountedOnceAndConflictsAreRejected() throws {
        let chosen: Set<String> = ["app"]
        let aliases: [String: Set<String>] = ["example.selected": chosen]
        let tokenRow = try ScreenTimeImportScope.recognizedTokens(token: "app",
            bundleIdentifier: nil, selected: chosen, bundleAliases: aliases)
        let bundleRow = try ScreenTimeImportScope.recognizedTokens(token: Optional<String>.none,
            bundleIdentifier: "example.selected", selected: chosen, bundleAliases: aliases)
        XCTAssertEqual(tokenRow, bundleRow)
        var ledger = ScreenTimeContributionLedger<String>(knownBundles: ["app": "example.selected"])
        try ledger.record(token: "app", bundleIdentifier: nil, categoryID: "SOCIAL_MEDIA",
            seconds: 120, isExplicit: true)
        try ledger.record(token: nil, bundleIdentifier: "example.selected", categoryID: "SOCIAL_MEDIA",
            seconds: 120, isExplicit: true)
        let rows = try ledger.contributions()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.seconds, 120)
        XCTAssertThrowsError(try ledger.record(token: nil, bundleIdentifier: "example.selected",
            categoryID: "SOCIAL_MEDIA", seconds: 121, isExplicit: true))
    }

    // [13] Repeated rows for the same app and destination should not make its footprint grow
    // twice.
    func testSameGroupDestinationCountsAnAppOnceAcrossRepeatedRows() throws {
        var ledger = ScreenTimeContributionLedger<String>()
        for _ in 0..<2 {
            try ledger.record(token: nil, bundleIdentifier: "example.group-child",
                categoryID: "SOCIAL_MEDIA", seconds: 120, isExplicit: false)
        }
        let rows = try ledger.contributions()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.categoryID, "SOCIAL_MEDIA")
        XCTAssertEqual(rows.first?.seconds, 120)
    }

    // [14] Conflicting group destinations need review instead of silently choosing whichever
    // response arrived first.
    func testDifferentGroupDestinationsRequireReviewInEitherResponseOrder() throws {
        for categories in [["SOCIAL_MEDIA", "VIDEO_STREAMING"], ["VIDEO_STREAMING", "SOCIAL_MEDIA"]] {
            var ledger = ScreenTimeContributionLedger<String>()
            for category in categories {
                try ledger.record(token: nil, bundleIdentifier: "example.group-child",
                    categoryID: category, seconds: 120, isExplicit: false)
            }
            XCTAssertThrowsError(try ledger.contributions()) { error in
                guard case ScreenTimeImportError.conflictingSelection = error else {
                    return XCTFail("Conflicting groups must request a selection review.")
                }
            }
        }
    }

    // [15] An explicit app choice should take priority over a wider group, regardless of Apple's
    // response order.
    func testDirectAppChoiceOverridesGroupsRegardlessOfResponseOrder() throws {
        let choices = [("SOCIAL_MEDIA", false), ("VIDEO_STREAMING", false), ("MESSAGING", true)]
        for order in [choices, Array(choices.reversed())] {
            var ledger = ScreenTimeContributionLedger<String>(knownBundles: ["app": "example.chosen"])
            for (category, direct) in order {
                try ledger.record(token: direct ? "app" : nil, bundleIdentifier: "example.chosen",
                    categoryID: category, seconds: 120, isExplicit: direct)
            }
            let rows = try ledger.contributions()
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows.first?.categoryID, "MESSAGING")
            XCTAssertEqual(rows.first?.seconds, 120)
            XCTAssertEqual(rows.first?.isExplicit, true)
        }
    }

    // [16] Partial identity details need a clear link supplied by Apple before their activity can
    // be combined.
    func testPartialIdentitiesNeedAnAppleProvidedPairBeforeTheyCanBeCounted() throws {
        var ledger = ScreenTimeContributionLedger<String>()
        try ledger.record(token: "opaque-app", bundleIdentifier: nil, categoryID: "SOCIAL_MEDIA",
            seconds: 120, isExplicit: false)
        try ledger.record(token: nil, bundleIdentifier: "example.group-child", categoryID: "SOCIAL_MEDIA",
            seconds: 120, isExplicit: false)
        XCTAssertThrowsError(try ledger.contributions())
        // [17] A later answer links these two identities directly, so no guess from an app name is
        // needed.
        try ledger.record(token: "opaque-app", bundleIdentifier: "example.group-child",
            categoryID: "SOCIAL_MEDIA", seconds: 120, isExplicit: false)
        let rows = try ledger.contributions()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.seconds, 120)
    }

    // [18] A shared text identity must not merge unrelated apps when their reported links
    // contradict each other.
    func testConflictingBundleAliasesCannotMergeUnrelatedApplications() throws {
        var ledger = ScreenTimeContributionLedger<String>()
        try ledger.record(token: "opaque-app", bundleIdentifier: "example.first", categoryID: "SOCIAL_MEDIA",
            seconds: 120, isExplicit: false)
        XCTAssertThrowsError(try ledger.record(token: "opaque-app", bundleIdentifier: "example.second",
            categoryID: "SOCIAL_MEDIA", seconds: 120, isExplicit: false))
        let rows = try ledger.contributions()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.bundleIdentifier, "example.first")
        var canonical = ScreenTimeContributionLedger<String>(knownBundles: ["app": "example.first"])
        XCTAssertThrowsError(try canonical.record(token: "app", bundleIdentifier: "example.second",
            categoryID: "SOCIAL_MEDIA", seconds: 120, isExplicit: true))
        XCTAssertTrue(try canonical.contributions().isEmpty)
    }

    // [19] Different reported times need a clear error, rather than an arbitrary choice of the
    // first row.
    func testGroupDuplicateDurationsAndDifferentCategoryBoundsCannotChooseTheFirstRow() throws {
        var ledger = ScreenTimeContributionLedger<String>()
        try ledger.record(token: nil, bundleIdentifier: "example.group-child", categoryID: "SOCIAL_MEDIA",
            seconds: 60, sourceSeconds: 120, isExplicit: false)
        XCTAssertThrowsError(try ledger.record(token: nil, bundleIdentifier: "example.group-child",
            categoryID: "SOCIAL_MEDIA", seconds: 60, sourceSeconds: 121, isExplicit: false))
        XCTAssertThrowsError(try ledger.record(token: nil, bundleIdentifier: "example.group-child",
            categoryID: "SOCIAL_MEDIA", seconds: 90, sourceSeconds: 120, isExplicit: false))
        XCTAssertEqual(try ledger.contributions().first?.seconds, 60)
    }

    // [20] Valid distinct apps can add up, but missing identities and impossible durations must
    // stop the result.
    func testDistinctKnownAppsAreAddedWhileAnonymousAndInvalidRowsAreRejected() throws {
        var ledger = ScreenTimeContributionLedger<String>(knownBundles: ["first": "example.first"])
        try ledger.record(token: "first", bundleIdentifier: nil, categoryID: "SOCIAL_MEDIA",
            seconds: 120, isExplicit: true)
        try ledger.record(token: nil, bundleIdentifier: "example.second", categoryID: "SOCIAL_MEDIA",
            seconds: 180, isExplicit: false)
        XCTAssertEqual(try ledger.contributions().reduce(0) { $0 + $1.seconds }, 300)
        XCTAssertThrowsError(try ledger.record(token: nil, bundleIdentifier: "", categoryID: "SOCIAL_MEDIA",
            seconds: 0, isExplicit: false))
        XCTAssertThrowsError(try ledger.record(token: "invalid", bundleIdentifier: nil, categoryID: "SOCIAL_MEDIA",
            seconds: .nan, isExplicit: false))
        XCTAssertThrowsError(try ledger.record(token: "invalid", bundleIdentifier: nil, categoryID: "SOCIAL_MEDIA",
            seconds: -1, isExplicit: false))
        XCTAssertEqual(try ledger.contributions().count, 2)
    }

    // [21] Tiny rounding differences need consistent treatment without allowing many duplicates to
    // add extra time.
    func testDuplicateRoundingToleranceDoesNotDependOnResponseOrderOrAccumulate() throws {
        for durations in [[120.0, 120.0005], [120.0005, 120.0]] {
            var ledger = ScreenTimeContributionLedger<String>()
            for seconds in durations {
                try ledger.record(token: nil, bundleIdentifier: "example.chosen", categoryID: "SOCIAL_MEDIA",
                    seconds: seconds, isExplicit: false)
            }
            XCTAssertEqual(try ledger.secondsByCategory()["SOCIAL_MEDIA"], 120.0005)
            XCTAssertThrowsError(try ledger.record(token: nil, bundleIdentifier: "example.chosen",
                categoryID: "SOCIAL_MEDIA", seconds: 120.0012, isExplicit: false))
        }
    }

    // [22] Ordinary Screen Time approval is not permission to take private activity out of Apple's
    // report view.
    func testOrdinaryApprovalCannotImportPrivateReportData() {
        let state = ScreenTimeAuthorizationDecision.state(permission: .approved,
            previouslyAuthorized: false, supportsDataAccess: true, enabled: true)
        XCTAssertEqual(state, .reportOnly)
        XCTAssertFalse(state.canImport)
    }

    // [23] Expanded access needs both a supported system and the intended build, not just a saved
    // permission label.
    func testExpandedApprovalRequiresSupportedOSAndEnabledBuild() {
        XCTAssertEqual(ScreenTimeAuthorizationDecision.state(permission: .approvedWithDataAccess,
            previouslyAuthorized: false, supportsDataAccess: true, enabled: true), .dataAccess)
        XCTAssertEqual(ScreenTimeAuthorizationDecision.state(permission: .approvedWithDataAccess,
            previouslyAuthorized: false, supportsDataAccess: false, enabled: true), .reportOnly)
        XCTAssertEqual(ScreenTimeAuthorizationDecision.state(permission: .approvedWithDataAccess,
            previouslyAuthorized: true, supportsDataAccess: true, enabled: false), .unavailable)
    }

    // [24] If another app takes the expanded access, this app needs to show the lost connection
    // honestly.
    func testAnotherAppTakingDataAccessIsShownAsRevocation() {
        XCTAssertEqual(ScreenTimeAuthorizationDecision.state(permission: .notDetermined,
            previouslyAuthorized: true, supportsDataAccess: true, enabled: true), .revoked)
        XCTAssertEqual(ScreenTimeAuthorizationDecision.state(permission: .denied,
            previouslyAuthorized: false, supportsDataAccess: true, enabled: true), .denied)
    }

    // [25] An exact selected app identity can still support matching when Apple does not return
    // its private token.
    func testSelectedBundleIdentifierCanMatchExpandedExportWithoutToken() {
        let mapping = ScreenTimeIdentityMapping.categoryID(token: Optional<String>.none,
            bundleIdentifier: "example.selected", tokenAssignments: ["selectedToken": "SOCIAL_MEDIA"],
            bundleAssignments: ["example.selected": "SOCIAL_MEDIA"])
        XCTAssertEqual(mapping, "SOCIAL_MEDIA")
    }

    // [26] A chosen app's two Apple-provided identities can be linked without guessing from its
    // name.
    func testChosenTokenResolvesItsApplicationAndBundleAlias() throws {
        var applications: [String: String] = [:]
        var bundles: [String: String] = [:]
        try ScreenTimeIdentityMapping.resolveSelectedApplication("resolved app", token: "chosen",
            bundleIdentifier: "example.selected", tokenAssignments: ["chosen": "SOCIAL_MEDIA"],
            resolvedApplications: &applications, bundleAssignments: &bundles)
        XCTAssertEqual(applications, ["resolved app": "SOCIAL_MEDIA"])
        XCTAssertEqual(ScreenTimeIdentityMapping.categoryID(token: Optional<String>.none,
            bundleIdentifier: "example.selected", tokenAssignments: ["chosen": "SOCIAL_MEDIA"],
            bundleAssignments: bundles), "SOCIAL_MEDIA")
    }

    // [27] Unchosen or missing identities must not create a new link that widens the person's
    // selection.
    func testUnselectedAndMissingTokensCannotCreateBundleAliases() throws {
        var applications: [String: String] = [:]
        var bundles = ["example.selected": "MESSAGING"]
        for token in ["unrelated", nil] {
            XCTAssertFalse(try ScreenTimeIdentityMapping.resolveSelectedApplication("unrelated app", token: token,
                bundleIdentifier: "example.selected", tokenAssignments: ["chosen": "SOCIAL_MEDIA"],
                resolvedApplications: &applications, bundleAssignments: &bundles))
        }
        XCTAssertTrue(applications.isEmpty)
        XCTAssertEqual(bundles, ["example.selected": "MESSAGING"])
    }

    // [28] One app cannot quietly belong to two calculation categories just because choices
    // conflict.
    func testSelectedAppsCannotResolveTheSameBundleIntoDifferentCategories() throws {
        var applications: [String: String] = [:]
        var bundles: [String: String] = [:]
        let choices = ["first": "MESSAGING", "second": "VIDEO_STREAMING"]
        try ScreenTimeIdentityMapping.resolveSelectedApplication("first app", token: "first",
            bundleIdentifier: "example.shared", tokenAssignments: choices,
            resolvedApplications: &applications, bundleAssignments: &bundles)
        XCTAssertThrowsError(try ScreenTimeIdentityMapping.resolveSelectedApplication("second app", token: "second",
            bundleIdentifier: "example.shared", tokenAssignments: choices,
            resolvedApplications: &applications, bundleAssignments: &bundles))
        XCTAssertEqual(bundles, ["example.shared": "MESSAGING"])
    }

    // [29] An empty app identifier should not create a wider match beyond the app that was
    // selected.
    func testEmptyBundleIdentifiersKeepOnlyTheSelectedApplicationMatch() throws {
        var applications: [String: String] = [:]
        var bundles: [String: String] = [:]
        for bundle in ["", nil] {
            try ScreenTimeIdentityMapping.resolveSelectedApplication("selected app", token: "chosen",
                bundleIdentifier: bundle, tokenAssignments: ["chosen": "SOCIAL_MEDIA"],
                resolvedApplications: &applications, bundleAssignments: &bundles)
        }
        XCTAssertEqual(applications, ["selected app": "SOCIAL_MEDIA"])
        XCTAssertTrue(bundles.isEmpty)
    }

    // [30] When reported links conflict, the importer should stop instead of picking an arbitrary
    // category.
    func testResolvedApplicationConflictsDoNotChooseAnArbitraryCategory() throws {
        var applications: [String: String] = [:]
        var bundles: [String: String] = [:]
        let choices = ["first": "MESSAGING", "second": "VIDEO_STREAMING"]
        try ScreenTimeIdentityMapping.resolveSelectedApplication("same app", token: "first",
            bundleIdentifier: nil, tokenAssignments: choices,
            resolvedApplications: &applications, bundleAssignments: &bundles)
        XCTAssertThrowsError(try ScreenTimeIdentityMapping.resolveSelectedApplication("same app", token: "second",
            bundleIdentifier: nil, tokenAssignments: choices,
            resolvedApplications: &applications, bundleAssignments: &bundles))
        XCTAssertEqual(applications, ["same app": "MESSAGING"])
        XCTAssertTrue(bundles.isEmpty)
    }

    // [31] The person's explicit selection takes priority, while unrecognized activity stays
    // unmapped.
    func testTokenAssignmentWinsOverRawIdentifierAndUnknownAppsStayUnmapped() {
        XCTAssertEqual(ScreenTimeIdentityMapping.categoryID(token: "chosen",
            bundleIdentifier: "example.selected", tokenAssignments: ["chosen": "MESSAGING"],
            bundleAssignments: ["example.selected": "SOCIAL_MEDIA"]), "MESSAGING")
        XCTAssertNil(ScreenTimeIdentityMapping.categoryID(token: Optional<String>.none,
            bundleIdentifier: "example.unselected", tokenAssignments: ["chosen": "MESSAGING"],
            bundleAssignments: ["example.selected": "SOCIAL_MEDIA"]))
    }

    // [32] A duplicate choice must be rejected so category totals do not depend on dictionary
    // order.
    func testDuplicateSelectionIsRejectedInsteadOfChoosingDictionaryOrder() throws {
        var assignments: [String: String] = [:]
        try ScreenTimeIdentityMapping.assign("app", to: "MESSAGING", in: &assignments)
        try ScreenTimeIdentityMapping.assign("app", to: "MESSAGING", in: &assignments)
        XCTAssertThrowsError(try ScreenTimeIdentityMapping.assign("app", to: "VIDEO_STREAMING", in: &assignments))
        XCTAssertEqual(assignments["app"], "MESSAGING")
    }

    // [33] An unusable older routine should not prevent an otherwise valid later import from being
    // planned.
    func testInvalidHistoricalRoutineDoesNotBlockLaterImports() {
        XCTAssertTrue(ScreenTimeImportPolicy.shouldContinue(after: FootprintError.invalidInput("Category was added later.")))
        XCTAssertTrue(ScreenTimeImportPolicy.shouldContinue(after: ScreenTimeImportError.incompleteData))
        XCTAssertTrue(ScreenTimeImportPolicy.shouldContinue(after: ScreenTimeImportError.invalidDuration))
        #if SCREEN_TIME_ENABLED
        if #available(iOS 26.4, *) {
            XCTAssertTrue(ScreenTimeImportPolicy.shouldContinue(after: DeviceActivityData.Error.missingData))
            XCTAssertFalse(ScreenTimeImportPolicy.shouldContinue(after: DeviceActivityData.Error.unauthorized))
            XCTAssertFalse(ScreenTimeImportPolicy.shouldContinue(after: DeviceActivityData.Error.unavailable))
        }
        #endif
        XCTAssertFalse(ScreenTimeImportPolicy.shouldContinue(after: ScreenTimeImportError.permissionRequired))
        XCTAssertFalse(ScreenTimeImportPolicy.shouldContinue(after: ScreenTimeImportError.conflictingSelection))
        XCTAssertFalse(ScreenTimeImportPolicy.shouldContinue(after: ScreenTimeImportError.selectionChanged))
        XCTAssertFalse(ScreenTimeImportPolicy.shouldContinue(after: FootprintError.damagedArchive))
    }

    // [34] Part of a day, or activity crossing its boundaries, cannot honestly be called a
    // completed daily input.
    func testPartialAndCrossDaySegmentsCannotBecomeCompletedDayInput() {
        let day = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 86400)
        XCTAssertTrue(ScreenTimeDayValidation.isCompleteSegment(day, for: day))
        XCTAssertFalse(ScreenTimeDayValidation.isCompleteSegment(DateInterval(start: day.start, duration: 3600), for: day))
        XCTAssertFalse(ScreenTimeDayValidation.isCompleteSegment(DateInterval(start: day.start, duration: 90000), for: day))
    }

    // [35] A specific app choice wins over a group, and website time must not be added as extra
    // app use.
    func testSpecificAppMappingOverridesCategoryWithoutCountingWebsiteResidual() throws {
        let allocation = try ScreenTimeAllocation.minutes(categorySeconds: 3600, categoryID: "SOCIAL_MEDIA",
            applications: [.init(seconds: 600, categoryID: "VIDEO_STREAMING"), .init(seconds: 1200, categoryID: nil)])
        XCTAssertEqual(allocation["VIDEO_STREAMING"], 10)
        XCTAssertEqual(allocation["SOCIAL_MEDIA"], 20)
        XCTAssertEqual(allocation.values.reduce(0, +), 30)
    }

    // [36] Overlapping app totals need the group's measured limit so the result cannot count the
    // same use twice.
    func testOverlappingApplicationsAreBoundedByCategoryTotal() throws {
        let allocation = try ScreenTimeAllocation.minutes(categorySeconds: 600, categoryID: "SOCIAL_MEDIA",
            applications: [.init(seconds: 600, categoryID: nil), .init(seconds: 600, categoryID: "VIDEO_STREAMING")])
        XCTAssertEqual(allocation["SOCIAL_MEDIA"], 5)
        XCTAssertEqual(allocation["VIDEO_STREAMING"], 5)
        XCTAssertEqual(allocation.values.reduce(0, +), 10)
    }

    // [37] An unknown selected app needs a clear Other category rather than an invented
    // description.
    func testUnknownSelectedApplicationHasExplicitOtherCategory() throws {
        let allocation = try ScreenTimeAllocation.minutes(categorySeconds: 120, categoryID: nil,
            applications: [.init(seconds: 120, categoryID: nil)])
        XCTAssertEqual(allocation["MISCELLANEOUS"], 2)
    }

    // [38] A website total without any app activity must not turn into time for an imaginary app.
    func testNoApplicationsDoesNotTurnWebsiteUseIntoAppTime() throws {
        XCTAssertTrue(try ScreenTimeAllocation.minutes(categorySeconds: 3600,
            categoryID: "SOCIAL_MEDIA", applications: []).isEmpty)
    }

    // [39] A real zero should survive, but negative or impossible durations must not reach the
    // footprint model.
    func testZeroIsKeptAndInvalidDurationsAreRejected() throws {
        XCTAssertEqual(try ScreenTimeAllocation.minutes(categorySeconds: 0, categoryID: "SOCIAL_MEDIA",
            applications: [.init(seconds: 0, categoryID: nil)])["SOCIAL_MEDIA"], 0)
        XCTAssertThrowsError(try ScreenTimeAllocation.minutes(categorySeconds: .nan, categoryID: nil, applications: []))
        XCTAssertThrowsError(try ScreenTimeAllocation.minutes(categorySeconds: 10, categoryID: nil,
            applications: [.init(seconds: -1, categoryID: nil)]))
    }

    // [40] A background request should begin at the correct local day even when the clocks change.
    func testBackgroundStartUsesLocalCalendarAcrossDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Zurich"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 12)))
        let next = try XCTUnwrap(BackgroundSchedule.nextDay(after: day, calendar: calendar))
        XCTAssertEqual(calendar.component(.day, from: next), 30)
        XCTAssertEqual(calendar.component(.hour, from: next), 0)
        XCTAssertEqual(next.timeIntervalSince(calendar.startOfDay(for: day)), 23 * 3600)
    }

    // [41] When iOS ends the time slot, work must stop and report completion only once.
    func testBackgroundExpirationCancelsAndCompletesOnce() {
        let lifetime = BackgroundTaskLifetime()
        XCTAssertFalse(lifetime.isCancelled)
        lifetime.cancel()
        XCTAssertTrue(lifetime.isCancelled)
        XCTAssertTrue(lifetime.claimCompletion())
        XCTAssertFalse(lifetime.claimCompletion())
    }

    // [42] A full date alone is not proof of zero app use. If Apple reports activity but no
    // app rows, keep the day pending instead of showing a garden based on missing time.
    func testCompleteAllAppSegmentWithActivityButNoAppRowsStaysPending() {
        let day = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 86400)
        XCTAssertThrowsError(try ScreenTimeAllActivityCoverage.requireUsableSegment(day, for: day,
            activitySeconds: 3600, applicationRowCount: 0, hasPositiveApplicationDuration: false)) { error in
            guard case ScreenTimeImportError.incompleteData = error else {
                return XCTFail("Unavailable app rows should leave the day pending")
            }
        }
    }

    // [43] Unknown or impossible source totals cannot confirm that an empty app list means zero.
    func testAllAppSegmentRejectsUnknownOrImpossibleAggregate() {
        let day = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 86400)
        for seconds in [Double.nan, .infinity, -1, 86401] {
            XCTAssertThrowsError(try ScreenTimeAllActivityCoverage.requireUsableSegment(day, for: day,
                activitySeconds: seconds, applicationRowCount: 0, hasPositiveApplicationDuration: false))
        }
    }

    // [44] A partial or neighbouring interval must not pass just because its app list is empty.
    func testAllAppCoverageStillRequiresTheWholeRequestedDay() {
        let day = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 86400)
        let partial = DateInterval(start: day.start, duration: 3600)
        XCTAssertThrowsError(try ScreenTimeAllActivityCoverage.requireUsableSegment(partial, for: day,
            activitySeconds: 0, applicationRowCount: 0, hasPositiveApplicationDuration: false))
    }

    // [45] A complete source that explicitly reports no activity can still represent a real zero.
    func testCompleteAllAppSegmentCanConfirmAvailableZeroUse() throws {
        let day = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 86400)
        try ScreenTimeAllActivityCoverage.requireUsableSegment(day, for: day,
            activitySeconds: 0, applicationRowCount: 0, hasPositiveApplicationDuration: false)
        try ScreenTimeAllActivityCoverage.requireUsableSegment(day, for: day,
            activitySeconds: 0, applicationRowCount: 1, hasPositiveApplicationDuration: false)
    }

    // [46] Screen-on totals may also include websites or system activity. Only the actual app
    // rows belong in the calculation; the remaining time must not be assigned to an app.
    func testAllAppCoverageDoesNotFillTheAggregateRemainderWithAppTime() throws {
        let day = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 86400)
        try ScreenTimeAllActivityCoverage.requireUsableSegment(day, for: day,
            activitySeconds: 600, applicationRowCount: 1, hasPositiveApplicationDuration: true)
        var ledger = ScreenTimeContributionLedger<String>()
        try ledger.record(token: "fixture-app", bundleIdentifier: "fixture.example", categoryID: "MISCELLANEOUS",
            seconds: 120, isExplicit: true)
        XCTAssertEqual(try ledger.secondsByCategory()["MISCELLANEOUS"], 120)
    }

    // [47] Three hours across familiar app types should remain three hours after local mapping.
    // These are fixed examples, not a copy of anyone's installed apps or usage.
    func testKnownAllAppRowsKeepThreeHoursAcrossMediaCategories() throws {
        let day = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 86400)
        let rows: [(String, Double)] = [
            ("net.whatsapp.WhatsApp", 1800), ("com.apple.Music", 3600), ("com.google.ios.youtube", 5400)
        ]
        try ScreenTimeAllActivityCoverage.requireUsableSegment(day, for: day,
            activitySeconds: 10800, applicationRowCount: rows.count, hasPositiveApplicationDuration: true)
        var ledger = ScreenTimeContributionLedger<String>()
        for (bundle, seconds) in rows {
            let category = AutomaticActivityClassification.category(bundleIdentifier: bundle)
            try ledger.record(token: bundle, bundleIdentifier: bundle, categoryID: category.rawValue,
                seconds: seconds, isExplicit: true)
        }
        let seconds = try ledger.secondsByCategory()
        XCTAssertEqual((seconds[FootprintCategory.messaging.rawValue] ?? -60) / 60, 30)
        XCTAssertEqual((seconds[FootprintCategory.audio.rawValue] ?? -60) / 60, 60)
        XCTAssertEqual((seconds[FootprintCategory.video.rawValue] ?? -60) / 60, 90)
        XCTAssertEqual(seconds.values.reduce(0, +) / 60, 180)
    }

    // [48] Unknown apps keep their time in Other, and two identities for the same app must not
    // double its contribution when Apple repeats the row.
    func testAllAppRowsKeepUnknownAppsAndCountDuplicateIdentitiesOnce() throws {
        var ledger = ScreenTimeContributionLedger<String>(knownBundles: ["music-token": "com.apple.Music"])
        try ledger.record(token: "music-token", bundleIdentifier: nil,
            categoryID: FootprintCategory.audio.rawValue, seconds: 3600, isExplicit: true)
        try ledger.record(token: nil, bundleIdentifier: "com.apple.Music",
            categoryID: FootprintCategory.audio.rawValue, seconds: 3600, isExplicit: true)
        let unknown = "fixture.example.unlisted"
        let category = AutomaticActivityClassification.category(bundleIdentifier: unknown)
        try ledger.record(token: "unknown-token", bundleIdentifier: unknown,
            categoryID: category.rawValue, seconds: 1800, isExplicit: true)
        let seconds = try ledger.secondsByCategory()
        XCTAssertEqual(seconds[FootprintCategory.audio.rawValue], 3600)
        XCTAssertEqual(seconds[FootprintCategory.other.rawValue], 1800)
        XCTAssertEqual(seconds.values.reduce(0, +) / 60, 90)
    }

    // [49] Empty app rows are still missing usable time when the source reports activity.
    // A zero-duration row must not turn that uncertainty into a completed zero-app day.
    func testPositiveAggregateWithOnlyZeroAppRowsStaysPending() throws {
        let day = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 86400)
        var ledger = ScreenTimeContributionLedger<String>()
        try ledger.record(token: "zero-row", bundleIdentifier: "fixture.example.zero",
            categoryID: FootprintCategory.other.rawValue, seconds: 0, isExplicit: true)
        let rows = try ledger.contributions()
        XCTAssertThrowsError(try ScreenTimeAllActivityCoverage.requireUsableSegment(day, for: day,
            activitySeconds: 600, applicationRowCount: rows.count,
            hasPositiveApplicationDuration: rows.contains { $0.seconds > 0 })) { error in
            guard case ScreenTimeImportError.incompleteData = error else {
                return XCTFail("Rows without usable app time should leave the day pending")
            }
        }
    }

    #if DEBUG
    // [50] A broad comparison locates the gap without revealing the person's exact activity.
    // Screen-on totals can include non-app activity, so these bands are not a completeness verdict.
    func testCoverageBandsExposeOnlyBroadComparisons() {
        XCTAssertEqual(ScreenTimeCoverageBand.compare(appSeconds: 0, screenOnSeconds: 600), .zero)
        XCTAssertEqual(ScreenTimeCoverageBand.compare(appSeconds: 100, screenOnSeconds: 600), .underQuarter)
        XCTAssertEqual(ScreenTimeCoverageBand.compare(appSeconds: 150, screenOnSeconds: 600), .underHalf)
        XCTAssertEqual(ScreenTimeCoverageBand.compare(appSeconds: 300, screenOnSeconds: 600), .similar)
        XCTAssertEqual(ScreenTimeCoverageBand.compare(appSeconds: 600, screenOnSeconds: 600), .similar)
        XCTAssertEqual(ScreenTimeCoverageBand.compare(appSeconds: 700, screenOnSeconds: 600), .over)
        XCTAssertEqual(ScreenTimeCoverageBand.compare(appSeconds: 10, screenOnSeconds: 0), .over)
        XCTAssertNil(ScreenTimeCoverageBand.compare(appSeconds: .nan, screenOnSeconds: 600))
        XCTAssertNil(ScreenTimeCoverageBand.compare(appSeconds: 10, screenOnSeconds: .infinity))
        XCTAssertNil(ScreenTimeCoverageBand.compare(appSeconds: -1, screenOnSeconds: 600))
    }

    // [51] The receipt must have a small, fixed set of technical fields. Exact times used in the
    // calculation, app identities and Apple's error text never belong in the saved JSON.
    func testCoverageReceiptEncodesOnlyApprovedTechnicalFields() throws {
        var audit = ScreenTimeCoverageAccumulator(day: "2026-10-30", timeZone: "Europe/Zurich",
            scope: "allAuthorizedApps", capturedAt: Date(timeIntervalSince1970: 1_700_000_000), queryId: "fixture-query")
        audit.describeFilter(currentDeviceDefault: true, defaultUser: true,
            applicationsEmpty: true, categoriesEmpty: true, webDomainsEmpty: true)
        audit.observeResponse(freshThroughDay: true, deviceCount: 1)
        audit.observeSegment(sourceDay: "2026-10-30", matchesRequestedDay: true, complete: true,
            activitySeconds: 4000)
        audit.observeApplication(seconds: 701.234)
        audit.observeApplication(seconds: 701.234)
        var minutes = Dictionary(uniqueKeysWithValues: FootprintCategory.allCases.map { ($0.rawValue, 0.0) })
        minutes[FootprintCategory.other.rawValue] = 701.234 / 60
        audit.collected(uniqueSeconds: [701.234], minutes: minutes)
        var receipt = audit.snapshot()
        receipt.savedInputsMatchReturned = true
        receipt.savedRecordDayMatchesQuery = true
        receipt.savedRecordSourceIsScreenTime = true
        receipt.savedRecordContainsAllModelCategories = true
        receipt.savedPositiveUsageHasZeroTrafficAssumption = false
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(receipt)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let allowed: Set<String> = ["query_id", "captured_at", "query_day", "query_time_zone", "activity_scope",
            "data_source", "device_filter", "user_filter", "application_filter_empty", "category_filter_empty",
            "web_domain_filter_empty", "response_count", "device_count", "segment_count", "matching_segment_count",
            "application_row_count", "positive_application_row_count", "unique_contribution_count", "source_query_day",
            "source_query_days_match_requested", "source_fresh_through_day", "matching_segments_complete",
            "raw_apps_vs_screen_on", "unique_apps_vs_screen_on", "returned_all_model_categories",
            "app_seconds_to_returned_minutes_conserved", "saved_inputs_match_returned", "saved_record_day_matches_query",
            "saved_record_source_is_screen_time", "saved_record_contains_all_model_categories",
            "saved_positive_usage_has_zero_traffic_assumption", "outcome"]
        XCTAssertEqual(Set(fields.keys), allowed)
        XCTAssertEqual(fields["raw_apps_vs_screen_on"] as? String, "underHalf")
        XCTAssertEqual(fields["unique_apps_vs_screen_on"] as? String, "underQuarter")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("701.234"))
        audit.stopped(NSError(domain: "fixture.private.app", code: 7,
            userInfo: [NSLocalizedDescriptionKey: "fixture private app and exact usage details"]))
        let stopped = try encoder.encode(audit.snapshot())
        XCTAssertEqual(audit.snapshot().outcome, "system_error")
        XCTAssertFalse(String(decoding: stopped, as: UTF8.self).contains("fixture.private.app"))
        XCTAssertFalse(String(decoding: stopped, as: UTF8.self).contains("exact usage details"))
    }

    // [52] Equal overall totals can hide a category being lost or moved. Compare every returned
    // category on the phone, then save only whether that comparison passed.
    func testCoverageConservationChecksEachSavedCategory() {
        let minutes = [FootprintCategory.video.rawValue: 2.0, FootprintCategory.audio.rawValue: 1.0]
        let saved = [CategoryUsage(category: .video, minutes: 2, gigabytesPerHour: 1, wifiShare: 0.8),
                     CategoryUsage(category: .audio, minutes: 1, gigabytesPerHour: 0, wifiShare: 0.8)]
        XCTAssertTrue(ScreenTimeCoverageConservation.savedInputsMatch(minutes, usages: saved))
        XCTAssertTrue(ScreenTimeCoverageConservation.secondsMatchMinutes(180, minutes: minutes))
        XCTAssertFalse(ScreenTimeCoverageConservation.secondsMatchMinutes(60, minutes: minutes))
        let swapped = [CategoryUsage(category: .video, minutes: 1, gigabytesPerHour: 1, wifiShare: 0.8),
                       CategoryUsage(category: .audio, minutes: 2, gigabytesPerHour: 0, wifiShare: 0.8)]
        XCTAssertFalse(ScreenTimeCoverageConservation.savedInputsMatch(minutes, usages: swapped))
        XCTAssertFalse(ScreenTimeCoverageConservation.savedInputsMatch(minutes, usages: [saved[0]]))
        XCTAssertFalse(ScreenTimeCoverageConservation.savedInputsMatch(minutes, usages: [saved[0], saved[0]]))
    }

    // [53] No response is still unknown, rather than a measured zero. A stale or partial day
    // must remain visible as an unsuccessful query in the technical note.
    func testCoverageUnknownOrStaleResponseDoesNotPretendToHaveZeroCoverage() {
        var audit = ScreenTimeCoverageAccumulator(day: "2026-10-30", timeZone: "Europe/Zurich", scope: "allAuthorizedApps")
        XCTAssertNil(audit.snapshot().rawAppsVsScreenOn)
        XCTAssertNil(audit.snapshot().uniqueAppsVsScreenOn)
        audit.observeResponse(freshThroughDay: false, deviceCount: 1)
        audit.stopped(ScreenTimeImportError.incompleteData)
        XCTAssertEqual(audit.snapshot().sourceFreshThroughDay, false)
        XCTAssertEqual(audit.snapshot().outcome, "incomplete_data")
        XCTAssertNil(audit.snapshot().rawAppsVsScreenOn)
        XCTAssertNil(audit.snapshot().appSecondsToReturnedMinutesConserved)
    }

    // [54] Replacing a query with its later save check keeps one receipt, and a short limit
    // prevents a development check from becoming an unlimited activity journal.
    func testCoverageJournalKeepsTwentyQueriesAndRoundTripsItsIdentifiers() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var journal = ScreenTimeCoverageJournal(updatedAt: now)
        for index in 0..<25 {
            let audit = ScreenTimeCoverageAccumulator(day: "2026-10-30", timeZone: "Europe/Zurich",
                scope: "allAuthorizedApps", capturedAt: now, queryId: "fixture-query-\(index)")
            journal.append(audit.snapshot())
        }
        XCTAssertEqual(journal.receipts.count, 20)
        XCTAssertEqual(journal.receipts.first?.queryId, "fixture-query-5")
        var updated = try XCTUnwrap(journal.receipts.last)
        updated.outcome = "saved"
        journal.append(updated)
        XCTAssertEqual(journal.receipts.count, 20)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let data = try encoder.encode(journal)
        let decoded = try decoder.decode(ScreenTimeCoverageJournal.self, from: data)
        XCTAssertEqual(decoded.receipts.last?.queryId, "fixture-query-24")
        XCTAssertEqual(decoded.receipts.last?.outcome, "saved")
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), ["schema_version", "debug_only", "updated_at", "receipts"])
    }

    // [55] A local day may contain twenty-three or twenty-five hours. Missing hours and
    // overlapping answers must stay visible rather than being treated as a full day.
    func testAlternativeProbeChecksClockChangeIntervalsAndDuplicates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Zurich"))
        for components in [DateComponents(year: 2026, month: 3, day: 29), DateComponents(year: 2026, month: 10, day: 25)] {
            let start = try XCTUnwrap(calendar.date(from: components))
            let end = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
            let day = DateInterval(start: start, end: end)
            var hours: [DateInterval] = []
            var cursor = start
            while cursor < end {
                let next = try XCTUnwrap(calendar.date(byAdding: .hour, value: 1, to: cursor))
                hours.append(DateInterval(start: cursor, end: min(next, end)))
                cursor = next
            }
            let full = ScreenTimeProbeIntervalCoverage.evaluate(hours, requested: day)
            XCTAssertTrue(full.coversRequestedDay)
            XCTAssertTrue(full.intervalsWithinRequestedDay)
            XCTAssertFalse(full.overlappingIntervals)
            let duplicate = ScreenTimeProbeIntervalCoverage.evaluate(hours + [try XCTUnwrap(hours.first)], requested: day)
            XCTAssertTrue(duplicate.coversRequestedDay)
            XCTAssertEqual(duplicate.duplicateIntervalCount, 1)
            XCTAssertFalse(duplicate.overlappingIntervals)
            XCTAssertFalse(ScreenTimeProbeIntervalCoverage.evaluate(Array(hours.dropFirst()), requested: day).coversRequestedDay)
            let overlap = DateInterval(start: start.addingTimeInterval(1800), duration: 3600)
            XCTAssertTrue(ScreenTimeProbeIntervalCoverage.evaluate(hours + [overlap], requested: day).overlappingIntervals)
            let extra = DateInterval(start: end, duration: 3600)
            let extraResult = ScreenTimeProbeIntervalCoverage.evaluate(hours + [extra], requested: day)
            XCTAssertFalse(extraResult.intervalsWithinRequestedDay)
            XCTAssertTrue(extraResult.coversRequestedDay)
        }
    }

    // [56] Using an app in two different hours is not a duplicate, even if both durations match.
    // Repeated representations inside one hour still count just once.
    func testAlternativeProbeKeepsDistinctHoursButDeduplicatesTheSameInterval() throws {
        let first = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 3600)
        let second = DateInterval(start: first.end, duration: 3600)
        var ledger = ScreenTimeSegmentedCoverageLedger<String>(knownBundles: ["fixture-token": "fixture.app"])
        try ledger.record(interval: first, token: "fixture-token", bundle: "fixture.app", seconds: 120)
        try ledger.record(interval: first, token: nil, bundle: "fixture.app", seconds: 120)
        try ledger.record(interval: second, token: "fixture-token", bundle: "fixture.app", seconds: 120)
        XCTAssertEqual(try ledger.durations().count, 2)
        XCTAssertEqual(try ledger.durations().reduce(0, +), 240)
    }

    // [58] Partial hours can still help compare Apple's answers. The receipt keeps
    // those observed rows without calling them a complete day or saving an estimate.
    func testAlternativeProbePreservesObservedBandWhenIntervalCoverageIsIncomplete() {
        var audit = ScreenTimeCoverageAccumulator(day: "2026-10-30", timeZone: "Europe/Zurich",
            scope: "allAuthorizedApps")
        audit.observeSegment(sourceDay: "2026-10-30", matchesRequestedDay: true,
            complete: true, activitySeconds: 600)
        audit.observeApplication(seconds: 120)
        audit.collected(uniqueSeconds: [120], minutes: [FootprintCategory.other.rawValue: 2])
        audit.stopped(ScreenTimeImportError.incompleteData)
        let receipt = audit.snapshot()
        XCTAssertEqual(receipt.outcome, "incomplete_data")
        XCTAssertEqual(receipt.uniqueContributionCount, 1)
        XCTAssertEqual(receipt.uniqueAppsVsScreenOn, .underQuarter)
        XCTAssertEqual(receipt.appSecondsToReturnedMinutesConserved, true)
    }

    // [57] The comparison report contains no duration values, app identities or raw intervals.
    // Its original-endpoint control also keeps a possible rounding effect separate from grouping.
    func testAlternativeProbeEncodesOnlyTechnicalComparisons() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var report = ScreenTimeCoverageProbeReport(capturedAt: now, queryDay: "2026-10-30", queryTimeZone: "Europe/Zurich")
        let coverage = ScreenTimeCoverageSnapshot(queryId: "fixture-query", capturedAt: now,
            queryDay: "2026-10-30", queryTimeZone: "Europe/Zurich", activityScope: "allAuthorizedApps")
        let day = DateInterval(start: now, duration: 86400)
        report.variants = ScreenTimeCoverageProbeVariant.allCases.map {
            ScreenTimeCoverageProbeVariantReport(variant: $0, coverage: coverage,
                intervalCoverage: ScreenTimeProbeIntervalCoverage.evaluate([day], requested: day))
        }
        report.dailyCachedMatchesDailyLive = true
        report.hourlyCachedMatchesHourlyLive = false
        report.hourlyLiveMatchesDailyLive = false
        report.hourlyLiveVsDailyLive = .over
        report.originalEndpointMatchesAdjustedDailyLive = true
        report.sameDeviceAcrossVariants = true
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(report)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let allowed: Set<String> = ["schema_version", "debug_only", "captured_at", "query_day", "query_time_zone",
            "cache_may_already_be_warm", "production_history_saved", "variants", "daily_cached_matches_daily_live",
            "hourly_cached_matches_hourly_live", "hourly_live_matches_daily_live", "hourly_live_vs_daily_live",
            "original_endpoint_matches_adjusted_daily_live", "same_device_across_variants", "outcome"]
        XCTAssertEqual(Set(fields.keys), allowed)
        let variants = try XCTUnwrap(fields["variants"] as? [[String: Any]])
        XCTAssertEqual(variants.count, 5)
        XCTAssertEqual(Set(try XCTUnwrap(variants.first).keys),
            ["variant", "coverage", "interval_coverage", "screen_on_reference_deduplicated_by_interval"])
        let intervalFields = try XCTUnwrap(variants[0]["interval_coverage"] as? [String: Any])
        XCTAssertEqual(Set(intervalFields.keys), ["unique_interval_count", "duplicate_interval_count",
            "intervals_within_requested_day", "covers_requested_day", "overlapping_intervals"])
        XCTAssertEqual(ScreenTimeCoverageProbeVariant.allCases.filter(\.originalEndpoint), [.dailyLiveOriginalEndpoint])
        XCTAssertTrue(ScreenTimeCoverageProbeVariant.allCases.prefix(2).allSatisfy(\.cached))
        XCTAssertFalse(report.productionHistorySaved)
    }
    #endif
}
