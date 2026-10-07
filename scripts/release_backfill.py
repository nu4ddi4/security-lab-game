"""Append a newly supported platform without replacing a published game build."""
import re
import subprocess

from release_version import tag


def unchanged_game(source_sha):
    if not re.fullmatch(r'[0-9a-f]{40}', source_sha or ''):
        raise ValueError('Expected the published source commit')
    if subprocess.run(['git', 'cat-file', '-e', source_sha + '^{commit}'], capture_output=True).returncode:
        subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', source_sha], check=True)
    return subprocess.run(['git', 'diff', '--quiet', source_sha, 'HEAD', '--', 'godot', 'assets']).returncode == 0


def android_assets(version):
    return {tag(version) + '.apk', tag(version) + '.apk.sha256', 'android-build-info.json'}


def select_backfill(releases, base, branch, pipeline_sha):
    if branch != 'main':
        return None
    for release in releases:
        if release.get('draft') or release.get('prerelease') or release.get('tag_name') != tag(base):
            continue
        assets = release.get('assets', [])
        names = {asset['name'] for asset in assets if asset.get('state') == 'uploaded' and asset.get('size', 0) > 0}
        owned_retry = any(asset.get('label') == 'Codex pipeline ' + pipeline_sha for asset in assets)
        if tag(base) + '.exe' in names and (tag(base) + '.apk' not in names or owned_retry):
            if unchanged_game(release.get('target_commitish')):
                return release
    return None
