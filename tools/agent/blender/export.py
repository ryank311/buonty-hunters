"""Exports the open .blend to a .glb with the project's settings and reports on it.

Run through `tools/dev blender export <name>`, which opens art/blender/<name>.blend in a
windowless Blender and passes `--out art/models/<name>.glb`.

Conventions it applies and checks (see docs/DESIGN.md for the art direction):
  - 1 Blender unit is 1 metre; the exporter converts Z-up to Godot's Y-up.
  - Modifiers are applied on export; cameras and lights are left out.
  - Objects whose names end in -colonly or -convcolonly become collision in Godot and
    are not drawn; -col and -convcol objects are drawn and collide.
"""

import argparse
import json
import sys

import bpy
from mathutils import Vector

COLLISION_SUFFIXES = ("-col", "-convcol", "-colonly", "-convcolonly")
HIDDEN_SUFFIXES = ("-colonly", "-convcolonly")
# Largest budget in docs/DESIGN.md for anything that is not the soldier.
TRIANGLE_NOTE_ABOVE = 800


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1:])


def triangle_count(obj, depsgraph):
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    mesh.calc_loop_triangles()
    count = len(mesh.loop_triangles)
    evaluated.to_mesh_clear()
    return count


def main():
    options = parse_args()
    scene = bpy.context.scene
    depsgraph = bpy.context.evaluated_depsgraph_get()
    meshes = [obj for obj in scene.objects if obj.type == "MESH"]
    if not meshes:
        print("PROBLEM the file has no mesh objects")
        return 1

    notes = []
    visible_triangles = 0
    collision_objects = []
    low = Vector((float("inf"),) * 3)
    high = Vector((float("-inf"),) * 3)
    for obj in meshes:
        if obj.name.endswith(COLLISION_SUFFIXES):
            collision_objects.append(obj.name)
        if not obj.name.endswith(HIDDEN_SUFFIXES):
            visible_triangles += triangle_count(obj, depsgraph)
            for corner in obj.bound_box:
                point = obj.matrix_world @ Vector(corner)
                low = Vector(map(min, low, point))
                high = Vector(map(max, high, point))
        if any(abs(value - 1.0) > 1e-4 for value in obj.scale):
            notes.append(f"{obj.name} has unapplied scale {tuple(round(v, 3) for v in obj.scale)}; apply it so collision and physics match the mesh")

    size = high - low
    if abs(low.z) > 0.01:
        notes.append(f"lowest point is at z={low.z:.3f} m; a prop that stands on the ground should start at z=0")
    if visible_triangles > TRIANGLE_NOTE_ABOVE:
        notes.append(f"{visible_triangles} triangles is above the prop and weapon budgets in docs/DESIGN.md")
    if not collision_objects:
        notes.append("no collision object; name a simple mesh <Name>-colonly (or -convcolonly) if the player should not walk through this")

    bpy.ops.export_scene.gltf(
        filepath=options.out,
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
        export_extras=True,
        export_materials="EXPORT",
        # Preserve every nonzero influence instead of truncating at four. glTF
        # can store a second JOINTS/WEIGHTS set; Godot supports eight influences.
        export_all_influences=True,
    )
    print("EXPORT " + json.dumps({
        "glb": options.out,
        "size_m": [round(size.x, 3), round(size.y, 3), round(size.z, 3)],
        "triangles": visible_triangles,
        "objects": [obj.name for obj in meshes],
        "collision": collision_objects,
        "materials": sorted({slot.material.name for obj in meshes for slot in obj.material_slots if slot.material}),
    }))
    for note in notes:
        print("NOTE " + note)
    return 0


try:
    code = main()
except Exception as error:  # Blender would otherwise exit 0 after a failed script.
    print(f"PROBLEM {type(error).__name__}: {error}")
    code = 1
sys.exit(code)
