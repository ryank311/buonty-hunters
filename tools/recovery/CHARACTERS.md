# Recovered characters and native motion

## Play and inspect

Restart the game with Godot's Stop and Play buttons. The playable character is now the recovered **seal_A_cqb**, using its original proportions, skin weights and 26-part rig. **[ / ]** cycles through all 202 character variants in either direction. Selection survives respawn and level changes during the current run; restarting selects CQB again.

Open **Cmd+1 / F1 → Recovery Lab**, then press **Tab**. Search the characters and 402 motion clips, or filter clips by category. The left display shows the selected recovered character; the right shows your current playable character. Both sample the same native clip at the same time. Pause, scrub, advance one original 30 Hz frame, or turn the models to inspect them. **Use selected character for player** makes the selected model playable without resetting position, health or ammunition. Tab, Escape or Close returns to walking.

The player uses native standing, walking, running, backpedaling, strafing, crouching, crawling, jump, landing and dive poses, with a short crossfade when changing clips. The existing controller owns movement and collision. This is an initial gameplay hookup, not a completed animation state machine. Reload, firing, throws, interactions, aim layers and most one-shot clips still need deliberate integration and event timing. The browser marks **50 partial-body clips**; missing tracks currently fall back to that character's bind pose and need a base pose or layer for gameplay.

## Collection and files

| Recovered input | Imported result |
| --- | --- |
| 560 character occurrences | 202 distinct textured, rigged models, including variants and LODs |
| 1,178 animation occurrences | 402 distinct original clips |
| Original character rigs | 26 native parts; no mapping to the retired prototype skeleton |

Characters are deduplicated by geometry, influences, bind transforms and texture content; motions by full track data. Every occurrence remains in `resources/recovered/catalogue.json`. All models use **0.1 metres per source unit**, without individual normalization. The largest measured influence bind-position discrepancy in the glTF conversion was **0.102 mm**. All positive weights are retained, up to Godot's eight-influence limit; larger counts are rejected.

| Files | Purpose |
| --- | --- |
| `art/blender/recovered_char_*.blend` | 202 editable character sources |
| `art/models/recovered_char_*.glb` | Their exported Godot models |
| `art/blender/textures/recovered_characters/` | Content-hashed source textures |
| `art/blender/recovered_motion_library.blend` | Reference SEAL with all 402 actions for Blender inspection/editing |
| `resources/recovered/native.res` | Runtime raw native tracks and per-character bind calibration, including the pilot SEAL |
| `resources/recovered/catalogue.json` | Names, categories, provenance, duplicate occurrences, partial/extra tracks and original root travel |
| `tests/fixtures/recovered_fidelity.json` | Representative deformation expectations computed directly from decoded archive data |

`soldier.blend/glb`, `soldier_recovered.blend/glb`, and `original.res` / `soldier.res` are historical prototype/retarget experiments. They are not the runtime character or animation source. The default rebuild no longer requires or exports the old player rig. `--legacy-retarget` explicitly opts into that retired experiment.

## How playback preserves the recovered models

`native_motion_player.gd` reconstructs the original local and global transforms from decoded tracks, then converts them into each imported skeleton's bone axes. The conversion is derived from the original native bind matrices and the imported global rest transforms. It does not rescale limb lengths or alter weights. Matching bone names alone is insufficient: Blender changed local axes, and the pilot SEAL and later collection imports have different axes despite identical names. Directly attaching the old exported AnimationLibrary caused the distorted Recovery Lab model.

Horizontal root travel is held at the character's native bind X/Z for controller-driven, in-place playback. Vertical source motion remains, except during gameplay jumps where capsule physics supplies vertical travel. Raw tracks, including weapon/helper tracks and root travel, remain in `native.res` and the decoded collection.

`recovered_locomotion.gd` chooses full-body clips and crossfades local transforms over 0.12 seconds. Running has no procedural hand-axis/torso correction, so its settled pose matches the Lab at any camera pitch. Jumping maps the physical flight phase to frames 7–19 of `seal_jump`, then plays `seal_land_soft`. Diving follows `seal_dive2prone` through its last authored frame before blending into prone, retaining its authored root height. The decoder appends a copy of frame zero at `frameCount`; one-shot playback must stop before this wrap sample. Side dives also have a small controller-driven bank.

The recovered M4 follows the native right-hand `rifle` track. Other long-gun classes currently share this M4 visual; pistols and equipment still use placeholders. Dedicated weapon models, precise sockets, pitch-aware aiming and action layers remain follow-up work. Ragdolls inherit the selected character and initial native pose, but use the prototype physics bodies.

## Rebuild

The local decoded recovery tree is required only to rebuild, not to run the committed game. See [README.md](README.md) for extraction and Python dependencies. Save work in the agent's Blender instance before recipes open another source.

1. Run `previous/recovery/.venv/bin/python tools/recovery/prepare_characters.py`. It stages glTF interchange files and updates the catalogue. `--motions-only` reuses the prepared character manifest.
2. Run `python3 tools/recovery/collection_calls.py`. Submit the numbered `collection_*.py` recipes printed by this command to Blender MCP's `execute_blender_code`, in order. They import the staged assets and save `.blend` sources; they are not shell Python programs.
3. Export using the project pipeline, then build the runtime library from the decoded native tracks:

```sh
xargs tools/dev blender export < previous/recovery/staging/characters/export_names.txt
tools/dev import
previous/recovery/.venv/bin/python tools/recovery/prepare_native_runtime.py
tools/dev godot --headless --path . --script res://tools/recovery/import_native_library.gd
tools/dev import
tools/dev check
tools/dev test
tools/dev godot --headless --path . --script tests/native_fidelity_regression.gd -- --all-recovered
tools/dev shot recovery_start recovery_character --sheet
```

For runtime decoder/calibration changes only, start at `prepare_native_runtime.py`; rebuilding Blender files is unnecessary unless geometry, bind poses or editable actions changed. Runtime motions currently come from the decoded source, so editing a Blender action alone does not update `native.res`. A future edited-action pipeline must convert its axes back to native space or provide equivalent calibrated tracks.

Prop-budget and static-collision exporter notes are expected for skinned characters; actor collision is supplied separately. Inspect animated feet before changing offsets. Materials approximate base color and alpha cutouts, rather than all original PS2 effects.

## Validation

`recovered_collection_regression` checks all 202 models' skeletons, weights and textures, samples all 402 motions at three times on the Lab rigs, and exercises searching, model selection, switching and gameplay integration. `native_fidelity_regression` compares imported skin deformation with independently decoded archive transforms: 35 committed samples cover five representative rigs including the original pilot. The optional full audit covers **1,421 poses across all 203 imported rigs**, with a measured maximum position error of **0.016 mm** and basis-vector error of **0.000015**.

`recovered_motion_regression` checks that the actual player matches the Lab's run pose, jumping advances once with physics-owned height, landing finishes, and the dive preserves the native pose through a low prone landing. Existing movement, collision, weapon and ragdoll suites remain required. Structural checks and representative screenshots do not establish that every recovered clip is gameplay-ready.

Final validation: `tools/dev check` (81 files) and all 15 regression suites (458 checks) passed. The final rendered session confirmed browser selection and playable native running with no runtime errors.

For the next import tasks, start with [the asset recovery handoff](../../docs/ASSET_RECOVERY_HANDOFF.md).
