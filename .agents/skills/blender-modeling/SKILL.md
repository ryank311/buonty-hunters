---
name: blender-modeling
description: Build 3D models and level objects in Blender through the blender MCP server and bring them into the Godot game - props, cover, architecture pieces, weapons, anything with a mesh. Use when asked to model, sculpt, block out, or edit a 3D asset or .blend file, export a .glb, fix a model's scale, origin, facing, materials, or collision, or check how an asset looks in the game.
---

# Modelling in Blender for this game

Each asset is one source file, `art/blender/<name>.blend`, exported to `art/models/<name>.glb`. Blender is where the model is built; `tools/dev` exports it, renders previews, and puts it in the game.

## The loop

1. **Build** with the `blender` MCP server's `execute_blender_code`. Your own Blender starts at the first tool call and opens behind the user's windows; nothing else needs launching. The scene persists between calls, so work in small steps.
2. **Save** from Blender: `bpy.ops.wm.save_as_mainfile(filepath="art/blender/<name>.blend")`. Relative paths resolve from the repo root.
3. **Look**: `tools/dev blender preview <name>` renders front-right, back-left, front, and side views beside a 1.8 m figure. Read the PNG it prints. This is the reliable check for shape and scale.
4. **Export**: `tools/dev blender export <name>` writes the `.glb` with the project's settings and reports size in metres, triangle count, collision objects, and anything that looks wrong. Fix what the `NOTE` lines say, or decide they do not apply.
5. **Import**: `tools/dev import`, so Godot picks up the new or changed `.glb`.
6. **See it in the game**: `tools/dev shot --model=<name>` stands the model on the Movement Lab start line, 6 m ahead and to the right of the soldier, and prints the PNG to read. `--at=x,y,z` and `--yaw=degrees` move and turn it (the soldier is at 0, 0, 26 facing -Z); repeat `--model` to line several up; add `level=town spawn=West1` to see it in the town. To walk around the model or shoot it, use a `godot-playtest` session and `H.apply(tree, {"place": [...]})`.

A change is done when the export has no unexplained notes and you have looked at the model in the game, not only in Blender. The game's lighting, scale, and collision are what count.

`art/blender/crate.blend` is a small reference asset that follows every convention below.

## Conventions

| Topic | Rule |
|---|---|
| Units | 1 Blender unit is 1 metre. The soldier stands 1.8 m, crouches at 1.15 m, lies prone at 0.55 m, and is 0.64 m wide. |
| Origin | The asset stands on the ground at z = 0, centred on the origin, so it sits on the floor when placed at y = 0 in Godot. |
| Facing | Blender +Y becomes Godot's forward (-Z). Point anything directional (a muzzle, a door's outside) along +Y. Blender's Z-up is converted to Godot's Y-up on export. |
| Transforms | Build at real size. Leave object scale at 1 (the export flags unapplied scale). |
| Collision | The player walks through a model that has none. Add a simple mesh named `<Name>-colonly` (exact shape) or `<Name>-convcolonly` (one convex hull, cheaper; right for boxes, barrels, posts). It becomes a static body in Godot and is not drawn. Keep it simpler than the visible mesh and set `display_type = "WIRE"` so it does not hide the model in the viewport. |
| Materials | Principled BSDF with a base colour and roughness near 0.9; no textures are needed at this stage. Palette: olive, stone, sand, faded wood. Material names become Godot material names. |
| Budgets | Common props 100-600 triangles, weapons 300-800, the soldier 2,000-4,000 (`docs/DESIGN.md`, "PS2 visual and audio direction"). Read that section before starting a visible asset. |
| Names | `lowercase_snake` file names. Object names become Godot node names, so name them for what they are. |
| Assets | Model original geometry. Do not pull from asset libraries or AI generators unless the user asks. |

## Writing code for Blender

Scripts run under a validator ("safe mode"). They may import `bpy`, `bmesh`, `mathutils`, `math`, and other pure-Python modules, and may save, open, render, import, and export through `bpy.ops`. They may not import `os` or `sys`, open files directly, or use the network. Two limits are easy to trip over:

- Call only functions defined with `def` in the same script, builtins, or module attributes. Calling a parameter or a lambda (`build(bm)` where `build` was passed in) is rejected.
- Nothing carries over between calls except Blender's own data. Define helpers again in each script, or keep each script self-contained.

A rejected script comes back with the line and the reason; rewrite it within the limits. Tested building blocks (boxes, cylinders, materials, collision, bevels, opening and saving files, framing the viewport) are in [reference/recipes.md](reference/recipes.md). Use `bpy_api_lookup` instead of guessing an operator or property name.

Every tool takes a `user_prompt` argument; pass a short description of the task.

## Looking at the work

- `tools/dev blender preview <name>` shows the saved file: four fixed views, real colours, collision hidden, scale figure included. Use it for anything you will judge.
- `get_viewport_screenshot` shows the live viewport as it is. Frame the model first (recipe in the reference) or the shot may be of empty grid. Good for a quick check mid-build.
- `get_scene_info` and `get_object_info` return names, positions, bounding boxes, and vertex counts without an image.

## Putting a model in a level

Levels are `scenes/levels/*.tscn`. Instance the `.glb` there as a `PackedScene`:

```
[ext_resource type="PackedScene" path="res://art/models/crate.glb" id="crate"]

[node name="SupplyCrate" parent="Cover" instance=ExtResource("crate")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 4, 0, -2)
```

The `ext_resource` line goes with the others at the top of the file; the last three numbers of the transform are the position. Try positions with `place` first, then write the one that works. Afterwards run the `godot-dev-loop` checks; `prototype_smoke` walks the town routes and will catch a prop that blocks one.

## Your Blender instance

- Each kind of agent has its own: Claude Code on port 9886, Codex on 9887. `tools/dev blender status` lists what is running, the open file, and whether it has unsaved changes.
- It runs with factory settings and never touches the user's own Blender, preferences, or files outside the repo.
- Start a new asset with `bpy.ops.wm.read_homefile(use_empty=True)`; continue one with `bpy.ops.wm.open_mainfile(filepath="art/blender/<name>.blend")`. Save before switching files: opening another discards unsaved work.
- Save when you finish. Leave Blender running so the user can look at the result; `tools/dev blender stop` closes it and refuses if there are unsaved changes.

## Troubleshooting

| Symptom | Do |
|---|---|
| A tool reports it cannot connect to Blender | `tools/dev blender status`, then `tools/dev blender start`. The log is `.agent/blender/<port>.log`. |
| `Rejected by safe mode` | Rewrite within the limits above. Only the user lifts safe mode (`SOCOM_BLENDER_UNSAFE=1`). |
| The model is tiny, huge, or lying on its side in the game | Check `size_m` in the export report against the conventions; rebuild at real size with scale 1. |
| The model is missing or stale in Godot | `tools/dev import` after every export; then `tools/dev check`. |
| The player walks through it | No collision object was exported; the export report lists `collision`. |
| Something is off with the setup | `tools/dev doctor`, then `tools/dev blender smoke`. |
