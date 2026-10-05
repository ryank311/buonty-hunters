"""Run this recipe through execute_blender_code; prepare_level.py --batch fills in MAPS.

Input is prepared by prepare_level.py: Blender-space OBJ files for the world, sky
and collision, with level.mtl naming each original texture. Saves one
art/blender/<asset>.blend per map; then `tools/dev blender export <asset>...`
writes the GLBs the game loads.
"""
import bpy
import json

ROOT = '/Users/king/socom'
STAGING = ROOT + '/previous/recovery/staging/levels/'
MAPS = ['__MAPS__']
LEVELS = [{'asset': 'recovered_map_' + m.lower(), 'map': m, 'world': STAGING + m + '/world.obj', 'sky': STAGING + m + '/sky.obj',
           'collision': STAGING + m + '/collision.obj', 'source': 'converted/levels/' + m + '/level.obj', 'scale': 0.1} for m in MAPS]


def prepare_material(mat):
    """The OBJ importer built the textured material from level.mtl; match the
    pilot's look and store the texture relative to art/blender."""
    shader = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None) if mat.use_nodes else None
    if shader is None:
        return
    shader.inputs['Roughness'].default_value = 0.9
    shader.inputs['Specular IOR Level'].default_value = 0.1
    mat.use_backface_culling = False
    for node in mat.node_tree.nodes:
        if node.type == 'TEX_IMAGE' and node.image and not node.image.filepath.startswith('//'):
            node.image.filepath = bpy.path.relpath(bpy.path.abspath(node.image.filepath), start=ROOT + '/art/blender')
    cutout = shader.inputs['Alpha'].is_linked
    if cutout:
        mat.surface_render_method = 'DITHERED'
    mat['recovered_cutout'] = cutout


def import_obj(path):
    before = set(bpy.data.objects)
    window = bpy.context.window_manager.windows[0]
    with bpy.context.temp_override(window=window):
        bpy.ops.wm.obj_import(filepath=path, forward_axis='Y', up_axis='Z')
    return [o for o in bpy.data.objects if o not in before]


def group(name, objects):
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    for obj in objects:
        # The game applies each surface's original blend mode by material name.
        obj.data.name = obj.name
        obj.parent = root
    return root


def build_level(LEVEL):
    bpy.ops.wm.read_homefile(use_empty=True)
    group('World', import_obj(LEVEL['world']))
    if LEVEL.get('sky'):
        group('Sky', import_obj(LEVEL['sky']))
    for mat in bpy.data.materials:
        prepare_material(mat)
    collision = import_obj(LEVEL['collision'])[0]
    collision.name = LEVEL['asset'] + '-colonly'
    collision.display_type = 'WIRE'
    collision.hide_render = True
    collision.hide_set(True)
    scene = bpy.context.scene
    scene['recovery_source'] = LEVEL['source']
    scene['recovery_map'] = LEVEL['map']
    scene['source_units_to_meters'] = LEVEL['scale']
    bpy.ops.wm.save_as_mainfile(filepath=ROOT + '/art/blender/' + LEVEL['asset'] + '.blend')
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    print('LEVEL ' + json.dumps({'asset': LEVEL['asset'], 'objects': len(meshes),
                                 'triangles': sum(len(o.data.polygons) for o in meshes if o is not collision),
                                 'collision': len(collision.data.polygons), 'materials': len(bpy.data.materials)}))


for level in LEVELS:
    build_level(level)
