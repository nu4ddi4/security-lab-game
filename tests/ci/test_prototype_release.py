import copy
import importlib.util
from pathlib import Path
import sys
import unittest

SCRIPTS = Path(__file__).resolve().parents[2] / 'scripts'
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location('prototype_release', SCRIPTS / 'prototype-release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
spec = importlib.util.spec_from_file_location('prototype_android', SCRIPTS / 'prototype-android-build.py')
android = importlib.util.module_from_spec(spec)
spec.loader.exec_module(android)


class PrototypeReleaseTests(unittest.TestCase):
    def setUp(self):
        self.sha, self.repo, self.version = 'a' * 40, 'owner/game', '0.2.0-beta.1'
        self.run = {'status':'completed', 'conclusion':'success', 'head_sha':self.sha,
                    'head_branch':'beta',
                    'head_repository':{'full_name':self.repo},
                    'path':'.github/workflows/godot-prototype.yml', 'event':'push'}
        self.jobs = [{'name':name, 'conclusion':'success'} for name in ['quick / test','prototype','android']]
        self.artifacts = [{'name':'SecurityLab-0.2.0-beta.1-' + platform, 'expired':False,
                           'size_in_bytes':42, 'workflow_run':{'head_sha':self.sha}}
                          for platform in ['Windows-x64','Android']]

    def validate(self, jobs=None, artifacts=None, run=None):
        return release.validate_build(run or self.run, self.jobs if jobs is None else jobs,
                                      self.artifacts if artifacts is None else artifacts,
                                      self.repo, self.sha, self.version)

    def test_both_platforms_are_required(self):
        self.assertEqual(set(self.validate()), {'Windows-x64','Android'})
        for jobs in [self.jobs[:2],self.jobs[1:],self.jobs[::2],[dict(job,conclusion='skipped') for job in self.jobs]]:
            with self.subTest(jobs=jobs), self.assertRaises(ValueError): self.validate(jobs=jobs)

    def test_android_artifact_must_be_verified_and_same_version(self):
        for field,value in [('expired',True),('size_in_bytes',0),('name','SecurityLab-beta-0.1.1-Android'),('workflow_run',{'head_sha':'b'*40})]:
            artifacts = copy.deepcopy(self.artifacts)
            artifacts[1][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError): self.validate(artifacts=artifacts)
        with self.assertRaises(ValueError): self.validate(artifacts=self.artifacts[:1])
        with self.assertRaises(ValueError): self.validate(artifacts=self.artifacts+self.artifacts[1:])

    def test_incomplete_failed_and_foreign_builds_are_rejected(self):
        for field,value in [('status','in_progress'),('conclusion','failure'),('head_branch','main'),('head_sha','b'*40),('head_repository',{'full_name':'fork/game'})]:
            with self.subTest(field=field), self.assertRaises(ValueError): self.validate(run=dict(self.run,**{field:value}))

    def test_android_version_codes_increase_at_each_semantic_boundary(self):
        versions = ['0.2.0-beta.1','0.2.0-beta.2','0.2.0','0.2.1-beta.1','0.2.1','0.2.999','0.3.0','0.999.999','1.0.0']
        codes = [android.version_code(version) for version in versions]
        self.assertEqual(sorted(set(codes)),codes)
        for version in ['0.1.1000','-1.0.0','0.8.0-beta.999','3.0.0']:
            with self.subTest(version=version), self.assertRaises(ValueError): android.version_code(version)

    def test_main_requires_both_platforms(self):
        run = dict(self.run, head_branch='main')
        artifacts = [dict(a, name=a['name'].replace('-beta.1', '')) for a in self.artifacts]
        self.assertEqual(set(release.validate_build(run, self.jobs, artifacts, self.repo, self.sha, '0.2.0')), {'Windows-x64','Android'})
        with self.assertRaises(ValueError):
            release.validate_build(run, self.jobs[:2], artifacts, self.repo, self.sha, '0.2.0')

    def test_version_allocation_and_retry_identity(self):
        from release_version import next_version, identity
        existing = [{'tag_name': 'SecurityLab-0.8.0-beta.1'}, {'tag_name':'SecurityLab-0.8.0'}]
        self.assertEqual(next_version('0.8.0', 'beta', existing), '0.8.0-beta.2')
        self.assertEqual(next_version('0.8.0', 'main', existing), '0.8.1')
        self.assertEqual(next_version('0.9.0', 'main', existing), '0.9.0')
        self.assertEqual(identity('0.8.0', self.sha)['channel'], 'stable')

    def test_stable_android_never_falls_back_to_public_test_keys(self):
        import os
        from unittest.mock import patch
        with patch.dict(os.environ, {}, clear=True), self.assertRaises(ValueError):
            android.require_private_signing()
        preset = android.preset('0.8.0', Path('/private/release.keystore'), alias='release', password='fixture')
        self.assertIn('keystore/release_user="release"', preset)
        self.assertNotIn('androiddebugkey', preset)

    def test_failed_run_cannot_create_or_upload_release(self):
        import os
        from unittest.mock import patch
        env = {'GITHUB_REPOSITORY': release.REPOSITORY, 'GITHUB_SHA': self.sha,
               'GITHUB_REF':'refs/heads/beta', 'GITHUB_RUN_ID':'42',
               'SECURITY_LAB_RELEASE_VERSION':self.version}
        def api(path, **kwargs):
            if path.endswith('/actions/runs/42'): return dict(self.run, conclusion='failure')
            if '/jobs?' in path: return {'jobs':self.jobs}
            if '/artifacts?' in path: return {'artifacts':self.artifacts}
            return None
        with patch.dict(os.environ, env), patch.object(release, 'find_release', return_value=None), \
                patch.object(release, 'github', side_effect=api), \
                patch.object(release.subprocess, 'check_output', return_value=self.sha), \
                patch.object(release.subprocess, 'run') as mutate, self.assertRaises(ValueError):
            release.main()
        mutate.assert_not_called()

    def test_published_retry_only_recovers_update_channel(self):
        import json
        import os
        from unittest.mock import patch
        env = {'GITHUB_REPOSITORY': release.REPOSITORY, 'GITHUB_SHA': self.sha,
               'GITHUB_REF':'refs/heads/beta', 'GITHUB_RUN_ID':'42',
               'SECURITY_LAB_RELEASE_VERSION':self.version}
        published = {'target_commitish':self.sha,'prerelease':True,'draft':False,'html_url':'https://example.test/release'}
        def download(command, **kwargs):
            self.assertEqual(command[:3], ['gh','release','download'])
            directory = Path(command[command.index('--dir') + 1])
            (directory / 'update.json').write_text(json.dumps({'commit':self.sha,'version':self.version,'app_id':release.PRODUCT}))
        with patch.dict(os.environ, env), patch.object(release, 'find_release', return_value=published), \
                patch.object(release, 'github', return_value=None), \
                patch.object(release.subprocess, 'check_output', return_value=self.sha), \
                patch.object(release.subprocess, 'run', side_effect=download) as commands, \
                patch.object(release, 'publish_channel') as recover:
            release.main()
        commands.assert_called_once()
        recover.assert_called_once()

    def test_beta_channel_version_order(self):
        self.assertLess(release.version_key('0.3.0-beta.1'), release.version_key('0.3.1-beta.1'))
        self.assertLess(release.version_key('0.3.0-beta.1'), release.version_key('0.3.0-beta.2'))
        for version in ['0.3.0-dev.1', 'invalid']:
            with self.subTest(version=version), self.assertRaises(ValueError): release.version_key(version)
