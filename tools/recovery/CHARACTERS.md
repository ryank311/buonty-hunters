# Recovered characters and native motion

## Play and inspect

Restart the game with Godot's Stop and Play buttons. The playable character is now the recovered **seal_A_cqb**, using its original proportions, skin weights and 26-part rig. **[ / ]** cycles through all 202 character variants in either direction. Selection survives respawn and level changes during the current run; restarting selects CQB again.

Open **Cmd+1 / F1 → Recovery Lab**, then press **Tab**. Search the characters and 402 motion clips, or filter clips by category. The left display shows the selected recovered character; the right shows your current playable character. Both sample the same native clip at the same time. Pause, scrub, advance one original 30 Hz frame, or turn the models to inspect them. **Use selected character for player** makes the selected model playable without resetting position, health or ammunition. Tab, Escape or Close returns to walking.

The player uses native standing, walking, running, backpedaling, strafing, crouching, crawling, jump, landing and dive poses, with a short crossfade when changing clips. The existing controller owns movement and collision. This is an initial gameplay hookup, not a completed animation state machine. Raised aiming/fire poses, native recoil, timer-synchronized reloads and weapon swaps are connected. Throws, interactions and most other one-shots still need deliberate integration and event timing. The browser marks **50 partial-body clips**; inspection uses bind fallback; gameplay preserves the base pose on untracked bones. Pistol locomotion uses the matching rifle leg cycle.

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
| `resources/recovered/catalogue.json` | Names, categories, provenance, duplicate occurrences, partial/extra tracks, and `root_travel_m` (always zero: see Locomotion) |
| `tests/fixtures/recovered_fidelity.json` | Representative deformation expectations computed directly from decoded archive data |

`soldier.blend/glb`, `soldier_recovered.blend/glb`, and `original.res` / `soldier.res` are historical prototype/retarget experiments. They are not the runtime character or animation source. The default rebuild no longer requires or exports the old player rig. `--legacy-retarget` explicitly opts into that retired experiment.

## How playback preserves the recovered models

`native_motion_player.gd` reconstructs the original local and global transforms from decoded tracks, then converts them into each imported skeleton's bone axes. The conversion is derived from the original native bind matrices and the imported global rest transforms. It does not rescale limb lengths or alter weights. Matching bone names alone is insufficient: Blender changed local axes, and the pilot SEAL and later collection imports have different axes despite identical names. Directly attaching the old exported AnimationLibrary caused the distorted Recovery Lab model.

Horizontal root travel is held at the character's native bind X/Z for controller-driven, in-place playback. Vertical source motion remains, except during gameplay jumps where capsule physics supplies vertical travel. Raw tracks, including weapon/helper tracks and root travel, remain in `native.res` and the decoded collection.

`recovered_locomotion.gd` chooses full-body clips and crossfades local transforms over 0.12 seconds. Unraised running has no procedural hand-axis/torso correction, so its settled pose matches the Lab at any camera pitch. Forward walk/run jumps use `seal_runningjump_launch` or `seal_p_runningjump_launch` at the authored 30 Hz cadence. Takeoff direction selects the family once; releasing movement in flight does not change it, while changing weapons selects the matching upper-body variant at the same time. A fall that outlasts the launch continues into `seal_runningjump_in_air` and holds its final authored pose. Falling off a ledge starts directly in that airborne take. Stationary, backward and sideways hops retain frames 7–19 of `seal_jump`, driven by physical flight phase. Capsule physics owns jump height throughout. Stationary touchdowns use the rifle/pistol `land_soft` take; moving touchdowns resume gait.

Diving follows `seal_dive2prone` through its last authored frame before blending into prone, retaining its authored root height. The decoder appends a copy of frame zero at `frameCount`; one-shot playback must stop before this wrap sample. Side dives also have a small controller-driven bank.

The recovered M4 follows the native right-hand `rifle` track. Other long-gun classes currently share this M4 visual; pistols and equipment still use placeholders. Dedicated weapon models, precise sockets and remaining action/event layers are follow-up work. Clips using the older `weapon` attachment name are supported alongside `rifle` and `pistol`. Ragdolls inherit the selected character and initial native pose, but use the prototype physics bodies.

## Idle, aiming and gunplay

The raw key duration is not always the gameplay duration. The decoded `READERC.ZAR` `motion.rdr` gives stationary playback cycles of **6 seconds for rifle stand**, **5 for pistol stand and both crouches**, and **3 for prone**. `recovered_locomotion.gd` applies those values without changing the archive library or the Lab's raw timeline. This fixes the fast half-second idle loop. Moving cycles are turned by distance: see Locomotion.

`recovered_gunplay.gd` layers gunplay over that base:

- **Aim / ready:** right mouse button raises the source `seal_fp_*` or `seal_pfp_*` fire pose. An actual shot also raises it, and it remains ready for five seconds after the last shot or aim input. Blend in is 0.1 seconds; lowering takes 0.5 seconds. These are fire poses, not exclusively first-person clips; the browser category now says **Weapon fire poses**. Standing rifle fire cycles in one second; crouched rifle fire in five; other stationary fire poses in one, per `motion.rdr`.
- **Movement and pitch:** fire variants follow the locomotion phase. Where no dedicated fire variant exists, the stance's upper body overlays the existing legs. Missing tracks always preserve the base. While raised, camera pitch (including existing camera recoil) rotates the original aim helper around model-space right; it never guesses yaw from a hand axis. Pitch is limited to ±65° standing/crouched and ±25° prone.
- **Recoil:** only successful rounds trigger a pulse. The difference between the original two recoil poses is applied above the hips, selecting rifle standing/crouch/prone or pistol standing/prone clips. Pistol crouch uses the pistol upper-body delta. A 0.16-second attack/recovery envelope scales by the current weapon's kick and stance stability; this envelope is new tuning, not a recovered original firing rule. Dry triggers, swapping, reloads and airborne/dive states do not keep a stale recoil layer. Camera recoil and damage rules remain owned by combat.
- **Reload:** standing, crouching, prone, moving, pistol and shotgun variants follow the existing reload timer, stop before the appended wrap sample, and blend out. Moving reloads preserve the gait. Changing stance or starting to move retains normalized progress. Swapping cancels the layer and the existing ammo transaction. Animation does not grant ammo or decide shot timing.

The weapon attachment blends with the body pose, then follows the final right-hand transform. Muzzle flashes and shot origins follow the resulting socket. Movement transitions store the unlayered pose separately so recoil/aim cannot accumulate into subsequent crossfades. The Lab remains an inspection of the raw clips; these layers apply only to gameplay.

`recovered_swap.gd` adds the native swap layer after gunplay. Rifle-to-pistol uses `seal_rifle2pistol`, its crouch/prone variants, or the partial `seal_mv_rifle2pistol` while moving; returning to the rifle reverses the take. Moving and airborne swaps preserve the base legs. Rapid reversal turns back from the current source phase. Equipment changes use the rifle/pistol `handsfree` takes, and replacing the active primary uses `seal_swaprifle`. Playback follows the destination weapon's existing draw timer, including its firing lockout, rather than changing gameplay to the longer archive timing. Stow/draw visibility changes are calibrated gameplay choices, not recovered event callbacks. Visible firearms follow the normal stance's native grip sockets: the swap's extra weapon tracks can move away from the hand, most visibly in prone. The layer blends out over 0.08 seconds, and reset clears it. Grenade throwing is mapped by `recovered_throw.gd` (below).

## Locomotion

Feet hold the ground because the legs are driven the way the original drove them. The research under `previous/recovery/research` (the motion player and locomotion notes) describes the original's rules; the numbers come from `motion.rdr` and the clips themselves.

- **Every gait clip carries its ground travel.** `skel_root` moves at a constant speed along the ground in each one: 3.65 m a cycle for `seal_run` (5.77 m/s at its own rate), 1.87 m for `seal_walk_alert`, 3.30 m for the sideways runs, 1.22 m for the crouch walk, 0.86 m for the crawl. Playback holds the root in place, and `recovered_locomotion.gd` reads the travel (`travel()`) to turn the cycle: `cadence = speed / stride`, so the feet cover exactly the ground the controller does. The original did the same; at its 6.5 m/s run it played `seal_run` at 1.13x.
- **The catalogue's `root_travel_m` is not that travel.** The decoder closes every channel on a copy of its first key, so first-to-last key travel is zero for every clip. Read the travel up to the key before the last, scaled by `n / (n - 1)`.
- **Clips are chosen by speed band.** `motion.rdr` gives each clip of a set the speeds it plays between (`transition_speed_A`/`_B`), and two clips share an overlap: forward `seal_walk_alert` 0-4, `seal_jog_alert` 2-6.15, `seal_run` 4.01-6.5 m/s; backward `seal_walk_bw` 0-2.8, `seal_run_bw` 2-3.7; right `seal_rstrafe` 0-2.8, `seal_rstrafe_fast` 1-5, `seal_run_90r` 3-6.5; left `seal_lstrafe` 0-2.3, `seal_lstrafe_fast` 0.9-4.5, `seal_run_90l` 2.5-6.5. These are the player's set in `animset.rdr`; `seal_walk` and `seal_jog` are the guards'. Crouched and prone movement has one clip a direction.
- **Forward and strafe sets mix by direction**, in proportion to the angle of travel, at one shared phase. The strafe clips turn the hips toward the travel, so a diagonal turns them part of the way; the stride of a mix is each clip's stride by its share.
- **A landing at rest plays the landing clip; one that comes down moving runs straight on**, as in the original.
- **Raised weapon.** The strafes, crouch walks, and crawls hold the weapon within about ten degrees of straight ahead through their whole cycle, which is why the original's animation set has "Fire walk", "Fire jog", "Fire run" and their backward and pistol forms but no fire strafe. `aims()` measures this once per clip. A clip that aims by itself is left alone; one that does not takes its fire variant's upper body over its own legs before the direction mix is blended. Laying the standing fire stance over a strafe is wrong: that stance turns the torso 60 degrees right, and the faster left strafes turn the hips 30 to 45 degrees left, a twist of over 100 between them.

Movement speeds in `resources/movement` are the original's top speeds for each set. `tests/movement_regression.gd` measures, in the running game, how far a planted foot slides in each gait, and where the barrel points and how far the chest turns from the hips while aiming on the move.

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

`recovered_motion_regression` checks that the actual player matches the Lab's run pose, jumping advances once with physics-owned height, landing finishes, and the dive preserves the native pose through a low prone landing. `recovered_gunplay_regression` checks idle timing, aim direction, actual-shot recoil, dry fire, reload progress/completion/cancellation, and pistol/prone layers. Existing movement, collision, weapon and ragdoll suites remain required. Structural checks and representative screenshots do not establish that every recovered clip is gameplay-ready.

`recovered_actions_regression` covers forward walk/run jumps with both weapon holds, releasing movement in flight, extended falls, native swap deformation in every stance and while moving, grip placement, visibility, firing lockout, rapid reversal, reload interruption, equipment changes, midair swaps, replacement firearms and reset. Rendered filmstrips complement those checks for takeoff/recovery and standing/prone weapon changes.

The original character replacement passed 15 suites (458 checks). See the handoff for the latest gunplay verification; live inspection covers raised rifle/pistol aim, recoil and reloading in addition to native locomotion.

For the next import tasks, start with [the asset recovery handoff](../../docs/ASSET_RECOVERY_HANDOFF.md).

## Grenade throws in gameplay

`recovered_throw.gd` layers the native `seal_throwgrenade`, `seal_tossgrenade`, `seal_crouch_throwgrenade`, `seal_prone_throwgrenade` and `seal_prone_tossgrenade` takes after gunplay/swaps. Light standing throws use the underhand toss; stronger throws use overhand. Running retains the gameplay strength/style bands but uses the native overhand upper body over the live legs, rather than the old invented sidearm pose. Crouch has one recovered throw for all strengths; prone selects toss/throw. The original rig, bind corrections and authored 30 Hz samples are preserved, ending before the decoder's wrap sample.

Holding progresses to a wind-up pose and waits there. Release continues from that source time; the same clock drives combat's pending release and cooldown. Hold/release frames are respectively 10/13 (standing throw), 16/19 (standing toss), 10/14 (crouch), 18/20 (prone throw), 10/14 (prone toss). These release frames were chosen from the decoded right-hand forward swing and visually checked; they are **not verified original gameplay event times**. Standing stationary throws retain the whole body; moving/airborne throws retain locomotion legs and capsule height using the existing model-space upper-body blend. No pitch twist is added. Stance or strength changes during wind-up crossfade between takes.

`PracticeWeapon.throw_launch()` samples the native release-hand position for both prediction and launch, retaining the existing wall obstruction guard, velocity, gravity and charge controls. Combat alone consumes/refunds ammo. Switching character cancels a pending throw before replacing its driver, refunding only an unreleased grenade. Pistols' partial throw variants, lean tosses, kick and return throws remain available in the Recovery Lab but are not gameplay actions yet.

Visual verification: standing underhand/overhand, crouched, both prone takes and a running throw, plus the player HUD and arc; hidden sandbox logs were clear. Existing throw/reticle/layout suites cover trajectory prediction, inventory, input and presentation layout.
