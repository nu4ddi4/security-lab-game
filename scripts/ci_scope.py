"""Select affected runtimes and preserve the required `test` check."""
import argparse
import json
import os
from pathlib import Path
import subprocess


def classify(paths, has_godot=False, main_push=False):
    web = godot = False
    for path in paths:
        if path in {'.github/workflows/ci.yml', '.gitattributes', 'package.json', 'package-lock.json', 'scripts/ci_scope.py'}:
            web = godot = True
        elif path.startswith(('godot/', 'installer/', 'tests/native/', 'scripts/godot-', 'scripts/prototype-', 'scripts/ci-godot-', '.github/actions/godot-setup/', '.github/actions/inno-setup/')) or path in {'.github/workflows/godot-native.yml', '.github/workflows/native-update.yml'}:
            godot = True
        elif path.startswith('assets/authoring/'):
            continue
        elif path.startswith(('src/', 'vendor/', 'tests/browser/', 'tests/server/', 'assets/')) or path in {'index.html', 'run.py', 'launcher.py', 'requirements-build.txt', 'playwright.config.js', 'tests/engine.test.js', 'tests/scene.test.js', 'tests/windows_launcher.ps1'}:
            web = True
            godot |= path == 'assets/models/security_lab.glb'
        elif path.startswith('.github/actions/windows-build/') or path in {'.github/workflows/package.yml', '.github/workflows/release.yml', 'scripts/ci_release.py'}:
            web = True
        elif path == 'docs/RELEASE.md':
            # Permit a corrected, still-unreleased version to rebuild on main.
            web |= main_push
        elif path.startswith(('docs/', 'tests/ci/')) or path in {'AGENTS.md', 'README.md', '.gitignore', '.github/workflows/branch-cleanup.yml', 'scripts/ci_branch_cleanup.py'} or path.endswith('.md'):
            continue
        elif path.startswith('scripts/'):
            web = True
        else:
            # Unknown runtime paths must not silently bypass validation.
            web = godot = True
    return {'web': web, 'godot': godot and has_godot}


def select(paths, event, has_godot):
    default = event.get('repository', {}).get('default_branch', 'main')
    main_push = event.get('ref') == 'refs/heads/' + default and 'pull_request' not in event
    scope = classify(paths, has_godot, main_push)
    package = main_push or ('pull_request' in event and not event['pull_request'].get('draft', False))
    scope.update({'windows_web': scope['web'] and package, 'windows_godot': scope['godot'] and package})
    return scope


def gate(needs):
    if needs.get('scope', {}).get('result') != 'success':
        raise ValueError('Runtime selection did not succeed')
    selected = needs['scope']['outputs']
    for job in ['web', 'godot', 'windows_web', 'windows_godot']:
        result = needs.get(job, {}).get('result')
        expected = selected.get(job)
        if expected not in {'true', 'false'}:
            raise ValueError('Missing selection: ' + job)
        if result != ('success' if expected == 'true' else 'skipped'):
            raise ValueError(job + ': ' + str(result))


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
    parser = argparse.ArgumentParser()
    parser.add_argument('--gate', action='store_true')
    args = parser.parse_args()
    if args.gate:
        gate(json.loads(os.environ['CI_NEEDS']))
        print('All selected checks succeeded.')
        return
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text(encoding='utf-8'))
    scope = select(changed_paths(event, os.environ['GITHUB_SHA']), event, Path('godot/project.godot').exists())
    with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
        for name, value in scope.items():
            output.write(name + '=' + str(value).lower() + '\n')
    print(json.dumps(scope))


if __name__ == '__main__':
    main()
