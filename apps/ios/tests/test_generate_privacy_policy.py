"""Policy generation checks use a temporary app tree, without a website or personal data."""
# [01] Build a small throwaway project so these checks cannot rewrite the real app or publish a page.
from pathlib import Path
import json
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CONFIG = Path('Configuration/PrivacyPolicyContent.json')
APP_POLICY = Path('iosApp/PrivacyPolicyContent.swift')


class PrivacyPolicyGenerationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name)
        # [02] Match the real checkout depth so a public-copy test stays inside this throwaway repository.
        self.make_fixture(self.repository / 'DigitalFootprintExplorer/iosApp')

    def make_fixture(self, folder):
        self.root = folder
        self.web = self.repository / 'docs'
        for relative in (Path('scripts/generate_privacy_policy.py'), CONFIG, APP_POLICY):
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, destination)
        self.script = self.root / 'scripts/generate_privacy_policy.py'
        self.policy = self.root / APP_POLICY

    # [03] Exercise the real command, including its folder choices and exit status.
    def run_generator(self, *arguments):
        return subprocess.run([sys.executable, str(self.script), *arguments],
                              cwd=self.root, capture_output=True, text=True, check=False)

    # [04] A fresh clone needs only the app configuration; generation must not create website documents by default.
    def test_default_generation_needs_no_website_and_rebuilds_the_same_app_policy(self):
        expected = self.policy.read_bytes()
        self.policy.unlink()
        result = self.run_generator()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.policy.read_bytes(), expected)
        self.assertFalse((self.root / 'docs').exists())
        self.assertFalse(self.web.exists())

    # [05] App-only checks must work when public pages are deliberately absent from this checkout.
    def test_default_check_accepts_the_app_copy_without_website_files(self):
        result = self.run_generator('--check')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / 'docs').exists())
        self.assertFalse(self.web.exists())

    # [06] Report a changed local policy without quietly replacing it during a read-only check.
    def test_stale_check_fails_without_rewriting_the_app_copy(self):
        drift = self.policy.read_bytes() + b'\n// Deliberate test drift\n'
        self.policy.write_bytes(drift)
        result = self.run_generator('--check')
        self.assertEqual(result.returncode, 1)
        self.assertIn(APP_POLICY.as_posix(), result.stderr)
        self.assertEqual(self.policy.read_bytes(), drift)
        self.assertFalse((self.root / 'docs').exists())
        self.assertFalse(self.web.exists())

    # [07] Either layout should update the same website folder, without leaving policy copies inside the app.
    def test_explicit_web_mode_checks_missing_pages_then_generates_matching_copies(self):
        for layout in ('DigitalFootprintExplorer/iosApp', 'apps/ios'):
            with self.subTest(layout=layout):
                self.make_fixture(self.repository / layout)
                shutil.rmtree(self.web, ignore_errors=True)
                missing = self.run_generator('--check', '--include-web')
                self.assertEqual(missing.returncode, 1)
                self.assertNotIn('Traceback', missing.stderr)
                for name in ('privacy-policy.html', 'privacy-policy.md', 'privacy-policy-content.json'):
                    self.assertIn('../../docs/' + name, missing.stderr)
                self.assertFalse(self.web.exists())
                self.assertFalse((self.root / 'docs').exists())
                generated = self.run_generator('--include-web')
                self.assertEqual(generated.returncode, 0, generated.stderr)
                for name in ('privacy-policy.html', 'privacy-policy.md'):
                    self.assertIn('DFE Team', (self.web / name).read_text())
                self.assertEqual(json.loads((self.web / 'privacy-policy-content.json').read_text()),
                                 json.loads((self.root / CONFIG).read_text()))
                self.assertEqual((self.web / 'privacy-policy-content.json').read_bytes(),
                                 (self.root / CONFIG).read_bytes())
                self.assertFalse((self.root / 'docs').exists())
                current = self.run_generator('--check', '--include-web')
                self.assertEqual(current.returncode, 0, current.stderr)

    # [08] A check must name every stale public copy without replacing it or touching the offline policy.
    def test_web_check_reports_each_outside_app_copy_without_rewriting_it(self):
        generated = self.run_generator('--include-web')
        self.assertEqual(generated.returncode, 0, generated.stderr)
        offline = self.policy.read_bytes()
        for name in ('privacy-policy.html', 'privacy-policy.md', 'privacy-policy-content.json'):
            with self.subTest(name=name):
                path = self.web / name
                original = path.read_bytes()
                drift = original + b'\nDeliberate public-copy drift\n'
                path.write_bytes(drift)
                try:
                    result = self.run_generator('--check', '--include-web')
                    self.assertEqual(result.returncode, 1)
                    self.assertIn('../../docs/' + name, result.stderr)
                    self.assertNotIn('Traceback', result.stderr)
                    self.assertEqual(path.read_bytes(), drift)
                    self.assertEqual(self.policy.read_bytes(), offline)
                finally:
                    path.write_bytes(original)
        current = self.run_generator('--check', '--include-web')
        self.assertEqual(current.returncode, 0, current.stderr)


if __name__ == '__main__':
    unittest.main()
