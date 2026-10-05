---
name: live-game
description: Inspect and change the game while it is running and being played, through the game MCP server (the live link) - read what the player just did, tune movement, camera, and weapon feel at once, look at a pose or animation from any angle or in slow motion, set up a scene, edit any variable, hot-reload edited scripts, restart in place. Use when the user is playing and says how something feels or looks ("walking is slow", "the jump is floaty", "that animation is off", "recoil kicks too much"), asks to change, inspect, or debug the running game, or wants to iterate on feel without restarting.
---

# Working on the running game

The game serves MCP itself while it runs (`scripts/live/`, the `Live` autoload). The `game` MCP server (`tools/agent/live-mcp.mjs`) is the way in: it stays up between games, finds the ones that are running, and forwards each tool call. It is separate from the `godot` server, which works on the project and on hidden sessions of its own.

The link runs in the real game and only there: a window, run as a player runs it (F5 in the editor, `tools/dev play`, or `game_launch`). It never runs in a test: not in a regression suite, not in `tools/dev shot`, not in anything headless or QA. Without the MCP tools, `tools/dev live call <tool> '<json>'` does the same from a shell, and `tools/dev live status` shows what is running.

## It is the user's game

Every tool of the `game` server acts on the real game. There is no test instance behind it and no way to ask it for one, so when the user says "the walk feels slow" and you change it, it changes in the window they are playing.

- **Read freely.** `state`, `telemetry`, `logs`, `screenshot`, `inspect`, `tuning_get` disturb nothing.
- **Change what they asked about.** Do not teleport, respawn, freeze, drive, or restart their game unless the request calls for it, and say what you did.
- **If the game is not running,** say so or open it with `game_launch`. The window does not take their keyboard focus unless you pass `focus: true` because they asked to play now.
- `state` reports `window_focused`: false means they have tabbed away and the game is sitting in its menu.

**An experiment of your own** (measuring a gait, trying a risky change, looking at something without interrupting them) does not belong in their game. Use a hidden QA sandbox: `SOCOM_LIVE_AGENT=<your name> tools/dev live sandbox` prints a port, and `tools/dev live call <tool> '<json>' --port=<n>` reaches it; `tools/dev live stop <n>` ends it. It has default tuning, no sound, and no saved settings. What you learn there is about a test instance: never report it as the state of the user's game, and never do there what they asked to have done in theirs.

## The feel loop

1. **Find out what they felt.** `telemetry` covers the last seconds of actual play: speed in each movement state, how long starts and stops took, jump height and air time, turn rate, shots. "Walking feels slow" should become "walked at 1.6 m/s for 6 s" before anything changes.
2. **Read the values behind it.** `tuning_get` lists movement, camera, and weapon values, which differ from the defaults, and their ranges.
3. **Change it live.** `tuning_set {"changes": {"movement.walk_speed": 2.0}}` takes effect on the next tick. The user sees a notice on their HUD and the value in the F1 menu. Change one thing at a time, by a step they can feel (15 to 25 percent), and say the old and new value.
4. **Let them play, and repeat.** Their next `telemetry` shows whether it did what you meant.
5. **Keep it.** `tuning_save` writes the live values into the default resources under `resources/` (they show in `git diff`). Then run `tools/dev test`: the suites assert on several default speeds and timings, and a deliberate feel change means updating those numbers.

A value that is not in a tuning profile (a constant in a script, a curve, a blend time) is a code change: edit the file, then `reload`.

## Tools

| Tool | Use |
|---|---|
| `state` | Digest of the game now. Cheaper than a picture. |
| `telemetry` | What the player did, in numbers and a timeline. `samples` adds raw rows. |
| `logs` | print output, warnings, and errors with script and line. |
| `screenshot` | `view: "player"` is their screen. `back`, `front`, `left`, `right`, `top`, `quarter`, `orbit` look at a `target` from outside without moving their camera. |
| `filmstrip` | Frames over time in one picture. With `input` it plays that input; without, it records what is happening. |
| `tuning_get` / `tuning_set` / `tuning_save` | Read, change live, and write feel values to the default files. |
| `setup` | Level, spawn, position, facing, stance, class, weapon, ammo, health, soldiers, placed models, menu, freeze: the keys of `tools/agent/harness.gd`, and `scenario` for its named starting points. |
| `play` | Hold input for an exact number of ticks and get the digest: `{"frames": 60, "forward": 1}`, `tap`, `hold`, `turn`, `trace`, `walk_to`. |
| `time` | `frozen`, `scale` (slow motion), `step` (ticks). |
| `inspect` / `set` / `call` | Read variables, write them, and call methods on anything: `player`, `weapon`, `camera`, `soldier`, `hud`, `level`, `actor:<NAME>`, a node path, or a variable chain such as `weapon.recoil`. |
| `eval` | GDScript in the game, with `live`, `session`, `player`, `level`, `tree` in scope. |
| `reload` / `restart` | Bring edited files into the running game. |
| `game_status` / `game_launch` / `game_stop` | Whether the game is running, open it, close one you opened. |

Units: metres `[x, y, z]`, degrees (yaw 0 faces -Z, positive turns left), ticks of 1/60 s.

## After editing code

| Change | Do |
|---|---|
| Function bodies, constants, new functions | `reload`. Takes effect next tick; the game keeps its state. |
| A new variable | `reload` starts it at its declared value on existing nodes. One that holds an object stays null (`still_empty` in the answer): `restart`. |
| `_ready` or `_init` logic, node structure, autoloads, a new `class_name` | `restart`. The player comes back at the same place with the same class, weapon, and tuning. |
| A level scene or a resource | `reload`, then `setup {"level": ..., "reload": true}` to rebuild the level, or `tuning_set {"reset": true}` to re-read tuning defaults. |
| A model (`.glb`) or other imported asset | `tools/dev import`, then `restart`. |

`reload` with no arguments takes every file changed on disk since the game loaded it, including other people's edits in this shared checkout; name `paths` to take only yours. A script that does not compile is refused and the game keeps the version it had. Run `tools/dev check` before `reload` or `restart`, and read `logs {"level": "errors"}` after.

## Looking at animation

- **A pose:** `time {"frozen": true}`, then `screenshot` from `left`, `front`, and `top`. `time {"step": 3}` moves on a few ticks.
- **A motion you can drive:** `filmstrip {"view": "right", "every": 4, "input": {"forward": 1}}`, in a sandbox unless the user wants to watch. Raise `frames` or `every` to cover a whole cycle.
- **A motion the user is doing:** ask them to do it, then `filmstrip` with no input, or `time {"scale": 0.25}` so they can watch it themselves.
- **The numbers driving it:** `inspect {"path": "soldier", "props": "all"}` returns the blend and phase values.

Always put time back: `time {"frozen": false, "scale": 1}`. A banner tells the user the game is held, and Esc releases a freeze.

## Limits

- `setup`, `play`, and `filmstrip` with input close the menu for as long as they run and reopen it. In the user's own game that saves their F1 settings, as closing the menu always does.
- State set by `setup` skips the checks a player is held to; its `notes` say when a state is not reachable by playing.
- `set`, `call`, and `eval` run with the game's full access and are not screened. Keep them to the game.
- One call runs at a time in each game. A call that never returns is given up on after its time allowance; `logs` usually shows the script error that stopped it.
- A game started from the Godot editor comes back from `restart` detached from the editor's debugger and Stop button.

## Troubleshooting

| Symptom | Do |
|---|---|
| "The game is not running" | The user starts it (F5 or `tools/dev play`), or `game_launch` opens it. A sandbox does not count and is never used in its place. |
| The game is running but not found | It was started in QA mode or with `SOCOM_LIVE=0`. Have them restart it; `tools/dev doctor` checks the autoload. |
| `state` or `setup` says the harness did not load | A gameplay change broke `tools/agent/harness.gd`. `logs` has the error; `tools/dev test agent_harness` shows what drifted. |
| A reloaded script misbehaves | `logs {"level": "errors"}`, then fix and `reload`, or `restart`. |
| Tools are missing from the agent | `tools/dev live smoke` tests the whole chain; `tools/dev doctor` checks the registration. |
