# Harness reference

Source: `tools/agent/harness.gd`. Load it with `const H = preload("res://tools/agent/harness.gd")`. Every function takes the `SceneTree` first. The same keys work on the command line: `tools/dev shot level=lab stance=prone step.frames=30 step.forward=1`, or as JSON with `--spec='<json>'` and `--step='<json>'`.

Units: positions are metres `[x, y, z]`; angles are degrees (yaw 0 faces -Z and positive turns left; positive pitch looks up); a frame is one physics tick of 1/60 s.

## Scenarios

`H.scenario(tree, name, overrides := {})` respawns the player as a rifleman, refills every weapon, stands the level's soldiers back up, restores default tuning, then applies the scenario. `overrides` takes any `apply` key.

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
| `reset` | bool | Respawn at the current spawn as a rifleman, refill weapons, clear bullet marks, grenades, smoke and claymores, restore the level's soldiers and default tuning. |
| `level` | `"town"` \| `"lab"` | Switch level if different. `reload: true` forces a reload. |
| `spawn` | index or marker name | Select that spawn and respawn there (`West1`...`East5`; `Start`, `Range`, `Stairs`). |
| `at` | level node path | Teleport to a node, e.g. `"Locations/Market"`, `"Spawns/East3"`. |
| `pos` | `[x, y, z]` | Teleport. Use `y` 0.1 on ground level. |
| `yaw`, `pitch` | degrees | Face a direction. |
| `class` | `"rifleman"` \| `"marksman"` \| `"breacher"` \| `"pointman"` | Change class in place, with a full loadout (`resources/classes/`). |
| `roster` | bool | `false` removes the level's own soldiers (`scripts/combat/roster.gd`) for an experiment that places its own. They return with the next `reset`, so pass it on every scenario that needs the level empty. |
| `actors` | `[{"team": 0\|1, "class": id, "pos": [x, y, z], "yaw": deg, "travel": m, "name": text, "dead": bool}]` | Add stand-in soldiers: team 0 is the player's, `travel` makes one walk that far either side of `pos`, `dead` starts it as a body to search. They last until the next reset or level change. |
| `stance` | `"stand"` \| `"crouch"` \| `"prone"` | Force the stance (no clearance check; see `notes`). |
| `weapon` | `"primary"` \| `"secondary"` \| `"frag"` \| `"smoke"` \| `"flash"` \| `"claymore"` \| slot index | Equip, ready to use at once. Part of a weapon's name works too (`"sniper"`); `notes` says so when the class does not carry it. |
| `ammo`, `reserve` | int | Rounds in the active weapon's magazine / reserve. |
| `health` | float | Player health. 0 eliminates the player: the body stays and the view moves to a teammate. |
| `tuning` | `{"movement"\|"camera"\|"weapon": {property: value}}` | Set profile properties for this run (see `scripts/resources/*_profile.gd`). `weapon` is the active one. |
| `place` | `[{"scene": "res://art/models/crate.glb", "pos": [x, y, z], "yaw": deg, "scale": n}]` | Drop scenes into the level for a look: a model fresh out of Blender, a prop in context. They collide like any level object, last until the next `reset` or level change, and are never saved. |
| `look_at` | `[x, y, z]` or level node path | Put the crosshair on a point, e.g. `"Targets/Target25"`. |
| `hold` | `["aim", ...]` | Keep actions pressed until the next harness call. |
| `panel` | `"class"` \| `"search"` | Open the class menu, or the menu for the body within reach. |
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

Input actions: `move_forward`, `move_back`, `move_left`, `move_right`, `walk`, `jump`, `crouch`, `prone`, `lean_left`, `lean_right`, `fire`, `aim`, `reload`, `equip_rifle` (the primary), `equip_pistol`, `equip_item_1`, `equip_item_2`, `interact` (search a body), `class_menu`, `zoom_in`, `zoom_out`, `ui_up`, `ui_down`, `ui_accept`, `ui_cancel`, `reset_player`, `next_spawn`, `switch_level`, `start_lap`, `debug_view`, `pause`, `tuning`, and the controller-only `pad_stance` (tap crouches, hold goes prone or dives). Holding `crouch` for 0.35 s goes prone; while running forward it dives.

## walk_to(tree, points, speed := 4.0, leg_frames := 900)

Walks `[[x, z], ...]` in order: faces each point and holds forward until within 0.35 m. Adds `walk`: `{"arrived": bool, "seconds": simulated time, "blocked_before": [x, z]}` (the last only when a leg timed out). Waypoints for the three town routes are in `tests/prototype_smoke.gd`.

## state(tree)

```json
{
  "level": "lab", "location": "RIFLE RANGE", "spawn": "Start",
  "menu": false, "frozen": false, "tick": 771,
  "player": {"pos": [23, 0, 5], "yaw": 1.1, "pitch": -2.3, "speed": 0, "vertical_speed": 0,
             "stance": "stand", "on_floor": true, "health": 100, "alive": true, "aiming": false, "diving": false},
  "class": "rifleman",
  "weapon": {"name": "FIELD RIFLE", "slot": 0, "ammo": 24, "reserve": 90, "reloading": false,
             "shots": 6, "hits": 2, "spread": 0.25, "last_damage": 34.0, "scoped": false},
  "carried": [{"name": "FIELD RIFLE", "kind": "firearm", "ammo": 24, "reserve": 90},
              {"name": "SERVICE PISTOL", "kind": "firearm", "ammo": 12, "reserve": 36},
              {"name": "FRAG GRENADE", "kind": "frag", "ammo": 2, "reserve": 0},
              {"name": "SMOKE GRENADE", "kind": "smoke", "ammo": 1, "reserve": 0}],
  "aim": {"hit": "Target10", "point": [23.0, 1.05, -4.94], "distance": 12.95, "muzzle_blocked": false},
  "camera": {"arm": 3.0, "fov": 60.0},
  "targets": {"Target10": {"pos": [23, 1.05, -5], "lit": false, "damage": 34.0}},
  "actors": [{"name": "TANGO 1", "team": 1, "alive": true, "health": 100, "pos": [14, 0, 12]}],
  "live": {"throwable": 1, "smoke_cloud": 1},
  "notice": "Lap started",
  "notes": ["prone has no clearance here; a player could not hold this stance"]
}
```

- `aim.hit` is the node under the crosshair; `aim.distance` is measured from the camera, which sits about 3 m behind the player; `aim.muzzle_blocked` is true when cover stops the bullet near the muzzle.
- `camera.arm` shrinks below the tuned distance when geometry pushes the camera in.
- `weapon.spread` is the current shot cone half-angle in degrees.
- `weapon.slot` is 0 for the primary, 1 for the pistol, 2 and up for equipment; `carried` lists every slot, and for equipment `ammo` is the number left. `weapon.last_damage` is what the most recent hit did after distance and hit region; a shotgun shell counts once in `hits` however many pellets land.
- `targets` appears on the Movement Lab; `lit` is true briefly after a hit and `damage` is what the last hit did.
- `actors` lists the other soldiers, the level's own and any added with `actors`. Team 0 is the player's.
- `live` counts what is in flight or on the ground: `bullet` (a sniper round), `throwable`, `smoke_cloud`, `claymore`, `blast_fx`.
- `watching` appears while the player is eliminated: a teammate's name, or `your body`.
- `placed` lists the scenes added with `place`, when there are any.
- `notice` is the HUD message currently shown; `notes` lists requests that could not be honoured.
- `tick` is the engine's tick counter and keeps counting while frozen.

## Reaching past the harness

Anything not covered is ordinary GDScript against the live tree: `H.session(tree)` is the root session (`scripts/levels/test_session.gd`), with `.player`, `.hud`, and `.level`. Wait with `await tree.physics_frame`. Add a harness helper when you find yourself writing the same snippet twice.
