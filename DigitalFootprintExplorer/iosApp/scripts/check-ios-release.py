#!/usr/bin/env python3
"""Inspect a local DFE bundle. Never upload or alter signing resources."""
# [01] This tool checks a local release candidate without uploading it or changing the team's signing resources.
import argparse
from datetime import datetime, timezone
import ipaddress
import json
import plistlib
import re
import struct
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import urlsplit

APP_ID = 'ch.zhaw.digitalfootprintexplorer.ios'
WIDGET_ID = APP_ID + '.GardenWidget'
GROUP_ID = 'group.' + APP_ID
WATCH_ID = APP_ID + '.watchkitapp'
WATCH_WIDGET_ID = WATCH_ID + '.GardenWidget'
WATCH_GROUP_ID = GROUP_ID + '.watch'
WATCH_GROUP_INFO_KEY = 'DFEWatchAppGroupIdentifier'
TEAM_ID = 'PQ9M73T7N8'
FAMILY_KEY = 'com.apple.developer.family-controls'
USAGE_KEY = FAMILY_KEY + '.app-and-website-usage'
GROUP_KEY = 'com.apple.security.application-groups'
TEAM_KEY = 'com.apple.developer.team-identifier'
WIDGET_AUTOMATIC_KEY = 'DFEWidgetAutomaticImportEnabled'
SOURCE_REVISION_KEY = 'DFESourceRevision'
PREVIEW_MARKER = b'-ui-automatic-preview'

PREVIEW_MARKERS = (
    PREVIEW_MARKER, b'-ui-example-history', b'-ui-legacy-today',
    b'-ui-watch-example', b'Example preview', b'DFE_WATCH_ENV',
    b'-ui-watch-complication', b'-ui-watch-text-size', b'-ui-watch-privacy-redacted',
    b'UI test layout geometry', b'today.layoutGeometry', b'UITestAdaptiveGeometryReceipt',
    b'UITestIsolation', b'BackgroundArchiveFingerprint', b'IsolatedGardenNotificationClient',
    b'-ui-disconnect-preview', b'-ui-revoked-preview',
    b'dfe.screenTime.debug.lastScopeMutation.v1', b'dfe.screenTime.debug.lastScopeMutationAt.v1',
    b'DFEBackgroundDebugBridge', b'DFEBackgroundDiagnostics', b'DFENotificationDiagnostics',
    b'ScreenTimeCoverageDiagnostics', b'DFEScreenTimeCoverageDiagnostics',
    b'-dfe-coverage-alternatives', b'ScreenTimeCoverageProbeReport', b'alternatives-v1.json',
    b'dfe-background-probe-', b'scheduleForceQuitReminderTest', b'DFE Reminder Test', b'-dfe-force-quit-reminder-test',
    b'_simulateLaunchForTaskWithIdentifier', b'_simulateExpirationForTaskWithIdentifier',
    b'-ui-large-text', b'-ui-extra-large-text', b'Completed refreshes:',
    b'-ui-testing', b'-reset-ui-state', b'dfe-ui-testing.json', b'dfe-unit-host-',
    b'dfe.isolated-ui-screen-time', b'dfe.isolated-unit-screen-time.',
    b'ProbeRefreshIntent', b'Check widget access', b'WidgetActivityProbeDriver', b'widget-activity-probe-',
)


# [02] Unreadable settings count as missing evidence, so a broken file cannot pass a release check.
def decode_plist(data):
    try:
        result = plistlib.loads(data)
        return result if isinstance(result, dict) else {}
    except (ValueError, TypeError, OverflowError):
        return {}


# [03] A missing file should give the same failed check as an unreadable one, rather than stop the whole report.
def read_plist(path):
    try:
        return decode_plist(path.read_bytes())
    except OSError:
        return {}


# [04] Only a successful local inspection can supply evidence for the release report.
def command_output(arguments):
    result = subprocess.run(arguments, capture_output=True, check=False)
    return result.stdout if result.returncode == 0 else b''


# [05] Read the rights actually carried by the built app, since project settings alone do not prove its access.
def signed_entitlements(bundle):
    return decode_plist(command_output(
        ['/usr/bin/codesign', '-d', '--entitlements', '-', '--xml', str(bundle)]
    ))


# [06] The embedded Apple profile tells us which app and rights this particular build may use.
def read_profile(bundle):
    path = bundle / 'embedded.mobileprovision'
    if not path.is_file():
        return {}
    return decode_plist(command_output(['/usr/bin/security', 'cms', '-D', '-i', str(path)]))


# [07] Both the team and app must match; another ZHAW app must not pass just because it shares the team.
def identity_matches(entitlements, identifier):
    return bool(
        isinstance(entitlements, dict)
        and entitlements.get('application-identifier') == TEAM_ID + '.' + identifier
        and entitlements.get(TEAM_KEY) == TEAM_ID
    )


# [08] The app and widget should share only their own garden history, with no extra shared group.
def groups_match(entitlements, group=GROUP_ID):
    groups = entitlements.get(GROUP_KEY)
    return isinstance(groups, list) and groups == [group]


# [20] Reading protected activity from a widget is a separate, explicit build choice.
# Both labels must agree; a string such as "true" cannot quietly turn that access on.
def widget_automatic_mode(info, widget_info):
    host = info.get(WIDGET_AUTOMATIC_KEY, False)
    widget = widget_info.get(WIDGET_AUTOMATIC_KEY, False)
    matches = isinstance(host, bool) and isinstance(widget, bool) and host is widget
    return matches, matches and host is True


# [22] A new importer needs its own source label. Matching placeholders cannot identify the code being tested.
def source_identity_matches(info, widget_info, required):
    if not required:
        return True

    def usable(value):
        if not isinstance(value, str) or not value or value != value.strip() or len(value) > 256:
            return False
        if any(character.isspace() or ord(character) < 32 for character in value):
            return False
        lowered = value.casefold()
        placeholders = {
            'unavailable', 'unknown', 'missing', 'placeholder', 'source_revision',
            'dfe_source_revision', 'verified_source_fingerprint',
        }
        return (lowered not in placeholders and not lowered.startswith('your_')
                and '$(' not in value and '${' not in value)

    host = info.get(SOURCE_REVISION_KEY)
    widget = widget_info.get(SOURCE_REVISION_KEY)
    return usable(host) and usable(widget) and host == widget


# [21] The older widget reads only a saved garden. The new route needs both protected rights,
# but only when both targets explicitly declare that route.
def widget_protected_access_matches(entitlements, enabled):
    if enabled:
        return entitlements.get(FAMILY_KEY) is True and entitlements.get(USAGE_KEY) is True
    return FAMILY_KEY not in entitlements and USAGE_KEY not in entitlements


# [09] A Store build needs a current Store profile. A phone-testing profile is not enough, even with an empty device list.
def distribution_profile_matches(profile, identifier, needs_usage, group=GROUP_ID):
    entitlements = profile.get('Entitlements', {})
    if not isinstance(entitlements, dict):
        return False
    expiry = profile.get('ExpirationDate')
    valid_date = isinstance(expiry, datetime) and (
        expiry.replace(tzinfo=timezone.utc) if expiry.tzinfo is None else expiry
    ) > datetime.now(timezone.utc)

    is_store = 'ProvisionedDevices' not in profile and not profile.get('ProvisionsAllDevices', False)
    usage_allowed = (
        entitlements.get(FAMILY_KEY) is True and entitlements.get(USAGE_KEY) is True
    ) if needs_usage else FAMILY_KEY not in entitlements and USAGE_KEY not in entitlements
    return bool(
        is_store and valid_date and usage_allowed
        and profile.get('TeamIdentifier') == [TEAM_ID]
        and identity_matches(entitlements, identifier)
        and groups_match(entitlements, group)
        and entitlements.get('get-task-allow') is False
    )


# [10] Compare the public signing certificate with Apple's allowed list. Private keys stay untouched, and temporary copies are removed.
def signing_certificate_matches_profile(bundle, profile):
    """Compare the public signing leaf with the profile; never read a private key."""
    allowed = profile.get('DeveloperCertificates') if isinstance(profile, dict) else None
    if not isinstance(allowed, list) or not allowed or not all(
        isinstance(certificate, bytes) and certificate for certificate in allowed
    ):
        return False
    try:


        with tempfile.TemporaryDirectory(prefix='dfe-signing-certificates-') as directory:
            prefix = Path(directory) / 'signer'
            result = subprocess.run(
                ['/usr/bin/codesign', '-d', '--extract-certificates=' + str(prefix), str(bundle)],
                capture_output=True, check=False, timeout=15,
            )
            if result.returncode != 0:
                return False
            leaf = prefix.with_name(prefix.name + '0').read_bytes()
            return bool(leaf) and leaf in allowed
    except (OSError, subprocess.SubprocessError):
        return False


# [11] Reject local addresses and draft links before they can reach customers. This does not prove the page is published.
def public_https_url(value):
    if not isinstance(value, str) or not value or any(character.isspace() for character in value):
        return False
    try:
        parts = urlsplit(value)
        host = (parts.hostname or '').lower().rstrip('.')
        port = parts.port
    except ValueError:
        return False
    try:
        ipaddress.ip_address(host)
        return False
    except ValueError:
        pass
    placeholders = ('localhost', 'example.com', 'example.org', 'example.net', 'approved-host')
    return bool(
        parts.scheme == 'https' and '.' in host
        and all(host != item and not host.endswith('.' + item) for item in placeholders)
        and not host.endswith(('.invalid', '.localhost', '.test', '.local'))
        and port in (None, 443) and not parts.username and not parts.password
        and not parts.fragment and '$(' not in value and '${' not in value
    )


# [12] Declare only the APIs this target uses. The Watch uses uptime to limit its own refresh wait;
# that elapsed-time value is not part of the phone result or any transfer.
def privacy_manifest_matches(manifest, needs_defaults, *, needs_elapsed_time=False):
    if not manifest or manifest.get('NSPrivacyTracking') is not False:
        return False
    if manifest.get('NSPrivacyCollectedDataTypes') != [] or manifest.get('NSPrivacyTrackingDomains', []) != []:
        return False
    entries = manifest.get('NSPrivacyAccessedAPITypes')
    expected = {}
    if needs_defaults:
        expected['NSPrivacyAccessedAPICategoryUserDefaults'] = ['CA92.1']
    if needs_elapsed_time:
        expected['NSPrivacyAccessedAPICategorySystemBootTime'] = ['35F9.1']
    if not isinstance(entries, list) or len(entries) != len(expected):
        return False
    reviewed = set()
    for entry in entries:
        if not isinstance(entry, dict):
            return False
        category = entry.get('NSPrivacyAccessedAPIType')
        if not isinstance(category, str) or category not in expected or category in reviewed:
            return False
        if entry.get('NSPrivacyAccessedAPITypeReasons') != expected[category]:
            return False
        reviewed.add(category)
    return reviewed == expected.keys()


# [13] Check the Store artwork size, solid background and PNG structure. This check does not decode pixels or verify image checksums.
def source_icon_matches(project_root):
    assets = project_root / 'DigitalFootprintExplorer/iosApp/iosApp/Assets.xcassets/AppIcon.appiconset'
    try:
        contents = json.loads((assets / 'Contents.json').read_text())
        data = (assets / 'AppIcon.png').read_bytes()
        image = {'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}
        declared = image in contents.get('images', [])
        if data[:8] != b'\x89PNG\r\n\x1a\n':
            return False
        offset = 8
        dimensions_ok = False
        ended = False
        while offset + 12 <= len(data):
            length = struct.unpack('>I', data[offset:offset + 4])[0]
            kind = data[offset + 4:offset + 8]
            payload = data[offset + 8:offset + 8 + length]
            if len(payload) != length or offset + length + 12 > len(data):
                return False
            if kind == b'IHDR':
                if offset != 8 or length != 13:
                    return False
                width, height, depth, colour, _, _, _ = struct.unpack('>IIBBBBB', payload)
                dimensions_ok = (width, height, depth, colour) == (1024, 1024, 8, 2)
            if kind == b'tRNS':
                return False
            if kind == b'IEND':
                ended = length == 0
                break
            offset += length + 12
        return declared and dimensions_ok and ended
    except (OSError, ValueError, TypeError, AttributeError, struct.error):
        return False


# [14] An app setting must not send this check outside the app folder to read an unrelated file.
def executable_path(bundle, info):
    name = info.get('CFBundleExecutable')
    if not isinstance(name, str) or not name or Path(name).name != name or name in ('.', '..'):
        return None
    executable = bundle / name
    return executable if executable.is_file() else None


# [15] Test examples and private diagnostics belong in test builds; scan the actual program for known leftovers.
def release_preview_absent(bundle, info):
    executable = executable_path(bundle, info)
    try:
        return executable is not None and all(marker not in executable.read_bytes() for marker in PREVIEW_MARKERS)
    except OSError:
        return False


# [16] An artwork file in the project is not enough. The built app also needs its compiled icon.
def packaged_icon_matches(bundle, info):
    icons = info.get('CFBundleIcons', {})
    primary = icons.get('CFBundlePrimaryIcon', {}) if isinstance(icons, dict) else {}
    return bool(
        isinstance(primary, dict) and primary.get('CFBundleIconName') == 'AppIcon'
        and (bundle / 'Assets.car').is_file()
    )


# [23] A watch companion shows a saved phone result. It must not link the phone's activity APIs or shared calculator.
# Static library contents need a separate source/build review; this check reads only the linked library list.
def watch_framework_links_match(bundle, info):
    executable = executable_path(bundle, info)
    if executable is None:
        return False
    output = command_output(['/usr/bin/otool', '-L', str(executable)])
    if not output:
        return False
    forbidden = (b'FamilyControls.framework/', b'DeviceActivity.framework/',
                 b'ManagedSettings.framework/', b'Shared.framework/')
    return not any(item in output for item in forbidden)


# [24] Every embedded program is checked separately; a local unsigned build cannot count as tested Store signing.
def bundle_signature_valid(bundle, *, deep=False):
    arguments = ['/usr/bin/codesign', '--verify', '--strict']
    if deep:
        arguments.append('--deep')
    return subprocess.run(arguments + [str(bundle)], capture_output=True, check=False).returncode == 0


# [25] These keys describe a dependent watch app, not an independent source of Screen Time activity.
def watch_companion_metadata_matches(info, watch_info, watch_widget_info):
    extension = watch_widget_info.get('NSExtension', {})
    return bool(
        watch_info.get('WKApplication') is True
        and watch_info.get('WKCompanionAppBundleIdentifier') == info.get('CFBundleIdentifier') == APP_ID
        and watch_info.get('WKRunsIndependentlyOfCompanionApp') is False
        and watch_info.get('WKWatchOnly', False) is False
        and watch_info.get('CFBundlePackageType') == 'APPL'
        and watch_widget_info.get('CFBundlePackageType') == 'XPC!'
        and watch_info.get('CFBundleSupportedPlatforms') == watch_widget_info.get('CFBundleSupportedPlatforms') == ['WatchOS']
        and watch_info.get('UIDeviceFamily') == watch_widget_info.get('UIDeviceFamily') == [4]
        and watch_info.get('MinimumOSVersion') == watch_widget_info.get('MinimumOSVersion') == '10.0'
        and watch_info.get(WATCH_GROUP_INFO_KEY) == watch_widget_info.get(WATCH_GROUP_INFO_KEY) == WATCH_GROUP_ID
        and isinstance(extension, dict)
        and extension.get('NSExtensionPointIdentifier') == 'com.apple.widgetkit-extension'
        and watch_info.get(WIDGET_AUTOMATIC_KEY, False) is False
        and watch_widget_info.get(WIDGET_AUTOMATIC_KEY, False) is False
    )


# [17] The archive label and the app inside it must describe the same version, or a reviewer could receive the wrong build.
def archive_identity_matches(archive_info, info):
    properties = archive_info.get('ApplicationProperties', {})
    return isinstance(properties, dict) and all(
        properties.get(key) == info.get(key) and info.get(key)
        for key in ('CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion')
    )


# [18] Keep build preparation separate from Store signing. Passing these local checks is not Apple approval or proof of real-device behaviour.
def inspect_bundle(app, *, version='1.0', archive=None, project_root=None):
    widgets = list((app / 'PlugIns').glob('*.appex'))
    if len(widgets) != 1:
        return {'preparation_ok': False, 'error': 'Expected one embedded widget.'}
    widget = widgets[0]
    watches = list((app / 'Watch').glob('*.app'))
    if len(watches) != 1:
        return {'preparation_ok': False, 'error': 'Expected one embedded watch companion.'}
    watch = watches[0]
    watch_widgets = list((watch / 'PlugIns').glob('*.appex'))
    if len(watch_widgets) != 1:
        return {'preparation_ok': False, 'error': 'Expected one widget inside the watch companion.'}
    watch_widget = watch_widgets[0]
    info = read_plist(app / 'Info.plist')
    widget_info = read_plist(widget / 'Info.plist')
    watch_info = read_plist(watch / 'Info.plist')
    watch_widget_info = read_plist(watch_widget / 'Info.plist')
    automatic_mode_matches, widget_automatic_enabled = widget_automatic_mode(info, widget_info)
    build = info.get('CFBundleVersion', '')
    common = {
        'host_identifier': info.get('CFBundleIdentifier') == APP_ID,
        'widget_identifier': widget_info.get('CFBundleIdentifier') == WIDGET_ID,
        'widget_automatic_import_configuration_matches': automatic_mode_matches,
        'source_identity_matches': source_identity_matches(info, widget_info, widget_automatic_enabled),
        'version_matches': info.get('CFBundleShortVersionString') == widget_info.get('CFBundleShortVersionString') == version,
        'build_matches': bool(re.fullmatch(r'[1-9]\d*(\.\d+){0,2}', str(build))) and build == widget_info.get('CFBundleVersion'),
        'host_privacy_manifest': privacy_manifest_matches(read_plist(app / 'PrivacyInfo.xcprivacy'), True),
        'widget_privacy_manifest': privacy_manifest_matches(read_plist(widget / 'PrivacyInfo.xcprivacy'), False),
        'shared_group_configuration': info.get('DFEAppGroupIdentifier') == widget_info.get('DFEAppGroupIdentifier') == GROUP_ID,
        'iphone_targets': info.get('UIDeviceFamily') == widget_info.get('UIDeviceFamily') == [1],
        'minimum_ios_matches': info.get('MinimumOSVersion') == widget_info.get('MinimumOSVersion') == '26.4',
        'host_executable_present': executable_path(app, info) is not None,
        'widget_executable_present': executable_path(widget, widget_info) is not None,
        'host_icon_packaged': packaged_icon_matches(app, info),
        'automatic_preview_absent': release_preview_absent(app, info),
        'widget_automatic_preview_absent': release_preview_absent(widget, widget_info),
        'no_embedded_test_bundles': not any(app.rglob('*.xctest')),
        'encryption_declaration': info.get('ITSAppUsesNonExemptEncryption') is False,
        'watch_identifiers': watch_info.get('CFBundleIdentifier') == WATCH_ID
            and watch_widget_info.get('CFBundleIdentifier') == WATCH_WIDGET_ID,
        'watch_companion_metadata': watch_companion_metadata_matches(info, watch_info, watch_widget_info),
        'watch_version_matches': watch_info.get('CFBundleShortVersionString')
            == watch_widget_info.get('CFBundleShortVersionString') == info.get('CFBundleShortVersionString'),
        'watch_build_matches': watch_info.get('CFBundleVersion') == watch_widget_info.get('CFBundleVersion') == build,
        'watch_source_matches': source_identity_matches(info, watch_info, True)
            and source_identity_matches(info, watch_widget_info, True),
        'watch_executables_present': executable_path(watch, watch_info) is not None
            and executable_path(watch_widget, watch_widget_info) is not None,
        'watch_privacy_manifests': privacy_manifest_matches(read_plist(watch / 'PrivacyInfo.xcprivacy'), False, needs_elapsed_time=True)
            and privacy_manifest_matches(read_plist(watch_widget / 'PrivacyInfo.xcprivacy'), False),
        'watch_assets_packaged': packaged_icon_matches(watch, watch_info)
            and (watch_widget / 'Assets.car').is_file(),
        'watch_preview_absent': release_preview_absent(watch, watch_info)
            and release_preview_absent(watch_widget, watch_widget_info),
        'watch_framework_links_reviewed': watch_framework_links_match(watch, watch_info)
            and watch_framework_links_match(watch_widget, watch_widget_info),
        'watch_payload_not_packaged': not any(app.rglob('phone-garden-companion-v1.json')),
    }
    if archive is not None:
        common['archive_identity_matches'] = archive_identity_matches(read_plist(archive / 'Info.plist'), info)
    if project_root is not None:
        common['source_marketing_icon'] = source_icon_matches(project_root)
    app_entitlements = signed_entitlements(app)
    widget_entitlements = signed_entitlements(widget)
    app_profile = read_profile(app)
    widget_profile = read_profile(widget)
    watch_entitlements = signed_entitlements(watch)
    watch_widget_entitlements = signed_entitlements(watch_widget)
    watch_profile = read_profile(watch)
    watch_widget_profile = read_profile(watch_widget)
    store = {
        'bundle_signature_valid': bundle_signature_valid(app, deep=True),
        'privacy_url_configured': public_https_url(info.get('DFEPrivacyPolicyURL')),
        'support_url_configured': public_https_url(info.get('DFESupportURL')),
        'host_protected_entitlements': app_entitlements.get(FAMILY_KEY) is True and app_entitlements.get(USAGE_KEY) is True,
        'signed_host_group': groups_match(app_entitlements),
        'signed_widget_group': groups_match(widget_entitlements),
        'signed_host_identity': identity_matches(app_entitlements, APP_ID),
        'signed_widget_identity': identity_matches(widget_entitlements, WIDGET_ID),
        'debugger_disabled': app_entitlements.get('get-task-allow') is False and widget_entitlements.get('get-task-allow') is False,
        'widget_protected_access_matches_mode': widget_protected_access_matches(widget_entitlements, widget_automatic_enabled),
        'host_distribution_profile': distribution_profile_matches(app_profile, APP_ID, True),
        'host_certificate_matches_profile': signing_certificate_matches_profile(app, app_profile),
        'widget_distribution_profile': distribution_profile_matches(widget_profile, WIDGET_ID, widget_automatic_enabled),
        'widget_certificate_matches_profile': signing_certificate_matches_profile(widget, widget_profile),
        'watch_signatures_valid': bundle_signature_valid(watch) and bundle_signature_valid(watch_widget),
        'watch_signed_identity': identity_matches(watch_entitlements, WATCH_ID)
            and identity_matches(watch_widget_entitlements, WATCH_WIDGET_ID),
        'watch_signed_local_group': groups_match(watch_entitlements, WATCH_GROUP_ID)
            and groups_match(watch_widget_entitlements, WATCH_GROUP_ID),
        'watch_has_no_screen_time_keys': widget_protected_access_matches(watch_entitlements, False)
            and widget_protected_access_matches(watch_widget_entitlements, False),
        'watch_debugger_disabled': watch_entitlements.get('get-task-allow') is False
            and watch_widget_entitlements.get('get-task-allow') is False,
        'watch_distribution_profile': distribution_profile_matches(watch_profile, WATCH_ID, False, WATCH_GROUP_ID),
        'watch_widget_distribution_profile': distribution_profile_matches(watch_widget_profile, WATCH_WIDGET_ID, False, WATCH_GROUP_ID),
        'watch_certificate_matches_profile': signing_certificate_matches_profile(watch, watch_profile),
        'watch_widget_certificate_matches_profile': signing_certificate_matches_profile(watch_widget, watch_widget_profile),
    }
    if not widget_automatic_enabled:
        store['widget_has_no_screen_time_keys'] = widget_protected_access_matches(widget_entitlements, False)
    preparation_ok = all(common.values())
    return {
        'version': info.get('CFBundleShortVersionString'), 'build': build,
        'widget_automatic_import_enabled': widget_automatic_enabled,
        'source_revision': info.get(SOURCE_REVISION_KEY),
        'inspection_scope': 'archive' if archive is not None else 'local bundle',
        'preparation_ok': preparation_ok,
        'store_static_checks_passed': preparation_ok and all(store.values()),
        'bundle_checks': common, 'store_checks': store,
        'limitations': [
            'Does not confirm URL availability or organization approval.',
            'Does not confirm upload history, device tests, App Review approval or store metadata.',
            'Checks expected privacy declarations, not whether every SDK uses data as declared.',
            'Checks profile contents and the public signing-leaf match, not Apple approval or certificate trust/revocation.',
            'Checks the known DEBUG fixture, isolation and diagnostic markers in all four executables, not all possible debug code.',
            'Does not replace Xcode Organizer validation.',
            'Checks matching configured source labels for the automatic widget, not the underlying source fingerprint.',
            'Checks watch companion packaging and local signing evidence, not paired-device delivery or widget refresh timing.',
            'Checks linked watch framework names, not every library statically linked into its executable.',
            'Does not execute or validate live companion payloads; the payload codec and storage need their own tests.',
        ],
    }


# [19] Inspect one local app or archive and return a clear pass or failure for the selected review scope.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--bundle', type=Path)
    source.add_argument('--archive', type=Path)
    parser.add_argument('--version', default='1.0')
    parser.add_argument('--project-root', type=Path, help='Optionally inspect the source marketing icon in this repository.')
    parser.add_argument('--require-store', action='store_true')
    args = parser.parse_args()
    bundles = list((args.archive / 'Products' / 'Applications').glob('*.app')) if args.archive else [args.bundle]
    if len(bundles) != 1 or not bundles[0].is_dir():
        report = {'preparation_ok': False, 'error': 'Expected one local application bundle.'}
    else:
        report = inspect_bundle(bundles[0], version=args.version, archive=args.archive, project_root=args.project_root)
    print(json.dumps(report, indent=2))
    passed = report.get('store_static_checks_passed', False) if args.require_store else report['preparation_ok']
    return 0 if passed else 2


if __name__ == '__main__':
    raise SystemExit(main())
