"""Run focused Godot checks without importing office models or export templates."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

SUITES = {
    'rules': [(['--script', 'res://prototype/tests/unit.gd'], 'INVESTIGATION_UNIT')],
    'services': [(['--script', 'res://prototype/tests/services_runner.gd'], 'INVESTIGATION_SERVICES'),
                 (['--script', 'res://tests/diagnostics_test.gd'], 'NATIVE_DIAGNOSTICS'),
                 (['--script', 'res://tests/native_update_test.gd'], 'NATIVE_UPDATE_TEST'),
                 (['--script', 'res://tests/content_pack_test.gd'], 'CONTENT_PACK_TEST')],
    'scene': [(['--script', 'res://tests/input_bindings_test.gd'], 'INPUT_BINDINGS_TEST'),
              (['--', '--prototype-smoke', '--prototype-dummy'], 'INVESTIGATION_SMOKE'),
              (['--', '--prototype-smoke', '--prototype-dummy', '--prototype-input-review'], 'INPUT_REVIEW')],
}


def run(godot, directory, arguments, marker=None):
    started = time.monotonic()
    try:
        result = subprocess.run([godot, '--headless', '--path', str(directory), *arguments],
                                capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=90)
    except subprocess.TimeoutExpired as error:
        partial = (error.stdout or b'') + (error.stderr or b'')
        if isinstance(partial, bytes): partial = partial.decode('utf-8', errors='replace')
        raise SystemExit('Godot check timed out: ' + str(arguments) + '\n' + partial) from error
    output = result.stdout + result.stderr
    if result.returncode or 'SCRIPT ERROR:' in output or 'ERROR:' in output:
        raise SystemExit(output)
    if marker:
        summaries = [line[len(marker) + 1:] for line in output.splitlines() if line.startswith(marker + ' ')]
        if not summaries or not json.loads(summaries[-1]).get('passed'):
            raise SystemExit(output or 'Missing successful check: ' + marker)
        print(marker, summaries[-1], flush=True)
    print('CHECK_SECONDS', round(time.monotonic() - started, 2), marker or 'import', flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', default=os.environ.get('SECURITY_LAB_GODOT_CONSOLE', 'godot'))
    parser.add_argument('--project', default='godot')
    parser.add_argument('--suite', choices=[*SUITES, 'all'], default='all')
    args = parser.parse_args()
    if not subprocess.check_output([args.godot, '--version'], text=True).startswith('4.7.2.stable'):
        raise SystemExit('Godot 4.7.2 stable is required.')
    source = Path(args.project).resolve()
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix='security-lab-check-') as temporary:
        target = Path(temporary)
        for name in ['scripts', 'resources', 'prototype', 'tests']:
            shutil.copytree(source / name, target / name,
                            ignore=shutil.ignore_patterns('results', '.godot', '*.png'))
        (target / 'assets/fonts').mkdir(parents=True)
        shutil.copyfile(source / 'assets/fonts/NotoSansKR.ttf', target / 'assets/fonts/NotoSansKR.ttf')
        shutil.copyfile(source / 'project.godot', target / 'project.godot')
        run(args.godot, target, ['--editor', '--import'])
        for suite in SUITES if args.suite == 'all' else [args.suite]:
            for arguments, marker in SUITES[suite]:
                run(args.godot, target, arguments, marker)
    print('SUITE_SECONDS', round(time.monotonic() - started, 2), args.suite)


if __name__ == '__main__':
    main()
