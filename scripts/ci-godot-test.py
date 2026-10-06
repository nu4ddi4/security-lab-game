"""Test pure native rules and the real dummy scene without importing legacy GLB."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


def run(godot, directory, arguments, marker=None):
    try:
        result = subprocess.run([godot, '--headless', '--path', str(directory), *arguments],
                                capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=90)
    except subprocess.TimeoutExpired as error:
        raise SystemExit('Godot check timed out: ' + str(arguments)) from error
    output = result.stdout + result.stderr
    if result.returncode or 'SCRIPT ERROR:' in output or 'ERROR:' in output:
        raise SystemExit(output)
    if marker:
        summaries = [line[len(marker) + 1:] for line in output.splitlines() if line.startswith(marker + ' ')]
        if not summaries or not json.loads(summaries[-1]).get('passed'):
            raise SystemExit(output)
        print(marker, summaries[-1])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--project', default='godot')
    args = parser.parse_args()
    version = subprocess.check_output([args.godot, '--version'], text=True)
    if not version.startswith('4.7.2.stable'):
        raise SystemExit('Godot 4.7.2 stable is required.')
    source = Path(args.project).resolve()
    with tempfile.TemporaryDirectory(prefix='security-lab-ci-') as temporary:
        target = Path(temporary)
        for name in ['scripts/missions.gd', 'scripts/save_manager.gd', 'scripts/player.gd', 'tests/unit.gd']:
            destination = target / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / name, destination)
        for name in ['resources', 'tests']:
            for path in (source / name).glob('*.json'):
                destination = target / path.relative_to(source)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, destination)
        prototype = (source / 'prototype/main.tscn').exists()
        if prototype:
            shutil.copytree(source / 'prototype', target / 'prototype')
            (target / 'assets/fonts').mkdir(parents=True)
            shutil.copyfile(source / 'assets/fonts/NotoSansKR.ttf', target / 'assets/fonts/NotoSansKR.ttf')
        scene = 'run/main_scene="res://prototype/main.tscn"\n' if prototype else ''
        (target / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Security Lab CI"\n' + scene + '[physics]\ncommon/physics_ticks_per_second=120\n', encoding='utf-8')
        run(args.godot, target, ['--editor', '--import'])
        run(args.godot, target, ['--script', 'res://tests/unit.gd'], 'NATIVE_UNIT')
        if prototype:
            run(args.godot, target, ['--script', 'res://prototype/tests/unit.gd'], 'INVESTIGATION_UNIT')
            run(args.godot, target, ['--', '--prototype-smoke'], 'INVESTIGATION_SMOKE')


if __name__ == '__main__':
    main()
