"""Validate native publication provenance; publish immutable payload before channel manifest."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

REPO = 'nu4ddi4/security-lab-game'
PREFIX = f'https://github.com/{REPO}/releases/download/'


def selection(event, ref, repository):
    inputs = event.get('inputs', {})
    channel = inputs.get('channel', 'dev')
    version = inputs.get('version', '0.7.0-dev.0')
    publish = inputs.get('publish') in [True, 'true']
    if ref.startswith('refs/tags/'):
        match = re.fullmatch(r'refs/tags/native-(stable|beta|dev)-v(.+)', ref)
        if not match:
            raise ValueError('Invalid native release tag')
        channel, version = match.groups()
        publish = True
    if channel not in ['stable', 'beta', 'dev']:
        raise ValueError('Invalid channel')
    pattern = r'(0|[1-9]\d{0,4})\.(0|[1-9]\d{0,4})\.(0|[1-9]\d{0,4})'
    pattern += '' if channel == 'stable' else '-' + channel + r'\.(0|[1-9]\d{0,8})'
    if not re.fullmatch(pattern, version) or any(int(n) > 65535 for n in version.split('-')[0].split('.')):
        raise ValueError('Version/channel mismatch')
    if publish and (repository != REPO or ref != 'refs/heads/godot-port' and not ref.startswith('refs/tags/native-')):
        raise ValueError('Publication requires the original repository and godot-port or a native tag')
    return channel, version, publish


def validate_package(directory, channel, version, sha):
    data = json.loads((directory / 'update.json').read_text(encoding='utf-8-sig'))
    build = json.loads((directory / 'build_info.json').read_text(encoding='utf-8-sig'))
    for value in [data, build]:
        if any(value.get(k) != v for k, v in {'schema': 1, 'app_id': 'security-lab-native', 'platform': 'windows-x86_64', 'install_layout': 1, 'channel': channel, 'version': version, 'commit': sha}.items()):
            raise ValueError('Package identity mismatch')
    if build.get('updates_default') is not (channel == 'stable') or build.get('manifest_url') != PREFIX + f'native-channel-{channel}/update.json':
        raise ValueError('Build channel defaults/URL mismatch')
    expected_url = PREFIX + f'native-{channel}-v{version}/SecurityLabSetup.exe'
    setup = directory / 'SecurityLabSetup.exe'
    if data.get('installer_url') != expected_url or data.get('size') != setup.stat().st_size or not 1024 <= data['size'] <= 536870912:
        raise ValueError('Invalid installer URL/size')
    with setup.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    if data.get('sha256') != digest:
        raise ValueError('Installer SHA-256 mismatch')
    if not re.fullmatch('[0-9a-f]{64}', data.get('exe_sha256', '')) or not re.fullmatch('[0-9a-f]{40}', sha):
        raise ValueError('Invalid EXE digest/commit')
    return data


def gh(*arguments, check=True):
    return subprocess.run(['gh', *arguments, '-R', REPO], text=True, check=check, capture_output=True)


def version_key(version):
    core, *pre = version.split('-')
    return (*map(int, core.split('.')), int(pre[0].split('.')[1]) if pre else 0)


def reject_stale_channel(channel, version):
    alias = f'native-channel-{channel}'
    if gh('release', 'view', alias, check=False).returncode != 0:
        return
    with tempfile.TemporaryDirectory(prefix='native-channel-') as temporary:
        gh('release', 'download', alias, '--pattern', 'update.json', '--dir', temporary)
        previous = json.loads((Path(temporary) / 'update.json').read_text(encoding='utf-8-sig'))
        selection({'inputs': {'channel': channel, 'version': previous.get('version', '')}}, 'refs/heads/godot-port', REPO)
        if previous.get('channel') != channel or previous.get('app_id') != 'security-lab-native' or version_key(version) <= version_key(previous['version']):
            raise ValueError('Channel cannot move backwards or republish its current version')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--select', action='store_true')
    parser.add_argument('--directory', type=Path)
    args = parser.parse_args()
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text(encoding='utf-8'))
    channel, version, publish = selection(event, os.environ['GITHUB_REF'], os.environ['GITHUB_REPOSITORY'])
    if args.select:
        if publish:
            subprocess.run(['git', 'fetch', 'origin', 'godot-port'], check=True)
            subprocess.run(['git', 'merge-base', '--is-ancestor', os.environ['GITHUB_SHA'], 'origin/godot-port'], check=True)
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as file:
            file.write(f'channel={channel}\nversion={version}\npublish={str(publish).lower()}\n')
        return
    if not publish:
        raise SystemExit('Artifact-only run cannot publish')
    data = validate_package(args.directory, channel, version, os.environ['GITHUB_SHA'])
    reject_stale_channel(channel, version)
    tag = f'native-{channel}-v{version}'
    if gh('release', 'view', tag, check=False).returncode == 0:
        raise SystemExit('Version is already published; immutable payload will not be replaced')
    assets = [str(args.directory / name) for name in ['SecurityLabSetup.exe', 'update.json', 'build_info.json']]
    command = ['release', 'create', tag, *assets, '--target', data['commit'], '--title', f'Security Lab Native {version} ({channel})', '--notes', 'Windows Native installer; SHA-256 and channel metadata included.', '--latest=false']
    if channel != 'stable':
        command.append('--prerelease')
    gh(*command)
    alias = f'native-channel-{channel}'
    if gh('release', 'view', alias, check=False).returncode != 0:
        gh('release', 'create', alias, '--target', data['commit'], '--title', f'Native {channel} update channel', '--notes', 'Channel metadata. Installers use immutable native version releases.', '--prerelease', '--latest=false')
    # Metadata is published last, after the immutable setup is available.
    gh('release', 'upload', alias, str(args.directory / 'build_info.json'), '--clobber')
    gh('release', 'upload', alias, str(args.directory / 'update.json'), '--clobber')
    print(f'Published {tag}; refreshed only {alias}')


if __name__ == '__main__':
    main()
