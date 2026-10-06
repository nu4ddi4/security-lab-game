"""Configure extracted native textures after the first headless Godot import.

Extracted JPG/PNG files are reproducible derivatives of the embedded GLB images.
Check in their import settings, not a second copy of the image data.
"""
from pathlib import Path
root=Path('godot/assets/models')
for path in [*root.glob('*.jpg.import'), *root.glob('*.png.import')]:
    text=path.read_text(encoding='utf-8')
    text=text.replace('compress/mode=0','compress/mode=2')
    path.write_text(text,encoding='utf-8')
print('Native VRAM compression configured')
