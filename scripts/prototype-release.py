"""Publish a verified prototype artifact as a separate, non-latest prerelease."""
import hashlib
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
    version = os.environ['PROTOTYPE_BETA_VERSION']
    if not run_id.isdecimal() or not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise ValueError('Invalid verified build reference')
    if not re.fullmatch(r'\d+\.\d+\.\d+-beta\.\d+', version):
        raise ValueError('Use an explicit prototype beta version')
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
    jobs = github(prefix + '/actions/runs/' + run_id + '/jobs?per_page=100')['jobs']
    if not any(job['name'] == 'prototype' and job.get('conclusion') == 'success' for job in jobs):
        raise ValueError('Windows EXE verification did not succeed')
    artifacts = github(prefix + '/actions/runs/' + run_id + '/artifacts?per_page=100')['artifacts']
    matching = [item for item in artifacts if item['name'] == 'SecurityLab-Prototype-0.1.0-Windows-x64']
    if (len(matching) != 1 or matching[0].get('expired') is not False
            or matching[0].get('size_in_bytes', 0) <= 0
            or matching[0].get('workflow_run', {}).get('head_sha', sha) != sha):
        raise ValueError('Prototype artifact is missing, expired or from another commit')
    tag = 'prototype-v' + version
    if github(prefix + '/releases/tags/' + tag, missing_ok=True) is not None:
        raise ValueError('This beta already exists; keep it or choose the next beta version')
    if github(prefix + '/git/ref/tags/' + tag, missing_ok=True) is not None:
        raise ValueError('This beta tag already exists')
    with tempfile.TemporaryDirectory(prefix='prototype-beta-') as temporary:
        directory = Path(temporary)
        download = directory / 'download'
        subprocess.run(['gh', 'run', 'download', run_id, '--repo', repository,
                        '--name', matching[0]['name'], '--dir', str(download)], check=True)
        original = download / ('SecurityLab-Prototype-0.1.0-' + sha[:7] + '-Windows-x64.exe')
        checksum = original.with_suffix('.sha256')
        digest = hashlib.sha256(original.read_bytes()).hexdigest()
        if checksum.read_text(encoding='utf-8').strip() != digest + '  ' + original.name:
            raise ValueError('Downloaded EXE differs from the verified artifact checksum')
        exe = directory / ('SecurityLab-Prototype-' + version + '-Windows-x64.exe')
        shutil.copyfile(original, exe)
        archive = exe.with_suffix('.zip')
        with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as bundle:
            bundle.write(exe, exe.name)
        sums = directory / 'SHA256SUMS.txt'
        sums.write_text(''.join(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.name + '\n'
                                for path in [exe, archive]), encoding='utf-8')
        notes = directory / 'release-notes.md'
        notes.write_text('Windows 조사 프로토타입. EXE만 실행하면 됩니다.\n\n'
                         '5~7일차 상세 조사와 정식 결말은 개발 중입니다.\n', encoding='utf-8')
        subprocess.run(['gh', 'release', 'create', tag, str(exe), str(archive), str(sums),
                        '--repo', repository, '--target', sha, '--prerelease', '--latest=false',
                        '--title', 'Security Lab Prototype ' + version, '--notes-file', str(notes)], check=True)
    release = github(prefix + '/releases/tags/' + tag)
    if not release.get('prerelease') or release.get('draft'):
        raise ValueError('The beta must be a published prerelease')
    print(release['html_url'])
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as summary:
        summary.write('[Security Lab Prototype ' + version + '](' + release['html_url'] + ')\n')


if __name__ == '__main__':
    main()
