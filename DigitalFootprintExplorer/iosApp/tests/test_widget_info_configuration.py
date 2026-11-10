"""Keep each built route's widget declaration aligned with its actual project settings."""

from pathlib import Path
import plistlib
import re
import unittest
import xml.etree.ElementTree as ET


IOS_ROOT = Path(__file__).resolve().parents[1]
MODE_KEY = 'DFEWidgetAutomaticImportEnabled'
FEATURE_FLAG = 'DFE_WIDGET_AUTOMATIC_IMPORT'
CONFIGURATIONS = {
    'Debug': ('80FE41CA496DB01600889AD9', 'DFE00000000000000000010A'),
    'Release': ('0CC4062AC0A102913E739023', 'DFE00000000000000000010B'),
    'ScreenTimeDebug': ('DFE000000000000000000022', 'DFE00000000000000000010C'),
    'ScreenTimeRelease': ('DFE000000000000000000023', 'DFE00000000000000000010D'),
}


def settings(identifier):
    text = (IOS_ROOT / 'iosApp.xcodeproj/project.pbxproj').read_text()
    match = re.search(rf'^\t\t{identifier} /\*.*?\*/ = \{{(.*?)^\t\t\}};', text, re.M | re.S)
    if match is None:
        raise AssertionError(f'The expected target configuration is missing: {identifier}')
    return match.group(1)


def value(block, key):
    match = re.search(rf'^\s*{re.escape(key)} = ([^;]+);', block, re.M)
    if match is None:
        raise AssertionError(f'The target setting is missing: {key}')
    return match.group(1).strip().strip('"')


class WidgetInfoConfigurationTests(unittest.TestCase):
    # [01] Two copies are needed for different routes, but their other app information must stay the same.
    def test_cache_only_info_pairs_differ_only_in_the_mode_boolean(self):
        pairs = (
            ('iosApp/Info.plist', 'Configuration/AppCacheOnlyInfo.plist'),
            ('GardenWidget/Info.plist', 'Configuration/WidgetCacheOnlyInfo.plist'),
        )
        for automatic, cache_only in pairs:
            with self.subTest(path=automatic):
                active = plistlib.loads((IOS_ROOT / automatic).read_bytes())
                passive = plistlib.loads((IOS_ROOT / cache_only).read_bytes())
                self.assertIs(active.pop(MODE_KEY), True)
                self.assertIs(passive.pop(MODE_KEY), False)
                self.assertEqual(active, passive, 'Update both Info variants when ordinary app information changes.')

    # [02] Checking the files alone would miss a target accidentally pointing at the wrong variant.
    def test_actual_target_settings_match_host_widget_modes_and_rights(self):
        for name, identifiers in CONFIGURATIONS.items():
            with self.subTest(configuration=name):
                modes = []
                for identifier in identifiers:
                    block = settings(identifier)
                    self.assertEqual(value(block, 'GENERATE_INFOPLIST_FILE'), 'YES')
                    info = plistlib.loads((IOS_ROOT / value(block, 'INFOPLIST_FILE')).read_bytes())
                    mode = info[MODE_KEY]
                    self.assertIs(type(mode), bool)
                    self.assertEqual(mode, FEATURE_FLAG in block)
                    modes.append(mode)
                self.assertEqual(modes[0], modes[1], 'The app and its widget must describe the same route.')
                widget = settings(identifiers[1])
                entitlements = plistlib.loads((IOS_ROOT / value(widget, 'CODE_SIGN_ENTITLEMENTS')).read_bytes())
                for key in ('com.apple.developer.family-controls',
                            'com.apple.developer.family-controls.app-and-website-usage'):
                    self.assertEqual(entitlements.get(key, False), modes[1])

    # [03] A developer's temporary profile must not become the signing choice for everyone who clones the app.
    def test_automatic_widget_signing_stays_a_local_choice(self):
        for name in ('ScreenTimeDebug', 'ScreenTimeRelease'):
            with self.subTest(configuration=name):
                block = settings(CONFIGURATIONS[name][1])
                self.assertEqual(value(block, 'CODE_SIGN_STYLE'), '$(DFE_WIDGET_CODE_SIGN_STYLE)')
                self.assertEqual(value(block, 'PROVISIONING_PROFILE_SPECIFIER'), '$(DFE_WIDGET_PROFILE_SPECIFIER)')
                self.assertIn(value(block, 'DEVELOPMENT_TEAM'), ('$(TEAM_ID)', '${TEAM_ID}'))

    # [04] App-only flags could leave guarded tests uncompiled, while a scheme could silently omit screen tests.
    def test_screen_time_checks_share_the_feature_flag_and_include_both_test_targets(self):
        shared = (IOS_ROOT / 'Configuration/ScreenTime.xcconfig').read_text()
        match = re.search(r'^SWIFT_ACTIVE_COMPILATION_CONDITIONS\s*=\s*([^\n]+)', shared, re.M)
        self.assertIsNotNone(match)
        flags = match.group(1)
        self.assertIn('$(inherited)', flags)
        self.assertIn('SCREEN_TIME_ENABLED', flags)
        self.assertIn(FEATURE_FLAG, flags)
        for project_configuration in ('DFE000000000000000000020', 'DFE000000000000000000021'):
            self.assertEqual(value(settings(project_configuration), 'baseConfigurationReferenceRelativePath'),
                             'ScreenTime.xcconfig')
        for test_configuration in ('DFE000000000000000000024', 'DFE000000000000000000025',
                                   'DFE000000000000000000026', 'DFE000000000000000000027'):
            block = settings(test_configuration)
            override = re.search(r'^\s*SWIFT_ACTIVE_COMPILATION_CONDITIONS = ([^;]+);', block, re.M)
            if override is not None:
                self.assertIn('$(inherited)', override.group(1))
        scheme = ET.parse(IOS_ROOT / 'iosApp.xcodeproj/xcshareddata/xcschemes/iosApp-ScreenTime.xcscheme')
        action = scheme.getroot().find('TestAction')
        self.assertIsNotNone(action)
        self.assertEqual(action.attrib['buildConfiguration'], 'ScreenTimeDebug')
        testables = action.findall('Testables/TestableReference')
        names = {item.find('BuildableReference').attrib['BlueprintName'] for item in testables}
        self.assertEqual(names, {'iosAppTests', 'iosAppUITests'})
        self.assertTrue(all(item.attrib.get('skipped') == 'NO' for item in testables))

    # [05] A warm local build can hide a missing framework. Both users of Shared need the same producer first.
    def test_app_and_widget_wait_for_one_shared_framework_producer(self):
        project = (IOS_ROOT / 'iosApp.xcodeproj/project.pbxproj').read_text()
        producer_id = 'DFE000000000000000000130'
        phase_id = '30F37E60F75DDBAEADE13C7E'
        producer = settings(producer_id)
        self.assertEqual(value(producer, 'isa'), 'PBXAggregateTarget')
        self.assertIn(phase_id, producer)
        self.assertEqual(project.count(':shared:embedAndSignAppleFrameworkForXcode'), 1)
        for target_id, dependency_id in (
            ('F2331A42642BB616260C67E2', 'DFE000000000000000000136'),
            ('DFE000000000000000000108', 'DFE000000000000000000137'),
        ):
            target = settings(target_id)
            self.assertIn(dependency_id, target)
            self.assertNotIn(phase_id, target, 'Two Gradle producers could write the same framework at once.')
            self.assertTrue(value(settings(dependency_id), 'target').startswith(producer_id))
        self.assertIn('DFE000000000000000000110', settings('F2331A42642BB616260C67E2'))
        configuration_list = settings('DFE000000000000000000131')
        for identifier, name, kotlin_type in (
            ('DFE000000000000000000132', 'Debug', 'Debug'),
            ('DFE000000000000000000133', 'Release', 'Release'),
            ('DFE000000000000000000134', 'ScreenTimeDebug', 'Debug'),
            ('DFE000000000000000000135', 'ScreenTimeRelease', 'Release'),
        ):
            with self.subTest(configuration=name):
                self.assertIn(identifier, configuration_list)
                configuration = settings(identifier)
                self.assertEqual(value(configuration, 'name'), name)
                self.assertEqual(value(configuration, 'KOTLIN_FRAMEWORK_BUILD_TYPE'), kotlin_type)
                self.assertEqual(value(configuration, 'ENABLE_USER_SCRIPT_SANDBOXING'), 'NO')
                self.assertEqual(value(configuration, 'FRAMEWORKS_FOLDER_PATH'), '$(TARGET_NAME)/Frameworks')


if __name__ == '__main__':
    unittest.main()
