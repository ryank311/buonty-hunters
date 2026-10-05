"""Run this recipe through execute_blender_code, replacing ASSET for each pilot.

Input is prepared by prepare_pilot.py. No external execution or filesystem access
outside Blender's own data API is needed. Saves the .blend, then tools/dev exports.
"""
import bpy
import json
import math
from mathutils import Matrix, Vector, Quaternion, Euler

ASSET = 'recovered_m4'
ROOT = '/Users/king/socom'
PILOT_DATA_JSON = '__PREPARED_JSON__'


def read_data(name):
    # The caller injects plain JSON data. Blender safe mode forbids text-datablock
    # loading (an execution path), so this recipe does not read or execute a file.
    if PILOT_DATA_JSON != '__PREPARED_JSON__':
        return json.loads(PILOT_DATA_JSON)
    scene = bpy.context.scene
    data = json.loads(scene['pilot_meta'])
    data['meshes'] = [json.loads(scene['pilot_mesh_'+str(i)]) for i in range(scene['pilot_mesh_count'])]
    data['references'] = [json.loads(scene['pilot_reference_'+str(i)]) for i in range(scene['pilot_reference_count'])]
    return data


def source_matrix(values):
    return Matrix([values[i:i+4] for i in range(0, 16, 4)]).transposed()


def converted(matrix, scale):
    axes = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    value = axes @ matrix @ axes.transposed()
    value.translation *= scale
    return value


def make_material(key, spec):
    mat = bpy.data.materials.new(spec['name'].replace('.tif', ''))
    mat.use_nodes = True
    shader = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    shader.inputs['Roughness'].default_value = 0.9
    shader.inputs['Specular IOR Level'].default_value = 0.1
    mat.use_backface_culling = False
    if spec.get('image'):
        tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image = bpy.data.images.load(spec['image'], check_existing=True)
        tex.image.filepath = bpy.path.relpath(spec['image'], start=ROOT+'/art/blender')
        mat.node_tree.links.new(tex.outputs['Color'], shader.inputs['Base Color'])
        if spec.get('cutout'):
            mat.node_tree.links.new(tex.outputs['Alpha'], shader.inputs['Alpha'])
            mat.surface_render_method = 'DITHERED'
    mat['recovered_texture'] = spec.get('source', '')
    mat['recovered_cutout'] = spec.get('cutout', False)
    return mat


def make_mesh(spec, materials):
    mesh = bpy.data.meshes.new(spec['name']+'_mesh')
    mesh.from_pydata(spec['vertices'], [], spec['faces'])
    mesh.update()
    obj = bpy.data.objects.new(spec['name'], mesh)
    bpy.context.collection.objects.link(obj)
    if spec.get('material'):
        mesh.materials.append(materials[spec['material']])
    if spec.get('uv'):
        layer = mesh.uv_layers.new(name='UVMap')
        for loop in mesh.loops:
            layer.data[loop.index].uv = spec['uv'][loop.vertex_index]
    return obj


def import_obj(path):
    window = bpy.context.window_manager.windows[0]
    with bpy.context.temp_override(window=window):
        bpy.ops.wm.obj_import(filepath=path, forward_axis='Y', up_axis='Z')


def build_rig(data, objects):
    armature = bpy.data.armatures.new('RecoveredSkeleton')
    rig = bpy.data.objects.new('RecoveredSealRig', armature)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    window = bpy.context.window_manager.windows[0]
    area = next(a for a in window.screen.areas if a.type == 'VIEW_3D')
    with bpy.context.temp_override(window=window, area=area, active_object=rig, object=rig):
        bpy.ops.object.mode_set(mode='EDIT')
        for part, world in zip(data['parts'], data['bindWorld']):
            bone = armature.edit_bones.new(part['name'])
            bone.head, bone.tail = (0, 0, 0), (0, 0.08, 0)
            bone.matrix = converted(source_matrix(world), data['scale'])
            bone.length = 0.08
            if part['parent'] >= 0:
                bone.parent = armature.edit_bones[data['parts'][part['parent']]['name']]
        bpy.ops.object.mode_set(mode='OBJECT')
    for obj, spec in zip(objects, data['meshes']):
        for part in data['parts']:
            obj.vertex_groups.new(name=part['name'])
        for index, weights in enumerate(spec['weights']):
            for bone, weight in weights:
                obj.vertex_groups[bone].add([index], weight, 'REPLACE')
        obj.parent = rig
        modifier = obj.modifiers.new('RecoveredWeights', 'ARMATURE')
        modifier.object = rig
    rig.animation_data_create()
    actions = {}
    for clip in data['clips']:
        action = bpy.data.actions.new(clip['name'])
        action.use_fake_user = True
        action['recovered_source'] = clip['source']
        action['root_motion'] = 'XZ held at bind position for in-place inspection; vertical motion preserved'
        rig.animation_data.action = action
        tracks = {p['name']: p for p in clip['parts']}
        for frame in range(clip['frameCount']+1):
            worlds = []
            for part in data['parts']:
                local = source_matrix(part['bindLocal'])
                track = tracks.get(part['name'])
                if track:
                    ts, qs = track['translations'], track['rotations']
                    t = Vector(ts[:3] if len(ts) == 3 else ts[3*frame:3*frame+3])
                    q = qs[:4] if len(qs) == 4 else qs[4*frame:4*frame+4]
                    rotation = Quaternion((q[3], q[0], q[1], q[2])).normalized()
                    local = rotation.to_matrix().to_4x4()
                    if part['name'] == 'skel_root':
                        t.x, t.z = part['bindLocal'][12], part['bindLocal'][14]
                    local.translation = t
                parent = worlds[part['parent']] if part['parent'] >= 0 else source_matrix(data['modelMatrix'])
                worlds.append(parent @ local)
            for part in data['parts']:
                pb = rig.pose.bones[part['name']]
                desired = converted(worlds[part['index']], data['scale'])
                if part['parent'] >= 0:
                    parent_pose = converted(worlds[part['parent']], data['scale'])
                    basis = pb.bone.matrix_local.inverted() @ pb.parent.bone.matrix_local @ parent_pose.inverted() @ desired
                else:
                    basis = pb.bone.matrix_local.inverted() @ desired
                location, rotation, scale = basis.decompose()
                pb.rotation_mode = 'QUATERNION'
                # Preserve a continuous hemisphere for component-wise fcurve interpolation.
                if frame and pb.rotation_quaternion.dot(rotation) < 0:
                    rotation.negate()
                pb.location, pb.rotation_quaternion, pb.scale = location, rotation, scale
                pb.keyframe_insert(data_path='location', frame=frame+1, group=part['name'])
                pb.keyframe_insert(data_path='rotation_quaternion', frame=frame+1, group=part['name'])
                pb.keyframe_insert(data_path='scale', frame=frame+1, group=part['name'])
        for fc in action.fcurves:
            for key in fc.keyframe_points:
                key.interpolation = 'LINEAR'
        actions[clip['name']] = action
    bpy.context.scene.render.fps = 30
    errors = []
    for sample in data['references']:
        rig.animation_data.action = actions[sample['clip']]
        bpy.context.scene.frame_set(sample['frame'])
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        maximum, squared, count = 0.0, 0.0, 0
        for obj, positions, indices in zip(objects, sample['positions'], sample['indices']):
            evaluated = obj.evaluated_get(depsgraph)
            mesh = evaluated.to_mesh()
            for index, expected in zip(indices, positions):
                vertex = mesh.vertices[index]
                error = (vertex.co-Vector(expected)).length
                maximum = max(maximum, error)
                squared += error*error
                count += 1
            evaluated.to_mesh_clear()
        errors.append({'clip': sample['clip'], 'frame': sample['frame'], 'max_error_m': maximum,
                       'rms_error_m': math.sqrt(squared/count)})
    report = {'bones': len(data['parts']), 'max_influences': data['max_influences'], 'poses': errors}
    print('SKIN_CHECK '+json.dumps(report))
    if max(e['max_error_m'] for e in errors) > 0.002:
        raise ValueError('Blender deformation differs from recovered bone-local data by over 2 mm')
    rig['recovery_validation'] = json.dumps(report)
    rig.animation_data.action = actions['seal_walk']
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 26
    bpy.context.scene.frame_set(1)
    return rig


def build_asset():
    data = read_data(ASSET)
    bpy.ops.wm.read_homefile(use_empty=True)
    # Keep data available if an interactive import needs a correction before saving.
    if data.get('parts'):
        bpy.context.scene['pilot_meta'] = json.dumps({k: v for k, v in data.items() if k not in ('meshes', 'references')})
        for group in ['meshes', 'references']:
            singular = 'mesh' if group == 'meshes' else 'reference'
            bpy.context.scene['pilot_'+singular+'_count'] = len(data[group])
            for i, item in enumerate(data[group]):
                bpy.context.scene['pilot_'+singular+'_'+str(i)] = json.dumps(item)
    materials = {k: make_material(k, v) for k, v in data['materials'].items()}
    if data.get('obj'):
        import_obj(data['obj'])
        objects = []
        for spec in data['meshes']:
            obj = bpy.data.objects[spec['name']]
            obj.data.materials.clear()
            obj.data.materials.append(materials[spec['material']])
            objects.append(obj)
    else:
        objects = [make_mesh(spec, materials) for spec in data['meshes']]
    if data.get('parts'):
        build_rig(data, objects)
    if data.get('collision'):
        import_obj(data['collision']['obj'])
        helper = bpy.data.objects['RecoveredPlaza-colonly']
        helper.display_type = 'WIRE'
        helper.hide_render = True
        helper.hide_set(True)
    bpy.context.scene['recovery_source'] = data['source']['path']
    bpy.context.scene['source_units_to_meters'] = data['scale']
    points = [o.matrix_world @ Vector(c) for o in objects for c in o.bound_box]
    bpy.context.view_layer.update()
    points = [o.matrix_world @ Vector(c) for o in objects for c in o.bound_box]
    low = Vector([min(p[i] for p in points) for i in range(3)])
    high = Vector([max(p[i] for p in points) for i in range(3)])
    for window in bpy.context.window_manager.windows:
        for area in window.screen.areas:
            if area.type == 'VIEW_3D':
                area.spaces.active.shading.type = 'MATERIAL'
                view = area.spaces.active.region_3d
                view.view_location = (low+high)/2
                view.view_distance = (high-low).length*1.3
                view.view_rotation = Euler((math.radians(70), 0, math.radians(145))).to_quaternion()
    for key in list(bpy.context.scene.keys()):
        if key.startswith('pilot_'):
            del bpy.context.scene[key]
    bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/art/blender/'+ASSET+'.blend')
    print('PILOT '+json.dumps({'asset': ASSET, 'size': list(high-low), 'meshes': len(objects)}))


build_asset()
