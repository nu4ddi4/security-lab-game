"""Export a signed, self-contained prototype APK and a matching emulator QA APK."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import urllib.request
import zipfile

from release_version import android_code, build_version, channel, tag
from release_backfill import unchanged_game

PACKAGE = 'com.nu4ddi4.securitylab.prototype'
# AOSP publishes these development-only test keys. Using the pinned certificate
# keeps prototype APK upgrades installable across runners without a secret key.
# Main and beta intentionally share this public key during pre-launch testing.
TEST_KEY_SOURCE = 'https://raw.githubusercontent.com/aosp-mirror/platform_build/android-15.0.0_r1/target/product/security/'
TEST_KEY_HASHES = {
    'testkey.pk8': '495675d32e89a149d5abe191f4e9c0e218b9068714e9b53a7c91e164a0741a23',
    'testkey.x509.pem': 'a4384ba815b9499a5ce349b4e33c1755278873fe2eac150a068823f526e6dbde',
}


def version_code(version):
    return android_code(version)


def make_test_keystore(directory):
    for name, digest in TEST_KEY_HASHES.items():
        data = urllib.request.urlopen(TEST_KEY_SOURCE + name, timeout=30).read()
        if hashlib.sha256(data).hexdigest() != digest:
            raise ValueError('AOSP prototype signing material differs from its pinned hash')
        (directory / name).write_bytes(data)
    pem = directory / 'testkey.pem'
    subprocess.run(['openssl', 'pkcs8', '-inform', 'DER', '-in', str(directory / 'testkey.pk8'),
                    '-nocrypt', '-out', str(pem)], check=True, capture_output=True)
    keystore = directory / 'prototype-test.p12'
    subprocess.run(['openssl', 'pkcs12', '-export', '-in', str(directory / 'testkey.x509.pem'),
                    '-inkey', str(pem), '-name', 'androiddebugkey', '-out', str(keystore),
                    '-passout', 'pass:android'], check=True, capture_output=True)
    return keystore


def configure_editor(sdk, java):
    directory = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'godot'
    settings = directory / 'editor_settings-4.7.tres'
    text = settings.read_text(encoding='utf-8')
    for key, value in {'export/android/android_sdk_path': str(sdk), 'export/android/java_sdk_path': str(java)}.items():
        assignment = key + '=' + json.dumps(value)
        if re.search('^' + re.escape(key) + '=.*$', text, re.MULTILINE):
            text = re.sub('^' + re.escape(key) + '=.*$', assignment, text, flags=re.MULTILINE)
        else:
            text += '\n' + assignment + '\n'
    settings.write_text(text, encoding='utf-8')


def preset(version, keystore, qa=False, alias="androiddebugkey", password="android"):
    signing = "debug" if qa or channel(version) == "beta" else "release"
    return '''[preset.0]
name="Android Prototype"
platform="Android"
runnable=true
export_filter="all_resources"
include_filter="prototype/version.json,prototype/content/*.json,prototype/tests/*.json,prototype/build_info.json,resources/*.json,resources/*.ps1,assets/fonts/OFL.txt,assets/fonts/Gaegu-OFL.txt,LICENSES.txt"
exclude_filter="prototype/tests/results/*"
export_path=""
script_export_mode=2

[preset.0.options]
gradle_build/use_gradle_build=false
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=true
version/code={code}
version/name="{version}"
package/unique_name="{package}"
package/name="{display_name}"
package/signed=true
keystore/{signing}={keystore}
keystore/{signing}_user={alias}
keystore/{signing}_password={password}
screen/immersive_mode=true
permissions/internet=true
command_line/extra_args="{args}"
'''.format(code=version_code(version), version=version, package=PACKAGE, display_name='Security Lab Beta' if channel(version) == 'beta' else 'Security Lab',
           keystore=json.dumps(str(keystore)), signing=signing, alias=json.dumps(alias), password=json.dumps(password), args='--audio-driver Dummy -- --prototype-smoke --prototype-capture-dir=user://qa-ui' if qa else '')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', default=os.environ.get('SECURITY_LAB_GODOT_CONSOLE', 'godot'))
    parser.add_argument('--output-dir', default='prototype-android-dist')
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('prototype_build', Path(__file__).with_name('prototype-build.py'))
    build = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(build)
    godot = shutil.which(args.godot) or str(Path(args.godot).resolve())
    if not subprocess.check_output([godot, '--version'], text=True).startswith('4.7.2.stable'):
        raise SystemExit('Godot 4.7.2 stable is required.')
    root = Path(__file__).resolve().parents[1]
    version = build_version(root / 'godot')
    pipeline_sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    source_sha = os.environ.get('SECURITY_LAB_RELEASE_SOURCE_SHA') or pipeline_sha
    if source_sha != pipeline_sha and not unchanged_game(source_sha):
        raise ValueError('Cannot append an APK with different game resources to a published version')
    sdk = Path(os.environ.get('ANDROID_HOME', os.environ.get('ANDROID_SDK_ROOT', '')))
    java = Path(os.environ['JAVA_HOME'])
    signer = sdk / 'build-tools/35.0.1/apksigner'
    if not signer.is_file():
        raise SystemExit('Android build-tools 35.0.1 are required.')
    output = Path(args.output_dir).resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='security-lab-android-') as temporary:
        directory = Path(temporary)
        target = directory / 'project'
        target.mkdir()
        # Data packs are a Windows feature: Android keeps the game scene as its main scene.
        build.stage(root / 'godot', target, '.'.join(subprocess.check_output([godot, '--version'], text=True).split('.')[:3]), launcher=False)
        identity_path = target / 'prototype/build_info.json'
        identity = json.loads(identity_path.read_text(encoding='utf-8'))
        identity.pop('compat', None)
        identity['platform'] = 'android'
        identity['commit'] = source_sha
        identity_path.write_text(json.dumps(identity), encoding='utf-8')
        (target / 'android').mkdir()
        shutil.copyfile(root / 'godot/android/app-icon.svg', target / 'android/app-icon.svg')
        project = (target / 'project.godot').read_text(encoding='utf-8')
        project = project.replace('[application]', '[application]\nconfig/icon="res://android/app-icon.svg"')
        project = project.replace('textures/vram_compression/import_etc2_astc=false', 'textures/vram_compression/import_etc2_astc=true')
        project += '\n[input_devices]\npointing/emulate_touch_from_mouse=false\npointing/emulate_mouse_from_touch=true\n'
        project = project.replace('window/stretch/mode="canvas_items"', 'window/stretch/mode="canvas_items"\nwindow/handheld/orientation=6')
        (target / 'project.godot').write_text(project, encoding='utf-8')
        build.check(godot, target)
        configure_editor(sdk, java)
        keystore = make_test_keystore(directory)
        alias, password = 'androiddebugkey', 'android'
        certificate = subprocess.check_output(['openssl', 'x509', '-in', str(directory / 'testkey.x509.pem'), '-outform', 'DER'])
        cert_hash = hashlib.sha256(certificate).hexdigest()
        for qa in [False, True]:
            name = tag(version) + ('-qa' if qa else '') + '.apk'
            apk = output / name
            (target / 'export_presets.cfg').write_text(preset(version, keystore, qa, alias, password), encoding='utf-8')
            build.run([godot, '--headless', '--path', str(target), '--export-release' if channel(version) == 'stable' and not qa else '--export-debug', 'Android Prototype', str(apk)], target, timeout=180)
            certificates = subprocess.check_output([str(signer), 'verify', '--print-certs', str(apk)], text=True)
            if 'Signer #1 certificate SHA-256 digest: ' + cert_hash not in certificates:
                raise ValueError('APK certificate differs from the pinned public signing key')
            with zipfile.ZipFile(apk) as bundle:
                print('APK_SIZE', json.dumps({'file': name, 'compressed': apk.stat().st_size,
                      'uncompressed': sum(info.file_size for info in bundle.infolist()),
                      'largest': [(info.filename, info.file_size) for info in sorted(bundle.infolist(), key=lambda info: info.file_size, reverse=True)[:5]]}), flush=True)
                for abi in ['arm64-v8a', 'x86_64']:
                    if 'lib/' + abi + '/libgodot_android.so' not in bundle.namelist():
                        raise ValueError('Missing APK architecture: ' + abi)
            digest = hashlib.sha256(apk.read_bytes()).hexdigest()
            apk.with_suffix('.sha256').write_text(digest + '  ' + name + '\n', encoding='utf-8')
            print('PROTOTYPE_APK', json.dumps({'file': name, 'versionCode': version_code(version), 'sha256': digest}))
        record = dict(identity, pipeline_commit=pipeline_sha, signing='public-aosp-test', certificate_sha256=cert_hash)
        (output / 'android-build-info.json').write_text(json.dumps(record), encoding='utf-8')


if __name__ == '__main__':
    main()
