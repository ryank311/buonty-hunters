"""Submit through Blender MCP after replacing NAMES with a bounded list of assets.

The interchange files come from prepare_characters.py. All Blender I/O uses its
native glTF importer and save operator. Final GLBs use tools/dev blender export.
"""
import bpy
import json
from mathutils import Vector, Euler

ROOT = '/Users/king/socom'
NAMES = ['recovered_char_alban_informant']

for name in NAMES:
    bpy.ops.wm.read_homefile(use_empty=True)
    # The glTF importer converts seconds to frames using the current scene rate.
    bpy.context.scene.render.fps = 30
    bpy.context.scene.render.fps_base = 1.0
    window = bpy.context.window_manager.windows[0]
    area = next(a for a in window.screen.areas if a.type == 'VIEW_3D')
    with bpy.context.temp_override(window=window, area=area):
        bpy.ops.import_scene.gltf(filepath=ROOT+'/previous/recovery/staging/characters/'+name+'.gltf',
                                  import_pack_images=False, bone_heuristic='BLENDER',
                                  guess_original_bind_pose=False, disable_bone_shape=True)
    rigs = [obj for obj in bpy.data.objects if obj.type == 'ARMATURE']
    if len(rigs) != 1:
        raise ValueError('Expected one armature: '+name)
    rig = rigs[0]
    for image in bpy.data.images:
        if image.source == 'FILE':
            image.filepath = bpy.path.relpath(image.filepath, start=ROOT+'/art/blender')
    # glTF import adds NLA strips for browsing. Export actions individually and
    # start in a representative stand pose, with no stacked NLA playback.
    if rig.animation_data:
        for track in list(rig.animation_data.nla_tracks):
            rig.animation_data.nla_tracks.remove(track)
        for action in bpy.data.actions:
            action.use_fake_user = True
            # Float seconds can put an end key just below its integral 30 Hz
            # frame. Snap before the exporter chooses the action's bake range.
            for curve in action.fcurves:
                for key in curve.keyframe_points:
                    key.co.x = round(key.co.x)
                curve.update()
            action.use_frame_range = True
            action.frame_start = 0
            action.frame_end = max(1, round(action.curve_frame_range[1]))
        stand = next((a for a in bpy.data.actions if a.name == 'seal_stand'), None)
        if stand:
            rig.animation_data.action = stand
            if stand.slots:
                rig.animation_data.action_slot = stand.slots[0]
    bpy.context.scene.render.fps = 30
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    objects = [obj for obj in bpy.data.objects if obj.type == 'MESH']
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    low = Vector([min(p[i] for p in points) for i in range(3)])
    high = Vector([max(p[i] for p in points) for i in range(3)])
    for window in bpy.context.window_manager.windows:
        for area in window.screen.areas:
            if area.type == 'VIEW_3D':
                view = area.spaces.active.region_3d
                view.view_location = (low+high)*0.5
                view.view_distance = (high-low).length*1.4
                view.view_rotation = Euler((1.35, 0, 2.75)).to_quaternion()
    bpy.context.scene['recovery_interchange'] = 'previous/recovery/staging/characters/'+name+'.gltf'
    bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/art/blender/'+name+'.blend')
    print('CHARACTER '+json.dumps({'name':name,'bones':len(rig.data.bones),
                                  'meshes':len(objects),'actions':len(bpy.data.actions),
                                  'size_m':list(high-low)}))
