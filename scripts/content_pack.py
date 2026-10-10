"""The downloadable game-data pack: which executables can run it and how it is exported.

A pack replaces scripts, scenes and content inside the installed executable. That is
only safe while everything the executable decided at startup is unchanged: the engine,
project settings, export options, the registered `class_name` scripts and the large
assets that only ship inside the executable. The compat key hashes exactly those
inputs, so the pipeline needs no manual "executable changed" decision: when the key
differs from the installed build, the update falls back to the full installer.
"""
import hashlib
from pathlib import Path
import re

HEAVY_EXCLUDE = 'assets/models/*,assets/textures/*,assets/fonts/*.ttf'
PACK_PRESET = 'Windows Content'


def _digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def class_registry(root):
    """Every `class_name` script outside tests, as sorted `Name=path` lines."""
    entries = []
    for path in sorted(Path(root).rglob('*.gd')):
        relative = path.relative_to(root).as_posix()
        if relative.startswith('tests/') or '/tests/' in relative:
            continue
        for name in re.findall(r'^class_name\s+(\w+)', path.read_text(encoding='utf-8'), re.MULTILINE):
            entries.append(name + '=res://' + relative)
    return entries


def normalized_project(text):
    # The version changes with every release; nothing else may differ.
    return re.sub(r'^config/version="[^"]*"\n?', '', text, flags=re.MULTILINE)


def normalized_presets(text):
    return re.sub(r'application/(file|product)_version="[^"]*"', 'application/\\1_version=""', text)


def compat_key(staged, godot_version):
    """Compat key of a staged project (before Godot has imported anything)."""
    staged = Path(staged)
    assets = [path.relative_to(staged).as_posix() + ':' + _digest(path)
              for path in sorted((staged / 'assets').rglob('*')) if path.is_file()]
    parts = [
        'godot=' + godot_version,
        'project=' + normalized_project((staged / 'project.godot').read_text(encoding='utf-8')),
        'presets=' + normalized_presets((staged / 'export_presets.cfg').read_text(encoding='utf-8')),
        'classes=' + '\n'.join(class_registry(staged)),
        'assets=' + '\n'.join(assets),
    ]
    return hashlib.sha256('\n--\n'.join(parts).encode('utf-8')).hexdigest()


def pack_preset(executable_preset):
    """The executable preset without the heavy assets, exported with --export-pack."""
    preset = executable_preset.replace('[preset.0]', '[preset.1]').replace('[preset.0.options]', '[preset.1.options]')
    preset = preset.replace('name="Windows Prototype"', 'name="' + PACK_PRESET + '"')
    preset = re.sub(r'^exclude_filter="([^"]*)"$', lambda match: 'exclude_filter="' + match.group(1) + ',' + HEAVY_EXCLUDE + '"',
                    preset, flags=re.MULTILINE)
    return preset
