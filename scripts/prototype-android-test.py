"""Install, run, update and relaunch APKs on the active Android emulator."""
import argparse
import io
import json
import os
from pathlib import Path
import subprocess
import time
from PIL import Image

PACKAGE = 'com.nu4ddi4.securitylab.prototype'


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
    # Godot 4.7 keeps its rendering activity private; launch the exported entry
    # selected by Android, exactly as tapping the installed app icon does.
    component = adb('shell', 'cmd', 'package', 'resolve-activity', '--brief',
                    '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.LAUNCHER',
                    '-p', PACKAGE).strip().splitlines()[-1]
    if not component.startswith(PACKAGE + '/'):
        raise ValueError('Android could not resolve the installed app launcher: ' + component)
    adb('shell', 'am', 'start', '-W', '-n', component)


def read_save():
    text = adb('shell', 'run-as', PACKAGE, 'cat', 'files/investigation/save.json')
    return json.loads(text)


def rendered_image(data):
    with Image.open(io.BytesIO(data)) as image:
        sample = image.convert('RGB').resize((160, 90))
        colors = sample.getcolors(maxcolors=16)
        return colors is None and any(high - low > 32 for low, high in sample.getextrema())


def capture_startup(directory):
    # The render loop can precede Android's first surface presentation. Wait for
    # actual visible pixels, so a black screenshot cannot count as rendered UI.
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        data = adb('exec-out', 'screencap', '-p', binary=True)
        (directory / 'android-startup.png').write_bytes(data)
        if rendered_image(data):
            return
        time.sleep(1)
    raise ValueError('Android did not present the game screen')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', default='prototype-android-dist')
    args = parser.parse_args()
    directory = Path(args.directory)
    metadata = json.loads(Path('godot/prototype/version.json').read_text())
    stem = 'SecurityLab-proto-' + metadata['version']
    apk, qa = directory / (stem + '.apk'), directory / (stem + '-qa.apk')
    adb('wait-for-device')
    print('ANDROID_STORAGE', adb('shell', 'df', '-h', '/data').strip(), flush=True)
    # Avoid Android's one-time system fullscreen tutorial covering review images.
    adb('shell', 'settings', 'put', 'secure', 'immersive_mode_confirmations', 'confirmed')
    adb('install', '-r', str(apk))
    adb('shell', 'pm', 'clear', PACKAGE)
    launch()
    ready = wait_for('PROTOTYPE_READY')
    if ready.get('day') != 1:
        raise ValueError('Fresh Android investigation did not start on day 1')
    wait_for('PROTOTYPE_FRAME_READY')
    capture_startup(directory)
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
    captures = directory / 'ui'
    captures.mkdir(exist_ok=True)
    for name in ['01-briefing','02-dialogue','03-terminal','04-messenger','05-notes','06-field','07-settings']:
        data = adb('exec-out', 'run-as', PACKAGE, 'cat', 'files/qa-ui/' + name + '.png', binary=True)
        if not data.startswith(b'\x89PNG\r\n\x1a\n'):
            raise ValueError('Missing Android rendered UI capture: ' + name)
        (captures / (name + '.png')).write_bytes(data)
        if not rendered_image(data):
            raise ValueError('Android rendered an empty UI capture: ' + name)
    if result.get('platform') != 'Android' or not result.get('passed') or not result.get('mobile') or not result.get('touchDefault') or not result.get('keyboardDetected'):
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
