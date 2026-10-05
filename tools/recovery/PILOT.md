# Recovered asset pilot

## Open and inspect

Click Godot's **Play ▶** button (or press **F5**), then choose **Cmd+1 / F1 → Recovery Lab**. The player starts in front of a recovered M4 and a SEAL model. Walk through the surrounding Crossroads plaza with the normal controls. Command-number shortcuts work while the game has keyboard focus; Mac HUD hints show these shortcuts.

The pilot now also has a [complete character/motion collection](CHARACTERS.md): **Tab** opens its browser, with 202 characters and 402 clips compared against the currently selected recovered player character.

| Key | Inspection action |
| --- | --- |
| Tab | Open/close the character and animation browser |
| Cmd+6 / F6 | Cycle the motion collection (the original four pilot clips come first) |
| Cmd+7 / F7 | Pause/resume the character animation |
| Cmd+9 / F9 | Pause and advance one original 30 Hz animation frame |
| Cmd+8 / F8 | Toggle the recovered collision wireframe |
| N | Cycle Showcase, Plaza and NorthStreet spawns |
| Backspace | Return to the selected spawn and refill |
| Cmd+1 / F1 | Return to the other levels or adjust camera settings |

The pilot stands remain inspection displays. The playable soldier now uses recovered character geometry and native full-body locomotion; the browser’s **Use selected character for player** button and **[ / ]** switch the playable model. The M4 follows the recovered hand/weapon track. Raised aim/fire poses, recoil and reload layers are now connected; weapon-specific models and remaining actions are follow-up work. The recovery area has no combat roster. The M4 and character can be viewed from every side; the plaza has visible fences at its cropped edges.

## First assets

| Source | Editable Blender file | Godot export |
| --- | --- | --- |
| M83 `m4Acarbine` | `art/blender/recovered_m4.blend` | `art/models/recovered_m4.glb` |
| M83 `seal_A_scuba` | `art/blender/recovered_seal.blend` | `art/models/recovered_seal.glb` |
| MP72 Crossroads plaza | `art/blender/recovered_crossroads.blend` | `art/models/recovered_crossroads.glb` |

The original PNGs used by the Blender materials are copied to `art/blender/textures/recovered_*/`. The glTF export embeds them; Godot extracts its own images next to each GLB. The full recovery collection and intermediary files remain under ignored `previous/recovery/`.

- A shared **0.1 metre per source unit** conversion preserves proportions across all three assets. The M4 is 0.886 m long. This is the pilot's explicit calibration, not proof of an original authored unit convention.
- The M4 has **563 nondegenerate, distinct triangles** and both source texture bindings. Its muzzle points Blender +Y / Godot -Z; its bottom is at zero. Source assembly had 621 triangles including repeated/degenerate faces.
- The character retains **26 skeleton parts**, seven texture surfaces and all nonzero weights. Its source reports up to five influence slots, including a zero-weight slot; this model's maximum number of distinct positive influences is four. The exporter now preserves additional influence sets for future models instead of applying a four-weight limit.
- The pilot source contains four original clips, baked at their stored **30 Hz** key times. Track names map to bone names; bone matrices retain the original hierarchy and rest pose. Horizontal root travel is held at the bind position for in-place inspection. Vertical motion stays intact, and the original unmodified tracks remain in the recovery collection. Current runtime playback uses `native.res` and per-rig axis conversion; see [CHARACTERS.md](CHARACTERS.md) before changing the rig or its motions.
- The map is a **60 × 60 m** crop around source position `[1275, 43.5, 1445]`. It retains **10,453 visual triangles** and **3,933 collision triangles**. Crop edges interpolate UVs. Sky, destroyed-state, shadow and pulse meshes, exact duplicates and degenerate triangles are omitted. Camera/trigger volumes and water surfaces are excluded from solid collision.
- `recovery_lab.gd` explicitly enables **two-sided concave collision**. This is necessary because the original probes accept both polygon orientations. Without it, several floors are ignored from above. Apply the same setting when moving this recovered collision to another Godot scene.

## Rebuild

First prepare data and bounded Blender MCP recipes:

```sh
previous/recovery/.venv/bin/python tools/recovery/prepare_pilot.py
python3 tools/recovery/pilot_calls.py recovered_m4
python3 tools/recovery/pilot_calls.py recovered_seal
python3 tools/recovery/pilot_calls.py recovered_crossroads
```

Submit the generated files in `previous/recovery/staging/pilot/calls/<asset>/` to the Blender MCP **execute_blender_code** tool in numbered order. These files are recipes for that tool, not ordinary Python terminal programs. Save any in-progress agent Blender work first: the first call starts an empty scene. Each recipe uses approved Blender modeling/import/save APIs and stays under the tool's 200 KB limit. The character's prepared data travel as plain JSON, never executable text.

The final call creates the `.blend`. For the character it also compares Blender-deformed vertices with independently calculated positions from the original bone-local influences at 12 sampled poses. The validation report is stored on `RecoveredSealRig` as `recovery_validation`. Any sampled error over 2 mm stops the recipe before saving.

Then use the normal asset loop:

```sh
tools/dev blender preview recovered_m4 recovered_seal recovered_crossroads
tools/dev blender export recovered_m4 recovered_seal recovered_crossroads
tools/dev import
tools/dev check
tools/dev test
tools/dev shot recovery_start recovery_character recovery_weapon recovery_plaza --sheet --state
```

The Blender preview command renders material colors for scale/shape checks; the Godot shots verify actual texture rendering. Export notes about the prop triangle budget do not apply to a character or map section. The map extends below the plaza's zero plane because it includes lower terrain. Display models intentionally have no collision of their own; their inspection stands have separate simple collision.

## Verified on 2026-10-05

- All three Blender files were visually inspected, previewed and exported through `tools/dev blender`.
- At 12 sampled poses (32 vertices per material surface), maximum Blender skinning error against recovered data was **0.0303 mm**.
- Godot import and the **72-file project check** passed.
- All **12 regression suites** passed, including **22 recovery checks**: texture links, skeleton/clip import, normalized weights, animated foot movement, stationary horizontal root, pause/frame stepping, collision overlay, three grounded spawns, a route around the gazebo, wall blocking, and returning to the existing lab.
- F6/F7/F8/F9 were exercised through actual runtime input events. The new menu entry and the three assets were inspected in Godot screenshots.

## Remaining work

Materials use recovered base-color textures with simple rough lighting and alpha cutouts. Exact PS2 GS blending, vertex lighting, animated effects and original normal handling remain to be reconstructed; the current meshes use reconstructed face normals. LOD/state selection beyond the pilot filters is not a general solution for every recovered asset.

The map's collision behaves as static Godot geometry. Original ladder, climbing, water and destruction behaviors are not implemented. The cropped level is an inspection fixture, not a complete gameplay port. Original audio/video are still native archive data.

The next character milestone is weapon sockets and locomotion/stance integration on the actual player, with aim blending and gameplay hitboxes tested separately. The next map milestone is a reusable state/LOD and collision-material importer, then a larger connected section.
