# Regression checks: when and how

## First decide whether to write one

Most changes here get no new test. The game is a prototype whose feel is tuned daily; a change is verified by looking at it (`tools/dev shot`, the `godot` or `game` MCP server), and git checkpoints are what catch a later break: diff, bisect, or revert. A test costs time on every run after it, and work on every change that touches what it pinned.

| The change | Test? |
|---|---|
| A new feature or mechanic still being shaped | No. Look at it and play it. Consider one when it has settled and has a rule worth holding. |
| A speed, height, damage, timing, or any other tuning value | No. Never. |
| How a pose, animation, effect, or HUD element looks | No. Take a screenshot or a filmstrip. |
| A bug fix that is plain in the diff | No. |
| A rule with cases nobody plays through: ammunition across swaps and cancelled reloads, room checks, a settings file from an older version | Yes, one check in the suite for that area. |
| A drift nobody would see in a diff or in a minute of play: feet sliding over the ground, the barrel off aim by degrees | Yes, with a wide limit. |
| The second time the same thing breaks | Yes. |
| Tooling other tools depend on: the harness, the live link | Yes. |

Then look for the place: the table in [SKILL.md](../SKILL.md) lists the suites by area. Extend an existing check before adding one, and add a check to an existing suite before adding a file. A new suite needs a new area of the game, and never goes in `tests/core.txt` unless it is fast, about something every change can break, and blind to tuning.

## A check that lasts

- **Read values from the game; never write them into the check.** Speeds, jump height, magazine sizes, damage, and reload times live in the profiles (`player.movement`, `player.weapon.profile`, `player.camera_settings`).

  ```gdscript
  # Breaks the day someone retunes the run:
  check(distance > 5.8 and distance < 6.0, "Runs 5.9 m in the first second")
  # Holds whatever the run speed is:
  var run_speed: float = player.movement.run_speed
  check(distance > run_speed * 0.7 and distance < run_speed, "Reaches the run speed within a second (%.2f m at %.1f m/s)" % [distance, run_speed])
  ```

- **Compare instead of measuring** where you can: running spreads shots wider than walking, a far hit does less than a near one, prone is steadier than standing.
- **Wait for the event, not for a count of ticks** tuned to today's speed: walk until the player is on the landing, with a limit, not for 170 ticks.
- **One check per behaviour.** Loop over the cases, keep the worst, and report it in one line. Seven window sizes are one check, not forty-two.
- **Assert what a player would notice**, not the internals that produce it today. A check on a private variable of a system that is about to be rewritten is a check to delete.
- **Say what was measured** in the description (`"... (%.2f m)" % distance`), so a failure explains itself in the summary.
- **Use fixed seeds** (`weapon.rng.seed = 7`) for anything random.

When a check fails after a change you meant to make: if it pinned the old value, make it independent of the value; if the behaviour it held is gone, delete it. Updating the expected number is the wrong fix both times. When you remove or replace a system, remove its checks in the same change.

## Keeping it fast

A suite is allowed 20 s; the runner marks a slower one `SLOW`. The costs, measured here:

- About 2.5 s to start Godot and load the game, per suite. This is why a check goes into an existing suite.
- About 6 ms per physics tick with a level's six stand-in soldiers, 3 ms without. Start scenarios with `{"roster": false}` unless the check needs them.
- `H.step()` costs several ticks of overhead and builds a full state digest each call. Use it for a stretch of input; inside a per-tick loop, hold the input once and `await physics_frame`.
- Long waits. Do not sit through an 18 s smoke grenade or a 30 s walk across the map to assert one thing at the end; shorten the timer on the object, or start next to the place.

## Skeleton

```gdscript
extends SceneTree
## What this suite covers, in a sentence or two.
const H = preload("res://tools/agent/harness.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	print("PASS " if condition else "FAIL ", description)
	if not condition:
		failures.append(description)

func _run() -> void:
	var session: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	await H.scenario(self, "lab_start", {"roster": false})
	var player: PrototypePlayer = session.player

	var run: Dictionary = await H.step(self, 60, {"forward": 1.0})
	var distance: float = 26.0 - run.player.pos[2]
	var run_speed: float = player.movement.run_speed
	check(distance > run_speed * 0.7 and distance < run_speed, "Reaches the run speed within a second (%.2f m at %.1f m/s)" % [distance, run_speed])

	print("\nRESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
```

`tools/dev test` discovers any `tests/*.gd` that `extends SceneTree`; no registration is needed. After adding a file, run `tools/dev import` so it gets its `.uid`.

## What the runner expects

- One line per check, starting with `PASS ` or `FAIL `. The runner counts them; a suite with no `PASS` line is reported as failed.
- `quit(1)` when anything failed. Always reach `quit()`: a script error before it leaves the process running until the 240 s timeout.

## How the suites run

`godot --headless --fixed-fps 60 --script res://tests/<name>.gd -- --qa`

- `--fixed-fps 60` steps the simulation as fast as the CPU allows with a constant 1/60 s tick, so results do not depend on machine speed.
- `--headless` means no renderer, audio, or vibration. Assert on state and geometry, not pixels. For pixels use `tools/dev shot` or the `godot-playtest` skill.
- `-- --qa` makes the session ignore saved player tuning and never write settings.
- The live link (`scripts/live/`) never starts in a suite. `tests/live_regression.gd` builds its own server on a private port.

## Useful hooks in the game

- The scenario harness, `tools/agent/harness.gd`: `H.scenario(tree, name, overrides)` puts the game in a named state, `H.apply(tree, spec)` in any state (level, position, stance, class, weapon, ammunition, actors, tuning), `H.step(tree, frames, input)` plays real input for an exact number of ticks, and `H.state(tree)` returns a digest. Its header documents every key.
- `player.test_command = {"move": Vector2, "jump": bool}` overrides movement input for as long as it is set.
- `player.reset_at(transform)` teleports and fully resets the player and weapon.
- `player.request_stance(0|1|2)` asks for stand, crouch, or prone the way input does, and returns whether there was room.
- `player.weapon.query_aim()` returns what the crosshair would hit; `player.weapon.shoot(hit)` and `player.weapon.tick(delta, fire, reload)` drive the weapon without input.
- `session.load_level(lab)`, `session.reset_player()`, `session.set_modal(open)` switch level, respawn, and open the tuning menu.
- Send real input with `Input.parse_input_event(...)` when the check is about input handling; `tests/feel_regression.gd` has helpers that press controller buttons and move sticks this way.

For known-good coordinates (range targets, the low ceiling, the prone tunnel, stair bases) read the `SCENARIOS` table in `tools/agent/harness.gd` and `tests/prototype_smoke.gd`.
