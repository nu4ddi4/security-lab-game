import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DiagnosticsPackagingTests(unittest.TestCase):
    def test_windows_export_has_diagnostics_and_metadata(self):
        preset = (ROOT / 'godot/export_presets.cfg').read_text(encoding='utf-8')
        for name in ['scripts/diagnostics.gd', 'scripts/diagnostics_serializer.gd',
                     'tests/diagnostics_review.gd']:
            self.assertIn('res://' + name, preset)
            self.assertTrue((ROOT / 'godot' / name).is_file())
        self.assertIn('resources/*.json', preset)
        info = json.loads((ROOT / 'godot/resources/build_info.json').read_text(encoding='utf-8'))
        self.assertEqual(info['app_id'], 'security-lab-native')
        self.assertIn(info['channel'], ['stable', 'beta', 'dev'])

    def test_fast_ci_and_exported_ci_run_real_diagnostics(self):
        quick = (ROOT / 'scripts/ci-godot-test.py').read_text(encoding='utf-8')
        self.assertIn("'scripts/diagnostics_serializer.gd'", quick)
        self.assertIn("'NATIVE_DIAGNOSTICS'", quick)
        windows = (ROOT / '.github/workflows/godot-native.yml').read_text(encoding='utf-8')
        self.assertIn('SecurityLab.exe\' --headless -- --qa-diagnostics', windows)
        self.assertIn('DIAGNOSTICS_REVIEW', windows)
        build = (ROOT / 'scripts/godot-build.ps1').read_text(encoding='utf-8')
        self.assertIn('git rev-parse HEAD', build)
        self.assertIn('WriteAllBytes($nativeInfoPath, $nativeInfoOriginal)', build)


if __name__ == '__main__':
    unittest.main()
