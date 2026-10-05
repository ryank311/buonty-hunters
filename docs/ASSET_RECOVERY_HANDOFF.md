# Asset recovery handoff

Updated 2026-10-05. This is the starting point for agents importing the remaining disc assets. Read the root `AGENTS.md` and the relevant Blender/Godot skills before editing.

## Direction and current state

Use the recovered assets wherever possible. The user has retired the prototype player appearance and rejected changing recovered proportions to fit it. The player and stand-in actors now use original 26-part characters. Default: `recovered_char_seal_a_cqb`. There are 202 switchable character variants and 402 native motion clips. **[ / ]** switches the player; **Recovery Lab → Tab → Use selected character for player** chooses a specific one. No old-player retarget or leg-motion toggle is needed.

The existing movement, camera, stance, combat and collision controller remains. Native clips now cover basic standing/crouching/prone movement, jumping, landing, diving, raised aim/fire poses, recoil and reloads. Idle timing follows `motion.rdr` rather than raw key duration. Crossfades are 0.12 seconds. Most recovered actions are inspection-ready, not connected to gameplay events. All 43 recovered gun designs (73 geometry variants) are installed. Firearm profiles use their own recovered models and native muzzle markers; equipment still uses placeholder visuals. Recovery Lab → Tab → Guns browses and equips the collection using recovered recoil/spread/modes and prototype damage/ammunition; launchers are inspection-only. Recovery Lab contains a cropped Crossroads plaza with original collision. All 22 multiplayer maps are installed; most individual static props still need integration.

**Multiplayer scope only.** The 12 campaign maps have been removed from the main project. Do not reimport them: `prepare_level.py --all` selects only multiplayer maps, and named preparation and Blender batches reject campaign IDs. Their installed files are preserved locally under `previous/recovery/retired/campaign-project-20261005/` with a hash manifest; the ISO and decoded sources remain intact. Keep shared characters, weapons, motions, props and HUD textures even if their provenance references a campaign archive. Old Quarter and both labs remain development spaces.

## Where to find the assets

| Location | Use |
| --- | --- |
| `previous/SOCOM II - U.S. Navy SEALs (USA).iso` | Original local disc image; preserve it |
| `previous/recovery/index.html` | Searchable offline catalogue |
| `previous/recovery/reports/assets.json` | Authoritative converted asset inventory, names, categories and paths |
| `previous/recovery/reports/libraries.json` | Library occurrences and archive provenance |
| `previous/recovery/reports/validation.json` | Extraction coverage and unresolved texture bindings |
| `previous/recovery/converted/models/` | Textured OBJ/MTL, scene graphs and `.skin.json.gz` character records |
| `previous/recovery/converted/levels/<map-id>/` | Assembled geometry, collision and original placements |
| `previous/recovery/converted/animations/` | Compressed decoded motion JSON |
| `previous/recovery/native/` | Original buffers, records, animations, sound banks and compiled configuration data |
| `resources/recovered/catalogue.json` | Committed deduplicated character/clip manifest with source occurrences |
| `art/blender/`, `art/models/` | Editable sources and exported runtime models |

The offline tree is ignored by Git and by Godot. Back it up separately. A fresh clone can run all normal game tests and use the committed assets without the ISO. Rebuilding the collection or importing additional disc assets requires this tree; recreate it using [the recovery README](../tools/recovery/README.md) if absent. This recovered cooked data and compiled records, not the lost editable source project.

Extraction yielded 15,270 texture entries (3,398 distinct PNG hashes), 4,813 static model entries, 560 character occurrences, 34 assembled levels, 1,178 motion occurrences and 703 decoded configuration records. These are occurrence counts, not unique finished runtime assets. Character/motion deduplication produces 202/402 respectively. Audio/video remain preserved native files rather than transcoded game resources.

## Integration paths and traps

### HUD and crosshairs

The bottom-center context HUD now uses the recovered action icons for functional doors, ledge climbs and body search. All 43 doors across nine multiplayer maps use their native hinge programs and moving collision. Read [ACTIONS.md](../tools/recovery/ACTIONS.md) for controls, reconstruction evidence and remaining mission-action limits.

Read [HUD.md](../tools/recovery/HUD.md). All 174 distinct HUD/HUD2/HUDW textures are committed under `art/ui/recovered/`, with a searchable `index.html` and `resources/recovered/hud_catalogue.json` provenance. Rebuild with `python3 tools/recovery/prepare_hud.py`; no Blender step is needed for these 2D source images. Rifle, sidearm, shotgun, grenade and scope reticles are connected to gameplay, including team tint and the muzzle-obstruction pip. Context action icons are connected as described above; other unused HUD icons remain catalogued. Preserve source padding, alpha and the original 640×448 coordinate mapping. The current angular spread/recoil system is still an approximation; the guide distinguishes recovered constants from adaptations.

### Characters and animations

Read [CHARACTERS.md](../tools/recovery/CHARACTERS.md) for commands, runtime behavior and verification. Key code:

- `prepare_characters.py`: decoded skin data → staged glTF + catalogue; retains all positive weights, original bind positions, texture links and common scale.
- `collection_calls.py` / `blender_characters.py`: bounded Blender MCP recipes → saved `.blend` sources. Default builds no old-player retarget.
- `prepare_native_runtime.py` / `import_native_library.gd`: decoded motions and bind matrices → `resources/recovered/native.res`, plus independently calculated deformation fixtures.
- `native_motion_player.gd`: raw native poses → per-model imported bone axes. `recovery_library.gd` binds it in the Lab and gameplay.
- `soldier_skin.gd`: actual character model, per-instance mesh/material ownership, hand/weapon placement and ragdoll skin. Owned materials avoid stale renderer queries when another instance is removed. `recovered_locomotion.gd`: gameplay clip choice, stationary cycle timing, partial pistol locomotion and jump/dive timing. `recovered_gunplay.gd`: raised fire poses, model-space pitch, upper-body recoil and reload layers synchronized to combat.
- `soldier_proxy.gd`: controller-facing posture bookkeeping and old hidden proxy joints. Many old posture tests inspect those hidden joints; they do not replace native model tests.

**Do not attach raw tracks by matching bone names.** The pilot SEAL and collection imports have different Blender bone axes. The native player uses original bind matrices and imported rest transforms to preserve deformation. Removing that correction mangles the models. Do not change limb lengths or normalize characters individually. Blender action edits currently do not flow into `native.res`; an edited-action pipeline must explicitly convert imported axes back to native transforms.

**One-shots contain a wrap sample.** Decoded clips append frame zero at `frameCount`; last authored time is `(frameCount - 1) / 30`. Sampling the full duration during a dive snaps back to standing. Gameplay jumps skip grounded anticipation, use frames 7–19, hold the source root height at its initial value while physics moves the capsule, then play `seal_land_soft`. Dives must retain their lowering root motion. Running must match the Lab before adding any aim layer; a guessed hand-axis correction previously twisted the torso.

Fifty clips have missing body tracks. The Lab uses bind fallback; gameplay uses the base pose for untracked bones, including rifle legs under partial pistol locomotion. Treat partial clips as layers, not complete poses. Root X/Z motion is held in place for gameplay, and that travel turns each gait's cycle so feet hold the ground (the catalogue's `root_travel_m` is zero for every clip and is not it; see the character guide's Locomotion section). Rifle/pistol/helper tracks are retained. Reload progress/completion now follow the existing combat timer, and successful rounds trigger native recoil. Grenade release, foot contacts, death and interactions still need authored mappings. `seal_fp_*` / `seal_pfp_*` are fire-pose variants; do not classify them as first-person-only assets. See the character guide for the source idle cycles, fire hold, blending and the newly tuned recoil envelope.

**Traversal uses the original dynamics.** `dynamics.rdr` (disc `READERC.ZAR`) supplies gravity 235 units/s² (23.5 m/s²), `step_height` 6.5 units (0.65 m), `max_slope` 50° and the climb bands `low/med/high_climb_height` 1.3/2.15/2.65 m. The climb clips' root rise confirms those bands are metres (`seal_climbcrate` rises 1.29 m, `seal_climb_medium` 2.15 m). The jump apex is a feel choice, 1.0 m, so the player can hop onto obstacles between the step and climb heights; how the original applied `jump_factor` 0.85 is not decoded. `scripts/player/traversal.gd` steps the body onto ledges up to step height and, when Jump is pressed facing a ledge in a climb band with room on top, plays "Climb crate", "Climb medium", or "Stand -> Hang" then "Hang -> Climb", moving the body along the clip's root track scaled to the ledge. `traversal_regression` covers it. Not yet used: hop-downs, `seal_climb_over` (vault), ladders and ladder slides, fall damage (`FALLING_DAMAGE_*`) and the hard landing threshold (`land_hard_fall_rate`).

### Weapons and props

Read [WEAPONS.md](../tools/recovery/WEAPONS.md) for the complete gun collection, native high-detail branch selection, muzzle markers, editable sources, runtime catalogue and rebuild commands. `recovered_weapons.gd` exposes loadable model paths and equip profiles. Read [WEAPON_PROFILES.md](../tools/recovery/WEAPON_PROFILES.md) for the original stance accuracy tables, firing flags, cadence, shared-model profile selection, parser provenance and runtime adaptations. Use [PILOT.md](../tools/recovery/PILOT.md), `prepare_pilot.py`, `pilot_calls.py` and `blender_pilot.py` for the original static-import example. Select source entries by context and content, keep provenance and material references, and choose the intended LOD/state explicitly. Work in bounded batches with separate asset names so agents do not overwrite each other's `.blend` files or manifests.

The established conversion is **0.1 metres per source unit**, Y-up in Godot, canonical forward -Z. Preserve source placement/origin metadata when centering an inspection asset. The pilot M4 was centered for display; the gun collection keeps the original attachment origin directly. `WeaponProfile.recovered_model` selects a catalogue ID; `SoldierSkin` loads both held models and their native muzzle markers. Do not stretch recovered guns. Preserve damage and ammunition rules when changing visuals.

Every installed model needs its `.blend` in `art/blender/` and an export via `tools/dev blender export <name>`. Never hand-edit a final GLB or its `.import`. Copy required textures into the source texture tree, use relative paths, and keep duplicates content-addressed where practical. Materials currently approximate base color, cutouts and roughness. PS2 blending, vertex lighting, original normals, animated materials and billboards need further work; do not claim a pixel-exact reconstruction.

### Levels

The extraction's assembled OBJ is a recovery representation, not a ready-to-play map: it can contain LOD branches, alternate/destroyed states and clutter together. Use the scene graph and placement matrices to select branches and preserve reusable object instances. The Crossroads pilot demonstrates a deliberate crop, source origin and collision filters; its filters are not universal for other maps.

Import original collision separately from render geometry. Recovered concave collision in the pilot needs **`backface_collision = true`**; otherwise some floors can be crossed from above. Exclude non-solid source polygons as the pilot does, inspect winding and scale, and verify spawn grounding, walls, stairs and routes in Godot. Keep existing levels available while adding each recovered map. Do not run `tools/build_graybox.py`; it overwrites level scenes.

**Whole multiplayer maps are installed.** [LEVELS.md](../tools/recovery/LEVELS.md) covers the pipeline: `prepare_level.py` (state/sky/collision selection, original lighting, fog, blend modes and spawns into `resources/recovered/levels/<id>.json`), the batched Blender MCP recipe `blender_level.py`, export, and `scripts/levels/recovered_map.gd` (`RecoveredMap`), which the session loads with `load_map(id)` and the menu lists under **Maps**. `recovered_maps_regression` loads every installed map, checks its fog, sky shader and two-sided collision, and grounds the player at every spawn. Selection rules are name/texture patterns over the assembled OBJ, not the scene graph; spot-check each map and extend `DROP`/`SKY` rather than editing a GLB.

## Suggested next work batches

| Batch | Concrete completion criteria |
| --- | --- |
| Firearms | Collection installed; remaining work includes optional suppressor/thermal-scope configurations, per-gun tuning, launcher firing and underbarrel alternate fire |
| Props | Curate reusable doors, crates, cover and furnishings, retain materials/origins, add appropriate collision and a preview scene |
| Levels | All 22 multiplayer maps are installed. Next: decode team spawns and objectives, PS2 vertex lighting, rain/dust followers, animated/scrolling and additive materials, water and destructible states, AI navigation |
| Actions | Extend the working aim/fire/recoil/reload layers with weapon swap, throw and interaction events; review remaining partial clips and one-shots without changing native proportions |
| Materials/effects | Reconstruct validated PS2 alpha/vertex-lighting cases per material type; preserve original base textures |

Parallel contributors should agree on ownership of shared catalogues, runtime libraries and scenes. Coordinate Blender use too: each agent identity has one shared Blender session. Save current work before a recipe opens another file. Keep manifests deterministic and record source context, transformation choices, validation and unresolved bindings with each batch.

## Verification and handoff requirements

Runtime exports are covered by [the Linux/SteamOS pipeline](LINUX_PLAYTEST.md): `tools/dev build linux` audits all installed GLBs and raw recovery JSON in the exported PCK. Keep newly added dynamic catalogues under the included runtime paths, and extend the inventory if adding another asset format. Do not ship source-only recovery trees or assume an editor-side load proves the packaged build works.

Run `tools/dev import` after new assets or scripts, `tools/dev check` before tests, and `tools/dev test --all` before handing off (a plain `tools/dev test` runs only the core suites). Use focused suites while iterating. For visible changes inspect hidden screenshots or a background Godot MCP session and stop that session before editing again.

- `native_fidelity_regression`: 35 committed archive-derived pose expectations across five representative rigs, including the previously broken pilot SEAL. Optional `--all-recovered` audit checks 1,421 poses across 203 imports after regenerating local staging.
- `recovered_collection_regression`: all 202 models, all 402 clips, searchable browser, live player selection, character switching and persistence.
- `recovered_motion_regression`: gameplay run equals Lab pose at varied view pitch; jump and landing advance once; dive avoids the wrap frame and settles prone.
- `recovered_gunplay_regression`: idle cadence, raised aim and pitch, actual-shot recoil, dry fire, reload progress and cancellation, and partial pistol/prone fire poses.
- `recovered_hud_regression`: recovered weapon reticle selection, actual fire/spread, pellet cone, grenade charge, team identification, muzzle obstruction, scope and modal visibility. See the HUD guide for source-art provenance and remaining engine-behavior approximations.
- `recovered_accuracy_regression`: all playable guns map to source records; stance inheritance, recoil/spread equations, fire-mode flags, cadence and trigger rules.
- `recovered_weapons_regression`: all gun exports, textures, triangle counts, source bounds, muzzle markers, browser search, equip, stance attachments and level changes.
- `recovery_regression`: pilot geometry, textures, collision and traversal. Existing combat, posture, movement, impact and ragdoll suites remain required.

The full native fidelity audit measured at most 0.016 mm translation error and 0.000015 basis-vector error. Run/jump/dive/prone transitions were inspected in the live renderer. These checks preserve source deformation; they do not certify every recovered animation, material or collision branch as finished gameplay content. Add meaningful checks for each newly integrated behavior and state remaining limits in the relevant guide.

Character replacement verification (before the gunplay pass): `tools/dev check` loaded 81 files; `tools/dev test` passed all 15 suites (458 checks); the five extraction tests and recovery Python syntax checks passed. Live inspection covered the Lab button selecting the scuba SEAL, selection surviving a level change, and native running at 4.5 m/s. The final background session stopped with no runtime errors. The ISO, decoded recovery tree and local diagnostic scripts remain outside Git.

Gunplay follow-up verification: `tools/dev check` passed; the full 16-suite run passed, including the previous run/jump/dive regressions. The expanded gunplay suite then passed 16 checks, including actual native forearm deformation and exact recovery to the fire-pose loop. Live inspection covered raised rifle aim, successful-shot recoil/muzzle flash, reloading, and pitched pistol fire; the final session reported no runtime errors. Concurrent live-link tooling is maintained separately from this animation pass.
