#!/usr/bin/env python3
"""Choose an existing iOS simulator from simctl JSON, without changing its state."""
import argparse
import json
import re
import sys


# [01] A hardware-specific runtime can sort above an ordinary release.
# Prefer an ordinary iOS runtime for the usual checks; a requested device still takes priority.
def select_simulator(data, preferred_id=None):
    devices = data.get('devices', {})
    if not isinstance(devices, dict):
        raise ValueError('The simulator list does not contain a devices dictionary.')
    available = []
    for runtime, entries in devices.items():
        match = re.fullmatch(r'com\.apple\.CoreSimulator\.SimRuntime\.iOS-(\d+(?:-\d+)*)(?:-(.+))?', runtime)
        if match is None or not isinstance(entries, list):
            continue
        version = tuple(int(number) for number in match.group(1).split('-'))
        for device in entries:
            if isinstance(device, dict) and device.get('isAvailable') is True and device.get('udid'):
                available.append((match.group(2) is None, version, device))
    if preferred_id:
        if any(device['udid'] == preferred_id for _, _, device in available):
            return preferred_id
        raise ValueError('The requested iOS simulator is missing or unavailable. No other device was selected.')
    phones = [entry for entry in available if 'iPhone' in entry[2].get('name', '')]
    if not phones:
        raise ValueError('Install an iOS iPhone simulator runtime in Xcode Settings, then try again.')
    best_runtime = max((ordinary, version) for ordinary, version, _ in phones)
    candidates = [device for ordinary, version, device in phones if (ordinary, version) == best_runtime]
    # [02] Reuse a booted phone on that runtime when possible, without booting or creating anything here.
    candidates.sort(key=lambda device: (device.get('state') != 'Booted', device.get('name', ''), device['udid']))
    return candidates[0]['udid']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preferred-id')
    args = parser.parse_args()
    try:
        print(select_simulator(json.load(sys.stdin), args.preferred_id))
    except (ValueError, TypeError, AttributeError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
