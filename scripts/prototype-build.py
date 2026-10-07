"""Build the integrated investigation beta as a standalone Windows EXE."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def run(command, directory, marker=None, timeout=90):
    try:
        result = subprocess.run(command, cwd=directory, capture_output=True, text=True,
                                encoding='utf-8', errors='replace', timeout=timeout)
    except subprocess.TimeoutExpired as error:
        raise SystemExit('Prototype check timed out: ' + str(command)) from error
    output = result.stdout + result.stderr
    if result.returncode or 'SCRIPT ERROR:' in output or 'ERROR:' in output:
        raise SystemExit(output or 'Prototype command failed.')
    if marker:
        summaries = [line[len(marker) + 1:] for line in output.splitlines() if line.startswith(marker + ' ')]
        if not summaries or not json.loads(summaries[-1]).get('passed'):
            raise SystemExit(output or 'Prototype check did not complete.')
        print(marker, summaries[-1])
    return output


def prototype_version(source):
    version = json.loads((source / 'prototype/version.json').read_text(encoding='utf-8'))['version']
    if not isinstance(version, str) or not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise SystemExit('Use a prototype version in X.Y.Z form.')
    return version


def stage(source, target):
    version = prototype_version(source)
    shutil.copytree(source / 'prototype', target / 'prototype')
    shutil.copytree(source / 'scripts', target / 'scripts')
    shutil.copytree(source / 'resources', target / 'resources')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source.parent, text=True).strip()
    metadata = {'schema': 1, 'app_id': 'security-lab-beta', 'platform': 'windows-x86_64',
                'version': version + '-beta.1', 'channel': 'beta', 'commit': commit,
                'install_layout': 1, 'updates_default': True,
                'manifest_url': 'https://github.com/nu4ddi4/security-lab-game/releases/download/beta-channel-beta/update.json'}
    (target / 'prototype/build_info.json').write_text(json.dumps(metadata), encoding='utf-8')
    for name in ['assets/models/Interior_07_Godot.glb', 'assets/textures/city-sunset.png', 'scripts/player.gd', 'assets/fonts/NotoSansKR.ttf', 'assets/fonts/OFL.txt', 'LICENSES.txt']:
        destination = target / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / name, destination)
    project = (source / 'project.godot').read_text(encoding='utf-8')
    project = project.replace('res://scenes/entry.tscn', 'res://prototype/main.tscn')
    project = project.replace('Forward Plus', 'GL Compatibility').replace('"forward_plus"', '"gl_compatibility"')
    project = project.replace('Offline security investigation simulator. Native companion to web v0.7.0.',
                              'Offline security investigation beta.')
    project = re.sub(r'^config/version="[^"]*"$', 'config/version="' + version + '-beta"', project, flags=re.MULTILINE)
    (target / 'project.godot').write_text(project, encoding='utf-8')
    (target / 'export_presets.cfg').write_text('''[preset.0]
name="Windows Prototype"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter="prototype/version.json,prototype/content/*.json,prototype/tests/*.json,prototype/build_info.json,resources/*.json,resources/*.ps1,assets/fonts/OFL.txt,LICENSES.txt"
exclude_filter="prototype/tests/results/*"
export_path=""
script_export_mode=2

[preset.0.options]
binary_format/embed_pck=true
binary_format/architecture="x86_64"
debug/export_console_wrapper=0
texture_format/s3tc_bptc=true
codesign/enable=false
application/modify_resources=true
application/file_version="0.1.0.0"
application/product_version="0.1.0.0"
application/product_name="Security Lab Beta"
application/file_description="Offline security investigation beta"
'''.replace('0.1.0.0', version + '.0'), encoding='utf-8')


def check(godot, target):
    run([godot, '--headless', '--editor', '--path', str(target), '--import'], target)
    run([godot, '--headless', '--path', str(target), '--script', 'res://prototype/tests/unit.gd'],
        target, 'INVESTIGATION_UNIT')
    run([godot, '--headless', '--path', str(target), '--script', 'res://prototype/tests/services.gd'], target, 'INVESTIGATION_SERVICES')
    run([godot, '--headless', '--path', str(target), '--', '--prototype-smoke'],
        target, 'INVESTIGATION_SMOKE')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', default=os.environ.get('SECURITY_LAB_GODOT_CONSOLE', 'godot'))
    parser.add_argument('--output', help='Defaults to prototype-dist/SecurityLab-beta-X.Y.Z.exe')
    parser.add_argument('--check-only', action='store_true')
    parser.add_argument('--rendered-check', action='store_true', help='Also exercise and capture the exported Windows UI')
    args = parser.parse_args()
    godot = shutil.which(args.godot) or str(Path(args.godot).resolve())
    if not subprocess.check_output([godot, '--version'], text=True).startswith('4.7.2.stable'):
        raise SystemExit('Godot 4.7.2 stable is required.')
    root = Path(__file__).resolve().parents[1]
    version = prototype_version(root / 'godot')
    output = Path(args.output or ('prototype-dist/SecurityLab-beta-' + version + '.exe')).resolve()
    with tempfile.TemporaryDirectory(prefix='security-lab-prototype-') as directory:
        target = Path(directory)
        stage(root / 'godot', target)
        check(godot, target)
        baked_metadata = (target / "prototype/build_info.json").read_text(encoding="utf-8")
        if args.check_only:
            return
        if os.name != 'nt':
            raise SystemExit('Build and verify the Windows EXE on Windows; use --check-only elsewhere.')
        output.parent.mkdir(parents=True, exist_ok=True)
        run([godot, '--headless', '--path', str(target), '--export-release', 'Windows Prototype', str(output)],
            target, timeout=180)
        if not output.is_file() or output.stat().st_size < 1_000_000:
            raise SystemExit('Windows executable is missing or incomplete.')
    # Run only the EXE in a separate directory after the staged sources are deleted.
    with tempfile.TemporaryDirectory(prefix='security-lab-exe-only-') as directory:
        executable = Path(directory) / output.name
        shutil.copyfile(output, executable)
        for attempt in range(2):
            run([str(executable), '--headless', '--', '--prototype-smoke'],
                directory, 'INVESTIGATION_SMOKE')
            print('Standalone EXE launch', attempt + 1, 'passed.')
        if args.rendered_check:
            captures = output.parent / 'ui'
            run([str(executable), '--audio-driver', 'Dummy', '--', '--prototype-smoke',
                 '--prototype-capture-dir=' + str(captures)], directory, 'INVESTIGATION_SMOKE')
            expected = ['01-briefing', '02-dialogue', '03-terminal', '04-messenger', '05-notes', '06-field', '07-settings']
            if any(not (captures / (name + '.png')).is_file() for name in expected):
                raise SystemExit('Exported Windows UI captures are incomplete.')
            print('Rendered Windows EXE UI and interaction passed.')
    (output.parent / 'build_info.json').write_text(baked_metadata, encoding='utf-8')
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix('.sha256').write_text(digest + '  ' + output.name + '\n', encoding='utf-8')
    print('PROTOTYPE_EXE', json.dumps({'file':output.name, 'bytes':output.stat().st_size, 'sha256':digest}))


if __name__ == '__main__':
    main()
