import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('native_release', Path(__file__).parents[2] / 'scripts/godot-update-release.py')
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class NativeUpdates(unittest.TestCase):
    def test_channel_order(self):
        self.assertGreater(release.version_key('0.7.1-dev.10'), release.version_key('0.7.1-dev.9'))
        self.assertGreater(release.version_key('0.8.0'), release.version_key('0.7.9'))
    def test_feature_is_artifact_only(self):
        self.assertEqual(release.selection({}, 'refs/heads/feature/native-auto-update', release.REPO), ('dev', '0.7.0-dev.0', False))
        with self.assertRaises(ValueError): release.selection({'inputs': {'publish': True}}, 'refs/heads/feature/native-auto-update', release.REPO)

    def test_channels_and_tags(self):
        for channel in ['stable', 'beta', 'dev']:
            version = '0.7.1' if channel == 'stable' else f'0.7.1-{channel}.2'
            self.assertEqual(release.selection({}, f'refs/tags/native-{channel}-v{version}', release.REPO), (channel, version, True))

    def test_publication_origin(self):
        for branch in ['main', 'feature/native-auto-update']:
            with self.assertRaises(ValueError): release.selection({'inputs': {'publish': True}}, 'refs/heads/' + branch, release.REPO)
        with self.assertRaises(ValueError): release.selection({'inputs': {'publish': True}}, 'refs/heads/godot-port', 'attacker/fork')
        self.assertTrue(release.selection({'inputs': {'publish': True}}, 'refs/heads/godot-port', release.REPO)[2])

    def test_version_input_not_code(self):
        for version in ['0.7.1-dev.1;calc', '01.7.1-dev.1', '0.7.1-beta.1', '0.7.1', '65536.0.0-dev.1']:
            with self.assertRaises(ValueError): release.selection({'inputs': {'version': version}}, 'refs/heads/godot-port', release.REPO)

    def test_package_hash_and_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            installer = b'MZ' + b'x' * 1022
            (folder / 'SecurityLabSetup.exe').write_bytes(installer)
            identity = {'schema': 1, 'app_id': 'security-lab-native', 'platform': 'windows-x86_64', 'install_layout': 1, 'channel': 'dev', 'version': '0.7.1-dev.1', 'commit': 'a' * 40}
            build = {**identity, 'updates_default': False, 'manifest_url': release.PREFIX + 'native-channel-dev/update.json'}
            data = {**identity, 'installer_url': release.PREFIX + 'native-dev-v0.7.1-dev.1/SecurityLabSetup.exe', 'size': len(installer), 'sha256': hashlib.sha256(installer).hexdigest(), 'exe_sha256': 'b' * 64}
            (folder / 'update.json').write_text(json.dumps(data), encoding='utf-8')
            (folder / 'build_info.json').write_text(json.dumps(build), encoding='utf-8')
            release.validate_package(folder, 'dev', identity['version'], identity['commit'])
            (folder / 'SecurityLabSetup.exe').write_bytes(b'changed payload'.ljust(1024, b'x'))
            with self.assertRaises(ValueError): release.validate_package(folder, 'dev', identity['version'], identity['commit'])
            (folder / 'SecurityLabSetup.exe').write_bytes(installer)
            build['updates_default'] = True
            (folder / 'build_info.json').write_text(json.dumps(build), encoding='utf-8')
            with self.assertRaises(ValueError): release.validate_package(folder, 'dev', identity['version'], identity['commit'])
