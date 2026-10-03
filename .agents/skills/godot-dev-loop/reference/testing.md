# Writing a regression suite

A suite is a script in `tests/` that extends `SceneTree`, loads the real game scene, drives it, prints `PASS`/`FAIL` lines, and exits non-zero on failure. `tools/dev test` discovers it by that `extends SceneTree` line; no registration is needed.

## Skeleton

```gdscript
extends SceneTree

var failures: Array[String] = []
var session: Node3D
var player: PrototypePlayer

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	print("PASS " if condition else "FAIL ", description)
	if not condition:
		failures.append(description)

func frames(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame

func _run() -> void:
	session = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	player = session.player
	await frames(30)

	session.load_level(true)  # true = Movement Lab, false = Old Quarter
	await frames(15)
	player.reset_at(Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 25)))
	await frames(12)
	var start := player.position
	player.test_command = {"move": Vector2(0, -1)}  # x = right, y = -1 forward
	await frames(60)
	player.test_command = {}
	check(start.distance_to(player.position) > 3.85, "Runs about four metres in the first second")

	print("\nRESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
```

## What the runner expects

- One line per check, starting with `PASS ` or `FAIL `. The runner counts them; a suite with no `PASS` line is reported as failed.
- `quit(1)` when anything failed. Always reach `quit()`: a script error before it leaves the process running until the 240 s timeout.
- Put measured values in the description (`"... (%.3f m)" % distance`), so a failure explains itself in the summary.

## How the suites run

`godot --headless --fixed-fps 60 --script res://tests/<name>.gd -- --qa`

- `--fixed-fps 60` steps the simulation as fast as the CPU allows with a constant 1/60 s tick, so results do not depend on machine speed.
- `--headless` means no renderer, audio, or vibration. Assert on state and geometry, not pixels. For pixels use `tools/dev shot` or the `godot-playtest` skill.
- `-- --qa` makes the session ignore saved player tuning and never write settings.

## Useful hooks in the game

- `player.test_command = {"move": Vector2, "jump": bool}` overrides movement input for as long as it is set.
- `player.reset_at(transform)` teleports and fully resets the player and weapon.
- `player.request_stance(0|1|2)` asks for stand, crouch, or prone the way input does, and returns whether there was room.
- `player.weapon.query_aim()` returns what the crosshair would hit; `player.weapon.shoot(hit)` and `player.weapon.tick(delta, fire, reload)` drive the weapon without input.
- `session.load_level(lab)`, `session.reset_player()`, `session.set_modal(open)` switch level, respawn, and open the tuning menu.
- Send real input with `Input.parse_input_event(...)` when the test is about input handling; `tests/feel_regression.gd` has helpers that press controller buttons and move sticks this way.

For known-good coordinates (range targets, the low ceiling, the prone tunnel, stair bases, route waypoints) read `tests/prototype_smoke.gd` and the `SCENARIOS` table in `tools/agent/harness.gd`.
