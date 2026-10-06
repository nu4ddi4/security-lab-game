import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from ci_scope import classify, select, gate, changed_paths
from ci_release import validate_run, validate_artifact, should_publish
from ci_branch_cleanup import candidate, delete_with_lease


class ScopeTests(unittest.TestCase):
    def test_documentation_does_not_build_games(self):
        self.assertEqual(classify(['AGENTS.md', 'docs/CI.md', 'README.md'], True), {'web':False, 'godot':False})

    def test_each_runtime_and_shared_assets(self):
        self.assertEqual(classify(['godot/prototype/content/rules.json'], True), {'web':False, 'godot':True})
        self.assertEqual(classify(['.github/workflows/godot-prototype.yml'], True), {'web':False, 'godot':True})
        self.assertEqual(classify(['src/app.js'], True), {'web':True, 'godot':False})
        self.assertEqual(classify(['assets/models/security_lab.glb'], True), {'web':True, 'godot':True})
        self.assertEqual(classify(['godot/project.godot'], False), {'web':False, 'godot':False})
        self.assertEqual(classify(['assets/authoring/source.blend'], True), {'web':False, 'godot':False})

    def test_development_push_is_fast_but_pr_and_main_package(self):
        push = {'ref':'refs/heads/codex/example', 'repository':{'default_branch':'main'}}
        self.assertFalse(select(['src/app.js'], push, True)['windows_web'])
        self.assertTrue(select(['src/app.js'], {'pull_request':{'draft':False}}, True)['windows_web'])
        self.assertFalse(select(['src/app.js'], {'pull_request':{'draft':True}}, True)['windows_web'])
        self.assertTrue(select(['src/app.js'], {'ref':'refs/heads/main'}, True)['windows_web'])

    def test_unknown_paths_require_validation(self):
        self.assertEqual(classify(['new-runtime/game.dat'], True), {'web':True, 'godot':True})

    def test_release_note_recovery_is_only_on_main(self):
        self.assertFalse(classify(['docs/RELEASE.md'], main_push=False)['web'])
        self.assertTrue(classify(['docs/RELEASE.md'], main_push=True)['web'])

    def test_required_check_accepts_docs_and_rejects_failed_or_skipped_checks(self):
        needs = {'scope':{'result':'success', 'outputs':{key:'false' for key in ['web','godot','windows_web','windows_godot']}}}
        needs.update({key:{'result':'skipped'} for key in ['web','godot','windows_web','windows_godot']})
        gate(needs)
        needs['scope']['outputs']['godot'] = 'true'
        for result in ['skipped','failure','cancelled',None]:
            needs['godot']['result'] = result
            with self.subTest(result=result), self.assertRaises(ValueError): gate(needs)
        needs['godot']['result'] = 'success'
        gate(needs)
        needs['scope']['result'] = 'failure'
        with self.assertRaises(ValueError): gate(needs)

    def test_new_documentation_branch_uses_main_merge_base(self):
        with tempfile.TemporaryDirectory() as directory:
            git = lambda *args: subprocess.check_output(['git', '-C', directory, *args], text=True, stderr=subprocess.DEVNULL).strip()
            git('init', '-b', 'main')
            git('config', 'user.name', 'CI test')
            git('config', 'user.email', 'ci@example.invalid')
            Path(directory, 'runtime.bin').write_text('runtime')
            git('add', '.')
            git('commit', '-m', 'baseline')
            git('update-ref', 'refs/remotes/origin/main', git('rev-parse', 'HEAD'))
            git('checkout', '-b', 'codex/docs')
            Path(directory, 'README.md').write_text('documentation')
            git('add', '.')
            git('commit', '-m', 'docs')
            previous = os.getcwd()
            try:
                os.chdir(directory)
                paths = changed_paths({'ref':'refs/heads/codex/docs','before':'0'*40}, git('rev-parse', 'HEAD'))
            finally:
                os.chdir(previous)
            self.assertEqual(paths, ['README.md'])


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.repo = 'owner/game'
        self.sha = 'a' * 40
        self.run = {'status':'completed','conclusion':'success','head_branch':'main','head_repository':{'full_name':self.repo},'event':'push','path':'.github/workflows/ci.yml','head_sha':self.sha}
        self.jobs = [{'name':name,'conclusion':'success'} for name in ['test','windows_web / package']]
        self.artifact = {'name':'SecurityLab-Windows-X64','expired':False,'size_in_bytes':42,'workflow_run':{'head_sha':self.sha}}

    def test_verified_main_artifact_can_be_reused(self):
        self.assertEqual(validate_run(self.run, self.repo), self.sha)
        self.assertEqual(validate_artifact(self.run, self.jobs, [self.artifact]), self.artifact)

    def test_forks_pr_runs_failed_runs_and_different_commits_are_rejected(self):
        for field, value in [('head_branch','feature'),('head_repository',{'full_name':'fork/game'}),('event','pull_request'),('conclusion','failure'),('status','in_progress'),('path','.github/workflows/other.yml')]:
            run = dict(self.run, **{field:value})
            with self.subTest(field=field), self.assertRaises(ValueError): validate_run(run, self.repo)
        with self.assertRaises(ValueError): validate_run(self.run, self.repo, 'b'*40)

    def test_skipped_windows_build_is_not_release_ready(self):
        jobs = copy.deepcopy(self.jobs)
        jobs[1]['conclusion'] = 'skipped'
        with self.assertRaises(ValueError): validate_artifact(self.run, jobs, [self.artifact])

    def test_expired_empty_duplicate_and_wrong_sha_artifacts_are_rejected(self):
        for field, value in [('expired',True),('size_in_bytes',0),('workflow_run',{'head_sha':'b'*40})]:
            artifact = dict(self.artifact, **{field:value})
            with self.subTest(field=field), self.assertRaises(ValueError): validate_artifact(self.run, self.jobs, [artifact])
        for artifacts in [[], [self.artifact,self.artifact]]:
            with self.assertRaises(ValueError): validate_artifact(self.run, self.jobs, artifacts)

    def test_manual_package_run_is_supported(self):
        run = dict(self.run, path='.github/workflows/package.yml', event='workflow_dispatch')
        self.assertEqual(validate_run(run, self.repo, self.sha), self.sha)
        validate_artifact(run, [{'name':'package','conclusion':'success'}], [self.artifact])

    def test_old_run_cannot_replace_a_newer_release(self):
        self.assertFalse(should_publish('0.6.2',None,{'tag_name':'v0.7.0'}))
        self.assertFalse(should_publish('0.7.0',{'tag_name':'v0.7.0'},None))
        self.assertTrue(should_publish('0.10.0',None,{'tag_name':'v0.9.0'}))
        self.assertTrue(should_publish('0.1.0',None,None))


class CleanupTests(unittest.TestCase):
    def test_only_unprotected_codex_feature_branches_are_candidates(self):
        for name in ['main','godot-port','work']:
            self.assertFalse(candidate({'name':name}))
        self.assertFalse(candidate({'name':'codex/protected','protected':True}))
        self.assertTrue(candidate({'name':'codex/merged','protected':False}))

    def test_lease_preserves_concurrently_updated_branch(self):
        with tempfile.TemporaryDirectory() as directory:
            bare, local = Path(directory, 'origin.git'), Path(directory, 'local')
            subprocess.run(['git','init','--bare',str(bare)], check=True, capture_output=True)
            subprocess.run(['git','clone',str(bare),str(local)], check=True, capture_output=True)
            def git(*args):
                return subprocess.check_output(['git',*args], cwd=local, text=True, stderr=subprocess.DEVNULL).strip()
            git('config','user.name','CI test')
            git('config','user.email','ci@example.invalid')
            git('commit','--allow-empty','-m','merged')
            old = git('rev-parse','HEAD')
            git('push','origin','HEAD:refs/heads/codex/feature')
            git('commit','--allow-empty','-m','new work')
            newer = git('rev-parse','HEAD')
            git('push','origin','HEAD:refs/heads/codex/feature')
            self.assertFalse(delete_with_lease('codex/feature',old,local))
            self.assertIn(newer, git('ls-remote','origin','refs/heads/codex/feature'))
            self.assertTrue(delete_with_lease('codex/feature',newer,local))
            self.assertEqual(git('ls-remote','origin','refs/heads/codex/feature'), '')


if __name__ == '__main__':
    unittest.main()
