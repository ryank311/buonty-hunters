# Recovered context actions

The bottom-center action HUD and the action button now share one selection. **F / Y** opens or closes a door, climbs a reachable ledge, climbs a ladder from its foot or its head, or searches a body. On a ladder the stick climbs and descends, and the same button slides down it. The caption identifies the current action; **Tab / D-pad up/down** cycles multiple offers. Nintendo and PlayStation captions use their corresponding north-face-button labels. Jump retains its existing climb shortcut. **T** remains the route timer; using an action never starts it.

## Recovered evidence

- `native/scripts/disc/READERC.ZAR-1b7df1c973/00007-controller.rdr.json`: original `Action` and `Jump` are separate controls (PS2 X and Square). The prototype retains its established modern bindings rather than remapping the entire controller.
- `web/redotcom/docs/research/87-hud.md`, section 5, in the local recovery research: `CZActionBitmap` uses 50×50 icons centered at source x=306, y=365–415; additional icons at ±62 pixels; triangular pulse at 5/s; blue available and grey unavailable colors. The runtime uses the unchanged recovered HUD PNGs and maps the original 640×448 coordinates to this game's viewport. The action bitmaps decode bottom-up and are drawn flipped; at the user's request the pulse is slower (1.4/s, a 1.4 s breath) and keeps 40% of the original brightening, and icons draw at 70% opacity (40% for the unselected neighbours) — see the constants in `scripts/ui/context_hud.gd`.
- Each map's `READERM.ZAR/actions.rdr`: door node, valve, reach, optional elevation/team restrictions, bitmap, and animation. The installed multiplayer maps have **43 doors across nine maps**. Their configured `action_door_open` bitmap is retained for both states, as on the disc; the caption changes to CLOSE DOOR.
- The matching `MZANIM.ZAR` animation supplies the relative hinge quaternion and duration. Frostfire uses 100 degrees in 0.7 seconds; other doors retain their own angles and timings. See local research `92-doors.md` and its original-function references for reach, animation exclusion, valve 99 locking, and moving collision.

All recovery paths above are relative to `previous/recovery/`; runtime never reads that ignored tree. Text captions and selection keys are usability adaptations. This is not a claim that the prototype reproduces the entire original input layout or mission scripting engine.

## Runtime

`scripts/player/context_actions.gd` evaluates the aimed-at door, visible nearby body, and forward ledge. Reach, headroom, stance, ground state, death, and menus gate availability. Presses revalidate the target, so moving away from a prompt cannot operate it. A blocked climb or locked/busy door uses the grey icon and a reason. During traversal, diving, airborne motion, scope, or menus the HUD disappears. Door selection uses the actual camera ray; a wall in front prevents interaction.

`scripts/ui/context_hud.gd` draws the source icons and selected caption. `combat_director.gd` routes the action and selection events and retains its existing loot/class menus. Body search no longer draws a duplicate independent prompt.

`scripts/levels/recovered_actions.gd` partitions the map instance's original render and collision triangles according to the committed ownership manifest. Each door becomes an `AnimatableBody3D` with the source hinge and moving collision. The exported GLB, Blender source, shared cached mesh and texture data remain unchanged. Source-material checks and a mesh-size-derived quantization tolerance accommodate Godot's compressed render positions. Collision matches at full precision. Door movement waits when a soldier occupies the next swing position, and resumes when clear.

## Ladders

**Evidence.** Local research `86-traversal.md`, section 2, read from the game: a ladder is not a named object but two collision quads in one vertical plane whose `m_appflags` is 2, the span from the floor it stands on to the floor it reaches and a cap about a metre tall above it. It is climbed from the side its top floor is not on. `tools/recovery/prepare_ladders.py` finds them in each installed map's `converted/levels/<MAP>/collision.json.gz` and writes `resources/recovered/ladders.json`: **39 ladders on 14 maps**, every one sided by its top floor, matching the research note's table position for position.

**The climb** uses the original clips and numbers (`scripts/player/ladder_climb.gd`): "Stand -> Ladder" at the foot, "Climb ladder" driven by the stick at 0.759 m/s (7.59 source units a second, `ladder_speed` in the movement profile), "Climb off ladder" at the head, and the same clip in reverse to back down onto a ladder from the floor above. The hips stand 0.5565 m in front of the rungs and start the climb-off 0.8824 m under the top floor, the clips' own reference point. There is no turning and no firing on a ladder, and the rifle hangs where each clip's weapon track puts it. The action button plays "Ladder -> slide", falls at gravity x 0.8 in "Ladderslide", and lands with "Ladderslide land". Rungs and the slide play the original `.STEP_LADDER` and `~LADDER_SLIDE` (`tools/recovery/prepare_ladder_audio.ts`, `audio/ladder/`).

**Adaptations.** The original mounts a ladder on contact, with no button; here the foot and the head offer the climb on the action button, with the original climb icon, and nothing happens until it is pressed. The climb cycle advances by height covered rather than time, and the cycles between foot and head are each stretched a little from their authored metre so the last ends exactly where the climb-off begins; the original instead starts the climb-off at the first cycle end that clears the head and sets the soldier on the floor afterwards. The soldier is set down 0.45 m past the rungs (further where a lip or a post is in the way) instead of the clip's 0.3 m, which lies inside the ladder's own collision. Not reconstructed: the "180" turn clip before backing down (the soldier turns as the climb-off reverses), the slide from the head, one soldier to a ladder, and a climb-off reversed by another soldier in the way.

Every ladder on every map was climbed up, backed down from the head, and slid from part-way by `tools/recovery/verify_ladders.gd` on 2026-10-05; five needed care that is now general: a lip or rail post at the head (MP6, MP81), and feet buried up to 2.7 m in sloping ground (MP62).

A ladder in a level built by hand is a `Node3D` with `scripts/levels/ladder.gd`: its origin at the middle of the foot on the plane of the rungs, its -Z facing into the ladder, and its `height` set.

## Rebuilding

From the repository root, with the recovery decoder dependencies already installed:

```sh
TSX_TSCONFIG_PATH=previous/recovery/reports/decoder-tsconfig.json node --import ./previous/recovery/research/socom-unzipped/web/node_modules/tsx/dist/loader.mjs tools/recovery/prepare_actions.ts
previous/recovery/.venv/bin/python tools/recovery/prepare_actions.py
tools/dev import
tools/dev check
tools/dev test context_actions_regression feel_regression traversal_regression weapons_regression
```

Ladders need neither step: `previous/recovery/.venv/bin/python tools/recovery/prepare_ladders.py` reads the converted collision directly and prints each ladder it writes. Afterwards, or after re-exporting a map, climb them all (a few minutes; name maps to visit fewer):

```sh
tools/dev godot --headless --path . --fixed-fps 60 --script res://tools/recovery/verify_ladders.gd -- --qa
```

The TypeScript step decodes the map records, scene transforms, and selected native door programs into ignored staging. The Python step compiles ownership, restrictions, provenance, and unsupported-action diagnostics into `resources/recovered/actions/`. Rebuild this manifest when changing a map export's selected geometry or coordinate origin.

## Limits

This pass operates doors, the existing ledge climbs, and body weapon exchange. Bomb sites, airstrike switches, breach/satchel objectives and turret operation require their own gameplay executors. Unsupported map action records are retained in each manifest's `unavailable` list and are not presented as working actions. Door kick alternatives, character hand-to-handle animation alignment, original door sound events, AI notices and network valve replication are not reconstructed here. The door swing and collision are functional locally; no mission success is invented by activating a switch.

`context_actions_regression` checks every multiplayer door's geometry/collision ownership, original hinge motion, passage clearance, contextual climb completion and headroom refusal, controller use, stale targets, locked doors, modal exclusion, and body search. Existing traversal, combat and controller regressions remain required. Inspect the rendered HUD and actual open/closed passage as well as the test output.
