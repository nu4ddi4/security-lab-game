"""Publish only an existing successful Windows build from the same main commit."""
import json
import os
import re
import subprocess


def validate_run(run, repository, expected_sha=None):
    if run.get('status') != 'completed' or run.get('conclusion') != 'success':
        raise ValueError('Build run must have completed successfully')
    if run.get('head_branch') != 'main' or run.get('head_repository', {}).get('full_name') != repository:
        raise ValueError('Only this repository main builds can be released')
    if run.get('event') not in {'push', 'workflow_dispatch'} or run.get('path') not in {'.github/workflows/ci.yml', '.github/workflows/package.yml'}:
        raise ValueError('Unsupported build source')
    sha = run.get('head_sha', '')
    if not re.fullmatch(r'[0-9a-f]{40}', sha) or expected_sha and sha != expected_sha:
        raise ValueError('Package and release must use the same commit')
    return sha


def validate_artifact(run, jobs, artifacts):
    successful = {job['name'] for job in jobs if job.get('conclusion') == 'success'}
    required = {'test', 'windows_web / package'} if run['path'].endswith('/ci.yml') else {'package'}
    if not required <= successful:
        raise ValueError('Required Windows build and verification did not succeed')
    matching = [item for item in artifacts if item.get('name') == 'SecurityLab-Windows-X64']
    if len(matching) != 1:
        raise ValueError('Expected exactly one verified Windows artifact')
    artifact = matching[0]
    if artifact.get('expired') is not False or artifact.get('size_in_bytes', 0) <= 0:
        raise ValueError('Windows artifact is expired or empty')
    if artifact.get('workflow_run', {}).get('head_sha', run['head_sha']) != run['head_sha']:
        raise ValueError('Artifact commit differs from verified build')
    return artifact


def should_publish(version, existing, latest):
    if existing is not None:
        return False
    latest_tag = (latest or {}).get('tag_name', '')
    match = re.fullmatch(r'v(\d+)\.(\d+)\.(\d+)', latest_tag)
    return not match or tuple(map(int, version.split('.'))) > tuple(map(int, match.groups()))


def github(path, missing_ok=False):
    result = subprocess.run(['gh', 'api', path], capture_output=True, text=True, encoding='utf-8')
    if result.returncode:
        if missing_ok and 'HTTP 404' in result.stderr:
            return None
        raise RuntimeError(result.stderr)
    return json.loads(result.stdout)


def main():
    repository = os.environ['GITHUB_REPOSITORY']
    run_id = os.environ['RUN_ID']
    if not run_id.isdecimal():
        raise ValueError('Run ID must be numeric')
    prefix = 'repos/' + repository
    run = github(prefix + '/actions/runs/' + run_id)
    expected = os.environ['GITHUB_SHA'] if os.environ['GITHUB_EVENT_NAME'] == 'workflow_dispatch' else None
    sha = validate_run(run, repository, expected)
    # A build must still belong to protected main, rather than a moved branch.
    subprocess.run(['git', 'merge-base', '--is-ancestor', sha, 'origin/main'], check=True)
    package = json.loads(subprocess.check_output(['git', 'show', sha + ':package.json'], text=True))
    version = package['version']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Release version must be X.Y.Z')
    tag = 'v' + version
    if os.environ.get('RELEASE_TAG') and os.environ['RELEASE_TAG'] != tag:
        raise ValueError('Release tag must match the verified commit')
    existing = github(prefix + '/releases/tags/' + tag, missing_ok=True)
    latest = github(prefix + '/releases/latest', missing_ok=True) if existing is None else None
    publish = should_publish(version, existing, latest)
    if publish:
        jobs = github(prefix + '/actions/runs/' + run_id + '/jobs?per_page=100')['jobs']
        artifacts = github(prefix + '/actions/runs/' + run_id + '/artifacts?per_page=100')['artifacts']
        validate_artifact(run, jobs, artifacts)
    with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
        for key, value in {'publish':str(publish).lower(), 'sha':sha, 'run_id':run_id, 'tag':tag}.items():
            output.write(key + '=' + value + '\n')
    print(('Reuse verified Windows artifact: ' if publish else 'No new release: ') + tag)


if __name__ == '__main__':
    main()
