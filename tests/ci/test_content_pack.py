from pathlib import Path
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[2] / 'scripts'
sys.path.insert(0, str(SCRIPTS))
import content_pack

PROJECT = '[application]\nconfig/name="Lab"\nconfig/version="0.9.0-beta.1"\nrun/main_scene="res://prototype/bootstrap.tscn"\n'
PRESET = '[preset.0]\nname="Windows Prototype"\nexclude_filter="prototype/tests/results/*"\n\n[preset.0.options]\napplication/file_version="0.9.0.0"\napplication/product_version="0.9.0.0"\n'


def stage(root):
    root = Path(root)
    (root / 'scripts').mkdir()
    (root / 'assets/models').mkdir(parents=True)
    (root / 'project.godot').write_text(PROJECT, encoding='utf-8')
    (root / 'export_presets.cfg').write_text(PRESET, encoding='utf-8')
    (root / 'scripts/player.gd').write_text('class_name Player\nfunc speed(): return 1\n', encoding='utf-8')
    (root / 'assets/models/office.glb').write_bytes(b'glb-1')
    return root


class CompatKeyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = stage(self.directory.name)
        self.key = content_pack.compat_key(self.root, '4.7.2.stable')

    def tearDown(self):
        self.directory.cleanup()

    def test_data_only_changes_keep_the_executable_compatible(self):
        (self.root / 'scripts/player.gd').write_text('class_name Player\nfunc speed(): return 2\n', encoding='utf-8')
        (self.root / 'scripts/helper.gd').write_text('func plain(): pass\n', encoding='utf-8')
        (self.root / 'project.godot').write_text(PROJECT.replace('0.9.0-beta.1', '0.9.0-beta.7'), encoding='utf-8')
        (self.root / 'export_presets.cfg').write_text(PRESET.replace('0.9.0.0', '0.9.1.0'), encoding='utf-8')
        self.assertEqual(content_pack.compat_key(self.root, '4.7.2.stable'), self.key)

    def test_anything_the_executable_decides_at_startup_changes_the_key(self):
        changes = {
            'new global class': lambda: (self.root / 'scripts/more.gd').write_text('class_name More\n', encoding='utf-8'),
            'renamed global class': lambda: (self.root / 'scripts/player.gd').write_text('class_name Hero\n', encoding='utf-8'),
            'heavy asset': lambda: (self.root / 'assets/models/office.glb').write_bytes(b'glb-2'),
            'project setting': lambda: (self.root / 'project.godot').write_text(PROJECT + 'renderer/x=1\n', encoding='utf-8'),
            'export option': lambda: (self.root / 'export_presets.cfg').write_text(PRESET + 'texture_format/s3tc_bptc=false\n', encoding='utf-8'),
        }
        for name, change in changes.items():
            with self.subTest(name):
                change()
                self.assertNotEqual(content_pack.compat_key(self.root, '4.7.2.stable'), self.key)
                stage_again = tempfile.TemporaryDirectory()
                self.addCleanup(stage_again.cleanup)
                self.root = stage(stage_again.name)
        self.assertNotEqual(content_pack.compat_key(self.root, '4.8.0.stable'), self.key)

    def test_pack_preset_leaves_out_the_large_assets(self):
        preset = content_pack.pack_preset(PRESET)
        self.assertIn('[preset.1]', preset)
        self.assertIn('[preset.1.options]', preset)
        self.assertIn('name="' + content_pack.PACK_PRESET + '"', preset)
        for pattern in content_pack.HEAVY_EXCLUDE.split(','):
            self.assertIn(pattern, preset)
        self.assertNotIn('[preset.0]', preset)


if __name__ == '__main__':
    unittest.main()
