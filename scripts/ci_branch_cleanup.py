"""Remove fully merged codex branches, preserving concurrent branch updates."""
import json
import os
import subprocess


def candidate(branch):
    return branch['name'].startswith('codex/') and not branch.get('protected', False)


def delete_with_lease(branch, sha, directory=None):
    result = subprocess.run(['git', 'push', '--force-with-lease=refs/heads/' + branch + ':' + sha,
                             'origin', ':refs/heads/' + branch], cwd=directory,
                            capture_output=True, text=True)
    return result.returncode == 0


def main():
    repository = os.environ['GITHUB_REPOSITORY']
    subprocess.run(['git', 'fetch', '--no-tags', 'origin', '+refs/heads/*:refs/remotes/origin/*'], check=True)
    response = subprocess.check_output(['gh', 'api', '--paginate', '--slurp', 'repos/' + repository + '/branches?per_page=100'], text=True)
    branches = [branch for page in json.loads(response) for branch in page]
    for branch in branches:
        if not candidate(branch):
            continue
        name, sha = branch['name'], branch['commit']['sha']
        if subprocess.run(['git', 'merge-base', '--is-ancestor', sha, 'origin/main'], capture_output=True).returncode != 0:
            continue
        if delete_with_lease(name, sha):
            print('Removed merged branch: ' + name)
        else:
            print('Kept branch: ' + name + ' (ref changed or deletion unavailable)')


if __name__ == '__main__':
    main()
