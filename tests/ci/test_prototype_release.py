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
        self.sha, self.repo, self.version = 'a' * 40, 'owner/game', '0.2.0'
        self.run = {'status':'completed', 'conclusion':'success', 'head_sha':self.sha,
                    'head_branch':'codex/godot-investigation-prototype',
                    'head_repository':{'full_name':self.repo},
                    'path':'.github/workflows/godot-prototype.yml', 'event':'push'}
        self.jobs = [{'name':name, 'conclusion':'success'} for name in ['prototype','android']]
        self.artifacts = [{'name':'SecurityLab-proto-0.2.0-' + platform, 'expired':False,
                           'size_in_bytes':42, 'workflow_run':{'head_sha':self.sha}}
                          for platform in ['Windows-x64','Android']]

    def validate(self, jobs=None, artifacts=None, run=None):
        return release.validate_build(run or self.run, self.jobs if jobs is None else jobs,
                                      self.artifacts if artifacts is None else artifacts,
                                      self.repo, self.sha, self.version)

    def test_both_platforms_are_required(self):
        self.assertEqual(set(self.validate()), {'Windows-x64','Android'})
        for jobs in [self.jobs[:1],self.jobs[1:],[dict(job,conclusion='skipped') for job in self.jobs]]:
            with self.subTest(jobs=jobs), self.assertRaises(ValueError): self.validate(jobs=jobs)

    def test_android_artifact_must_be_verified_and_same_version(self):
        for field,value in [('expired',True),('size_in_bytes',0),('name','SecurityLab-proto-0.1.1-Android'),('workflow_run',{'head_sha':'b'*40})]:
            artifacts = copy.deepcopy(self.artifacts)
            artifacts[1][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError): self.validate(artifacts=artifacts)
        with self.assertRaises(ValueError): self.validate(artifacts=self.artifacts[:1])
        with self.assertRaises(ValueError): self.validate(artifacts=self.artifacts+self.artifacts[1:])

    def test_incomplete_failed_and_foreign_builds_are_rejected(self):
        for field,value in [('status','in_progress'),('conclusion','failure'),('head_branch','main'),('head_sha','b'*40),('head_repository',{'full_name':'fork/game'})]:
            with self.subTest(field=field), self.assertRaises(ValueError): self.validate(run=dict(self.run,**{field:value}))

    def test_android_version_codes_increase_at_each_semantic_boundary(self):
        versions = ['0.2.0','0.2.1','0.2.999','0.3.0','0.999.999','1.0.0']
        codes = [android.version_code(version) for version in versions]
        self.assertEqual(sorted(set(codes)),codes)
        for version in ['0.0.0','0.1.1000','-1.0.0']:
            with self.subTest(version=version), self.assertRaises(ValueError): android.version_code(version)
