# Harness reference

Source: `tools/agent/harness.gd`. Load it with `const H = preload("res://tools/agent/harness.gd")`. Every function takes the `SceneTree` first. The same keys work on the command line as `tools/dev shot --spec='<json>'` (apply) and `--step='<json>'` (step, plus `"frames"`).

Units: positions are metres `[x, y, z]`; angles are degrees (yaw 0 faces -Z and positive turns left; positive pitch looks up); a frame is one physics tick of 1/60 s.

## Scenarios

`H.scenario(tree, name, overrides := {})` respawns the player, refills both weapons, restores default tuning, then applies the scenario. `overrides` takes any `apply` key.

| Name | State |
|---|---|
| `town_spawn`, `town_east_spawn` | Old Quarter, first west / east team spawn |
| `town_market` | Facing the arch into the market |
| `town_courtyard` | Courtyard route, looking along it |
| `town_passage` | Inside the covered service passage |
| `town_west_stair` | Foot of the west stair, facing the balcony |
| `lab_start` | Movement Lab start line (distance markers ahead) |
| `lab_range`, `lab_range_moving` | Rifle range, crosshair on the 10 m target / the moving target |
| `lab_low_ceiling` | Crouched under the fixture that rejects standing |
| `lab_prone_tunnel` | Prone in the tunnel that rejects crouching |
| `lab_stairs` | Foot of the stair ramp |
| `lab_wall_camera` | Back against a wall, camera pulled in |
| `menu` | Tuning menu open on the Movement page |
| `rifle_empty`, `pistol_ready`, `crouch_aim` | On the range with an empty rifle / the pistol drawn / crouched in focus aim |

Add a scenario by adding a line to `SCENARIOS`. Prefer markers (`spawn`, `at`) to raw coordinates so level edits do not strand it.

## apply(tree, spec)

Applied in this order; every key is optional. Returns the state digest, plus `notes` for anything that could not be applied.

| Key | Value | Effect |
|---|---|---|
| `reset` | bool | Respawn at the current spawn, refill weapons, clear bullet marks, restore default tuning. |
| `level` | `"town"` \| `"lab"` | Switch level if different. `reload: true` forces a reload. |
| `spawn` | index or marker name | Select that spawn and respawn there (`West1`...`East5`; `Start`, `Range`, `Stairs`). |
| `at` | level node path | Teleport to a node, e.g. `"Locations/Market"`, `"Spawns/East3"`. |
| `pos` | `[x, y, z]` | Teleport. Use `y` 0.1 on ground level. |
| `yaw`, `pitch` | degrees | Face a direction. |
| `stance` | `"stand"` \| `"crouch"` \| `"prone"` | Force the stance (no clearance check; see `notes`). |
| `weapon` | `"rifle"` \| `"pistol"` | Equip, ready to fire at once. |
| `ammo`, `reserve` | int | Rounds in the active weapon's magazine / reserve. |
| `health` | float | Player health. |
| `tuning` | `{"movement"\|"camera"\|"weapon": {property: value}}` | Set profile properties for this run (see `scripts/resources/*_profile.gd`). `weapon` is the active one. |
| `look_at` | `[x, y, z]` or level node path | Put the crosshair on a point, e.g. `"Targets/Target25"`. |
| `hold` | `["aim", ...]` | Keep actions pressed until the next harness call. |
| `debug` | bool | Toggle the diagnostic overlay. |
| `settle` | frames (default 8) | Extra ticks to wait before reading state. |
| `menu` | `true` or page index | Open the tuning menu: 0 Movement, 1 Camera, 2 Controller, 3 Rifle recoil, 4 Pistol recoil, 5 Accuracy. |
| `freeze` | bool | Hold the world still after applying. Sticky until set to `false`. |

World setup always closes the menu first; ask for it again with `menu` if you want it open.

## step(tree, frames, input := {})

Plays exactly `frames` ticks (maximum 3600), then releases everything it pressed.

| Key | Value | Effect |
|---|---|---|
| `forward`, `right` | -1..1 | Analogue movement, like the left stick. |
| `hold` | `["fire", "aim", "walk", "crouch", "lean_left", ...]` | Actions held for the whole window. |
| `tap` | `["jump", "reload", "prone", "equip_pistol", "switch_level", ...]` | Actions pressed on the first tick and released two ticks later. |
| `turn`, `look_up` | degrees per second | Steady turn / pitch change. |
| `trace` | N | Adds `trace`: `[frame, x, y, z, speed]` sampled every N frames. |
| `speed` | 1..8 | Fast-forward. Ticks stay 1/60 s, so results match real time. |

Input actions: `move_forward`, `move_back`, `move_left`, `move_right`, `walk`, `jump`, `crouch`, `prone`, `lean_left`, `lean_right`, `fire`, `aim`, `reload`, `equip_rifle`, `equip_pistol`, `reset_player`, `next_spawn`, `switch_level`, `start_lap`, `debug_view`, `pause`, `tuning`, and the controller-only `pad_stance` (tap crouches, hold goes prone or dives). Holding `crouch` for 0.35 s goes prone; while running forward it dives.

## walk_to(tree, points, speed := 4.0, leg_frames := 900)

Walks `[[x, z], ...]` in order: faces each point and holds forward until within 0.35 m. Adds `walk`: `{"arrived": bool, "seconds": simulated time, "blocked_before": [x, z]}` (the last only when a leg timed out). Waypoints for the three town routes are in `tests/prototype_smoke.gd`.

## state(tree)

```json
{
  "level": "lab", "location": "RIFLE RANGE", "spawn": "Start",
  "menu": false, "frozen": false, "tick": 771,
  "player": {"pos": [23, 0, 5], "yaw": 1.1, "pitch": -2.3, "speed": 0, "vertical_speed": 0,
             "stance": "stand", "on_floor": true, "health": 100, "aiming": false, "diving": false},
  "weapon": {"name": "FIELD RIFLE", "ammo": 24, "reserve": 90, "reloading": false,
             "shots": 6, "hits": 2, "spread": 0.25},
  "aim": {"hit": "Target10", "point": [23.0, 1.05, -4.94], "distance": 12.95, "muzzle_blocked": false},
  "camera": {"arm": 3.0, "fov": 60.0},
  "targets": {"Target10": {"pos": [23, 1.05, -5], "lit": false}},
  "notice": "Lap started",
  "notes": ["prone has no clearance here; a player could not hold this stance"]
}
```

- `aim.hit` is the node under the crosshair; `aim.distance` is measured from the camera, which sits about 3 m behind the player; `aim.muzzle_blocked` is true when cover stops the bullet near the muzzle.
- `camera.arm` shrinks below the tuned distance when geometry pushes the camera in.
- `weapon.spread` is the current shot cone half-angle in degrees.
- `targets` appears on the Movement Lab; `lit` is true briefly after a hit.
- `notice` is the HUD message currently shown; `notes` lists requests that could not be honoured.
- `tick` is the engine's tick counter and keeps counting while frozen.

## Reaching past the harness

Anything not covered is ordinary GDScript against the live tree: `H.session(tree)` is the root session (`scripts/levels/test_session.gd`), with `.player`, `.hud`, and `.level`. Wait with `await tree.physics_frame`. Add a harness helper when you find yourself writing the same snippet twice.
