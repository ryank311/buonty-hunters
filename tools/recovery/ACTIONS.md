# Recovered context actions

The bottom-center action HUD and the action button now share one selection. **F / Y** opens or closes a door, climbs a reachable ledge, or searches a body. The caption identifies the current action; **Tab / D-pad up/down** cycles multiple offers. Nintendo and PlayStation captions use their corresponding north-face-button labels. Jump retains its existing climb shortcut. **T** remains the route timer; using an action never starts it.

## Recovered evidence

- `native/scripts/disc/READERC.ZAR-1b7df1c973/00007-controller.rdr.json`: original `Action` and `Jump` are separate controls (PS2 X and Square). The prototype retains its established modern bindings rather than remapping the entire controller.
- `web/redotcom/docs/research/87-hud.md`, section 5, in the local recovery research: `CZActionBitmap` uses 50×50 icons centered at source x=306, y=365–415; additional icons at ±62 pixels; triangular pulse at 5/s; blue available and grey unavailable colors. The runtime uses the unchanged recovered HUD PNGs and maps the original 640×448 coordinates to this game's viewport.
- Each map's `READERM.ZAR/actions.rdr`: door node, valve, reach, optional elevation/team restrictions, bitmap, and animation. The installed multiplayer maps have **43 doors across nine maps**. Their configured `action_door_open` bitmap is retained for both states, as on the disc; the caption changes to CLOSE DOOR.
- The matching `MZANIM.ZAR` animation supplies the relative hinge quaternion and duration. Frostfire uses 100 degrees in 0.7 seconds; other doors retain their own angles and timings. See local research `92-doors.md` and its original-function references for reach, animation exclusion, valve 99 locking, and moving collision.

All recovery paths above are relative to `previous/recovery/`; runtime never reads that ignored tree. Text captions and selection keys are usability adaptations. This is not a claim that the prototype reproduces the entire original input layout or mission scripting engine.

## Runtime

`scripts/player/context_actions.gd` evaluates the aimed-at door, visible nearby body, and forward ledge. Reach, headroom, stance, ground state, death, and menus gate availability. Presses revalidate the target, so moving away from a prompt cannot operate it. A blocked climb or locked/busy door uses the grey icon and a reason. During traversal, diving, airborne motion, scope, or menus the HUD disappears. Door selection uses the actual camera ray; a wall in front prevents interaction.

`scripts/ui/context_hud.gd` draws the source icons and selected caption. `combat_director.gd` routes the action and selection events and retains its existing loot/class menus. Body search no longer draws a duplicate independent prompt.

`scripts/levels/recovered_actions.gd` partitions the map instance's original render and collision triangles according to the committed ownership manifest. Each door becomes an `AnimatableBody3D` with the source hinge and moving collision. The exported GLB, Blender source, shared cached mesh and texture data remain unchanged. Source-material checks and a mesh-size-derived quantization tolerance accommodate Godot's compressed render positions. Collision matches at full precision. Door movement waits when a soldier occupies the next swing position, and resumes when clear.

## Rebuilding

From the repository root, with the recovery decoder dependencies already installed:

```sh
TSX_TSCONFIG_PATH=previous/recovery/reports/decoder-tsconfig.json node --import ./previous/recovery/research/socom-unzipped/web/node_modules/tsx/dist/loader.mjs tools/recovery/prepare_actions.ts
previous/recovery/.venv/bin/python tools/recovery/prepare_actions.py
tools/dev import
tools/dev check
tools/dev test context_actions_regression feel_regression traversal_regression weapons_regression
```

The TypeScript step decodes the map records, scene transforms, and selected native door programs into ignored staging. The Python step compiles ownership, restrictions, provenance, and unsupported-action diagnostics into `resources/recovered/actions/`. Rebuild this manifest when changing a map export's selected geometry or coordinate origin.

## Limits

This pass operates doors, the existing ledge climbs, and body weapon exchange. Bomb sites, airstrike switches, breach/satchel objectives, turret operation, ladders and their slides require their own gameplay executors. Unsupported map action records are retained in each manifest's `unavailable` list and are not presented as working actions. Door kick alternatives, character hand-to-handle animation alignment, original door sound events, AI notices and network valve replication are not reconstructed here. The door swing and collision are functional locally; no mission success is invented by activating a switch.

`context_actions_regression` checks every multiplayer door's geometry/collision ownership, original hinge motion, passage clearance, contextual climb completion and headroom refusal, controller use, stale targets, locked doors, modal exclusion, and body search. Existing traversal, combat and controller regressions remain required. Inspect the rendered HUD and actual open/closed passage as well as the test output.
