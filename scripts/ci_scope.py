"""Select quick Godot validation; documentation never triggers packaging."""
import json
import os
from pathlib import Path
import subprocess


def classify(paths):
    for path in paths:
        if path.startswith(('docs/', 'assets/authoring/')) or path in {
            'AGENTS.md', 'README.md', '.gitignore', '.editorconfig', '.gitattributes'}:
            continue
        if path.endswith('.md'):
            continue
        # Unknown paths are checked conservatively, including deleted files.
        return True
    return False


def changed_paths(event, sha):
    base = event.get('pull_request', {}).get('base', {}).get('sha') or event.get('before')
    if not base or base == '0' * 40:
        default = event.get('repository', {}).get('default_branch', 'main')
        if event.get('ref') != 'refs/heads/' + default:
            merge = subprocess.run(['git', 'merge-base', 'origin/' + default, sha], capture_output=True, text=True)
            if merge.returncode == 0:
                base = merge.stdout.strip()
    if not base or base == '0' * 40:
        return subprocess.check_output(['git', 'ls-files', '-z'], text=True).strip('\0').split('\0')
    # --no-renames includes both paths when a file moves between runtimes.
    result = subprocess.run(['git', 'diff', '--no-renames', '--name-only', '-z', base, sha], capture_output=True, text=True)
    if result.returncode != 0:
        # A force-push can remove the prior SHA from the checkout history.
        return subprocess.check_output(['git', 'ls-files', '-z'], text=True).strip('\0').split('\0')
    return result.stdout.strip('\0').split('\0')


def main():
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text(encoding='utf-8'))
    runtime = classify(changed_paths(event, os.environ['GITHUB_SHA']))
    with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
        output.write('runtime=' + str(runtime).lower() + '\n')
    print(json.dumps({'runtime': runtime}))


if __name__ == '__main__':
    main()
