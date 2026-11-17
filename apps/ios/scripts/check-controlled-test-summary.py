#!/usr/bin/env python3
"""Reject an incomplete controlled test run without printing individual test results."""

import json
import sys


# [01] Xcode can return success even when a guarded test was skipped. Count the actual outcomes too.
def check(summary):
    if not isinstance(summary, dict):
        raise ValueError('Expected a test summary object.')
    keys = ('totalTestCount', 'passedTests', 'failedTests', 'skippedTests', 'expectedFailures')
    counts = {key: summary.get(key) for key in keys}
    if any(type(value) is not int or value < 0 for value in counts.values()):
        raise ValueError('Missing or invalid test counts.')
    failures = summary.get('testFailures')
    if not isinstance(failures, list):
        raise ValueError('Missing test failure information.')
    passed = counts['passedTests']
    clean = (summary.get('result') == 'Passed' and passed > 0
             and counts['failedTests'] == 0 and counts['skippedTests'] == 0
             and counts['expectedFailures'] == 0 and counts['totalTestCount'] == passed
             and not failures)
    return clean, counts


def main():
    try:
        clean, counts = check(json.load(sys.stdin))
    except (ValueError, TypeError):
        print('The controlled test summary could not be verified. Review the result bundle.', file=sys.stderr)
        return 2
    # [02] A short count is enough for the build log; detailed names and messages stay in the result bundle.
    print(f"Controlled tests: {counts['passedTests']} passed, {counts['failedTests']} failed, "
          f"{counts['skippedTests']} skipped, {counts['expectedFailures']} expected failures.")
    if not clean:
        print('The controlled suite must finish with every selected test passing and no skips.', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
