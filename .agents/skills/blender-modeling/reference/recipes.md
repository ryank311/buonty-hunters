# Blender recipes

Every snippet here runs through `execute_blender_code` with safe mode on (Blender 4.5). Helpers are plain `def`s because safe mode rejects calls to parameters and lambdas, and they must be repeated in each script that uses them: only Blender's own data survives between calls.

## Start, open, save

```python
import bpy
bpy.ops.wm.read_homefile(use_empty=True)                          # new, empty file
bpy.ops.wm.open_mainfile(filepath="art/blender/crate.blend")      # continue an asset
bpy.ops.wm.save_as_mainfile(filepath="art/blender/crate.blend")   # first save, or save under a name
bpy.ops.wm.save_mainfile()                                        # save again
```

Paths are relative to the repo root. Opening or starting a file discards unsaved work in the current one.

## Helpers: materials, boxes, cylinders

```python
import bpy, bmesh

def material(name, colour, roughness=0.9):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = (colour[0], colour[1], colour[2], 1.0)
    shader.inputs["Roughness"].default_value = roughness
    mat.diffuse_color = (colour[0], colour[1], colour[2], 1.0)   # viewport colour
    return mat

def add_box(bm, size, centre, material_index=0):
    verts = bmesh.ops.create_cube(bm, size=1.0)["verts"]
    bmesh.ops.scale(bm, vec=size, verts=verts)
    bmesh.ops.translate(bm, vec=centre, verts=verts)
    for face in {face for vert in verts for face in vert.link_faces}:
        face.material_index = material_index

def add_cylinder(bm, radius, height, base, segments=12, material_index=0):
    verts = bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=radius, radius2=radius, depth=height)["verts"]
    bmesh.ops.translate(bm, vec=(base[0], base[1], base[2] + height / 2), verts=verts)
    for face in {face for vert in verts for face in vert.link_faces}:
        face.material_index = material_index

def finish(bm, name, materials=()):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for mat in materials:
        mesh.materials.append(mat)
    return obj
```

Sizes and positions are metres. `centre` is the middle of a box; `base` is the bottom centre of a cylinder. Give `add_cylinder` different `radius1`/`radius2` values (edit the helper) for a cone or taper. Building geometry into one `bmesh` and calling `finish` once makes a single object, which becomes a single node in Godot; `material_index` picks which of that object's materials a part uses.

## A complete asset: the reference crate

This is how `art/blender/crate.blend` was made (with the helpers above in the same script):

```python
bpy.ops.wm.read_homefile(use_empty=True)

bm = bmesh.new()
add_box(bm, (1.0, 1.0, 1.0), (0, 0, 0.5))                         # body, standing on z = 0
add_box(bm, (1.04, 1.04, 0.08), (0, 0, 0.12), material_index=1)   # lower band
add_box(bm, (1.04, 1.04, 0.08), (0, 0, 0.88), material_index=1)   # upper band
finish(bm, "Crate", [material("FadedWood", (0.45, 0.36, 0.24)), material("DarkWood", (0.30, 0.24, 0.16))])

bm = bmesh.new()
add_box(bm, (1.04, 1.04, 1.0), (0, 0, 0.5))
finish(bm, "Crate-convcolonly").display_type = "WIRE"            # collision hull, drawn as wire

bpy.ops.wm.save_as_mainfile(filepath="art/blender/crate.blend")
```

`tools/dev blender export crate` then reports `size_m [1.04, 1.04, 1.0]`, 36 triangles, and `collision ["Crate-convcolonly"]`.

## Collision

| Object name ends with | Godot result |
|---|---|
| `-colonly` | Static body with the mesh's exact triangles; the mesh itself is not drawn. Use for ramps, arches, anything concave. |
| `-convcolonly` | Static body with one convex hull; not drawn. Cheapest; use for boxes, barrels, posts, walls. |
| `-col` / `-convcol` | The visible mesh is drawn and also used as collision. Only for very simple meshes. |

A concave prop can carry several `-convcolonly` objects (`Arch-convcolonly`, `Arch2-convcolonly`); each becomes its own hull.

## Modifiers

```python
crate = bpy.data.objects["Crate"]
bevel = crate.modifiers.new("Bevel", "BEVEL")
bevel.width = 0.01
bevel.segments = 1
```

Modifiers are applied on export; the source file keeps them editable. They cost triangles: this one-segment bevel takes the crate from 36 to 132, so check the export report against the budget.

## Changing existing geometry

```python
import bpy, bmesh
obj = bpy.data.objects["Crate"]
bm = bmesh.new()
bm.from_mesh(obj.data)
bmesh.ops.translate(bm, vec=(0, 0, 0.1), verts=[v for v in bm.verts if v.co.z > 0.9])   # raise the top
bm.to_mesh(obj.data)
bm.free()
obj.data.update()
```

Edit mesh data, not object scale: `obj.scale` other than 1 is flagged by the export. To resize a whole object, scale its vertices with `bmesh.ops.scale(bm, vec=(...), verts=bm.verts)`.

## Removing things

```python
bpy.data.objects.remove(bpy.data.objects["Crate-convcolonly"])
```

## Framing the viewport for a screenshot

```python
import bpy
from math import radians
from mathutils import Euler, Vector
points = [o.matrix_world @ Vector(c) for o in bpy.context.scene.objects if o.type == "MESH" for c in o.bound_box]
low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
screen = bpy.context.window_manager.windows[0].screen   # bpy.context.screen is None after a file load
area = next(a for a in screen.areas if a.type == "VIEW_3D")
view = area.spaces.active.region_3d
view.view_perspective = "PERSP"
view.view_location = (low + high) / 2
view.view_distance = (high - low).length * 1.6
view.view_rotation = Euler((radians(65), 0, radians(35))).to_quaternion()
```

Then call `get_viewport_screenshot`. Change the last angle to orbit: 35 looks from the front-right, 215 from the back-left.

## Operators that need a 3D view

Most modelling is easier through `bmesh` and `bpy.data`, which need no context. An operator that insists on a viewport can be given one:

```python
window = bpy.context.window_manager.windows[0]
area = next(a for a in window.screen.areas if a.type == "VIEW_3D")
region = next(r for r in area.regions if r.type == "WINDOW")
with bpy.context.temp_override(window=window, area=area, region=region):
    bpy.ops.view3d.view_all()
```

Reach the window through `bpy.context.window_manager`, as here. `bpy.context.screen` and `bpy.context.window` are `None` in a script that has just opened or started a file.
