from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RebindingPackaging(unittest.TestCase):
    def test_both_games_use_shared_definitions(self):
        for path in ['godot/scripts/game.gd', 'godot/prototype/scripts/game.gd']:
            source = (ROOT / path).read_text(encoding='utf-8')
            self.assertIn('LabInputBindings.new()', source)
            self.assertNotIn('var mapping =', source)
        self.assertIn('LabInputRebinding.new()', (ROOT / 'godot/scripts/settings.gd').read_text(encoding='utf-8'))
        self.assertIn('InvestigationSettingsScreen.new()', (ROOT / 'godot/prototype/scripts/ui.gd').read_text(encoding='utf-8'))
        self.assertIn('extends LabInputRebinding', (ROOT / 'godot/prototype/scripts/settings_screen.gd').read_text(encoding='utf-8'))

    def test_windows_exports_and_fast_ci_include_real_checks(self):
        presets = (ROOT / 'godot/export_presets.cfg').read_text(encoding='utf-8')
        for script in ['input_bindings.gd', 'input_rebinding.gd']:
            self.assertIn('res://scripts/' + script, presets)
        builder = (ROOT / 'scripts/prototype-build.py').read_text(encoding='utf-8')
        self.assertIn("'input_review.gd'", builder)
        self.assertIn("'--prototype-input-review'", builder)
        fast = (ROOT / 'scripts/ci-godot-test.py').read_text(encoding='utf-8')
        self.assertIn("'INPUT_BINDINGS_TEST'", fast)
        self.assertIn("'INPUT_REVIEW'", fast)


if __name__ == '__main__':
    unittest.main()
