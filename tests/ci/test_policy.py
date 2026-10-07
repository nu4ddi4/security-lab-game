import os
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

    def test_workflow_contract_keeps_integration_fast_and_publication_explicit(self):
        ci = (ROOT / '.github/workflows/ci.yml').read_text()
        self.assertIn('branches: [beta]', ci)
        self.assertIn('branches: [main]', ci)
        self.assertIn('  test:', ci)
        self.assertNotIn('windows-latest', ci)
        self.assertIn('  workflow_call:', ci)
        for file in ['godot-prototype.yml', 'godot-prototype-release.yml']:
            workflow = (ROOT / '.github/workflows' / file).read_text()
            self.assertIn('  workflow_dispatch:', workflow)
            self.assertNotIn('  push:', workflow)
        self.assertIn("github.ref == 'refs/heads/beta'", (ROOT / '.github/workflows/godot-prototype-release.yml').read_text())


if __name__ == '__main__':
    unittest.main()
