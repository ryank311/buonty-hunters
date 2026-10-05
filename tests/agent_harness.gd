extends SceneTree
## Keeps tools/agent/harness.gd in step with the game it drives. If a gameplay change
## breaks one of these checks, update the harness (and its scenarios) to match.

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
	for index: int in range(30):
		await physics_frame
		await process_frame
	check(H.session(self) == session, "Harness finds the running session")
	var broken: Array[String] = []
	for title: String in H.SCENARIOS:
		var applied: Dictionary = await H.scenario(self, title)
		if applied.has("error") or applied.has("notes"):
			broken.append("%s: %s" % [title, applied.get("error", applied.get("notes"))])
	check(broken.is_empty(), "Every scenario applies cleanly (%s)" % ("%d scenarios" % H.SCENARIOS.size() if broken.is_empty() else "; ".join(broken)))
	var range_state: Dictionary = await H.scenario(self, "lab_range")
	check(range_state.level == "lab" and range_state.aim.hit == "Target10", "lab_range puts the crosshair on the 10 m target (%s)" % range_state.aim.hit)
	var burst: Dictionary = await H.step(self, 30, {"hold": ["fire"]})
	check(burst.weapon.shots >= 1 and burst.weapon.hits >= 1, "Held fire shoots and hits what the crosshair is on (%d shots, %d hits)" % [burst.weapon.shots, burst.weapon.hits])
	await H.scenario(self, "lab_start")
	var run: Dictionary = await H.step(self, 60, {"forward": 1.0})
	var distance: float = 26.0 - run.player.pos[2]
	var run_speed: float = session.player.movement.run_speed
	check(distance > run_speed * 0.7 and distance < run_speed, "Sixty ticks of forward input run forward (%.2f m at %.1f m/s)" % [distance, run_speed])
	await H.scenario(self, "lab_start")
	var fast: Dictionary = await H.step(self, 60, {"forward": 1.0, "speed": 4})
	check(fast.player.pos == run.player.pos, "Fast-forward lands on the same position as real time (%s)" % str(fast.player.pos))
	await H.scenario(self, "lab_start")
	var jump: Dictionary = await H.step(self, 50, {"tap": ["jump"], "trace": 5})
	var peak := 0.0
	for sample: Array in jump.trace:
		peak = maxf(peak, sample[2])
	check(peak > 0.1 and jump.player.on_floor, "A tapped jump leaves the floor and lands (%.2f m)" % peak)
	var low: Dictionary = await H.scenario(self, "lab_low_ceiling")
	var rise: Dictionary = await H.step(self, 20, {"tap": ["jump"]})
	check(low.player.stance == "crouch" and rise.player.stance == "crouch", "Real input cannot stand under the low ceiling")
	var switched: Dictionary = await H.step(self, 10, {"tap": ["switch_level"]})
	check(switched.level == "town", "Tapped shortcuts reach the session (level switched to %s)" % switched.level)
	var frozen: Dictionary = await H.scenario(self, "lab_range_moving", {"freeze": true})
	for index: int in range(30):
		await physics_frame
	var held: Dictionary = H.state(self)
	check(frozen.frozen and held.targets.MovingTarget.pos == frozen.targets.MovingTarget.pos, "Freeze holds the moving target still between calls")
	var thawed: Dictionary = await H.step(self, 30)
	check(thawed.frozen and thawed.targets.MovingTarget.pos != frozen.targets.MovingTarget.pos, "A step advances a frozen game and freezes it again")
	await H.apply(self, {"freeze": false})
	await H.scenario(self, "lab_start", {"tuning": {"movement": {"acceleration": 9.0}}})
	var tuned: Dictionary = await H.step(self, 60, {"forward": 1.0})
	await H.scenario(self, "lab_start")
	var restored: Dictionary = await H.step(self, 60, {"forward": 1.0})
	check(tuned.player.pos[2] > restored.player.pos[2] + 0.3 and restored.player.pos == run.player.pos, "Tuning overrides apply and a fresh scenario restores the defaults")
	var composed: Dictionary = await H.apply(self, {"level": "town", "at": "Locations/Market", "stance": "crouch", "weapon": "pistol", "ammo": 3, "health": 40, "hold": ["aim"]})
	check(composed.location == "MARKET" and composed.player.stance == "crouch" and composed.player.aiming and composed.weapon.ammo == 3 and composed.player.health == 40, "A composed state lands as described")
	var menu: Dictionary = await H.apply(self, {"menu": 1})
	check(menu.menu and session.hud.current_page == 1, "The tuning menu opens on the requested page")
	var walked: Dictionary = await H.scenario(self, "town_spawn")
	walked = await H.walk_to(self, [[-43, 9], [-43, 6]])
	check(walked.walk.arrived and not walked.menu, "walk_to follows waypoints (%.1f simulated seconds)" % walked.walk.seconds)
	var wrong: Dictionary = await H.apply(self, {"level": "moon", "stance": "fly", "weapon": "bow"})
	check(wrong.get("notes", []).size() == 3, "Requests that cannot be honoured are reported in notes")
	# The reference crate is 1 m wide with a collision box; walking into it must stop the player.
	await H.scenario(self, "lab_start", {"place": [{"scene": "res://art/models/crate.glb", "pos": [0.0, 0.0, 23.0]}]})
	var bumped: Dictionary = await H.step(self, 120, {"forward": 1.0})
	check(bumped.get("placed", []).size() == 1 and bumped.player.pos[2] > 23.7, "A placed model appears in the level and blocks the player (stopped at z=%.2f)" % bumped.player.pos[2])
	var cleared: Dictionary = await H.scenario(self, "lab_start")
	check(not cleared.has("placed"), "A fresh scenario removes placed models")
	print("\nRESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await physics_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
