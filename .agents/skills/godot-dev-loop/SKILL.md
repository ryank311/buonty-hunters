---
name: godot-dev-loop
description: Check, test, and look at changes to this Godot 4 project from the terminal with tools/dev. Use after editing any GDScript, scene, resource, or shader here; when asked to build, validate, run the regression suites, or capture screenshots of the game; when a script will not parse, a test hangs, or Godot behaves oddly; and before reporting any change as done.
---

# Godot dev loop

Every change goes through the same three steps, cheapest first. Fix the first failure before moving on.

| Step | Command | Time | What it proves |
|---|---|---|---|
| Check | `tools/dev check` | ~1 s | Every script, scene, resource, and shader loads. Errors come back as `path:line: message`. |
| Test | `tools/dev test [suite...]` | ~10 s | The core regression suites in `tests/` pass, plus any you name. |
| Look | `tools/dev shot <scenario...>` | ~4 s + 0.3 s each | What the player actually sees, as PNG files you can read. |

Run these from the repo root, spelled exactly as above (they are pre-approved in that form).

## Check

Run it after every edit, before anything slower. GDScript is only compiled when loaded, so a typo, a wrong argument count, or a broken `res://` path stays invisible until something loads the file. One real error often produces a trail of `Failed to compile depended scripts`; fix the first `Parse Error` and re-run.

## Test

```sh
tools/dev test                            # the core suites (tests/core.txt), about 10 s
tools/dev test weapons_regression throw_regression   # the suites for what you touched
tools/dev test --all                      # every suite, over a minute
```

Run the core after every change, and the suite for the area you changed while you iterate on it. Run `--all` once at the end of a large change or before a handover, not after every edit, and never two runs at once: the runner already starts as many suites as the machine should carry (`SOCOM_TEST_JOBS`, default two fewer than its cores), and a second run only slows both and the game someone is playing.

A passing run prints one line per suite and the total time. A failing run lists the failed checks, any script errors, and the log path under `.agent/logs/`. A suite that takes over 20 s is marked `SLOW`; trim it. A suite whose scripts fail to compile never reaches `quit()`, so the runner kills it after 240 s and reports `TIMEOUT`; running `check` first avoids that wait.

| Suite | Covers | Time |
|---|---|---|
| **Core** | | |
| `prototype_smoke` | Both graybox levels load; spawns, running, braking, jump, stance clearance, stairs, camera collision, shooting and reload, menu pause | 8 s |
| `movement_regression` | Planted feet hold the ground in every gait, a raised weapon stays on target while moving, prone, standing, and diving on a slope | 8 s |
| `agent_harness` | `tools/agent/harness.gd` against the game: every scenario, stepping, freeze, tuning reset | 12 s |
| **Movement and input** | | |
| `combat_movement_regression` | Shot cone by movement and stance, the reticle's parts, tap and hold on the stance key, the dive | 6 s |
| `feel_regression` | Controller input through InputMap, menus by pad, weapon swap and reload rules, recoil arithmetic, saved settings | 8 s |
| `camera_regression` | The 640x480 frame at any window size, framing, the reticle under recoil, the camera under a low ceiling | 9 s |
| `traversal_regression` | Stepping up, jumping, and climbing | 9 s |
| `context_actions_regression` | Context actions and their prompts: climbing a ledge, doors, searching a body | 11 s |
| `analog_footsteps_regression` | Stick deflection to gait, footfall sounds | 8 s |
| `window_focus_regression` | Losing and regaining window focus | 3 s |
| **Combat** | | |
| `weapons_regression` | Class loadouts, damage and falloff, sniper bullet flight and scope, grenades, smoke, flashbangs, claymores, elimination and spectating, searching bodies, level rosters | 17 s |
| `throw_regression` | Grenade throws: strength by hold or trigger squeeze, the arc shown, a soldier's own grenade | 12 s |
| `impact_regression` | Bullet-hole decals: placement, orientation, budget, level change | 3 s |
| `ragdoll_regression` | Death ragdolls: direction, rest, reset | 5 s |
| **HUD** | | |
| `hud_layout` | Safe area, clipping, and overlap at several resolutions; tuning pages fit | 4 s |
| `recovered_hud_regression` | The recovered reticles through loadout, aim, and throw | 5 s |
| `debug_loadout_regression` | The debug menu's weapon, equipment, and character selectors | 4 s |
| **The recovered soldier in play** | | |
| `recovered_motion_regression` | Run, pistol layering, jump, landing, and dive poses against the source clips | 6 s |
| `recovered_actions_regression` | Jump takeoffs and weapon swaps on the native rig | 12 s |
| `recovered_gunplay_regression` | Aim and fire poses, recoil on the arms, reloading, switching weapons | 10 s |
| `recovered_lean_prone_regression` | Leans and the prone crawl | 23 s |
| `recovered_accuracy_regression` | The original accuracy tables and fire modes | 5 s |
| **Recovered assets** (after a re-export from `tools/recovery`) | | |
| `recovered_collection_regression` | Every exported character and clip | 16 s |
| `recovered_weapons_regression` | Every exported gun | 7 s |
| `recovered_maps_regression` | Every installed map loads and grounds the player at its spawns | 19 s |
| `recovery_regression`, `native_fidelity_regression` | The Blender to Godot pilot and decoded transforms | 8 s |
| **Tooling** | | |
| `live_regression` | The live link: its HTTP endpoint, every tool, script reload | 10 s |

If `agent_harness` fails after a gameplay change, the game's internals moved under the harness. Update `tools/agent/harness.gd` (and its `SCENARIOS`) to match; the screenshot and playtest tooling depends on it.

### Writing tests: seldom

This prototype's feel and features change daily, and the user tunes values while playing. A change is verified by looking at it; git checkpoints are the safety net when something breaks later. Tests are kept for the few things that would break without anyone seeing, and every one added is paid for on every later run and every later change. Before writing one:

- **Would playing for a minute, or reading the diff, show the break?** Then no test. That covers a new feature still being shaped, anything visual (look with `tools/dev shot` or the live link instead), a tuning value, and a fix that is plain in the diff.
- **Is it already covered?** Read the suite for the area first. Extend a check there before adding one, and add a check before adding a file. A new suite needs a new area, not a new feature.
- **Worth a check**: a rule with cases nobody plays through (ammunition conserved across swaps and cancelled reloads, a settings file from an older version), a silent drift (feet sliding over the ground, the barrel straying off aim), something that has already broken more than once, and tooling other tools stand on.

When a check fails after a change you meant to make, do not re-baseline its number. Either the check holds a behaviour that still matters, in which case make it independent of the value, or it does not, in which case delete it. Delete the checks for anything you remove or replace. [reference/testing.md](reference/testing.md) has the skeleton and how to write a check that survives retuning.

## Look

Headless runs have no renderer, so anything visual needs a window. `tools/dev shot` opens a hidden one that never takes focus, so it is safe while someone is using the machine.

```sh
tools/dev shot                       # list scenarios
tools/dev shot lab_range town_market # one PNG each, paths printed as SHOT {...}
tools/dev shot --all --sheet         # contact sheets, six scenarios per image
tools/dev shot lab_range --state     # add the state digest (positions, ammo, aim target)
tools/dev shot lab_range ammo=0 stance=crouch                 # a scenario with overrides
tools/dev shot level=lab pos=0,0.1,20 stance=prone yaw=90     # any state, saved as custom.png
tools/dev shot lab_start step.frames=45 step.forward=1        # capture mid-run
tools/dev shot lab_start class=breacher weapon=frag            # another class, equipment in hand
tools/dev shot lab_start health=0                             # the eliminated view, watching a teammate
tools/dev shot --model=crate                                  # a model from art/models in the lab
```

`key=value` arguments are the harness `apply` keys and `step.key=value` the `step` keys; lists are comma-separated (`hold=aim,fire`). Nested keys such as `tuning` need the JSON forms `--spec='{...}'` and `--step='{...}'`, which an auto-approved command cannot carry, so expect a permission prompt for those.

Read the printed PNG path to see the frame. Prefer `--state` when a number answers the question (did the shot hit, where is the player, is the menu open); it costs far less than an image. Use `--sheet` when comparing many places at once, for example after a lighting or HUD change.

Scenarios and the keys are defined in `tools/agent/harness.gd`. To drive the game interactively (several inputs, reproduce a bug, tune values live), use the `godot-playtest` skill. To build or change a 3D model, use the `blender-modeling` skill.

## Godot rules that cost time when missed

- **Indent GDScript with tabs.** Mixed indentation is a parse error.
- **A new `class_name` or a new asset needs an import pass** before other files can use it: `tools/dev import`. The global class list and import cache live in `.godot/` and only the editor or an import refreshes them. `tools/dev doctor` reports classes missing from the cache.
- **`.uid` files travel with their script.** Move, rename, or delete `foo.gd` and `foo.gd.uid` together. Never write one by hand; the import pass creates them.
- **Never edit `.godot/`, `.mcp/`, or `.agent/`.** They are caches and tool output.
- **Do not run `tools/build_graybox.py`** unless asked. It regenerates the level scenes and audio and overwrites manual edits to them.
- **Launch Godot through `tools/dev godot ...`**, never the bare binary. The wrapper finds the engine, keeps a windowed run from taking the user's keyboard focus, and starts game runs in QA mode (saved player tuning ignored, settings never written).
- **Other people and agents share this checkout.** `tools/dev doctor` lists the Godot processes on the project; leave any you did not start. If `check` fails in a file you did not touch, someone may be mid-edit: re-run in a minute, and report it rather than fixing or reverting it.

## When something is off

`tools/dev doctor` checks the engine version against the project, Node, the MCP registration for both agents, a leftover MCP bridge autoload in `project.godot`, and the class cache.
