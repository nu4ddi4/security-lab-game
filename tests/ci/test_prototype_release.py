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
spec = importlib.util.spec_from_file_location('release_assets', SCRIPTS / 'clean-release-assets.py')
assets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assets)


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

    def test_main_requires_both_platforms_except_verified_android_append(self):
        run = dict(self.run, head_branch='main')
        artifacts = [dict(a, name=a['name'].replace('-beta.1', '')) for a in self.artifacts]
        self.assertEqual(set(release.validate_build(run, self.jobs, artifacts, self.repo, self.sha, '0.2.0')), {'Windows-x64', 'Android'})
        self.assertEqual(set(release.validate_build(run, self.jobs[::2], artifacts[1:], self.repo, self.sha, '0.2.0', android_only=True)), {'Android'})
        with self.assertRaises(ValueError):
            release.validate_build(run, self.jobs[::2], artifacts, self.repo, self.sha, '0.2.0')
        with self.assertRaises(ValueError):
            release.validate_build(run, self.jobs[:2], artifacts[:1], self.repo, self.sha, '0.2.0')

    def test_version_allocation_and_retry_identity(self):
        from release_version import next_version, identity
        existing = [{'tag_name': 'SecurityLab-0.8.0-beta.1'}, {'tag_name':'SecurityLab-0.8.0'}]
        self.assertEqual(next_version('0.8.0', 'beta', existing), '0.8.0-beta.2')
        self.assertEqual(next_version('0.8.0', 'main', existing), '0.8.1')
        self.assertEqual(next_version('0.9.0', 'main', existing), '0.9.0')
        self.assertEqual(identity('0.8.0', self.sha)['channel'], 'stable')

    def test_main_and_beta_keep_the_same_public_signing_identity(self):
        for version, qa, signing in [('0.8.1', False, 'release'), ('0.8.1', True, 'debug'), ('0.8.1-beta.3', False, 'debug')]:
            preset = android.preset(version, Path('/public/prototype-test.p12'), qa=qa)
            self.assertIn('keystore/' + signing + '_user="androiddebugkey"', preset)
            self.assertIn('keystore/' + signing + '="/public/prototype-test.p12"', preset)
            self.assertIn('package/unique_name="' + android.PACKAGE + '"', preset)

    def test_backfill_requires_unchanged_game_and_preserves_retry_version(self):
        from release_backfill import select_backfill
        from unittest.mock import patch
        published = {'tag_name': 'SecurityLab-0.8.1', 'draft': False, 'prerelease': False,
                     'target_commitish': self.sha, 'assets': [{'name': 'SecurityLab-0.8.1.exe', 'state': 'uploaded', 'size': 42}]}
        with patch('release_backfill.unchanged_game', return_value=True):
            self.assertIs(select_backfill([published], '0.8.1', 'main', self.sha), published)
            self.assertIsNone(select_backfill([published], '0.8.1', 'beta', self.sha))
            published['assets'].append({'name': 'SecurityLab-0.8.1.apk', 'state': 'uploaded', 'size': 42, 'label': 'Codex pipeline ' + self.sha})
            self.assertIs(select_backfill([published], '0.8.1', 'main', self.sha), published)
            self.assertIsNone(select_backfill([published], '0.8.1', 'main', 'b' * 40))
        with patch('release_backfill.unchanged_game', return_value=False):
            self.assertIsNone(select_backfill([published], '0.8.1', 'main', self.sha))

    def test_failed_android_backfill_cannot_upload_to_existing_release(self):
        from unittest.mock import patch
        run = dict(self.run, head_branch='main')
        jobs = [self.jobs[0], dict(self.jobs[2], conclusion='failure')]
        artifacts = [dict(self.artifacts[1], name='SecurityLab-0.2.0-Android')]
        def api(path):
            if path.endswith('/actions/runs/42'): return run
            if '/jobs?' in path: return {'jobs': jobs}
            if '/artifacts?' in path: return {'artifacts': artifacts}
            raise AssertionError(path)
        with patch.object(release, 'unchanged_game', return_value=True), patch.object(release, 'github', side_effect=api), \
                patch.object(release.subprocess, 'run') as mutate, self.assertRaises(ValueError):
            release.append_android({'assets': []}, Path('/unused'), self.repo, '0.2.0', self.sha, self.sha, '42')
        mutate.assert_not_called()

    def test_android_append_never_reuploads_windows_or_clobbers_assets(self):
        import hashlib
        import json
        import tempfile
        from unittest.mock import patch
        run = dict(self.run, head_branch='main')
        artifacts = [dict(self.artifacts[1], name='SecurityLab-0.2.0-Android')]
        def api(path):
            if path.endswith('/actions/runs/42'): return run
            if '/jobs?' in path: return {'jobs': self.jobs[::2]}
            if '/artifacts?' in path: return {'artifacts': artifacts}
            raise AssertionError(path)
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            android_dir = directory / 'Android'
            android_dir.mkdir()
            apk = android_dir / 'SecurityLab-0.2.0.apk'
            apk.write_bytes(b'verified fixture APK')
            apk.with_suffix('.sha256').write_text(hashlib.sha256(apk.read_bytes()).hexdigest() + '  ' + apk.name + '\n')
            (android_dir / 'android-smoke.json').write_text(json.dumps({field: True for field in ['passed', 'mobile', 'touchDefault', 'keyboardDetected']}))
            (android_dir / 'android-build-info.json').write_text(json.dumps({'commit': self.sha, 'pipeline_commit': self.sha,
                'version': '0.2.0', 'channel': 'stable', 'platform': 'android', 'app_id': release.PRODUCT, 'signing': 'public-aosp-test'}))
            with patch.object(release, 'unchanged_game', return_value=True), patch.object(release, 'github', side_effect=api), \
                    patch.object(release.subprocess, 'run') as mutate:
                release.append_android({'assets': [{'name': 'SecurityLab-0.2.0.exe'}]}, directory, self.repo, '0.2.0', self.sha, self.sha, '42')
            uploads = [call.args[0] for call in mutate.call_args_list if call.args[0][1:3] == ['release', 'upload']]
            self.assertEqual(len(uploads), 2)
            self.assertIn('.apk.sha256#Codex pipeline ', uploads[0][-1])
            self.assertTrue(any('.apk#Codex pipeline ' in command[-1] for command in uploads))
            self.assertTrue(all('--clobber' not in command and '.exe' not in command[-1] for command in uploads))

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
        published = {'target_commitish':self.sha,'prerelease':True,'draft':False,'html_url':'https://example.test/release',
                     'assets': [{'name': name, 'state': 'uploaded', 'size': 2048, 'digest': 'sha256:' + 'b'*64}
                                for name in ['SecurityLabSetup.exe', release.tag(self.version) + '.exe']]}
        def download(command, **kwargs):
            self.assertEqual(command[:3], ['gh','release','download'])
            directory = Path(command[command.index('--dir') + 1])
            self.assertEqual(command[command.index('--pattern') + 1], 'SHA256SUMS.txt')
            (directory / 'SHA256SUMS.txt').write_text(''.join('b'*64 + '  ' + a['name'] + '\n' for a in published['assets']))
        with patch.dict(os.environ, env), patch.object(release, 'find_release', return_value=published), \
                patch.object(release, 'github', return_value=None), \
                patch.object(release.subprocess, 'check_output', return_value=self.sha), \
                patch.object(release.subprocess, 'run', side_effect=download) as commands, \
                patch.object(release, 'publish_channel') as recover:
            release.main()
        commands.assert_called_once()
        recover.assert_called_once()

    def test_installer_updates_remove_only_optional_pack_metadata(self):
        manifest = {'app_id': release.PRODUCT, 'version': self.version, 'installer_url': 'installer.exe',
                    'sha256': 'b'*64, 'exe_sha256': 'c'*64, 'size': 2048}
        with_pack = dict(manifest, compat='d'*64, content_url='content.pck', content_size=42, content_sha256='e'*64)
        self.assertEqual(release.installer_manifest(with_pack), manifest)
        self.assertEqual(release.installer_manifest(manifest), manifest)

    def test_public_release_contains_only_executables_apk_and_checksums(self):
        import hashlib
        import json
        import os
        import tempfile
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            env = {'GITHUB_REPOSITORY': release.REPOSITORY, 'GITHUB_SHA': self.sha,
                   'GITHUB_REF': 'refs/heads/beta', 'GITHUB_RUN_ID': '42',
                   'GITHUB_STEP_SUMMARY': str(directory / 'summary'), 'SECURITY_LAB_RELEASE_VERSION': self.version}
            identity = {'schema': 1, 'app_id': release.PRODUCT, 'platform': 'windows-x86_64', 'install_layout': 1,
                        'channel': 'beta', 'version': self.version, 'commit': self.sha, 'compat': 'c'*64}
            manifest = dict(identity)
            uploads = {}
            def command(args, **kwargs):
                if args[1:3] == ['run', 'download']:
                    output = Path(args[args.index('--dir') + 1])
                    output.mkdir()
                    platform = args[args.index('--name') + 1].rsplit('-', 1)[-1]
                    names = ([release.tag(self.version) + '.apk'] if platform == 'Android' else
                             [release.tag(self.version) + '.exe', 'SecurityLabSetup.exe', 'SecurityLabContent.pck'])
                    for name in names:
                        path = output / name
                        path.write_bytes(name.encode())
                        path.with_suffix('.sha256').write_text(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + name + '\n')
                    if platform == 'Android':
                        (output / 'android-smoke.json').write_text(json.dumps({field: True for field in ['passed', 'mobile', 'touchDefault', 'keyboardDetected']}))
                        (output / 'android-build-info.json').write_text(json.dumps(dict(identity, platform='android', pipeline_commit=self.sha, signing='public-aosp-test')))
                    else:
                        manifest.update(installer_url='https://github.com/' + release.REPOSITORY + '/releases/download/' + release.tag(self.version) + '/SecurityLabSetup.exe',
                                        size=(output / names[1]).stat().st_size, sha256=hashlib.sha256((output / names[1]).read_bytes()).hexdigest(),
                                        exe_sha256=hashlib.sha256((output / names[0]).read_bytes()).hexdigest(),
                                        content_url='https://github.com/' + release.REPOSITORY + '/releases/download/' + release.tag(self.version) + '/SecurityLabContent.pck',
                                        content_size=(output / names[2]).stat().st_size, content_sha256=hashlib.sha256((output / names[2]).read_bytes()).hexdigest())
                        (output / 'update.json').write_text(json.dumps(manifest))
                        (output / 'build_info.json').write_text(json.dumps(identity))
                        (output / 'beta-windows-updater.json').write_text(json.dumps({'product': release.PRODUCT, 'passed': True}))
                elif args[1:3] == ['release', 'upload']:
                    for name in args[4:args.index('--repo')]:
                        path = Path(name)
                        uploads[path.name] = path.read_bytes()
            published = {'assets': [], 'html_url': 'https://example.test/release'}
            def find(*args):
                published['assets'] = [{'name': name, 'size': len(data), 'state': 'uploaded'} for name, data in uploads.items()]
                return published if uploads else None
            def api(path, **kwargs):
                if path.endswith('/actions/runs/42'): return dict(self.run, head_repository={'full_name': release.REPOSITORY})
                if '/jobs?' in path: return {'jobs': self.jobs}
                if '/artifacts?' in path: return {'artifacts': self.artifacts}
                return published if '/releases/tags/' in path else None
            with patch.dict(os.environ, env), patch.object(release, 'find_release', side_effect=find), \
                    patch.object(release, 'github', side_effect=api), patch.object(release.subprocess, 'run', side_effect=command), \
                    patch.object(release.subprocess, 'check_output', return_value=self.sha), patch.object(release, 'publish_channel') as publish:
                publish.side_effect = lambda repo, sha, path: self.assertEqual(json.loads(path.read_text()), release.installer_manifest(manifest))
                release.main()
            self.assertEqual(set(uploads), {release.tag(self.version) + '.exe', release.tag(self.version) + '.apk', 'SecurityLabSetup.exe', 'SHA256SUMS.txt'})
            self.assertEqual({line.split('  ')[1] for line in uploads['SHA256SUMS.txt'].decode().splitlines()}, set(uploads) - {'SHA256SUMS.txt'})

    def test_channel_cleanup_preserves_same_version_payload_and_rejects_replacement(self):
        import json
        import tempfile
        from unittest.mock import patch
        manifest = {'app_id': release.PRODUCT, 'channel': 'beta', 'version': self.version,
                    'sha256': 'b'*64, 'exe_sha256': 'c'*64}
        previous = dict(manifest, compat='d'*64, content_url='old.pck', content_size=42, content_sha256='e'*64)
        def download(command, **kwargs):
            if command[1:3] == ['release', 'download']:
                (Path(command[command.index('--dir') + 1]) / 'update.json').write_text(json.dumps(previous))
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'update.json'
            path.write_text(json.dumps(manifest))
            with patch.object(release, 'github', return_value={'assets': [{'name': 'update.json'}]}), \
                    patch.object(release.subprocess, 'run', side_effect=download) as commands:
                release.publish_channel(self.repo, self.sha, path)
                self.assertEqual(commands.call_args_list[-1].args[0][1:3], ['release', 'upload'])
                path.write_text(json.dumps(dict(manifest, sha256='f'*64)))
                with self.assertRaises(ValueError):
                    release.publish_channel(self.repo, self.sha, path)

    def test_published_recovery_rejects_mismatched_asset_digest(self):
        import tempfile
        from unittest.mock import patch
        published = {'assets': [{'name': name, 'state': 'uploaded', 'size': 2048, 'digest': 'sha256:' + 'f'*64}
                               for name in ['SecurityLabSetup.exe', release.tag(self.version) + '.exe']]}
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / 'SHA256SUMS.txt').write_text(''.join('b'*64 + '  ' + a['name'] + '\n' for a in published['assets']))
            with patch.object(release.subprocess, 'run'), self.assertRaises(ValueError):
                release.published_manifest(published, self.repo, self.version, self.sha, directory)

    def test_cleanup_preserves_binaries_and_merges_android_checksums(self):
        import tempfile
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory/'SHA256SUMS.txt').write_text('b'*64 + '  game.exe\n' + 'c'*64 + '  game.zip\n')
            (directory/'game.apk.sha256').write_text('d'*64 + '  game.apk\n')
            files = [{'name': name, 'digest': digest} for name, digest in
                     [('game.exe', 'sha256:' + 'b'*64), ('game.apk', 'sha256:' + 'd'*64), ('game.zip', None),
                      ('game.apk.sha256', None), ('build_info.json', None), ('SecurityLabContent.pck', None), ('SHA256SUMS.txt', None)]]
            published = {'id': 42, 'tag_name': 'v1', 'draft': False, 'assets': files}
            plan = assets.cleanup_plan(published, directory)
            self.assertEqual(plan['keep'], ['SHA256SUMS.txt', 'game.apk', 'game.exe'])
            self.assertEqual(plan['checksums'], 'b'*64 + '  game.exe\n' + 'd'*64 + '  game.apk\n')
            self.assertEqual(plan['binaries'], files[:2])
            files[0]['digest'] = 'sha256:' + 'f'*64
            with self.assertRaises(ValueError):
                assets.cleanup_plan(published, directory)

    def test_cleanup_leaves_zip_only_and_draft_releases_untouched(self):
        published = {'draft': False, 'assets': [{'name': 'game.zip'}]}
        self.assertIsNone(assets.cleanup_plan(published, Path('/unused')))
        self.assertIsNone(assets.cleanup_plan(dict(published, draft=True, assets=[{'name': 'game.exe'}]), Path('/unused')))

    def test_cleanup_compares_payload_identity_without_download_counters(self):
        item = {'name': 'game.exe', 'id': 42, 'size': 2048, 'digest': 'sha256:' + 'b'*64, 'state': 'uploaded', 'download_count': 0}
        self.assertEqual(assets.asset_identities([item]), assets.asset_identities([dict(item, download_count=100)]))
        self.assertNotEqual(assets.asset_identities([item]), assets.asset_identities([dict(item, size=4096)]))

    def test_beta_channel_version_order(self):
        self.assertLess(release.version_key('0.3.0-beta.1'), release.version_key('0.3.1-beta.1'))
        self.assertLess(release.version_key('0.3.0-beta.1'), release.version_key('0.3.0-beta.2'))
        for version in ['0.3.0-dev.1', 'invalid']:
            with self.subTest(version=version), self.assertRaises(ValueError): release.version_key(version)
