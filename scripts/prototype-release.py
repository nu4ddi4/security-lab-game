"""Publish only artifacts that passed this commit's platform validation."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from github_release import github, installer_manifest
from release_version import PRODUCT, REPOSITORY, channel, parts, tag
from release_backfill import unchanged_game


def validate_build(run, jobs, artifacts, repository, sha, version, android_only=False):
    branch = 'beta' if channel(version) == 'beta' else 'main'
    status_ok = (run.get('status') == 'completed' and run.get('conclusion') == 'success') or (
        run.get('status') == 'in_progress' and run.get('conclusion') is None)
    if (not status_ok or run.get('head_sha') != sha or run.get('head_branch') != branch
            or run.get('head_repository', {}).get('full_name') != repository
            or run.get('path') != '.github/workflows/godot-prototype.yml'
            or run.get('event') not in {'push', 'workflow_dispatch'}):
        raise ValueError('Expected successful platform validation from this commit and branch')
    platforms = ['Android'] if android_only else ['Windows-x64', 'Android']
    successful = {job['name'] for job in jobs if job.get('conclusion') == 'success'}
    required = {'quick / test', 'android'} | (set() if android_only else {'prototype'})
    if not required <= successful:
        raise ValueError('Quick checks and all release platform checks must succeed')
    selected = {}
    for platform in platforms:
        name = tag(version) + '-' + platform
        matching = [item for item in artifacts if item['name'] == name]
        if (len(matching) != 1 or matching[0].get('expired') is not False
                or matching[0].get('size_in_bytes', 0) <= 0
                or matching[0].get('workflow_run', {}).get('head_sha') != sha):
            raise ValueError('Artifact missing, expired, duplicated or from another commit: ' + platform)
        selected[platform] = matching[0]
    return selected


def verified_file(directory, name):
    path = directory / name
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if path.with_suffix('.sha256').read_text(encoding='utf-8').strip() != digest + '  ' + name:
        raise ValueError('Artifact differs from its verified checksum: ' + name)
    return path


def version_key(version):
    return parts(version)[:3] + (0 if parts(version)[3] else 1, parts(version)[3])


def published_manifest(release, repository, version, sha, directory):
    """Recover channel publication using the immutable payloads and checksums."""
    subprocess.run(['gh', 'release', 'download', tag(version), '--repo', repository,
                    '--pattern', 'SHA256SUMS.txt', '--dir', str(directory)], check=True)
    sums = {}
    for line in (directory / 'SHA256SUMS.txt').read_text(encoding='utf-8').splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  (.+)', line)
        if not match or match[2] in sums:
            raise ValueError('Invalid published checksums')
        sums[match[2]] = match[1]
    assets = {asset['name']: asset for asset in release['assets']}
    for name in ['SecurityLabSetup.exe', tag(version) + '.exe']:
        asset = assets.get(name, {})
        if (name not in sums or asset.get('state') != 'uploaded' or asset.get('size', 0) <= 0
                or asset.get('digest') not in {None, 'sha256:' + sums[name]}):
            raise ValueError('Published Windows payload differs from its checksums: ' + name)
    return {'schema': 1, 'app_id': PRODUCT, 'platform': 'windows-x86_64', 'install_layout': 1,
            'channel': channel(version), 'version': version, 'commit': sha,
            'installer_url': 'https://github.com/' + repository + '/releases/download/' + tag(version) + '/SecurityLabSetup.exe',
            'size': assets['SecurityLabSetup.exe']['size'], 'sha256': sums['SecurityLabSetup.exe'],
            'exe_sha256': sums[tag(version) + '.exe']}


def publish_channel(repository, sha, manifest_file):
    manifest = json.loads(manifest_file.read_text(encoding='utf-8'))
    release_channel = channel(manifest['version'])
    alias = 'beta-channel-' + release_channel
    prefix = 'repos/' + repository
    previous_release = github(prefix + '/releases/tags/' + alias, missing_ok=True)
    if previous_release and any(a['name'] == 'update.json' for a in previous_release.get('assets', [])):
        with tempfile.TemporaryDirectory(prefix='update-channel-') as temporary:
            subprocess.run(['gh', 'release', 'download', alias, '--repo', repository,
                            '--pattern', 'update.json', '--dir', temporary], check=True)
            previous = json.loads((Path(temporary)/'update.json').read_text(encoding='utf-8'))
        if previous.get('app_id') != PRODUCT or previous.get('channel') != release_channel:
            raise ValueError('Foreign update channel metadata')
        if previous == manifest:
            return
        # Permit only removal of optional pack metadata at the same version.
        if (installer_manifest(previous) != manifest
                and version_key(previous['version']) >= version_key(manifest['version'])):
            raise ValueError('Update channel cannot replace or move behind its current version')
    elif not previous_release:
        subprocess.run(['gh', 'release', 'create', alias, '--repo', repository,
                        '--target', sha, '--prerelease', '--latest=false',
                        '--title', 'Security Lab ' + release_channel + ' update channel',
                        '--notes', 'Update metadata; installers are in version releases.'], check=True)
    subprocess.run(['gh', 'release', 'upload', alias, str(manifest_file), '--repo', repository, '--clobber'], check=True)


def find_release(prefix, release_tag):
    published = github(prefix + '/releases/tags/' + release_tag, missing_ok=True)
    if published:
        return published
    # Draft tags may not exist until publication.
    return next((r for r in github(prefix + '/releases?per_page=100') if r['tag_name'] == release_tag), None)


def verify_android(directory, version, source_sha, pipeline_sha):
    apk = verified_file(directory, tag(version) + '.apk')
    report = json.loads((directory / 'android-smoke.json').read_text())
    record = json.loads((directory / 'android-build-info.json').read_text())
    if not all(report.get(field) is True for field in ['passed', 'mobile', 'touchDefault', 'keyboardDetected']):
        raise ValueError('Android report does not confirm mobile input checks')
    if (record.get('commit') != source_sha or record.get('pipeline_commit') != pipeline_sha
            or record.get('version') != version or record.get('channel') != channel(version)
            or record.get('platform') != 'android' or record.get('app_id') != PRODUCT
            or record.get('signing') != 'public-aosp-test'):
        raise ValueError('Android artifact differs from the verified release source or signing policy')
    return apk


def append_android(release, directory, repository, version, source_sha, pipeline_sha, run_id):
    if channel(version) != 'stable' or not unchanged_game(source_sha):
        raise ValueError('Only identical published main game sources may receive an APK')
    prefix = 'repos/' + repository
    run = github(prefix + '/actions/runs/' + run_id)
    jobs = github(prefix + '/actions/runs/' + run_id + '/jobs?per_page=100')['jobs']
    artifacts = github(prefix + '/actions/runs/' + run_id + '/artifacts?per_page=100')['artifacts']
    artifact = validate_build(run, jobs, artifacts, repository, pipeline_sha, version, android_only=True)['Android']
    download = directory / 'Android'
    subprocess.run(['gh', 'run', 'download', run_id, '--repo', repository,
                    '--name', artifact['name'], '--dir', str(download)], check=True)
    apk = verify_android(download, version, source_sha, pipeline_sha)
    checksum = apk.with_name(apk.name + '.sha256')
    shutil.copyfile(apk.with_suffix('.sha256'), checksum)
    # Append only. Existing Windows files, tags and aggregate checksums stay intact.
    for path in [apk, checksum]:
        existing = next((asset for asset in release['assets'] if asset['name'] == path.name), None)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if existing:
            if existing.get('size') != path.stat().st_size:
                raise ValueError('Existing release asset cannot be replaced: ' + path.name)
            if existing.get('digest'):
                if existing['digest'] != 'sha256:' + digest:
                    raise ValueError('Existing release checksum differs: ' + path.name)
            else:
                check = directory / 'existing'
                check.mkdir(exist_ok=True)
                subprocess.run(['gh', 'release', 'download', tag(version), '--repo', repository,
                                '--pattern', path.name, '--dir', str(check)], check=True)
                if hashlib.sha256((check / path.name).read_bytes()).hexdigest() != digest:
                    raise ValueError('Existing release checksum differs: ' + path.name)
            continue
        subprocess.run(['gh', 'release', 'upload', tag(version), '--repo', repository,
                        str(path) + '#Codex pipeline ' + pipeline_sha], check=True)


def main():
    repository = os.environ['GITHUB_REPOSITORY']
    sha = os.environ['GITHUB_SHA']
    source_sha = os.environ.get('SECURITY_LAB_RELEASE_SOURCE_SHA') or sha
    add_android = os.environ.get('SECURITY_LAB_APPEND_ANDROID') == 'true'
    run_id = os.environ['GITHUB_RUN_ID']
    version = os.environ['SECURITY_LAB_RELEASE_VERSION']
    release_tag = tag(version)
    branch = 'beta' if channel(version) == 'beta' else 'main'
    if repository != REPOSITORY or os.environ['GITHUB_REF'] != 'refs/heads/' + branch:
        raise ValueError('Publication requires the original main/beta branch')
    if subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip() != sha:
        raise ValueError('Publication checkout must match the tested commit')
    prefix = 'repos/' + repository
    reference = github(prefix + '/git/ref/tags/' + release_tag, missing_ok=True)
    if reference and reference['object']['sha'] != source_sha:
        raise ValueError('Release tag belongs to another commit')
    release = find_release(prefix, release_tag)
    if release and (release.get('target_commitish') != source_sha or release.get('prerelease') != (branch == 'beta')):
        raise ValueError('Existing version belongs to a different commit or channel')
    with tempfile.TemporaryDirectory(prefix='verified-release-') as temporary:
        directory = Path(temporary)
        if release and not release['draft']:
            if add_android:
                append_android(release, directory, repository, version, source_sha, sha, run_id)
            # Recover a failed channel update without rebuilding or replacing a published payload.
            manifest = published_manifest(release, repository, version, source_sha, directory)
            (directory/'update.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
            publish_channel(repository, source_sha, directory/'update.json')
            print(release['html_url'])
            return
        if source_sha != sha or add_android:
            raise ValueError('Platform append requires an existing published version')
        run = github(prefix + '/actions/runs/' + run_id)
        jobs = github(prefix + '/actions/runs/' + run_id + '/jobs?per_page=100')['jobs']
        artifacts = github(prefix + '/actions/runs/' + run_id + '/artifacts?per_page=100')['artifacts']
        selected = validate_build(run, jobs, artifacts, repository, sha, version)
        files = []
        for platform, artifact in selected.items():
            download = directory / platform
            subprocess.run(['gh', 'run', 'download', run_id, '--repo', repository,
                            '--name', artifact['name'], '--dir', str(download)], check=True)
            original = verified_file(download, release_tag + ('.apk' if platform == 'Android' else '.exe'))
            if platform == 'Android':
                verify_android(download, version, sha, sha)
            destination = directory / original.name
            shutil.copyfile(original, destination)
            files.append(destination)
        windows = directory / 'Windows-x64'
        report = json.loads((windows/'beta-windows-updater.json').read_text(encoding='utf-8-sig'))
        if report.get('product') != PRODUCT or report.get('passed') is not True:
            raise ValueError('Windows installation and rollback checks must pass')
        installer = verified_file(windows, 'SecurityLabSetup.exe')
        content = verified_file(windows, 'SecurityLabContent.pck')
        manifest = json.loads((windows/'update.json').read_text())
        identity = json.loads((windows/'build_info.json').read_text())
        if (manifest.get('app_id') != PRODUCT or manifest.get('commit') != sha
                or manifest.get('channel') != channel(version) or manifest.get('version') != version
                or manifest.get('sha256') != hashlib.sha256(installer.read_bytes()).hexdigest()
                or manifest.get('size') != installer.stat().st_size
                or manifest.get('exe_sha256') != hashlib.sha256(files[0].read_bytes()).hexdigest()
                or manifest.get('content_sha256') != hashlib.sha256(content.read_bytes()).hexdigest()
                or manifest.get('content_size') != content.stat().st_size
                or manifest.get('compat') != identity.get('compat') or not manifest.get('compat')
                or manifest.get('content_url') != 'https://github.com/'+repository+'/releases/download/'+release_tag+'/SecurityLabContent.pck'
                or identity.get('commit') != sha or identity.get('version') != version
                or identity.get('channel') != channel(version) or identity.get('app_id') != PRODUCT
                or manifest.get('installer_url') != 'https://github.com/'+repository+'/releases/download/'+release_tag+'/SecurityLabSetup.exe'):
            raise ValueError('Installer and manifest differ from the verified Windows build')
        destination = directory/'SecurityLabSetup.exe'
        shutil.copyfile(installer, destination)
        files.append(destination)
        # Keep validation records in Actions artifacts; only the update channel
        # needs metadata. The release download list contains playable files.
        (directory/'update.json').write_text(json.dumps(installer_manifest(manifest), indent=2), encoding='utf-8')
        sums = directory / 'SHA256SUMS.txt'
        sums.write_text(''.join(hashlib.sha256(path.read_bytes()).hexdigest()+'  '+path.name+'\n' for path in files))
        files.append(sums)
        if not release:
            subprocess.run(['gh','release','create',release_tag,'--repo',repository,'--target',sha,
                            '--draft','--title',release_tag,'--notes','Built and verified by Codex automation. Commit: '+sha], check=True)
        # Only drafts can be retried/replaced. A published version is immutable.
        subprocess.run(['gh','release','upload',release_tag,*map(str,files),'--repo',repository,'--clobber'], check=True)
        uploaded = find_release(prefix, release_tag)
        expected = {path.name: path.stat().st_size for path in files}
        actual = {asset['name']:asset['size'] for asset in uploaded['assets'] if asset.get('state')=='uploaded'}
        if actual != expected:
            raise ValueError('Uploaded files differ from the public download list; release remains draft and channel unchanged')
        subprocess.run(['gh','release','edit',release_tag,'--repo',repository,'--draft=false',
                        '--prerelease='+str(branch=='beta').lower(),'--latest='+str(branch=='main').lower()], check=True)
        publish_channel(repository, sha, directory/'update.json')
        published = github(prefix+'/releases/tags/'+release_tag)
        print(published['html_url'])
        with open(os.environ['GITHUB_STEP_SUMMARY'],'a') as output:
            output.write('['+release_tag+']('+published['html_url']+')\n')


if __name__ == '__main__':
    main()
