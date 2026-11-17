#!/usr/bin/env python3
"""Choose an existing iOS simulator from simctl JSON, without changing its state."""
import argparse
import json
import re
import sys


# [01] A hardware-specific runtime can sort above an ordinary release.
# Prefer an ordinary iOS runtime for the usual checks; a requested device still takes priority.
def select_simulator(data, preferred_id=None, *, standard_iphone_only=False,
                     minimum_version=None, sdk_version=None):
    devices = data.get('devices', {})
    if not isinstance(devices, dict):
        raise ValueError('The simulator list does not contain a devices dictionary.')
    available = []
    for runtime, entries in devices.items():
        match = re.fullmatch(r'com\.apple\.CoreSimulator\.SimRuntime\.iOS-(\d+(?:-\d+)*)(?:-(.+))?', runtime)
        if match is None or not isinstance(entries, list):
            continue
        version = tuple(int(number) for number in match.group(1).split('-'))
        # [03] Patch releases share the same SDK family. CI can bound the installed runtimes it accepts.
        version_family = (version + (0,))[:2]
        if ((minimum_version is not None and version_family < minimum_version)
                or (sdk_version is not None and version_family > sdk_version)):
            continue
        for device in entries:
            if isinstance(device, dict) and device.get('isAvailable') is True and device.get('udid'):
                available.append((match.group(2) is None, version, device))
    if standard_iphone_only:
        available = [entry for entry in available if entry[0] and is_standard_iphone(entry[2])]
    if preferred_id:
        if any(device['udid'] == preferred_id for _, _, device in available):
            return preferred_id
        raise ValueError('The requested iOS simulator is missing or unavailable. No other device was selected.')
    phones = [entry for entry in available if is_iphone(entry[2])]
    if not phones:
        if standard_iphone_only:
            raise ValueError('No standard iPhone simulator matches the selected SDK and runtime requirements.')
        raise ValueError('Install an iOS iPhone simulator runtime in Xcode Settings, then try again.')
    best_runtime = max((ordinary, version) for ordinary, version, _ in phones)
    candidates = [device for ordinary, version, device in phones if (ordinary, version) == best_runtime]
    # [02] Reuse a booted phone on that runtime when possible, without booting or creating anything here.
    candidates.sort(key=lambda device: (device.get('state') != 'Booted',
                                        not device.get('name', '').startswith('iPhone'),
                                        device.get('name', ''), device['udid']))
    return candidates[0]['udid']


def is_iphone(device):
    device_type = device.get('deviceTypeIdentifier', '')
    if device_type:
        return device_type.startswith('com.apple.CoreSimulator.SimDeviceType.iPhone-')
    return 'iPhone' in device.get('name', '')


def is_standard_iphone(device):
    return (is_iphone(device) and device.get('name') != 'iPhone Duo'
            and device.get('deviceTypeIdentifier') != 'com.apple.CoreSimulator.SimDeviceType.iPhone-Duo')


def version_family(value):
    match = re.fullmatch(r'(\d+)\.(\d+)(?:\.\d+)?', value)
    if match is None:
        raise argparse.ArgumentTypeError('Expected a version such as 27.0 or 27.2.1.')
    return int(match.group(1)), int(match.group(2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preferred-id')
    parser.add_argument('--standard-iphone-only', action='store_true')
    parser.add_argument('--minimum-version', type=version_family)
    parser.add_argument('--sdk-version', type=version_family)
    args = parser.parse_args()
    try:
        print(select_simulator(json.load(sys.stdin), args.preferred_id,
                               standard_iphone_only=args.standard_iphone_only,
                               minimum_version=args.minimum_version, sdk_version=args.sdk_version))
    except (ValueError, TypeError, AttributeError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
