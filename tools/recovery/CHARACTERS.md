# Recovered characters and motion library

## View and try

Restart the game with Godot's Stop and Play buttons. Open **Cmd+1 / F1 → Recovery Lab**, then press **Tab**. The browser releases the mouse and stops the player while the two display figures keep animating. Tab, Escape or Close returns to walking.

- Search the **202 character models**, including SEAL outfits, SAS, Spetsnaz, mission characters, civilians and lower-detail variants.
- Search or filter **402 clips** by locomotion, traversal, weapons/equipment, gestures, reactions, first-person or other motion.
- The recovered character is on the left; **our existing player mesh** is on the right. Both use the same clip and clock. Pause, scrub or advance one original 30 Hz frame to inspect the mapping.
- Use **Turn models** to inspect the same pose from different sides.
- **Try recovered leg motion on player** enables the first playable integration. Close the browser and walk/run forward, backward or sideways, standing or crouched. It remains enabled when switching levels during that run. Return to Recovery Lab to disable it. Restarting resets it.
- The trial transfers the recovered stride to our legs, solves the knees for our proportions, and blends back to the existing pose for jumping, diving, prone and throws. The existing controller still owns movement/collision; upper-body aim and weapon grips remain procedural.

The trial is intentionally optional. Full-body clips are ported for inspection; they are not all connected to gameplay. Reload completion, projectile release, climbing, death and interaction events must be mapped to game logic before those clips can replace the current behaviors. The browser marks **50 partial-body clips** whose missing tracks currently use the bind pose. Those need a base pose or an animation layer when used in gameplay.

## Collection and provenance

| Recovered input | Imported result |
| --- | --- |
| 560 character occurrences | 202 distinct textured, rigged models (including LODs/variants) |
| 1,178 animation occurrences | 402 distinct clips, on both the recovered and player rigs |
| 26 recovered skeleton parts | 19 mapped player bones |

Deduplication compares geometry, influences, bind transforms and texture content for characters, and full track data for motions. Every original occurrence remains in `resources/recovered/catalogue.json`; the untouched decoded/native records remain under `previous/recovery/`. All models share the established conversion of **0.1 metres per source unit**, rather than individual normalization. The largest discrepancy between an original influence's bind position and its glTF representation is **0.102 mm**. All positive influences are retained (up to Godot's eight-influence limit); the converter rejects larger counts instead of truncating them.

| Files | Purpose |
| --- | --- |
| `art/blender/recovered_char_*.blend` | 202 editable recovered characters |
| `art/models/recovered_char_*.glb` | Their Godot exports |
| `art/blender/textures/recovered_characters/` | Linked, content-hashed recovered textures |
| `art/blender/recovered_motion_library.blend` | Reference SEAL with all 402 original actions |
| `art/blender/soldier_recovered.blend` | Our player mesh/rig with all 402 retargeted actions |
| `art/models/recovered_motion_library.glb`, `soldier_recovered.glb` | Exported animation masters |
| `resources/recovered/original.res`, `soldier.res` | Shared Godot AnimationLibraries extracted from those exports |
| `resources/recovered/catalogue.json` | Names, categories, source paths, duplicate occurrences, missing/extra tracks and original root travel |

The original `soldier.blend` and `soldier.glb` remain the canonical player model. The retargeted master is an editable animation source; its library also drives the original mesh directly in the comparison view. Skeleton rest transforms agree within import precision.

## Mapping

The mapping is explicit in `prepare_characters.py` and the catalogue: hips → Hips; spinelo/spinehi → Spine/Chest; neck/head → Neck/Head; scapulae → Shoulders; biceps/forearms/hands → UpperArm/LowerArm/Hand; thighs/calves/feet → UpperLeg/LowerLeg/Foot. Root, aim helper and weighted shoulder transforms are accumulated before mapping, so their motion is not lost when their bones have no direct player counterpart. Toe motion has no independent target bone; weapon/prop/helper tracks remain in the decoded source and are listed as extra tracks.

For each frame the converter computes source global poses, applies the difference from each source bind rotation to the corresponding player bind rotation, then reconstructs the target hierarchy using the player's original joint offsets. It scales hip translation to the player's height. Horizontal **root travel is held in place** for inspection and controller-driven locomotion; vertical motion and hip sway remain. The original root tracks are still preserved in the decoded collection and their travel is recorded in the catalogue. Missing partial-body tracks use the reference bind pose, not an inferred gameplay layer.

The Blender recipe sets 30 fps **before** importing, snaps sampled keys to their integer frames and records explicit action endpoints. The Godot library step checks every duration against the archive and restores original names when Godot interprets an `_loop` suffix as an import instruction. This preserves the source timing and searchable names through both importers.

## Rebuild

Use the agent's Blender instance and save any in-progress work before opening another source file. The recipes below use Blender's native glTF importer and save operator; do not run their Python files as shell scripts.

1. Run `python3 tools/recovery/collection_calls.py --base`. Submit the printed `base.py` to Blender MCP's `execute_blender_code`. It exports the current `soldier.blend` to the staging base.
2. Run `previous/recovery/.venv/bin/python tools/recovery/prepare_characters.py`. This prepares glTF interchange data and the catalogue without editing final GLBs. `--motions-only` reuses the character manifest when only the player rig or retarget mapping changed.
3. Run `python3 tools/recovery/collection_calls.py`. Submit the numbered `collection_*.py` recipes to Blender MCP in order. Each bounded batch saves `.blend` sources. The last recipe imports both motion masters.
4. Export those sources through the project's normal pipeline:

```sh
xargs tools/dev blender export < previous/recovery/staging/characters/export_names.txt
tools/dev import
tools/dev godot --headless --path . --script res://tools/recovery/import_motion_library.gd
tools/dev import
tools/dev check
tools/dev test
tools/dev shot recovery_start recovery_character --sheet
```

The exporter's prop-budget and static-collision notes are expected for these skinned characters; their collisions belong to actors. Several original meshes extend slightly below the nominal bind ground plane. Inspect animated feet when deciding offsets. Texture lighting remains the pilot's approximate base-color material setup, not a reconstruction of all PS2 material effects.

`recovered_collection_regression` loads all 202 exports and checks skeletons, weights and textures; samples all 402 clips on both rigs at three times; checks fixed target joint lengths, synchronized playback, search/selection, browser input, and playable locomotion/fallback. The pilot collision/traversal checks remain in `recovery_regression`. Representative models also receive Blender previews and in-game visual inspection; passing structural checks is not a claim that every clip is gameplay-ready.

## Verified collection

The completed import passed `tools/dev check` (77 files) and `tools/dev test` (13 suites, 446 checks). All 402 original names and durations survive in both libraries. The browser was inspected with SEAL running, SAS reloading and civilian walking, alongside the retargeted player. Clicking the playable trial enabled recovered running at 4.5 m/s while grounded; crouch selection and prone fallback also pass the regression suite. The final live session reported no runtime errors.

Screenshots and the verification record are under `previous/recovery/reports/characters/`. These are representative visual checks; the remaining clips still need individual gameplay and event review.
