"""Release-gate regressions with synthetic bundles; no signing credentials are read."""
# [01] These checks use made-up bundles to exercise release safety rules without reading real signing credentials.
from copy import deepcopy
from datetime import datetime, timedelta
import importlib.util
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zlib

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/check-ios-release.py'
SPEC = importlib.util.spec_from_file_location('check_ios_release', SCRIPT)
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


# [02] Small local settings files let the tests build a pretend release without using anyone's app data.
def put_plist(path, value):
    path.write_bytes(plistlib.dumps(value))


class ReleaseChecksTests(unittest.TestCase):
    # [03] Create a fresh pretend app and widget for each check. Apple commands are replaced, so no real keys or profiles are used.
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.archive = self.root / 'DFE.xcarchive'
        self.app = self.archive / 'Products/Applications/DFE.app'
        self.widget = self.app / 'PlugIns/GardenWidget.appex'
        self.widget.mkdir(parents=True)
        self.info = {
            'CFBundleIdentifier': release.APP_ID, 'CFBundleShortVersionString': '1.0',
            'CFBundleVersion': '1', 'CFBundleExecutable': 'DFE',
            'DFEAppGroupIdentifier': release.GROUP_ID, 'UIDeviceFamily': [1],
            'MinimumOSVersion': '26.4', 'ITSAppUsesNonExemptEncryption': False,
            'DFEPrivacyPolicyURL': 'https://zhaw-init-softwareengineering.github.io/digital-footprint-explorer/privacy-policy.html',
            'DFESupportURL': 'https://zhaw-init-softwareengineering.github.io/digital-footprint-explorer/support-ios.html',
            'CFBundleIcons': {'CFBundlePrimaryIcon': {'CFBundleIconName': 'AppIcon'}},
        }
        self.widget_info = dict(self.info, CFBundleIdentifier=release.WIDGET_ID, CFBundleExecutable='GardenWidget')
        self.host_manifest = {
            'NSPrivacyTracking': False, 'NSPrivacyTrackingDomains': [],
            'NSPrivacyCollectedDataTypes': [],
            'NSPrivacyAccessedAPITypes': [{
                'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategoryUserDefaults',
                'NSPrivacyAccessedAPITypeReasons': ['CA92.1'],
            }],
        }
        self.widget_manifest = dict(self.host_manifest, NSPrivacyAccessedAPITypes=[])
        self.write_bundle()
        for bundle, executable in ((self.app, 'DFE'), (self.widget, 'GardenWidget')):
            (bundle / executable).write_bytes(b'synthetic release executable')
            (bundle / 'embedded.mobileprovision').write_bytes(b'synthetic profile')
        (self.app / 'Assets.car').write_bytes(b'synthetic asset catalog')
        self.app_entitlements = self.entitlements(release.APP_ID, True)
        self.widget_entitlements = self.entitlements(release.WIDGET_ID, False)
        self.signing_certificates = {
            str(self.app): b'synthetic host signing certificate',
            str(self.widget): b'synthetic widget signing certificate',
        }
        self.profiles = {
            str(self.app): self.profile(self.app_entitlements, self.signing_certificates[str(self.app)]),
            str(self.widget): self.profile(self.widget_entitlements, self.signing_certificates[str(self.widget)]),
        }
        self.signature_valid = True
        self.certificate_extraction_succeeds = True
        self.certificate_export_writes_leaf = True
        self.certificate_export_paths = []
        self.certificate_export_commands = []
        self.command_mock = patch.object(release.subprocess, 'run', side_effect=self.fake_command)
        self.command_mock.start()
        self.addCleanup(self.command_mock.stop)

    # [04] Write matching app and archive labels so each test can change just the detail it is checking.
    def write_bundle(self):
        put_plist(self.app / 'Info.plist', self.info)
        put_plist(self.widget / 'Info.plist', self.widget_info)
        put_plist(self.app / 'PrivacyInfo.xcprivacy', self.host_manifest)
        put_plist(self.widget / 'PrivacyInfo.xcprivacy', self.widget_manifest)
        put_plist(self.archive / 'Info.plist', {'ApplicationProperties': {
            key: self.info[key] for key in ('CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion')
        }})

    # [05] The pretend host may read activity; the pretend widget receives only the shared garden group.
    @staticmethod
    def entitlements(identifier, usage):
        value = {
            'application-identifier': release.TEAM_ID + '.' + identifier,
            release.TEAM_KEY: release.TEAM_ID,
            release.GROUP_KEY: [release.GROUP_ID], 'get-task-allow': False,
        }
        if usage:
            value.update({release.FAMILY_KEY: True, release.USAGE_KEY: True})
        return value

    # [06] Give the pretend release a current profile so expiry and wrong-team cases can be tested separately.
    @staticmethod
    def profile(entitlements, certificate=b'synthetic host signing certificate'):
        return {
            'TeamIdentifier': [release.TEAM_ID], 'Entitlements': deepcopy(entitlements),
            'DeveloperCertificates': [certificate],
            'ExpirationDate': datetime.now() + timedelta(days=30),
        }

    # [07] Stand in for Apple's inspection tools. Any unexpected request fails instead of reaching real signing resources.
    def fake_command(self, command, **kwargs):
        if command[:3] == ['/usr/bin/codesign', '-d', '--entitlements']:
            entitlements = self.app_entitlements if command[-1] == str(self.app) else self.widget_entitlements
            return subprocess.CompletedProcess(command, 0, plistlib.dumps(entitlements), b'')
        if command[:2] == ['/usr/bin/codesign', '-d'] and command[2].startswith('--extract-certificates'):

            # [08] Keep the prefix after =; a separate word would be read as another app path.
            self.assertEqual(len(command), 4)
            option, separator, value = command[2].partition('=')
            self.assertEqual((option, separator), ('--extract-certificates', '='))
            self.assertTrue(value)
            prefix = Path(value)
            self.certificate_export_commands.append(command)
            self.certificate_export_paths.append(prefix)
            if self.certificate_export_writes_leaf:
                prefix.with_name(prefix.name + '0').write_bytes(self.signing_certificates[command[-1]])
            return subprocess.CompletedProcess(command, 0 if self.certificate_extraction_succeeds else 1, b'', b'')
        if command[:3] == ['/usr/bin/security', 'cms', '-D']:
            bundle = str(Path(command[-1]).parent)
            return subprocess.CompletedProcess(command, 0, plistlib.dumps(self.profiles[bundle]), b'')
        if command[:2] == ['/usr/bin/codesign', '--verify']:
            return subprocess.CompletedProcess(command, 0 if self.signature_valid else 1, b'', b'')
        self.fail('Unexpected external command: ' + command[0])

    # [09] All tests use the same release entry point that checks a built app for a real review.
    def inspect(self):
        return release.inspect_bundle(self.app, archive=self.archive)

    # [10] A complete pretend candidate should pass, showing that valid settings are not rejected by accident.
    def test_expected_synthetic_store_candidate_passes_static_checks(self):
        result = self.inspect()
        self.assertTrue(result['preparation_ok'])
        self.assertTrue(result['store_static_checks_passed'])

    # [11] A build can be ready for inspection while still lacking the signing needed for the Store.
    def test_unsigned_candidate_can_pass_preparation_but_never_store_checks(self):
        self.signature_valid = False
        self.app_entitlements = {}
        self.widget_entitlements = {}
        for bundle in (self.app, self.widget):
            (bundle / 'embedded.mobileprovision').unlink()
        result = self.inspect()
        self.assertTrue(result['preparation_ok'])
        self.assertFalse(result['store_static_checks_passed'])

    # [12] A valid-looking profile cannot approve a build signed with a different certificate.
    def test_host_or_widget_signing_certificate_must_be_in_its_profile(self):
        for bundle in (self.app, self.widget):
            with self.subTest(bundle=bundle.name):
                profile = self.profiles[str(bundle)]
                original = profile['DeveloperCertificates']
                profile['DeveloperCertificates'] = [b'a different synthetic signing certificate']
                self.assertFalse(self.inspect()['store_static_checks_passed'])
                profile['DeveloperCertificates'] = original

    # [13] Missing evidence and timeouts must stop signing approval rather than silently count as success.
    def test_missing_malformed_or_unreadable_signing_certificate_fails_closed(self):
        for certificates in (None, [], 'not a certificate list', [b''], [1]):
            with self.subTest(certificates=certificates):
                profile = dict(self.profiles[str(self.app)], DeveloperCertificates=certificates)
                self.assertFalse(release.signing_certificate_matches_profile(self.app, profile))
        self.certificate_extraction_succeeds = False
        self.assertFalse(release.signing_certificate_matches_profile(self.app, self.profiles[str(self.app)]))
        self.certificate_extraction_succeeds = True
        self.certificate_export_writes_leaf = False
        self.assertFalse(release.signing_certificate_matches_profile(self.app, self.profiles[str(self.app)]))
        self.certificate_export_writes_leaf = True
        with patch.object(release.subprocess, 'run', side_effect=subprocess.TimeoutExpired('codesign', 15)):
            self.assertFalse(release.signing_certificate_matches_profile(self.app, self.profiles[str(self.app)]))

    # [14] Allow any certificate listed by Apple, but keep the app and widget identities separate.
    def test_any_authorized_leaf_is_allowed_and_host_widget_profiles_are_separate(self):
        for bundle in (self.app, self.widget):
            profile = self.profiles[str(bundle)]
            profile['DeveloperCertificates'].insert(0, b'another authorized synthetic certificate')
            self.assertTrue(release.signing_certificate_matches_profile(bundle, profile))
        self.assertFalse(release.signing_certificate_matches_profile(self.widget, self.profiles[str(self.app)]))
        self.assertTrue(self.inspect()['store_static_checks_passed'])

    # [15] Even a failed inspection must clean up its temporary public certificate files.
    def test_public_certificate_temporary_files_are_removed_on_success_and_failure(self):
        for success in (True, False):
            with self.subTest(success=success):
                self.certificate_extraction_succeeds = success
                self.assertEqual(release.signing_certificate_matches_profile(self.app, self.profiles[str(self.app)]), success)
                self.assertFalse(self.certificate_export_paths[-1].parent.exists())
                self.assertEqual(self.certificate_export_commands[-1], [
                    '/usr/bin/codesign', '-d',
                    '--extract-certificates=' + str(self.certificate_export_paths[-1]), str(self.app)])

    # [16] Customers must not receive a build with missing privacy details or unexpected tracking declarations.
    def test_missing_or_invalid_privacy_declarations_fail_preparation(self):
        examples = [{}, {'NSPrivacyTracking': False},
                    dict(self.host_manifest, NSPrivacyTracking=True),
                    dict(self.host_manifest, NSPrivacyCollectedDataTypes=[{'NSPrivacyCollectedDataType': 'NSPrivacyCollectedDataTypeOtherUsageData'}]),
                    dict(self.host_manifest, NSPrivacyAccessedAPITypes=[])]
        for manifest in examples:
            with self.subTest(manifest=manifest):
                put_plist(self.app / 'PrivacyInfo.xcprivacy', manifest)
                self.assertFalse(self.inspect()['preparation_ok'])

    # [17] A privacy reason must describe this use; copying another target's declaration is not enough.
    def test_wrong_required_reason_and_unreviewed_widget_api_fail(self):
        bad = deepcopy(self.host_manifest)
        bad['NSPrivacyAccessedAPITypes'][0]['NSPrivacyAccessedAPITypeReasons'] = ['1C8F.1']
        self.assertFalse(release.privacy_manifest_matches(bad, True))
        self.assertFalse(release.privacy_manifest_matches(self.host_manifest, False))

    # [18] Example data and test programs must not ship inside the customer app.
    def test_debug_preview_and_embedded_tests_fail_preparation(self):
        for marker in release.PREVIEW_MARKERS:
            with self.subTest(marker=marker.decode()):
                (self.app / 'DFE').write_bytes(b'executable' + marker)
                result = self.inspect()
                self.assertFalse(result['bundle_checks']['automatic_preview_absent'])
        (self.app / 'DFE').write_bytes(b'executable')
        (self.app / 'PlugIns/iosAppTests.xctest').mkdir()
        result = self.inspect()
        self.assertFalse(result['bundle_checks']['no_embedded_test_bundles'])

    # [19] The private background probe must remain outside the production app.
    def test_debug_diagnostic_in_host_fails_preparation(self):

        (self.app / 'DFE').write_bytes(b'executable DFEBackgroundDebugBridge')
        self.assertFalse(self.inspect()['preparation_ok'])

    # [20] Checking only the main app could miss an example-data path hidden in the widget.
    def test_debug_fixture_in_widget_fails_preparation(self):

        (self.widget / 'GardenWidget').write_bytes(b'executable -ui-automatic-preview')
        self.assertFalse(self.inspect()['preparation_ok'])

    # [21] Keep known leaked test names written here too, so removing them from the gate cannot hide the mistake.
    def test_every_known_debug_marker_is_rejected_in_each_executable(self):

        markers = sorted(set(release.PREVIEW_MARKERS) | {
            b'dfe.isolated-ui-screen-time', b'dfe.isolated-unit-screen-time.',
            b'scheduleForceQuitReminderTest', b'DFE Reminder Test', b'-dfe-force-quit-reminder-test',
            b'ScreenTimeCoverageDiagnostics', b'DFEScreenTimeCoverageDiagnostics',
            b'-dfe-coverage-alternatives', b'ScreenTimeCoverageProbeReport', b'alternatives-v1.json'})
        for bundle, executable in ((self.app, 'DFE'), (self.widget, 'GardenWidget')):
            for marker in markers:
                with self.subTest(bundle=bundle.name, marker=marker.decode()):
                    (bundle / executable).write_bytes(b'executable ' + marker)
                    self.assertFalse(self.inspect()['preparation_ok'])
                    (bundle / executable).write_bytes(b'synthetic release executable')

    # [22] The widget must belong to this app version and read the same approved garden group.
    def test_mismatched_bundle_version_or_shared_group_fails(self):
        for key, value in (('CFBundleVersion', '2'), ('CFBundleShortVersionString', '1.1'), ('DFEAppGroupIdentifier', 'group.other')):
            with self.subTest(key=key):
                changed = dict(self.widget_info, **{key: value})
                put_plist(self.widget / 'Info.plist', changed)
                self.assertFalse(self.inspect()['preparation_ok'])

    # [23] The package should promise only the devices and system versions this automatic path supports.
    def test_wrong_device_family_and_minimum_ios_fail(self):
        for key, value in (('UIDeviceFamily', [1, 2]), ('MinimumOSVersion', '16.0')):
            with self.subTest(key=key):
                put_plist(self.widget / 'Info.plist', dict(self.widget_info, **{key: value}))
                self.assertFalse(self.inspect()['preparation_ok'])

    # [24] A changed filename must not turn a release check into a read of unrelated local files.
    def test_executable_cannot_escape_the_bundle(self):
        outside = self.root / 'outside'
        outside.write_bytes(b'not an app executable')
        self.assertIsNone(release.executable_path(self.app, dict(self.info, CFBundleExecutable=str(outside))))
        self.assertIsNone(release.executable_path(self.app, dict(self.info, CFBundleExecutable='../outside')))

    # [25] Catch missing compiled artwork and archive labels that point to a different app.
    def test_missing_icon_or_archive_identity_fails(self):
        (self.app / 'Assets.car').unlink()
        self.assertFalse(self.inspect()['bundle_checks']['host_icon_packaged'])
        put_plist(self.archive / 'Info.plist', {'ApplicationProperties': {'CFBundleIdentifier': 'other.app'}})
        self.assertFalse(self.inspect()['bundle_checks']['archive_identity_matches'])

    # [26] Phone testing, company-only distribution and expired profiles do not qualify as Store signing.
    def test_store_profile_rejects_development_adhoc_enterprise_expired_and_wrong_team(self):
        baseline = self.profile(self.app_entitlements)
        for update in ({'ProvisionedDevices': ['synthetic-device']}, {'ProvisionedDevices': []},
                       {'ProvisionsAllDevices': True}, {'ExpirationDate': datetime.now() - timedelta(days=1)},
                       {'TeamIdentifier': ['OTHERTEAM0']}):
            with self.subTest(update=update):
                self.assertFalse(release.distribution_profile_matches(dict(baseline, **update), release.APP_ID, True))
        debug_profile = deepcopy(baseline)
        debug_profile['Entitlements']['get-task-allow'] = True
        self.assertFalse(release.distribution_profile_matches(debug_profile, release.APP_ID, True))

    # [27] Broad app rights or a missing activity right must not pass as the exact release configuration.
    def test_store_profile_requires_exact_app_group_identity_and_host_usage(self):
        for key, value in ((release.GROUP_KEY, [release.GROUP_ID, 'group.other']),
                           ('application-identifier', release.TEAM_ID + '.*'),
                           (release.TEAM_KEY, 'OTHERTEAM0'), (release.USAGE_KEY, False)):
            with self.subTest(key=key):
                profile = self.profile(self.app_entitlements)
                profile['Entitlements'][key] = value
                self.assertFalse(release.distribution_profile_matches(profile, release.APP_ID, True))

    # [28] The widget reads saved results; it should not gain the host's protected activity access or debugging rights.
    def test_widget_cannot_inherit_protected_access_or_enable_debugger(self):
        self.widget_entitlements[release.FAMILY_KEY] = True
        self.profiles[str(self.widget)] = self.profile(self.widget_entitlements)
        result = self.inspect()
        self.assertFalse(result['store_checks']['widget_has_no_screen_time_keys'])
        self.assertFalse(result['store_checks']['widget_distribution_profile'])
        self.widget_entitlements.pop(release.FAMILY_KEY)
        self.widget_entitlements['get-task-allow'] = True
        self.assertFalse(self.inspect()['store_checks']['debugger_disabled'])

    # [29] Draft links and private addresses would leave customers without useful support or privacy information.
    def test_https_urls_reject_unpublished_placeholders_and_nonpublic_addresses(self):
        invalid = ['', 'http://zhaw.ch', 'https://example.com/policy', 'https://sub.example.org/',
                   'https://127.0.0.1/', 'https://10.0.0.1/', 'https://[::1]/', 'https://host.local/',
                   'https://user:pass@zhaw.ch/', 'https://zhaw.ch:99999/', 'https://zhaw.ch/#draft',
                   'https://$(POLICY_HOST)/', 'https://zhaw.ch/with space', None]
        for value in invalid:
            with self.subTest(value=value):
                self.assertFalse(release.public_https_url(value))
        self.assertTrue(release.public_https_url('https://zhaw.ch/policy'))

    # [30] A broken settings file should produce a failed review result rather than crash the checker.
    def test_malformed_and_nondictionary_plists_are_reported_as_missing(self):
        for raw in (b'not a plist', plistlib.dumps(['unexpected']), plistlib.dumps('unexpected')):
            with self.subTest(raw_type=raw[:20]):
                (self.app / 'Info.plist').write_bytes(raw)
                self.assertFalse(self.inspect()['preparation_ok'])

    # [31] Try wrong sizes and transparency with a pretend PNG header. This checks packaging only, not image pixels.
    def test_source_marketing_icon_requires_declared_opaque_rgb_1024_png(self):
        directory = self.root / 'DigitalFootprintExplorer/iosApp/iosApp/Assets.xcassets/AppIcon.appiconset'
        directory.mkdir(parents=True)
        (directory / 'Contents.json').write_text(json.dumps({'images': [{
            'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024',
        }]}))
        def chunk(kind, payload):
            return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))
        def icon(width=1024, colour=2, transparency=False):
            header = chunk(b'IHDR', struct.pack('>IIBBBBB', width, 1024, 8, colour, 0, 0, 0))
            transparent = chunk(b'tRNS', b'\x00\x00\x00\x00\x00\x00') if transparency else b''

            (directory / 'AppIcon.png').write_bytes(b'\x89PNG\r\n\x1a\n' + header + transparent + chunk(b'IEND', b''))
        icon()
        self.assertTrue(release.source_icon_matches(self.root))
        for parameters in ({'width': 512}, {'colour': 6}, {'transparency': True}):
            with self.subTest(parameters=parameters):
                icon(**parameters)
                self.assertFalse(release.source_icon_matches(self.root))

    # [32] An automated build must not mistake local preparation for permission to distribute.
    def test_cli_exit_code_keeps_local_preparation_separate_from_store_readiness(self):
        self.signature_valid = False
        with patch('sys.argv', ['check-ios-release.py', '--archive', str(self.archive)]), patch('builtins.print'):
            self.assertEqual(release.main(), 0)
        with patch('sys.argv', ['check-ios-release.py', '--archive', str(self.archive), '--require-store']), patch('builtins.print'):
            self.assertEqual(release.main(), 2)


if __name__ == '__main__':
    unittest.main()
