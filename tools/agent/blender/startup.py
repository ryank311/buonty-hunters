"""Prepares the agents' Blender instance. Run by `tools/dev blender start`.

Blender is launched with factory settings, so nothing here touches the user's own
Blender preferences, add-ons, or files. The script:
  - loads the MCP add-on from the project-local copy and starts its socket server on
    the requested port,
  - empties the default scene,
  - writes a small state file every two seconds so `tools/dev blender status` can report
    what is open without talking to Blender.
"""

import argparse
import importlib.util
import json
import os
import sys

import bpy


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--addon", required=True)
    parser.add_argument("--state", required=True)
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return parser.parse_args(argv)


OPTIONS = parse_args()


def load_addon():
    spec = importlib.util.spec_from_file_location("blender_mcp", OPTIONS.addon)
    module = importlib.util.module_from_spec(spec)
    sys.modules["blender_mcp"] = module
    spec.loader.exec_module(module)
    module.register()
    # The add-on starts its server shortly after registering, on the scene's port.
    for scene in bpy.data.scenes:
        scene.blendermcp_port = OPTIONS.port
    return module


def empty_scene():
    for collection in (bpy.data.objects, bpy.data.meshes, bpy.data.cameras, bpy.data.lights, bpy.data.materials):
        for block in list(collection):
            collection.remove(block)


# Blender's own "dirty" flag misses changes made through the Python API, which is how
# agents edit, so scene updates since the last save are tracked here as well.
changed_since_save = False


@bpy.app.handlers.persistent
def on_scene_update(_scene, _depsgraph=None):
    global changed_since_save
    changed_since_save = True


@bpy.app.handlers.persistent
def on_saved_or_loaded(*_unused):
    global changed_since_save
    changed_since_save = False


def write_state():
    server = getattr(bpy.types, "blendermcp_server", None)
    state = {
        "pid": os.getpid(),
        "port": OPTIONS.port,
        "listening": bool(server and server.running),
        "file": bpy.data.filepath,
        "unsaved_changes": bool(bpy.data.objects) and (changed_since_save or bpy.data.is_dirty),
        "objects": len(bpy.data.objects),
    }
    temporary = OPTIONS.state + ".tmp"
    with open(temporary, "w") as handle:
        json.dump(state, handle)
    os.replace(temporary, OPTIONS.state)
    return 2.0


preferences = bpy.context.preferences
preferences.view.show_splash = False
# No .blend1 backups beside the project's source files.
preferences.filepaths.save_version = 0
# Source files live in git; compressed .blend files are several times smaller.
preferences.filepaths.use_file_compression = True

empty_scene()
load_addon()
bpy.app.handlers.depsgraph_update_post.append(on_scene_update)
bpy.app.handlers.save_post.append(on_saved_or_loaded)
bpy.app.handlers.load_post.append(on_saved_or_loaded)
bpy.app.timers.register(write_state, first_interval=1.0, persistent=True)
