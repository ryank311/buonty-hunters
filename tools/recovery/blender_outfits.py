"""Submit each generated batch through Blender MCP; export with tools/dev."""
import bpy
from mathutils import Vector

ROOT = '__ROOT__'
NAMES = []

for name in NAMES:
    bpy.ops.wm.read_homefile(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=ROOT + '/previous/recovery/staging/outfits/' + name + '.gltf')
    # Keep exact native origins. These parts attach to bones rather than floors.
    for image in bpy.data.images:
        if image.packed_file is None and image.filepath:
            image.pack()
    bpy.context.scene['recovered_attachment_origin'] = True
    bpy.context.scene['scale_metres_per_source_unit'] = .1
    for window in bpy.context.window_manager.windows:
        for area in window.screen.areas:
            if area.type == 'VIEW_3D':
                area.spaces.active.region_3d.view_location = Vector((0, 0, 0))
                area.spaces.active.region_3d.view_distance = .65
    bpy.ops.wm.save_as_mainfile(filepath=ROOT + '/art/blender/' + name + '.blend')
    print('Saved ' + name)
