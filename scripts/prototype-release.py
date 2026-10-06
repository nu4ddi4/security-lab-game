"""Publish a verified prototype artifact as a separate, non-latest prerelease."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

from ci_release import github


def main():
    repository = os.environ['GITHUB_REPOSITORY']
    run_id = os.environ['PROTOTYPE_RUN_ID']
    sha = os.environ['PROTOTYPE_BUILD_SHA']
    version = os.environ['PROTOTYPE_VERSION']
    if not run_id.isdecimal() or not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise ValueError('Invalid verified build reference')
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Use a prototype version in X.Y.Z form')
    configured_version = json.loads(Path('godot/prototype/version.json').read_text(encoding='utf-8'))['version']
    if version != configured_version:
        raise ValueError('Release version differs from the prototype version')
    prefix = 'repos/' + repository
    run = github(prefix + '/actions/runs/' + run_id)
    if (run.get('status') != 'completed' or run.get('conclusion') != 'success'
            or run.get('head_sha') != sha
            or run.get('head_branch') != 'codex/godot-investigation-prototype'
            or run.get('head_repository', {}).get('full_name') != repository
            or run.get('path') != '.github/workflows/godot-prototype.yml'
            or run.get('event') not in {'push', 'workflow_dispatch'}):
        raise ValueError('Expected the successful Windows prototype build from this branch')
    subprocess.run(['git', 'merge-base', '--is-ancestor', sha, 'HEAD'], check=True)
    subprocess.run(['git', 'diff', '--quiet', sha, 'HEAD', '--', 'godot', 'scripts/prototype-build.py'], check=True)
    jobs = github(prefix + '/actions/runs/' + run_id + '/jobs?per_page=100')['jobs']
    if not any(job['name'] == 'prototype' and job.get('conclusion') == 'success' for job in jobs):
        raise ValueError('Windows EXE verification did not succeed')
    artifacts = github(prefix + '/actions/runs/' + run_id + '/artifacts?per_page=100')['artifacts']
    tag = 'SecurityLab-proto-' + version
    matching = [item for item in artifacts if item['name'] == tag + '-Windows-x64']
    if (len(matching) != 1 or matching[0].get('expired') is not False
            or matching[0].get('size_in_bytes', 0) <= 0
            or matching[0].get('workflow_run', {}).get('head_sha', sha) != sha):
        raise ValueError('Prototype artifact is missing, expired or from another commit')
    release = github(prefix + '/releases/tags/' + tag, missing_ok=True)
    migrate = os.environ.get('PROTOTYPE_MIGRATE_FROM_TAG', '')
    if release is None and migrate:
        if not re.fullmatch(r'prototype-v\d+\.\d+\.\d+-beta\.\d+', migrate):
            raise ValueError('Unsupported old prototype tag')
        release = github(prefix + '/releases/tags/' + migrate)
    if release:
        if not release.get('prerelease') or release.get('draft'):
            raise ValueError('Only a published prototype prerelease can be updated')
        original_ref = github(prefix + '/git/ref/tags/' + release['tag_name'])
        if original_ref['object']['sha'] != sha:
            raise ValueError('Existing prototype release points to another build')
    reference = github(prefix + '/git/ref/tags/' + tag, missing_ok=True)
    if reference and reference['object']['sha'] != sha:
        raise ValueError('Prototype tag already points to another build')
    with tempfile.TemporaryDirectory(prefix='prototype-beta-') as temporary:
        directory = Path(temporary)
        download = directory / 'download'
        subprocess.run(['gh', 'run', 'download', run_id, '--repo', repository,
                        '--name', matching[0]['name'], '--dir', str(download)], check=True)
        original = download / (tag + '.exe')
        checksum = original.with_suffix('.sha256')
        digest = hashlib.sha256(original.read_bytes()).hexdigest()
        if checksum.read_text(encoding='utf-8').strip() != digest + '  ' + original.name:
            raise ValueError('Downloaded EXE differs from the verified artifact checksum')
        exe = directory / (tag + '.exe')
        shutil.copyfile(original, exe)
        archive = exe.with_suffix('.zip')
        with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as bundle:
            bundle.write(exe, exe.name)
        sums = directory / 'SHA256SUMS.txt'
        sums.write_text(''.join(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.name + '\n'
                                for path in [exe, archive]), encoding='utf-8')
        notes = directory / 'release-notes.md'
        notes.write_text(Path('docs/PROTOTYPE_RELEASE_NOTES.md').read_text(encoding='utf-8'), encoding='utf-8')
        if release:
            if reference is None:
                subprocess.run(['gh', 'api', '--method', 'POST', prefix + '/git/refs',
                                '-f', 'ref=refs/tags/' + tag, '-f', 'sha=' + sha, '--silent'], check=True)
            subprocess.run(['gh', 'release', 'upload', release['tag_name'], str(exe), str(archive), str(sums),
                            '--repo', repository, '--clobber'], check=True)
            payload = directory / 'release-update.json'
            payload.write_text(json.dumps({'tag_name':tag, 'name':tag, 'prerelease':True,
                                           'make_latest':'false'}), encoding='utf-8')
            subprocess.run(['gh', 'api', '--method', 'PATCH', prefix + '/releases/' + str(release['id']),
                            '--input', str(payload), '--silent'], check=True)
            updated = github(prefix + '/releases/tags/' + tag)
            expected = {exe.name, archive.name, sums.name}
            uploaded = {item['name'] for item in updated['assets'] if item.get('state') == 'uploaded'}
            if not expected <= uploaded:
                raise ValueError('Renamed prototype files were not fully uploaded')
            if migrate:
                old_stem = 'SecurityLab-Prototype-' + migrate.removeprefix('prototype-v') + '-Windows-x64'
                for item in updated['assets']:
                    if item['name'] in {old_stem + '.exe', old_stem + '.zip'}:
                        subprocess.run(['gh', 'api', '--method', 'DELETE',
                                        prefix + '/releases/assets/' + str(item['id']), '--silent'], check=True)
        else:
            subprocess.run(['gh', 'release', 'create', tag, str(exe), str(archive), str(sums),
                            '--repo', repository, '--target', sha, '--prerelease', '--latest=false',
                            '--title', tag, '--notes-file', str(notes)], check=True)
    release = github(prefix + '/releases/tags/' + tag)
    if (not release.get('prerelease') or release.get('draft')
            or release.get('tag_name') != tag or release.get('name') != tag):
        raise ValueError('The beta must be a published prerelease')
    expected = {tag + '.exe', tag + '.zip', 'SHA256SUMS.txt'}
    uploaded = {item['name'] for item in release['assets']
                if item.get('state') == 'uploaded' and item.get('size', 0) > 0}
    if not expected <= uploaded:
        raise ValueError('The prototype release is missing an uploaded file')
    print(release['html_url'])
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as summary:
        summary.write('[' + tag + '](' + release['html_url'] + ')\n')


if __name__ == '__main__':
    main()
