"""One identity for automatic builds, filenames, installers and update manifests."""
import json
import os
from pathlib import Path
import re

REPOSITORY = 'nu4ddi4/security-lab-game'
PRODUCT = 'security-lab-beta'  # Preserve the investigation product/save identity.


def parts(version):
    match = re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-beta\.([1-9]\d*))?', version)
    if not match:
        raise ValueError('Expected X.Y.Z or X.Y.Z-beta.N')
    return tuple(int(value) if value else 0 for value in match.groups())


def tag(version):
    parts(version)
    return 'SecurityLab-' + version


def build_version(source):
    base = json.loads((source / 'prototype/version.json').read_text(encoding='utf-8'))['version']
    version = os.environ.get('SECURITY_LAB_RELEASE_VERSION', base + '-beta.1')
    parts(version)
    return version


def channel(version):
    return 'beta' if parts(version)[3] else 'stable'


def identity(version, commit):
    return {'schema': 1, 'app_id': PRODUCT, 'platform': 'windows-x86_64',
            'version': version, 'channel': channel(version), 'commit': commit,
            'install_layout': 1, 'updates_default': True,
            'manifest_url': 'https://github.com/' + REPOSITORY + '/releases/download/beta-channel-' + channel(version) + '/update.json'}


def next_version(base, branch, releases):
    """Allocate from immutable published/draft releases; retries reuse their SHA upstream."""
    major, minor, patch, pre = parts(base)
    if pre or branch not in {'main', 'beta'}:
        raise ValueError('Expected a base version and main/beta branch')
    versions = []
    for release in releases:
        name = release.get('tag_name', '')
        if name.startswith('SecurityLab-'):
            try:
                versions.append(parts(name[len('SecurityLab-'):]))
            except ValueError:
                continue
    if branch == 'beta':
        sequence = max((v[3] for v in versions if v[:3] == (major, minor, patch) and v[3]), default=0) + 1
        if sequence > 998:
            raise ValueError('Beta sequence exhausted; raise the target version')
        return base + '-beta.' + str(sequence)
    stable = [v for v in versions if not v[3]]
    if stable and (major, minor, patch) <= max(v[:3] for v in stable):
        latest = max(v[:3] for v in stable)
        return '.'.join(map(str, (latest[0], latest[1], latest[2] + 1)))
    return base


def android_code(version):
    major, minor, patch, pre = parts(version)
    if any(number > 999 for number in (major, minor, patch)) or pre > 998:
        raise ValueError('Version components or beta sequence exceed Android allocation')
    code = (major * 1_000_000 + minor * 1_000 + patch) * 1000 + (pre or 999)
    if not 0 < code <= 2_100_000_000:
        raise ValueError('Android version code is outside the supported range')
    return code
