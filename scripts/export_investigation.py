"""Export the Investigation_Environment collection from its Blender master.

Append assets/authoring/Security_Lab_Investigation.blend into Interior 07 for
placement work, then export this collection only. Interior_07_Godot.glb remains
the losslessly preserved base, including Native decoration corrections.
"""
from pathlib import Path
import bpy

root = Path(__file__).resolve().parents[1]
collection = bpy.data.collections['Investigation_Environment']
bpy.ops.object.select_all(action='DESELECT')
for obj in collection.all_objects:
    obj.hide_set(False)
    obj.select_set(True)
bpy.ops.export_scene.gltf(
    filepath=str(root / 'godot/assets/models/Investigation_Environment.glb'),
    export_format='GLB', use_selection=True, use_active_scene=True,
    export_extras=True, export_apply=True, export_animations=False,
    export_cameras=False, export_lights=False, export_shared_accessors=True,
)
print('Investigation overlay exported; Interior 07 base untouched.')
