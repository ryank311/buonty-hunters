"""Renders a four-view sheet of the open .blend beside a 1.8 m reference figure.

Run through `tools/dev blender preview <name>`. No window opens; the Workbench engine
draws flat-lit material colours, which is enough to judge shape, proportion, and scale.
The top row shows front-right and back-left three-quarter views, the bottom row the
front (-Y) and the right side (+X).
"""

import argparse
import json
import math
import os
import sys
import tempfile

import bpy
import numpy
from mathutils import Vector

TILE = (640, 480)
FIGURE_HEIGHT = 1.8
# Collision-only objects are not drawn in the game.
HIDDEN_SUFFIXES = ("-colonly", "-convcolonly")
# (azimuth around Z in degrees measured from the front, elevation in degrees)
VIEWS = [(35, 20), (215, 20), (0, 5), (90, 5)]


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1:])


def bounds(objects):
    low = Vector((float("inf"),) * 3)
    high = Vector((float("-inf"),) * 3)
    for obj in objects:
        for corner in obj.bound_box:
            point = obj.matrix_world @ Vector(corner)
            low = Vector(map(min, low, point))
            high = Vector(map(max, high, point))
    return low, high


def add_box(name, size, location, colour):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    box = bpy.context.active_object
    box.name = name
    box.scale = size
    material = bpy.data.materials.new(name)
    material.diffuse_color = colour
    box.data.materials.append(material)
    return box


def main():
    options = parse_args()
    scene = bpy.context.scene
    models = [obj for obj in scene.objects if obj.type == "MESH"]
    if not models:
        print("PROBLEM the file has no mesh objects")
        return 1
    # Workbench draws each material's viewport colour; take it from the shader so a
    # material that only set its Principled base colour still shows in its real colour.
    for material in bpy.data.materials:
        if material.use_nodes and material.node_tree:
            shader = next((node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
            if shader and not shader.inputs["Base Color"].is_linked:
                material.diffuse_color = shader.inputs["Base Color"].default_value
    # Collision helpers would hide the model they wrap.
    for obj in models:
        if obj.name.endswith(HIDDEN_SUFFIXES):
            obj.hide_render = True
    low, high = bounds([obj for obj in models if not obj.hide_render] or models)

    # A person-sized figure stands behind and to the right of the model, clear of it in
    # both the front and the side view.
    figure = Vector((high.x + 0.45, high.y + 0.35))
    add_box("ReferenceFigure", (0.45, 0.25, FIGURE_HEIGHT), (figure.x, figure.y, FIGURE_HEIGHT / 2), (0.25, 0.45, 0.55, 1.0))
    low = Vector((low.x, low.y, min(low.z, 0.0)))
    high = Vector((figure.x + 0.225, figure.y + 0.125, max(high.z, FIGURE_HEIGHT)))
    centre = (low + high) / 2
    radius = (high - low).length / 2
    add_box("Ground", (radius * 6, radius * 6, 0.02), (centre.x, centre.y, -0.01), (0.32, 0.32, 0.30, 1.0))

    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_cavity = True
    scene.display.shading.show_shadows = True
    scene.render.resolution_x, scene.render.resolution_y = TILE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    if scene.world is None:
        scene.world = bpy.data.worlds.new("PreviewWorld")
    scene.world.color = (0.55, 0.57, 0.58)

    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera_data.lens = 50
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    distance = radius / math.tan(camera_data.angle_y / 2) * 1.15

    sheet = numpy.zeros((TILE[1] * 2, TILE[0] * 2, 4), dtype=numpy.float32)
    scratch = os.path.join(tempfile.gettempdir(), f"socom-preview-{os.getpid()}.png")
    for index, (azimuth, elevation) in enumerate(VIEWS):
        turn = math.radians(azimuth)
        lift = math.radians(elevation)
        # Azimuth 0 looks at the front of the model, which faces -Y in Blender.
        offset = Vector((math.sin(turn) * math.cos(lift), -math.cos(turn) * math.cos(lift), math.sin(lift))) * distance
        camera.location = centre + offset
        camera.rotation_euler = (centre - camera.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = scratch
        bpy.ops.render.render(write_still=True)
        image = bpy.data.images.load(scratch)
        pixels = numpy.array(image.pixels[:], dtype=numpy.float32).reshape(TILE[1], TILE[0], 4)
        bpy.data.images.remove(image)
        column, row = index % 2, index // 2
        # Image rows run bottom-up, so the first row of views goes in the upper half.
        top = TILE[1] * (1 - row)
        sheet[top:top + TILE[1], TILE[0] * column:TILE[0] * (column + 1)] = pixels
    os.remove(scratch)

    result = bpy.data.images.new("PreviewSheet", TILE[0] * 2, TILE[1] * 2)
    result.pixels = sheet.ravel()
    result.filepath_raw = options.out
    result.file_format = "PNG"
    result.save()
    size = bounds([obj for obj in models if not obj.hide_render] or models)
    print("PREVIEW " + json.dumps({
        "png": options.out,
        "views": ["front-right", "back-left", "front", "right side"],
        "size_m": [round(value, 3) for value in (size[1] - size[0])],
        "reference": "the blue-grey box is 1.8 m tall",
    }))
    return 0


try:
    code = main()
except Exception as error:  # Blender would otherwise exit 0 after a failed script.
    print(f"PROBLEM {type(error).__name__}: {error}")
    code = 1
sys.exit(code)
