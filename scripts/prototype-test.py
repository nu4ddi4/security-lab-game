"""Run the bounded Godot investigation checks with the pinned editor CLI."""
import argparse
import json
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--godot', default=os.environ.get('SECURITY_LAB_GODOT_CONSOLE', 'godot'))
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
version = subprocess.run([args.godot, '--version'], text=True, capture_output=True, check=True)
if not version.stdout.strip().startswith('4.7.2.stable'):
    raise SystemExit('Godot 4.7.2 stable CLI is required; use --godot PATH.')
commands = [
    (['--headless', '--path', 'godot', '--script', 'res://prototype/tests/unit.gd'], 'INVESTIGATION_UNIT'),
    (['--headless', '--path', 'godot', '--script', 'res://prototype/tests/services.gd'], 'INVESTIGATION_SERVICES'),
    (['--headless', '--path', 'godot', '--', '--prototype-smoke'], 'INVESTIGATION_SMOKE'),
]
for command, marker in commands:
    result = subprocess.run([args.godot, *command], cwd=root, text=True,
                            encoding='utf-8', errors='replace', capture_output=True, timeout=90)
    output = result.stdout + result.stderr
    summaries = [line[len(marker)+1:] for line in output.splitlines() if line.startswith(marker+' ')]
    if result.returncode or 'SCRIPT ERROR:' in output or 'ERROR:' in output or not summaries:
        print(output)
        raise SystemExit(result.returncode or 1)
    summary = json.loads(summaries[-1])
    print(marker, json.dumps(summary, ensure_ascii=False))
    if not summary.get('passed'):
        raise SystemExit(1)
