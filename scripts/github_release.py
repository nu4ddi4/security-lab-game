"""Small GitHub API helper shared by verified Godot release publication."""
import json
import subprocess


def github(path, missing_ok=False):
    result = subprocess.run(['gh', 'api', path], capture_output=True, text=True, encoding='utf-8')
    if result.returncode:
        if missing_ok and 'HTTP 404' in result.stderr:
            return None
        raise RuntimeError(result.stderr)
    return json.loads(result.stdout)
