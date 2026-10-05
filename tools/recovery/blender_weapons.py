"""Submit generated calls through Blender MCP; never execute this with shell Blender."""
import bpy
import json
from mathutils import Vector

ROOT = '__ROOT__'
DATA_JSON = '__DATA__'
data = json.loads(DATA_JSON)
bpy.ops.wm.read_homefile(use_empty=True)
materials = {}
for key, spec in data['materials'].items():
    mat = bpy.data.materials.new(spec['name'])
    mat.use_nodes = True
    shader = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    shader.inputs['Roughness'].default_value = .9
    shader.inputs['Specular IOR Level'].default_value = .1
    tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image = bpy.data.images.load(spec['image'], check_existing=True)
    tex.image.filepath = bpy.path.relpath(spec['image'], start=ROOT + '/art/blender')
    mat.node_tree.links.new(tex.outputs['Color'], shader.inputs['Base Color'])
    if spec['cutout']:
        mat.node_tree.links.new(tex.outputs['Alpha'], shader.inputs['Alpha'])
        mat.surface_render_method = 'DITHERED'
    mat['recovered_texture'] = spec['source']
    materials[key] = mat
window = bpy.context.window_manager.windows[0]
with bpy.context.temp_override(window=window):
    bpy.ops.wm.obj_import(filepath=data['obj'], forward_axis='Y', up_axis='Z')
for spec in data['meshes']:
    obj = bpy.data.objects[spec['name']]
    obj.data.materials.clear()
    obj.data.materials.append(materials[spec['material']])
marker = bpy.data.objects.new('Muzzle', None)
marker.location = data['muzzle_blender']
bpy.context.collection.objects.link(marker)
bpy.context.scene['recovered_name'] = data['source_name']
bpy.context.scene['scale_metres_per_source_unit'] = .1
bpy.context.scene['origin'] = 'Native weapon attachment origin; Blender +Y muzzle'
for area in window.screen.areas:
    if area.type == 'VIEW_3D':
        area.spaces.active.region_3d.view_distance = 1.8
        area.spaces.active.region_3d.view_location = Vector((0, .2, 0))
bpy.ops.wm.save_as_mainfile(filepath=ROOT + '/art/blender/' + data['name'] + '.blend')
print('Saved ' + data['name'])
