---
name: godot-dev-loop
description: Check, test, and look at changes to this Godot 4 project from the terminal with tools/dev. Use after editing any GDScript, scene, resource, or shader here; when asked to build, validate, run the regression suites, or capture screenshots of the game; when a script will not parse, a test hangs, or Godot behaves oddly; and before reporting any change as done.
---

# Godot dev loop

Every change goes through the same three steps, cheapest first. Fix the first failure before moving on.

| Step | Command | Time | What it proves |
|---|---|---|---|
| Check | `tools/dev check` | ~1 s | Every script, scene, resource, and shader loads. Errors come back as `path:line: message`. |
| Test | `tools/dev test [suite...]` | ~17 s for all | The headless regression suites in `tests/` pass. |
| Look | `tools/dev shot <scenario...>` | ~4 s + 0.3 s each | What the player actually sees, as PNG files you can read. |

Run these from the repo root, spelled exactly as above (they are pre-approved in that form).

## Check

Run it after every edit, before anything slower. GDScript is only compiled when loaded, so a typo, a wrong argument count, or a broken `res://` path stays invisible until something loads the file. One real error often produces a trail of `Failed to compile depended scripts`; fix the first `Parse Error` and re-run.

## Test

`tools/dev test` runs every suite in parallel; name suites to run fewer (`tools/dev test hud_layout feel_regression`). A passing run prints one line per suite. A failing run lists the failed checks, any script errors, and the log path under `.agent/logs/`.

| Suite | Covers | Time |
|---|---|---|
| `prototype_smoke` | Spawns, movement speeds, jump, stance clearance, camera collision, shooting, menu pause, all three town routes | 16 s |
| `feel_regression` | Limb posture while moving, controller input and menu navigation, weapon swap and reload rules, recoil | 3 s |
| `combat_movement_regression` | Shot spread by movement state, hold-to-prone, dive | 3 s |
| `impact_regression` | Bullet-hole decals: placement, orientation, budget, level change | 2 s |
| `hud_layout` | HUD safe area at several resolutions, minimap, tuning pages fit | 2 s |
| `posture_regression` | Soldier skeleton pose and rifle anchoring | 2 s |
| `agent_harness` | `tools/agent/harness.gd` against the live game: every scenario, stepping, freeze, tuning reset | 3 s |

Run the suites that cover what you touched while iterating, and all of them before you finish. A suite whose scripts fail to compile never reaches `quit()`, so the runner kills it after 240 s and reports `TIMEOUT`; running `check` first avoids that wait.

Any `tests/*.gd` that `extends SceneTree` is picked up automatically. To add one, see [reference/testing.md](reference/testing.md).

If `agent_harness` fails after a gameplay change, the game's internals moved under the harness. Update `tools/agent/harness.gd` (and its `SCENARIOS`) to match; the screenshot and playtest tooling depends on it.

## Look

Headless runs have no renderer, so anything visual needs a window. `tools/dev shot` opens a hidden one that never takes focus, so it is safe while someone is using the machine.

```sh
tools/dev shot                       # list scenarios
tools/dev shot lab_range town_market # one PNG each, paths printed as SHOT {...}
tools/dev shot --all --sheet         # contact sheets, six scenarios per image
tools/dev shot lab_range --state     # add the state digest (positions, ammo, aim target)
tools/dev shot --spec='{"level":"lab","pos":[0,0.1,20],"stance":"prone","yaw":90}'
tools/dev shot lab_start --step='{"frames":45,"forward":1}'   # capture mid-run
```

Read the printed PNG path to see the frame. Prefer `--state` when a number answers the question (did the shot hit, where is the player, is the menu open); it costs far less than an image. Use `--sheet` when comparing many places at once, for example after a lighting or HUD change.

Scenarios and the `--spec` / `--step` keys are defined in `tools/agent/harness.gd`. To drive the game interactively (several inputs, reproduce a bug, tune values live), use the `godot-playtest` skill.

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
