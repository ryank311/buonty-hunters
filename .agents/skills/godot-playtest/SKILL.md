---
name: godot-playtest
description: Drive the running game through the godot MCP server and the scenario harness - launch it hidden, jump to any level, spawn, stance, weapon, ammo, or menu state, simulate input tick-exactly, read live state as JSON, take screenshots, walk routes, and profile. Use when a change has to be seen or played to be verified, to reproduce or investigate a gameplay, camera, HUD, or collision bug, to try tuning values against the live game, or whenever asked to run, play, or screenshot the game interactively.
---

# Playtesting through the MCP

The `godot` MCP server (godot-mcp-runtime) launches the game with a small bridge injected, so you can run GDScript inside it, send input, and capture frames. `tools/agent/harness.gd` sits on top and turns "put the game in this state" and "play for N ticks" into one call each.

## The loop

1. **Launch hidden.** `run_project` with `{"projectPath": "<absolute repo root>", "background": true}`, on its own, and wait for it to return before calling any other tool on the server. Always pass `background: true` unless the user asks to watch: a visible window takes their keyboard focus and captures their mouse.
2. **Set up and act** with `run_script` and the harness (below). Each call returns a state digest.
3. **Observe.** Read the digest first. Call `take_screenshot` only when the question is visual.
4. **Stop.** `stop_project` when finished, and before changing code: the running game does not reload scripts. Edit, run `tools/dev check`, launch again.

Every `run_script` body has the same shape:

```gdscript
extends RefCounted
const H = preload("res://tools/agent/harness.gd")
func execute(scene_tree: SceneTree) -> Variant:
	return await H.scenario(scene_tree, "lab_range")
```

The `preload` warning in each response is expected.

## Harness calls

| Call | Does |
|---|---|
| `await H.scenario(tree, "name", overrides := {})` | Respawns cleanly, then applies a named scenario. `H.scenarios()` lists them. |
| `await H.apply(tree, spec)` | Applies any state on top of the current one: level, spawn, position, facing, stance, class, weapon, ammo, health, other soldiers, tuning values, menu page, freeze. |
| `await H.step(tree, frames, input := {})` | Plays exactly `frames` ticks (1/60 s each) holding the given input, then releases it. |
| `await H.walk_to(tree, [[x, z], ...])` | Walks waypoints at 4x speed and reports whether it arrived or where it was blocked. |
| `H.state(tree)` | Returns the digest without changing anything. |

All keys, the scenario list, and the digest fields are in [reference/harness.md](reference/harness.md). Typical bodies:

```gdscript
# Fire a half-second burst at the 10 m target and read the result.
await H.scenario(scene_tree, "lab_range")
return await H.step(scene_tree, 30, {"hold": ["fire"]})   # weapon.shots, weapon.hits, player.pitch

# Is there room to stand under the low ceiling? Tap jump (rises from crouch) and check.
await H.scenario(scene_tree, "lab_low_ceiling")
return await H.step(scene_tree, 20, {"tap": ["jump"]})    # player.stance, notice

# Try a tuning value without editing a resource, then measure one second of running.
await H.scenario(scene_tree, "lab_start", {"tuning": {"movement": {"acceleration": 9.0}}})
return await H.step(scene_tree, 60, {"forward": 1.0, "trace": 10})

# Open the tuning menu on the Camera page for a screenshot.
return await H.apply(scene_tree, {"menu": 1})
```

Combat uses the same calls. Each level starts with two teammates and four enemies (`actors` in the digest; places in `scripts/combat/roster.gd`); `"roster": false` clears them when a test should place its own.

```gdscript
# A frag against one enemy 12 m down the lane: throw, wait out the fuse at 4x speed.
await H.scenario(scene_tree, "lab_start", {"class": "breacher", "weapon": "frag", "roster": false,
	"actors": [{"team": 1, "pos": [0, 0, 14], "name": "TARGET"}]})
await H.step(scene_tree, 6, {"tap": ["fire"]})
return await H.step(scene_tree, 300, {"speed": 4})        # actors[0].alive, live, player.health

# A marksman's scoped shot at the far enemy; the bullet takes a few ticks to arrive.
await H.scenario(scene_tree, "lab_start", {"class": "marksman", "hold": ["aim"], "look_at": [8, 1.5, -30], "settle": 30})
return await H.step(scene_tree, 30, {"hold": ["aim"], "tap": ["fire"]})   # weapon.last_damage, actors

# Eliminate the player, then switch the view: teammates first, then the body.
await H.scenario(scene_tree, "lab_start", {"health": 0})
return await H.step(scene_tree, 4, {"tap": ["lean_right"]})   # watching

# Stand at a body with the search menu open, then take its primary.
await H.scenario(scene_tree, "lab_start", {"panel": "search",
	"actors": [{"team": 1, "class": "breacher", "pos": [0, 0, 24.6], "dead": true}]})
return await H.step(scene_tree, 4, {"tap": ["interact"]})    # carried[0]
```

Several harness calls can share one `run_script` body; return the last digest or build your own dictionary from them.

## Input: what reaches the game

- **`H.step` is the default.** It is tick-exact and repeatable, works while frozen, and handles both polled actions and event shortcuts.
- **MCP `simulate_input` with `key`** (W, A, S, D, F1, F2, Escape, ...) behaves like the keyboard. After the first harness call the game renders one frame per tick, so `{"type": "wait", "frames": 60}` is one second.
- **MCP `simulate_input` with `action`** reaches only actions the game polls: `move_*`, `fire`, `aim`, `jump`, `crouch`, `prone`, `reload`, `walk`, `lean_*`, `equip_*`. Shortcuts handled as events (`pause`, `tuning`, `switch_level`, `reset_player`, `next_spawn`, `debug_view`, `start_lap`) ignore it; use `key` or a harness `tap`.
- **`mouse_motion` does not turn the player** (the game reads screen-relative motion, which injected events lack). Aim with the harness: `yaw`, `pitch`, `look_at`, or `turn` / `look_up` rates in `step`.

## Observing cheaply

- The digest answers most questions: position, speed, stance, ammo, shots and hits, what the crosshair is on, camera arm length, HUD notice text.
- `take_screenshot` returns a 960x540 preview inline and saves the full frame under `.mcp/godot-runtime/screenshots/`. Use `responseMode: "full"` only to read small text.
- `get_debug_output` returns the game's `print()` output and script errors with stack traces. Check it whenever a result looks wrong.
- `get_ui_elements` lists every visible HUD and menu control with its text and rectangle.

## Repeatable timing

- `{"freeze": true}` in `apply` holds the world still between calls; `step` thaws for its window and freezes again. Use it when a moving target or a timer would otherwise drift while you think.
- `{"speed": 4}` in `step` (up to 8) fast-forwards with the tick length unchanged, so the outcome is identical to real time. `walk_to` does this by default.
- A call that plays more than about 25 s of real time needs a larger `timeout` on `run_script`.

## Limits and rules

- `run_script` code is screened. It hard-blocks process execution, `ClassDB.instantiate`, `Expression`, `str_to_var`, and `load()` / `call()` with non-literal arguments. File writes (`FileAccess`, `ConfigFile`, `save_png`, `ResourceSaver`) and networking are flagged in `warnings`; keep them out of snippets. Return data instead of writing files, and take screenshots with `take_screenshot`. Never set `GODOT_MCP_DISABLE_SECURITY`; that is the user's decision.
- The harness sets state by fiat: teleports and forced stances skip the clearance checks a player is held to. The digest's `notes` say when a state is not one a player could reach. Use `step` with real input when the question is "can the player do this".
- One live session per MCP server. The MCP's scene-editing tools refuse to run while it is live.
- Leave `launch_editor` and `attach_project` alone unless asked. The user runs their own editor, and an agent cannot see an editor window.
- The session edits `project.godot` (a temporary `McpBridge` autoload) and restores it on stop. If `tools/dev doctor` reports a leftover line, delete it.
- Without the MCP, `tools/dev shot` with `key=value` and `step.key=value` arguments covers single-shot captures (see the `godot-dev-loop` skill).

## Troubleshooting

| Symptom | Do |
|---|---|
| `run_project` says a session is already active | `stop_project`, then launch again. |
| Harness returns `No running session` | The main scene failed to load. `get_debug_output` shows why; `tools/dev check` usually names the file. |
| `run_script` returns a script error | Read the line number in the message; your snippet is compiled as written, tabs included. |
| A value did not change after an edit | The game was still running the old code. Stop, check, relaunch. |
| A harness call fails with a script error inside `harness.gd` | The game's internals changed under it. `tools/dev test agent_harness` shows what drifted; update `tools/agent/harness.gd`. |
| Tools are missing | `tools/dev doctor`, then `tools/dev mcp-smoke` to test the server end to end. |
