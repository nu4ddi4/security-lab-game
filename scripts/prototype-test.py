"""Compatibility entry for focused, asset-free investigation checks."""
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location('godot_checks', Path(__file__).with_name('ci-godot-test.py'))
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)

if __name__ == '__main__':
    checks.main()
