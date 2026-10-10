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

import content_pack
from release_version import build_version, identity, parts, tag


def run(command, directory, marker=None, timeout=90):
    try:
        result = subprocess.run(command, cwd=directory, capture_output=True, text=True,
                                encoding='utf-8', errors='replace', timeout=timeout)
    except subprocess.TimeoutExpired as error:
        partial = (error.stdout or b'') + (error.stderr or b'')
        if isinstance(partial, bytes): partial = partial.decode('utf-8', errors='replace')
        raise SystemExit('Prototype check timed out: ' + str(command) + '\n' + partial) from error
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


def stage(source, target, godot_version, launcher=True):
    version = build_version(source)
    shutil.copytree(source / 'prototype', target / 'prototype')
    shutil.copytree(source / 'scripts', target / 'scripts')
    shutil.copytree(source / 'resources', target / 'resources')
    (target / 'tests').mkdir()
    for name in ['input_review.gd', 'input_bindings_test.gd', 'diagnostics_test.gd']:
        shutil.copyfile(source / 'tests' / name, target / 'tests' / name)
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source.parent, text=True).strip()
    metadata = identity(version, commit)
    (target / 'prototype/version.json').write_text(json.dumps({'version': version, 'prerelease': metadata['channel'] == 'beta', 'tag_prefix': 'SecurityLab-'}), encoding='utf-8')
    for name in ['assets/models/Interior_07_Godot.glb', 'assets/models/Investigation_Environment.glb', 'assets/textures/city-sunset.png', 'scripts/player.gd', 'assets/fonts/NotoSansKR.ttf', 'assets/fonts/OFL.txt', 'assets/fonts/Gaegu-Regular.ttf', 'assets/fonts/Gaegu-OFL.txt', 'LICENSES.txt']:
        destination = target / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / name, destination)
    # Model settings can be copied immediately; extracted image policies must
    # wait until Godot creates their source files during the first import.
    for policy in (source / 'assets/models').glob('*.glb.import'):
        shutil.copyfile(policy, target / 'assets/models' / policy.name)
    project = (source / 'project.godot').read_text(encoding='utf-8')
    project = project.replace('Forward Plus', 'GL Compatibility').replace('"forward_plus"', '"gl_compatibility"')
    project = project.replace('window/stretch/mode="canvas_items"',
                              'window/stretch/mode="canvas_items"\nwindow/stretch/aspect="expand"')
    project = re.sub(r'^config/version="[^"]*"$', 'config/version="' + version + '"', project, flags=re.MULTILINE)
    # Windows builds start in the launcher, which mounts an approved data pack before the game.
    if launcher:
        project = project.replace('run/main_scene="res://prototype/main.tscn"', 'run/main_scene="res://prototype/bootstrap.tscn"')
    (target / 'project.godot').write_text(project, encoding='utf-8')
    executable_preset = '''[preset.0]
name="Windows Prototype"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter="prototype/version.json,prototype/content/*.json,prototype/tests/*.json,prototype/build_info.json,resources/*.json,resources/*.ps1,assets/fonts/OFL.txt,assets/fonts/Gaegu-OFL.txt,LICENSES.txt"
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
application/product_name="Security Lab"
application/file_description="Offline security investigation"
'''.replace('0.1.0.0', '.'.join(map(str, parts(version))))
    (target / 'export_presets.cfg').write_text(executable_preset + '\n' + content_pack.pack_preset(executable_preset), encoding='utf-8')
    # Compat key: which installed executables may run this build's data pack.
    metadata['compat'] = content_pack.compat_key(target, godot_version)
    (target / 'prototype/build_info.json').write_text(json.dumps(metadata), encoding='utf-8')


def configure_texture_compression(target):
    changed = False
    for pattern in ('*.jpg.import', '*.png.import'):
        for policy in (target / 'assets/models').glob(pattern):
            original = policy.read_text(encoding='utf-8')
            compressed = original.replace('compress/mode=0', 'compress/mode=2')
            if compressed != original:
                policy.write_text(compressed, encoding='utf-8')
                changed = True
    return changed


def check(godot, target):
    run([godot, '--headless', '--editor', '--path', str(target), '--import'], target)
    # GLB extraction precedes texture import settings, matching the native
    # build. Reimport only when generated textures still use lossless mode.
    if configure_texture_compression(target):
        run([godot, '--headless', '--editor', '--path', str(target), '--import'], target)
    if os.name == 'nt':
        script = Path(__file__).with_name('godot-diagnostics-windows-test.ps1')
        run(['pwsh', '-NoProfile', '-File', str(script), '-Godot', godot, '-Project', str(target)],
            target, 'NATIVE_DIAGNOSTICS')


def export_pack(godot, target, destination):
    run([godot, '--headless', '--path', str(target), '--export-pack', content_pack.PACK_PRESET, str(destination)], target, timeout=180)
    if not destination.is_file() or destination.stat().st_size < 10_000:
        raise SystemExit('Game-data pack is missing or incomplete.')


def check_content_pack(executable, probe, bundled, probe_version, directory):
    """The executable must mount an approved newer pack once, and roll it back when it never confirmed a stable start."""
    content = Path(directory) / 'content'
    content.mkdir()
    shutil.copyfile(probe, content / 'pending.pck')
    commit = 'f' * 40
    (content / 'pending.json').write_text(json.dumps({
        'version': probe_version, 'commit': commit, 'sha256': hashlib.sha256(probe.read_bytes()).hexdigest(),
        'size': probe.stat().st_size, 'compat': bundled['compat'], 'channel': bundled['channel']}), encoding='utf-8')
    command = [str(executable), '--headless', '--', '--prototype-smoke', '--content-dir=' + str(content)]

    def mounted():
        return [json.loads(line[len('CONTENT_PACK '):]) for line in run(command, directory, 'INVESTIGATION_SMOKE').splitlines()
                if line.startswith('CONTENT_PACK ')]

    first = mounted()
    if not first or first[-1].get('version') != probe_version or first[-1].get('commit') != commit:
        raise SystemExit('The executable did not mount the approved game-data pack.')
    active = content / 'active.json'
    record = json.loads(active.read_text(encoding='utf-8'))
    # A pack that proved stable keeps being used on the next start ...
    record['pending_boot'] = False
    active.write_text(json.dumps(record), encoding='utf-8')
    if not mounted():
        raise SystemExit('A confirmed game-data pack was not used on the next start.')
    # ... while one that never finished starting is dropped and remembered as bad.
    record['pending_boot'] = True
    active.write_text(json.dumps(record), encoding='utf-8')
    if mounted():
        raise SystemExit('An unconfirmed game-data pack was not rolled back.')
    if commit not in (content / 'rejected.json').read_text(encoding='utf-8'):
        raise SystemExit('A rolled-back game-data pack was not remembered as rejected.')
    print('Game-data pack mounts and rolls back inside the exported EXE.')


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
    version = build_version(root / 'godot')
    output = Path(args.output or ('prototype-dist/' + tag(version) + '.exe')).resolve()
    with tempfile.TemporaryDirectory(prefix='security-lab-prototype-') as directory:
        target = Path(directory)
        godot_version = '.'.join(subprocess.check_output([godot, '--version'], text=True).split('.')[:3])
        stage(root / 'godot', target, godot_version)
        check(godot, target)
        baked_metadata = (target / "prototype/build_info.json").read_text(encoding="utf-8")
        if args.check_only:
            run([godot, '--headless', '--path', str(target), '--', '--prototype-smoke'],
                target, 'INVESTIGATION_SMOKE')
            return
        if os.name != 'nt':
            raise SystemExit('Build and verify the Windows EXE on Windows; use --check-only elsewhere.')
        output.parent.mkdir(parents=True, exist_ok=True)
        run([godot, '--headless', '--path', str(target), '--export-release', 'Windows Prototype', str(output)],
            target, timeout=180)
        if not output.is_file() or output.stat().st_size < 1_000_000:
            raise SystemExit('Windows executable is missing or incomplete.')
        # The same sources without the heavy assets, plus a copy that claims a newer version
        # so the exported executable can be shown to mount and roll back a pack.
        pack = output.with_name('SecurityLabContent.pck')
        export_pack(godot, target, pack)
        info_file = target / 'prototype/build_info.json'
        original_info = info_file.read_text(encoding='utf-8')
        major, minor, patch, _ = parts(version)
        probe_version = '%d.%d.%d' % (major, minor, patch + 1)
        info_file.write_text(json.dumps(dict(json.loads(original_info), version=probe_version, commit='f' * 40)), encoding='utf-8')
        probe_directory = Path(tempfile.mkdtemp(prefix='security-lab-probe-'))
        probe = probe_directory / 'probe.pck'
        export_pack(godot, target, probe)
        info_file.write_text(original_info, encoding='utf-8')
    # Run only the EXE in a separate directory after the staged sources are deleted.
    with tempfile.TemporaryDirectory(prefix='security-lab-exe-only-') as directory:
        executable = Path(directory) / output.name
        shutil.copyfile(output, executable)
        run([str(executable), '--headless', '--', '--prototype-smoke'],
            directory, 'INVESTIGATION_SMOKE')
        print('Standalone EXE scene, save and reload passed.')
        run([str(executable), '--headless', '--', '--prototype-smoke', '--prototype-input-review'], directory, 'INPUT_REVIEW')
        run([str(executable), '--headless', '--', '--prototype-services'],
            directory, 'INVESTIGATION_SERVICES')
        print('Exported beta diagnostics, save and update identity passed.')
        check_content_pack(executable, probe, json.loads(baked_metadata), probe_version, directory)
        if args.rendered_check:
            captures = output.parent / 'ui'
            # CI uses a software GPU: cold shader setup and all landscape /
            # portrait captures can exceed three minutes with the furnished map.
            run([str(executable), '--audio-driver', 'Dummy', '--', '--prototype-smoke',
                 '--prototype-capture-dir=' + str(captures)], directory, 'INVESTIGATION_SMOKE', timeout=300)
            expected = ['01-briefing', '02-dialogue', '03-terminal', '04-messenger', '05-notes', '06-field', '07-settings']
            if any(not (captures / (name + '.png')).is_file() for name in expected):
                raise SystemExit('Exported Windows UI captures are incomplete.')
            print('Rendered Windows EXE UI and interaction passed.')
    (output.parent / 'build_info.json').write_text(baked_metadata, encoding='utf-8')
    shutil.rmtree(probe_directory, ignore_errors=True)
    for artifact in [output, pack]:
        artifact_digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
        artifact.with_suffix('.sha256').write_text(artifact_digest + '  ' + artifact.name + '\n', encoding='utf-8')
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    print('PROTOTYPE_PACK', json.dumps({'file': pack.name, 'bytes': pack.stat().st_size}))
    print('PROTOTYPE_EXE', json.dumps({'file':output.name, 'bytes':output.stat().st_size, 'sha256':digest}))


if __name__ == '__main__':
    main()
