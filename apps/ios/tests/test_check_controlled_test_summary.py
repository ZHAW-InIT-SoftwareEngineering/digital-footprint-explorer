"""Check that a successful command represents a real controlled test run."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/check-controlled-test-summary.py'
SPEC = importlib.util.spec_from_file_location('check_controlled_test_summary', SCRIPT)
summary_check = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(summary_check)


def passing_summary():
    return {'result': 'Passed', 'totalTestCount': 3, 'passedTests': 3,
            'failedTests': 0, 'skippedTests': 0, 'expectedFailures': 0, 'testFailures': []}


class ControlledSummaryTests(unittest.TestCase):
    def test_complete_passing_suite_is_accepted(self):
        clean, counts = summary_check.check(passing_summary())
        self.assertTrue(clean)
        self.assertEqual(counts['passedTests'], 3)

    def test_missing_failure_list_does_not_count_as_a_pass(self):
        summary = passing_summary()
        del summary['testFailures']
        with self.assertRaisesRegex(ValueError, 'Missing test failure information'):
            summary_check.check(summary)

    def test_skipped_result_or_test_is_rejected(self):
        for changes in ({'result': 'Skipped'}, {'skippedTests': 1, 'passedTests': 2}):
            with self.subTest(changes=changes):
                self.assertFalse(summary_check.check(passing_summary() | changes)[0])

    def test_empty_suite_is_rejected(self):
        summary = passing_summary() | {'totalTestCount': 0, 'passedTests': 0}
        self.assertFalse(summary_check.check(summary)[0])

    def test_expected_failures_and_inconsistent_totals_are_rejected(self):
        for changes in ({'expectedFailures': 1}, {'totalTestCount': 4}):
            with self.subTest(changes=changes):
                self.assertFalse(summary_check.check(passing_summary() | changes)[0])

    def test_invalid_counts_are_rejected(self):
        for bad_count in (False, -1, '3', None):
            with self.subTest(bad_count=bad_count):
                with self.assertRaisesRegex(ValueError, 'Missing or invalid test counts'):
                    summary_check.check(passing_summary() | {'passedTests': bad_count})

    def test_cli_keeps_test_details_in_the_result_bundle(self):
        summary = passing_summary() | {'testFailures': [{'testIdentifier': 'PRIVATE_TEST_DETAIL'}]}
        result = subprocess.run([sys.executable, str(SCRIPT)], input=json.dumps(summary), text=True,
                                capture_output=True, check=False)
        self.assertEqual(result.returncode, 2)
        self.assertIn('3 passed', result.stdout)
        self.assertNotIn('PRIVATE_TEST_DETAIL', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
