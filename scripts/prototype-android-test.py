"""Install, run, update and relaunch APKs on the active Android emulator."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time

PACKAGE = 'com.nu4ddi4.securitylab.prototype'
ACTIVITY = PACKAGE + '/com.godot.game.GodotApp'


def adb(*args, binary=False):
    return subprocess.check_output(['adb', *args], text=not binary, timeout=30)


def wait_for(marker, timeout=75):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        logs = adb('logcat', '-d', '-v', 'brief')
        if 'SCRIPT ERROR:' in logs or 'FATAL EXCEPTION' in logs:
            raise RuntimeError(logs[-16000:])
        for line in logs.splitlines():
            if marker + ' ' in line:
                return json.loads(line.split(marker + ' ', 1)[1])
        time.sleep(1)
    raise TimeoutError('APK did not report ' + marker + '\n' + logs[-16000:])


def launch():
    adb('logcat', '-c')
    adb('shell', 'am', 'start', '-W', '-n', ACTIVITY)


def read_save():
    text = adb('shell', 'run-as', PACKAGE, 'cat', 'files/investigation/save.json')
    return json.loads(text)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', default='prototype-android-dist')
    args = parser.parse_args()
    directory = Path(args.directory)
    metadata = json.loads(Path('godot/prototype/version.json').read_text())
    stem = 'SecurityLab-proto-' + metadata['version']
    apk, qa = directory / (stem + '.apk'), directory / (stem + '-qa.apk')
    adb('wait-for-device')
    adb('install', '-r', str(apk))
    adb('shell', 'pm', 'clear', PACKAGE)
    launch()
    ready = wait_for('PROTOTYPE_READY')
    if ready.get('day') != 1:
        raise ValueError('Fresh Android investigation did not start on day 1')
    time.sleep(2)
    (directory / 'android-startup.png').write_bytes(adb('exec-out', 'screencap', '-p', binary=True))
    # Android suspends apps without a desktop close request. Ensure this saves.
    adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
    time.sleep(1)
    original = read_save()
    adb('shell', 'am', 'force-stop', PACKAGE)
    # Only baked command-line arguments differ in the QA APK. Install it over
    # the production APK to exercise certificate compatibility and save retention.
    adb('install', '-r', str(qa))
    launch()
    result = wait_for('INVESTIGATION_SMOKE')
    if not result.get('passed') or not result.get('mobile') or not result.get('touchDefault') or not result.get('keyboardDetected'):
        raise ValueError('Android gameplay/input smoke failed: ' + json.dumps(result))
    if read_save() != original:
        raise ValueError('Android package update changed the real investigation save')
    (directory / 'android-smoke.json').write_text(json.dumps(result), encoding='utf-8')
    adb('shell', 'am', 'force-stop', PACKAGE)
    adb('install', '-r', str(apk))
    launch()
    resumed = wait_for('PROTOTYPE_READY')
    if resumed.get('day') != ready.get('day') or read_save() != original:
        raise ValueError('Reinstall/relaunch did not retain the original save')
    print('ANDROID_APK_VERIFIED', json.dumps({'passed': True, 'version': metadata['version'],
          'install': True, 'render': True, 'touch': True, 'keyboard': True, 'updateRetainsSave': True, 'relaunch': True}))
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as summary:
            summary.write('Android APK: installation, rendering, touch + keyboard, save retention and relaunch passed.\n')


if __name__ == '__main__':
    main()
