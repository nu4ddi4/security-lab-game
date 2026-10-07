"""Publish the verified Windows and Android prototype builds together."""
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


def validate_build(run, jobs, artifacts, repository, sha, version):
    if (run.get('status') != 'completed' or run.get('conclusion') != 'success'
            or run.get('head_sha') != sha
            or run.get('head_branch') != 'codex/godot-investigation-prototype'
            or run.get('head_repository', {}).get('full_name') != repository
            or run.get('path') != '.github/workflows/godot-prototype.yml'
            or run.get('event') not in {'push', 'workflow_dispatch'}):
        raise ValueError('Expected successful Windows and Android builds from this branch')
    if not {'prototype', 'android'} <= {job['name'] for job in jobs if job.get('conclusion') == 'success'}:
        raise ValueError('Windows and Android execution checks must both succeed')
    selected = {}
    for platform in ['Windows-x64', 'Android']:
        name = 'SecurityLab-proto-' + version + '-' + platform
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


def main():
    repository = os.environ['GITHUB_REPOSITORY']
    run_id = os.environ['PROTOTYPE_RUN_ID']
    sha = os.environ['PROTOTYPE_BUILD_SHA']
    tag_sha = os.environ['GITHUB_SHA']
    version = os.environ['PROTOTYPE_VERSION']
    if not run_id.isdecimal() or not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise ValueError('Invalid verified build reference')
    if (not re.fullmatch(r'[0-9a-f]{40}', tag_sha)
            or subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip() != tag_sha):
        raise ValueError('Expected the current publication commit')
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Use a prototype version in X.Y.Z form')
    metadata = json.loads(Path('godot/prototype/version.json').read_text(encoding='utf-8'))
    if version != metadata['version'] or metadata.get('prerelease') is not True:
        raise ValueError('Release version/channel differs from the prototype build')
    prefix = 'repos/' + repository
    run = github(prefix + '/actions/runs/' + run_id)
    jobs = github(prefix + '/actions/runs/' + run_id + '/jobs?per_page=100')['jobs']
    artifacts = github(prefix + '/actions/runs/' + run_id + '/artifacts?per_page=100')['artifacts']
    selected = validate_build(run, jobs, artifacts, repository, sha, version)
    subprocess.run(['git', 'merge-base', '--is-ancestor', sha, 'HEAD'], check=True)
    subprocess.run(['git', 'diff', '--quiet', sha, 'HEAD', '--', 'godot',
                    'scripts/prototype-build.py', 'scripts/prototype-android-build.py',
                    'scripts/prototype-android-test.py', '.github/workflows/godot-prototype.yml'], check=True)
    tag = 'SecurityLab-proto-' + version
    release = github(prefix + '/releases/tags/' + tag, missing_ok=True)
    reference = github(prefix + '/git/ref/tags/' + tag, missing_ok=True)
    if reference and reference['object']['sha'] != tag_sha:
        raise ValueError('Prototype tag points to another publication commit')
    if release and (not release.get('prerelease') or release.get('draft')):
        raise ValueError('Only a published prototype prerelease can be updated')
    with tempfile.TemporaryDirectory(prefix='prototype-release-') as temporary:
        directory = Path(temporary)
        files = []
        for platform, extension in [('Windows-x64', '.exe'), ('Android', '.apk')]:
            download = directory / platform
            subprocess.run(['gh', 'run', 'download', run_id, '--repo', repository,
                            '--name', selected[platform]['name'], '--dir', str(download)], check=True)
            original = verified_file(download, tag + extension)
            if platform == 'Android':
                report = json.loads((download / 'android-smoke.json').read_text(encoding='utf-8'))
                if not all(report.get(field) is True for field in ['passed','mobile','touchDefault','keyboardDetected']):
                    raise ValueError('Downloaded Android test report does not confirm mobile input checks')
            destination = directory / original.name
            shutil.copyfile(original, destination)
            files.append(destination)
        exe = files[0]
        archive = exe.with_suffix('.zip')
        with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as bundle:
            bundle.write(exe, exe.name)
        files.append(archive)
        sums = directory / 'SHA256SUMS.txt'
        sums.write_text(''.join(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.name + '\n'
                                for path in files), encoding='utf-8')
        files.append(sums)
        notes = directory / 'release-notes.md'
        notes.write_text(Path('docs/PROTOTYPE_RELEASE_NOTES.md').read_text(encoding='utf-8'), encoding='utf-8')
        # The publication commit must match the tested game/build sources. Tagging
        # this workflow's own commit also works with the scoped GITHUB_TOKEN.
        if reference is None:
            subprocess.run(['gh', 'api', '--method', 'POST', prefix + '/git/refs',
                            '-f', 'ref=refs/tags/' + tag, '-f', 'sha=' + tag_sha, '--silent'], check=True)
        if release:
            subprocess.run(['gh', 'release', 'upload', tag, *map(str, files),
                            '--repo', repository, '--clobber'], check=True)
        else:
            subprocess.run(['gh', 'release', 'create', tag, *map(str, files),
                            '--repo', repository, '--target', tag_sha, '--verify-tag', '--prerelease', '--latest=false',
                            '--title', tag, '--notes-file', str(notes)], check=True)
    release = github(prefix + '/releases/tags/' + tag)
    if (not release.get('prerelease') or release.get('draft')
            or release.get('tag_name') != tag or release.get('name') != tag):
        raise ValueError('Expected a published prototype prerelease')
    expected = {tag + '.exe', tag + '.zip', tag + '.apk', 'SHA256SUMS.txt'}
    uploaded = {item['name'] for item in release['assets']
                if item.get('state') == 'uploaded' and item.get('size', 0) > 0}
    if not expected <= uploaded:
        raise ValueError('The prototype release is missing an uploaded file')
    print(release['html_url'])
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as summary:
        summary.write('[' + tag + '](' + release['html_url'] + ')\n')


if __name__ == '__main__':
    main()
