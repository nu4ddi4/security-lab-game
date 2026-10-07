import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from ci_scope import classify, changed_paths


class PolicyTests(unittest.TestCase):
    def test_documentation_and_authoring_do_not_run_the_game(self):
        self.assertFalse(classify(['AGENTS.md', 'docs/CI.md', 'README.md', 'assets/authoring/master.blend']))
        for path in ['godot/prototype/scripts/game.gd', 'scripts/prototype-build.py', '.github/workflows/ci.yml', 'unknown-runtime/data']:
            with self.subTest(path=path): self.assertTrue(classify([path]))

    def test_new_branch_uses_merge_base(self):
        with tempfile.TemporaryDirectory() as directory:
            def git(*args):
                return subprocess.check_output(['git', '-C', directory, *args], text=True, stderr=subprocess.DEVNULL).strip()
            git('init', '-b', 'main')
            git('config', 'user.name', 'CI test')
            git('config', 'user.email', 'ci@example.invalid')
            git('commit', '--allow-empty', '-m', 'baseline')
            git('update-ref', 'refs/remotes/origin/main', git('rev-parse', 'HEAD'))
            git('checkout', '-b', 'refactor/docs')
            Path(directory, 'README.md').write_text('documentation')
            git('add', '.')
            git('commit', '-m', 'docs')
            previous = os.getcwd()
            try:
                os.chdir(directory)
                paths = changed_paths({'ref': 'refs/heads/refactor/docs', 'before': '0' * 40}, git('rev-parse', 'HEAD'))
            finally:
                os.chdir(previous)
            self.assertEqual(paths, ['README.md'])

    def test_release_requires_successful_platform_checks(self):
        ci = (ROOT / '.github/workflows/ci.yml').read_text()
        self.assertIn('branches: [main]', ci)
        self.assertNotIn('  push:', ci)
        self.assertIn('  test:', ci)
        workflow = (ROOT / '.github/workflows/godot-prototype.yml').read_text()
        self.assertIn('branches: [main, beta]', workflow)
        self.assertIn('needs: [quick, version, prototype, android]', workflow)
        self.assertIn("needs.prototype.result == 'success'", workflow)
        self.assertIn("needs.android.result == 'success'", workflow)
        self.assertIn("needs.version.outputs.append_android == 'true'", workflow)
        self.assertIn('cancel-in-progress: false', workflow)
        self.assertIn('prototype-android-review-${{ github.run_id }}-${{ github.run_attempt }}', workflow)
        self.assertEqual(workflow.count('overwrite: true'), 2)
        self.assertNotIn('  pull_request:', workflow)

        # Evaluate the actual condition, including Android-only additions to a
        # published version: no failed or skipped Android build may be uploaded.
        condition = re.search(r'\n  release:\n.*?\n    if: >-\n(.*?)\n    runs-on:', workflow, re.S).group(1)
        expression = ' '.join(condition.split()).replace('always()', 'True').replace('&&', ' and ').replace('||', ' or ')
        for branch, windows, android, quick, published, append, expected in [
            ('main', 'success', 'success', 'success', 'false', 'false', True),
            ('main', 'success', 'skipped', 'success', 'false', 'false', False),
            ('beta', 'success', 'success', 'success', 'false', 'false', True),
            ('beta', 'success', 'skipped', 'success', 'false', 'false', False),
            ('main', 'failure', 'success', 'success', 'false', 'false', False),
            ('main', 'success', 'success', 'failure', 'false', 'false', False),
            ('main', 'skipped', 'skipped', 'success', 'true', 'false', True),
            ('main', 'skipped', 'success', 'success', 'true', 'true', True),
            ('main', 'skipped', 'failure', 'success', 'true', 'true', False),
            ('main', 'skipped', 'skipped', 'success', 'true', 'true', False),
        ]:
            values = {'github.ref': 'refs/heads/' + branch, 'github.event_name': 'push',
                      'inputs.publish': False, 'needs.quick.result': quick,
                      'needs.version.result': 'success', 'needs.version.outputs.published': published,
                      'needs.version.outputs.append_android': append,
                      'needs.prototype.result': windows, 'needs.android.result': android}
            evaluated = expression
            for key, value in values.items():
                evaluated = evaluated.replace(key, repr(value))
            with self.subTest(branch=branch, windows=windows, android=android, quick=quick, published=published):
                self.assertEqual(eval(evaluated, {'__builtins__': {}}, {}), expected)


if __name__ == '__main__':
    unittest.main()
