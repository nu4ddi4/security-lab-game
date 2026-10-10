"""Exercise real HTTPRequest, hash/save gates and detached helper launch on loopback."""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import platform
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True)
    parser.add_argument('--results', default='godot/tests/results/updater-network.json')
    args = parser.parse_args()
    payload = b'MZ' + b'fixture payload; never executed'.ljust(4094, b'\0')
    server_modes = ['no-consent', 'declined', 'dialog-dismiss', 'dialog-close', 'dialog-confirm', 'ready', 'redirect-ready', 'hash-failure', 'size-failure', 'channel-failure', 'redirect-failure', 'oversized-manifest', 'no-local-option', 'disabled', 'helper-launch', 'save-failure', 'health-validation', 'bad-save-health', 'retry-after-failure', 'preview-newer-stable', 'preview-other-down', 'preview-off']
    skipped = []
    if platform.system() != 'Windows':
        server_modes.remove('helper-launch')
        skipped.append('helper-launch: requires Windows PowerShell')
    rows = []
    with tempfile.TemporaryDirectory(prefix='security-lab-update-http-') as temporary:
        project = Path(temporary)
        for name in ['scripts', 'resources', 'prototype']:
            shutil.copytree(Path('godot') / name, project / name, ignore=shutil.ignore_patterns('results'))
        (project / 'assets/fonts').mkdir(parents=True)
        shutil.copyfile('godot/assets/fonts/NotoSansKR.ttf', project / 'assets/fonts/NotoSansKR.ttf')
        identity = {'schema': 1, 'app_id': 'security-lab-beta', 'platform': 'windows-x86_64',
                    'install_layout': 1, 'channel': 'beta', 'version': '0.8.0-beta.1',
                    'commit': 'a' * 40, 'updates_default': True,
                    'manifest_url': 'https://github.com/nu4ddi4/security-lab-game/releases/download/beta-channel-beta/update.json'}
        (project / 'prototype/build_info.json').write_text(json.dumps(identity), encoding='utf-8')
        shutil.copyfile('tests/native/network_fixture.gd', project / 'fixture.gd')
        (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Security Lab · Native"\n', encoding='utf-8')
        subprocess.run([args.godot, '--headless', '--editor', '--path', str(project), '--import'], check=True, capture_output=True, timeout=30)
        for mode in server_modes:
            requests = []

            class Handler(BaseHTTPRequestHandler):
                def do_GET(self):
                    requests.append(self.path)
                    if mode == 'retry-after-failure' and self.path == '/beta/update.json' and requests.count(self.path) == 1:
                        self.send_error(500); return
                    if self.path in ['/stable/update.json', '/stable/SecurityLabSetup.exe'] and mode == 'preview-other-down':
                        self.send_error(404); return
                    if self.path == '/stable/update.json':
                        manifest = {'schema': 1, 'app_id': 'security-lab-beta', 'platform': 'windows-x86_64', 'install_layout': 1, 'channel': 'stable', 'version': '0.9.0', 'commit': 'c' * 40, 'sha256': hashlib.sha256(payload).hexdigest(), 'exe_sha256': 'a' * 64, 'size': len(payload), 'installer_url': f'http://127.0.0.1:{self.server.server_port}/stable/SecurityLabSetup.exe'}
                        body = json.dumps(manifest).encode()
                        self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body); return
                    if mode == 'redirect-failure':
                        self.send_response(302); self.send_header('Location', 'https://evil.example/update.json'); self.end_headers(); return
                    if mode == 'redirect-ready' and self.path == '/beta/update.json':
                        self.send_response(302); self.send_header('Location', f'http://127.0.0.1:{self.server.server_port}/redirect-manifest'); self.end_headers(); return
                    if self.path in ['/beta/update.json', '/redirect-manifest']:
                        manifest = {'schema': 1, 'app_id': 'security-lab-beta', 'platform': 'windows-x86_64', 'install_layout': 1, 'channel': 'dev' if mode == 'channel-failure' else 'beta', 'version': '0.8.1-beta.1', 'commit': 'a' * 40, 'sha256': 'b' * 64 if mode == 'hash-failure' else hashlib.sha256(payload).hexdigest(), 'exe_sha256': 'a' * 64, 'size': len(payload) + (1 if mode == 'size-failure' else 0), 'installer_url': f'http://127.0.0.1:{self.server.server_port}/beta/SecurityLabSetup.exe'}
                        body = b'x' * 20000 if mode == 'oversized-manifest' else json.dumps(manifest).encode()
                    elif self.path in ['/beta/SecurityLabSetup.exe', '/stable/SecurityLabSetup.exe']: body = payload
                    else: self.send_error(404); return
                    self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)

                def log_message(self, *_): pass

            server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
            command = [args.godot, '--headless', '--path', str(project), '--script', 'res://fixture.gd', '--', '--force-update-check', f'--update-url=http://127.0.0.1:{server.server_port}/beta/update.json', f'--fixture-mode={mode}']
            if mode.startswith('preview-'): command.append(f'--update-url-other=http://127.0.0.1:{server.server_port}/stable/update.json')
            if mode != 'no-local-option': command.append('--allow-local-update-url')
            if mode == 'disabled': command.append('--disable-updates')
            try:
                run = subprocess.run(command, text=True, encoding='utf-8', errors='replace', capture_output=True, timeout=30)
            finally: server.shutdown(); server.server_close(); thread.join()
            lines = [line[len('NATIVE_UPDATE_NETWORK '):] for line in run.stdout.splitlines() if line.startswith('NATIVE_UPDATE_NETWORK ')]
            if run.returncode or not lines or not json.loads(lines[-1])['passed'] or 'SCRIPT ERROR:' in run.stderr:
                raise SystemExit(run.stdout + run.stderr)
            if mode in ['disabled', 'no-local-option'] and requests:
                raise SystemExit('Disabled/disallowed updater sent a request')
            if mode in ['channel-failure', 'no-consent', 'declined', 'dialog-dismiss', 'dialog-close'] and '/beta/SecurityLabSetup.exe' in requests:
                raise SystemExit('Unapproved or cross-channel manifest triggered download')
            if mode in ['ready', 'redirect-ready', 'dialog-confirm', 'preview-other-down'] and requests.count('/beta/SecurityLabSetup.exe') != 1:
                raise SystemExit('Approved update did not download exactly once')
            if mode in ['preview-newer-stable', 'preview-off']:
                if requests.count('/stable/SecurityLabSetup.exe') != 1 or '/beta/SecurityLabSetup.exe' in requests:
                    raise SystemExit('The newer stable release was not the only download')
            if mode == 'preview-off' and '/beta/update.json' in requests:
                raise SystemExit('Beta preview off still read the beta channel')
            if mode == 'retry-after-failure' and requests.count('/beta/update.json') != 2:
                raise SystemExit('A failed check was not repeatable')
            if not mode.startswith('preview-') and any(path.startswith('/stable/') for path in requests):
                raise SystemExit('A single-channel check read another channel')
            row = json.loads(lines[-1]); row['requests'] = requests; rows.append(row)
    destination = Path(args.results); destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps({'passed': True, 'cases': rows, 'skipped': skipped}, indent=2, ensure_ascii=False), encoding='utf-8')
    print('NATIVE_UPDATE_NETWORK_TEST', json.dumps({'passed': True, 'cases': len(rows), 'skipped': skipped}))


if __name__ == '__main__': main()
