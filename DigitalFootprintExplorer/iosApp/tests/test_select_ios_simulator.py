"""Selection uses fixture inventories only; these tests never boot or change a simulator."""
from copy import deepcopy
import importlib.util
from pathlib import Path
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/select-ios-simulator.py'
SPEC = importlib.util.spec_from_file_location('select_ios_simulator', SCRIPT)
selector = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(selector)
PREFIX = 'com.apple.CoreSimulator.SimRuntime.'


def phone(identifier, name='iPhone 18 Pro', state='Shutdown', available=True):
    return {'udid': identifier, 'name': name, 'state': state, 'isAvailable': available}


class SimulatorSelectionTests(unittest.TestCase):
    # [01] A new special-device runtime must not quietly replace the ordinary test destination.
    def test_ordinary_runtime_wins_over_higher_sorting_booted_duo_variant(self):
        data = {'devices': {
            PREFIX + 'iOS-27-2-iPhone19-4': [phone('duo', 'iPhone Duo', 'Booted')],
            PREFIX + 'iOS-27-2': [phone('ordinary')],
        }}
        original = deepcopy(data)
        self.assertEqual(selector.select_simulator(data), 'ordinary')
        self.assertEqual(data, original)

    def test_versions_are_compared_as_numbers_and_latest_ordinary_is_selected(self):
        data = {'devices': {
            PREFIX + 'iOS-9-3': [phone('old')],
            PREFIX + 'iOS-27-1': [phone('older-booted', state='Booted')],
            PREFIX + 'iOS-27-2': [phone('current')],
        }}
        self.assertEqual(selector.select_simulator(data), 'current')

    def test_booted_phone_is_preferred_within_the_selected_runtime(self):
        data = {'devices': {PREFIX + 'iOS-27-2': [phone('shutdown'), phone('booted', state='Booted')]}}
        self.assertEqual(selector.select_simulator(data), 'booted')

    # [02] An explicit Duo or iPad destination is a deliberate choice, not a reason to fall back to a phone.
    def test_explicit_preset_is_respected_without_changing_the_inventory(self):
        data = {'devices': {
            PREFIX + 'iOS-27-2': [phone('ordinary'), phone('pad', 'iPad Pro')],
            PREFIX + 'iOS-27-2-iPhone19-4': [phone('duo', 'iPhone Duo')],
        }}
        original = deepcopy(data)
        for requested in ('duo', 'pad'):
            self.assertEqual(selector.select_simulator(data, requested), requested)
        self.assertEqual(data, original)

    def test_variant_is_used_only_when_no_ordinary_phone_is_available(self):
        data = {'devices': {
            PREFIX + 'iOS-27-2': [phone('unavailable', available=False)],
            PREFIX + 'iOS-27-2-iPhone19-4': [phone('duo', 'iPhone Duo')],
        }}
        self.assertEqual(selector.select_simulator(data), 'duo')

    def test_missing_or_unavailable_explicit_device_does_not_select_another_one(self):
        data = {'devices': {PREFIX + 'iOS-27-2': [phone('ordinary'), phone('offline', available=False)]}}
        for requested in ('missing', 'offline'):
            with self.assertRaises(ValueError):
                selector.select_simulator(data, requested)

    def test_watch_devices_and_malformed_runtime_labels_are_not_phone_fallbacks(self):
        data = {'devices': {
            PREFIX + 'watchOS-27-2': [phone('watch', 'Apple Watch')],
            PREFIX + 'iOS-not-a-version': [phone('bad')],
            PREFIX + 'iOS-27-2': [phone('pad', 'iPad Pro')],
        }}
        with self.assertRaises(ValueError):
            selector.select_simulator(data)


    def test_controlled_destination_falls_back_to_compatible_phone(self):
        data = {'devices': {
            PREFIX + 'iOS-26-4': [phone('old')],
            PREFIX + 'iOS-27-0': [phone('supported', 'iPhone 17')],
            PREFIX + 'iOS-27-1-iPhone19-4': [phone('duo', 'iPhone Duo')],
            PREFIX + 'iOS-27-2': [phone('ahead')],
        }}
        self.assertEqual(selector.select_simulator(data, standard_iphone_only=True,
                                                   minimum_version=(27, 0), sdk_version=(27, 1)), 'supported')

    def test_controlled_destination_accepts_a_patch_runtime_and_renamed_phone(self):
        renamed = phone('renamed', 'Local test device')
        renamed['deviceTypeIdentifier'] = 'com.apple.CoreSimulator.SimDeviceType.iPhone-17'
        data = {'devices': {PREFIX + 'iOS-27-2-1': [renamed]}}
        self.assertEqual(selector.select_simulator(data, standard_iphone_only=True,
                                                   minimum_version=(27, 0), sdk_version=(27, 2)), 'renamed')

    def test_controlled_destination_rejects_older_and_special_device_runtimes(self):
        data = {'devices': {
            PREFIX + 'iOS-26-4': [phone('old')],
            PREFIX + 'iOS-27-1-iPhone19-4': [phone('special')],
            PREFIX + 'iOS-27-1': [phone('duo', 'iPhone Duo')],
        }}
        with self.assertRaisesRegex(ValueError, 'No standard iPhone simulator'):
            selector.select_simulator(data, standard_iphone_only=True,
                                      minimum_version=(27, 0), sdk_version=(27, 1))


if __name__ == '__main__':
    unittest.main()
