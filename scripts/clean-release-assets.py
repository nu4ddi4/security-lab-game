"""Remove redundant release downloads, preserving binaries and their checksums."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import subprocess

from github_release import github, installer_manifest
from release_version import REPOSITORY

PREFIX = 'repos/' + REPOSITORY


def checksum_list(name):
    return name.startswith('SHA256SUMS') and name.endswith('.txt')


def asset_identities(assets):
    # Downloads may increment counters while maintenance is running.
    return sorted((a['name'], a['id'], a['size'], a.get('digest'), a['state']) for a in assets)


def cleanup_plan(release, directory):
    assets = release['assets']
    binaries = [a for a in assets if a['name'].endswith(('.exe', '.apk'))]
    # Ancient versions distributed only as ZIP must remain downloadable.
    if release['draft'] or not binaries:
        return None
    sums = [a for a in assets if checksum_list(a['name'])]
    if len(sums) != 1:
        raise ValueError('Expected exactly one checksum list: ' + release['tag_name'])
    hashes = {}
    for asset in assets:
        name = asset['name']
        if checksum_list(name) or name.endswith('.sha256'):
            for line in (directory/name).read_text(encoding='utf-8-sig').splitlines():
                match = re.fullmatch(r'([0-9a-fA-F]{64})\s+\*?(.+)', line.strip())
                if not match or (match[2] in hashes and hashes[match[2]] != match[1].lower()):
                    raise ValueError('Invalid or conflicting checksum: ' + name)
                hashes[match[2]] = match[1].lower()
    for asset in binaries:
        digest = hashes.get(asset['name'])
        if not digest or asset.get('digest') not in (None, 'sha256:' + digest):
            raise ValueError('Missing or mismatched binary checksum: ' + asset['name'])
    keep = {a['name'] for a in binaries + sums}
    remove = [a for a in assets if a['name'] not in keep]
    if not remove:
        return None
    return {'tag': release['tag_name'], 'id': release['id'], 'keep': sorted(keep),
            'binaries': binaries, 'remove': remove, 'checksum': sums[0]['name'],
            'checksums': ''.join(hashes[a['name']] + '  ' + a['name'] + '\n' for a in binaries)}


def download_backup(release, output):
    if Path(release['tag_name']).name != release['tag_name']:
        raise ValueError('Invalid release tag')
    directory = output/release['tag_name']
    directory.mkdir(parents=True, exist_ok=True)
    names = [a['name'] for a in release['assets']
             if checksum_list(a['name']) or a['name'].endswith(('.json', '.pck', '.sha256'))]
    if any(Path(name).name != name for name in names):
        raise ValueError('Invalid release asset name')
    if names:
        command = ['gh', 'release', 'download', release['tag_name'], '--repo', REPOSITORY, '--dir', str(directory)]
        for name in names:
            command += ['--pattern', name]
        subprocess.run(command, check=True)
        for asset in release['assets']:
            if asset['name'] not in names:
                continue
            data = (directory/asset['name']).read_bytes()
            if (len(data) != asset['size']
                    or asset.get('digest') not in (None, 'sha256:' + hashlib.sha256(data).hexdigest())):
                raise ValueError('Backup mismatch: ' + release['tag_name'] + '/' + asset['name'])
    return directory


def migrate_channel(release, output):
    directory = output/release['tag_name']
    original = json.loads((directory/'update.json').read_text())
    manifest = installer_manifest(original)
    if manifest == original:
        return
    # Refuse to overwrite a channel that advanced after the backup.
    current = github(PREFIX + '/releases/' + str(release['id']))
    if asset_identities(current['assets']) != asset_identities(release['assets']):
        raise ValueError('Update channel changed; rerun cleanup')
    path = directory/'updated'/'update.json'
    path.parent.mkdir()
    path.write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    subprocess.run(['gh', 'release', 'upload', release['tag_name'], str(path), '--repo', REPOSITORY, '--clobber'], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true', help='Apply the printed plan; default is read-only')
    parser.add_argument('--output', type=Path, required=True, help='Backup directory, retained by the maintenance workflow')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    releases = []
    page = 1
    while True:
        batch = github(PREFIX + '/releases?per_page=100&page=' + str(page))
        releases += batch
        if len(batch) < 100:
            break
        page += 1
    (args.output/'releases.json').write_text(json.dumps(releases, indent=2), encoding='utf-8')
    channels = [r for r in releases if r['tag_name'] in ['beta-channel-stable', 'beta-channel-beta']]
    selected = [r for r in releases if not r['draft'] and any(a['name'].endswith(('.exe', '.apk')) for a in r['assets'])]
    with ThreadPoolExecutor(max_workers=6) as pool:
        directories = list(pool.map(lambda r: download_backup(r, args.output), selected + channels))
    plans = [p for r, directory in zip(selected, directories) if (p := cleanup_plan(r, directory))]
    (args.output/'plan.json').write_text(json.dumps(plans, indent=2), encoding='utf-8')
    print(json.dumps({'releases': len(plans), 'remove': sum(len(p['remove']) for p in plans), 'apply': args.apply}), flush=True)
    if not args.apply:
        return
    for release in channels:
        migrate_channel(release, args.output)
    for plan in plans:
        current = github(PREFIX + '/releases/' + str(plan['id']))
        original = next(r for r in selected if r['id'] == plan['id'])
        if asset_identities(current['assets']) != asset_identities(original['assets']):
            raise ValueError('Release changed; rerun cleanup: ' + plan['tag'])
        checksum = args.output/plan['tag']/'updated'/plan['checksum']
        checksum.parent.mkdir(exist_ok=True)
        checksum.write_text(plan['checksums'], encoding='utf-8')
        subprocess.run(['gh', 'release', 'upload', plan['tag'], str(checksum), '--repo', REPOSITORY, '--clobber'], check=True)
        for asset in plan['remove']:
            subprocess.run(['gh', 'api', '--method', 'DELETE', PREFIX + '/releases/assets/' + str(asset['id'])], check=True)
        after = github(PREFIX + '/releases/' + str(plan['id']))
        uploaded_sum = next((a for a in after['assets'] if a['name'] == plan['checksum']), {})
        if ({a['name'] for a in after['assets']} != set(plan['keep'])
                or asset_identities([a for a in after['assets'] if a['name'].endswith(('.exe', '.apk'))]) != asset_identities(plan['binaries'])
                or uploaded_sum.get('size') != checksum.stat().st_size
                or uploaded_sum.get('digest') not in (None, 'sha256:' + hashlib.sha256(checksum.read_bytes()).hexdigest())):
            raise ValueError('Release verification failed: ' + plan['tag'])
        print('Cleaned ' + plan['tag'], flush=True)


if __name__ == '__main__':
    main()
