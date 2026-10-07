"""Choose an immutable release version before exporting any platform."""
import json
import os
from pathlib import Path
import subprocess
from release_version import REPOSITORY, next_version, parts, tag


def main():
    if os.environ['GITHUB_REPOSITORY'] != REPOSITORY:
        raise ValueError('Automatic releases are restricted to the original repository')
    pages = json.loads(subprocess.check_output(['gh', 'api', '--paginate', '--slurp',
        'repos/' + REPOSITORY + '/releases?per_page=100'], text=True))
    releases = [release for page in pages for release in page]
    branch = 'main' if os.environ['GITHUB_REF'] == 'refs/heads/main' else 'beta'
    sha = os.environ['GITHUB_SHA']
    # Retry a partial upload using the same draft; skip a fully published commit.
    existing = next((r for r in releases if r.get('target_commitish') == sha
                     and r['tag_name'].startswith('SecurityLab-')
                     and r.get('prerelease') == (branch == 'beta')), None)
    base = json.loads(Path('godot/prototype/version.json').read_text())['version']
    version = existing['tag_name'][len('SecurityLab-'):] if existing else next_version(base, branch, releases)
    parts(version)
    with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
        output.write('version=' + version + '\n')
        output.write('tag=' + tag(version) + '\n')
        output.write('published=' + str(bool(existing and not existing['draft'])).lower() + '\n')
    print(json.dumps({'version': version, 'already_published': bool(existing and not existing['draft'])}))


if __name__ == '__main__':
    main()
