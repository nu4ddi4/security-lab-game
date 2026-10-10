import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUITES = json.loads((ROOT / 'tests/suites.json').read_text(encoding='utf-8'))
TEST_DIRECTORIES = ['godot/tests', 'godot/tests/fixtures', 'godot/prototype/tests', 'tests/ci', 'tests/native']


def test_files_on_disk():
    found = set()
    for directory in TEST_DIRECTORIES:
        for path in (ROOT / directory).iterdir():
            if path.is_file() and path.suffix not in {'.uid', '.pyc'}:
                found.add(path.relative_to(ROOT).as_posix())
    return found


class SuiteCoverageTests(unittest.TestCase):
    def test_every_test_file_belongs_to_exactly_one_suite(self):
        listed = [path for paths in SUITES.values() for path in paths]
        self.assertEqual(sorted(path for path in set(listed) if listed.count(path) > 1), [], 'a test is listed in more than one suite')
        self.assertEqual(sorted(test_files_on_disk() - set(listed)), [], 'add new test files to tests/suites.json')
        self.assertEqual([path for path in listed if not (ROOT / path).is_file()], [], 'tests/suites.json lists a missing file')

    def test_runner_suites_are_declared(self):
        spec = importlib.util.spec_from_file_location('godot_checks', ROOT / 'scripts/ci-godot-test.py')
        checks = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(checks)
        self.assertLessEqual(set(checks.SUITES), set(SUITES))


if __name__ == '__main__':
    unittest.main()
