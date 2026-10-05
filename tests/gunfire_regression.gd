extends SceneTree
## Tracers on open guns (first round after a pause, then by chance) and the HUD's red
## marks toward enemy gunfire within its original Sound_Radius.
const H = preload("res://tools/agent/harness.gd")
const TRACER := preload("res://scripts/combat/tracer.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok:
		failures.append(description)

func tracers() -> Array:
	return root.find_children("*", "MeshInstance3D", true, false).filter(func(node: Node) -> bool: return node.get_script() == TRACER)

func _run() -> void:
	check(Gunfire.tracer_due("m4acarbine", true, 0, 0.99) and not Gunfire.tracer_due("m4acarbine", false, 2, 0.99) and Gunfire.tracer_due("m4acarbine", false, Gunfire.TRACER_GAP, 0.99), "Rule: a first round is a tracer, then by chance, never past the gap")
	check(not Gunfire.tracer_due("m4acarbine_sd", true, 99, 0.0) and not Gunfire.tracer_due("mp5sd", true, 99, 0.0), "Suppressed guns never fire tracers")
	check(Gunfire.sound_radius("m4acarbine") == 100.0 and Gunfire.sound_radius("mp5sd") == 5.0, "Sound radius is the original record's (M4 100 m, HK5SD 5 m)")
	var session: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	var player: PrototypePlayer = session.player
	await H.scenario(self, "lab_range", {"roster": false, "freeze": true})
	await H.step(self, 1, {"tap": ["fire"]})
	var first := tracers()
	check(first.size() == 1 and first[0].ally, "The first rifle round after a pause is a green (own side) tracer")
	await H.step(self, 60)
	check(tracers().is_empty(), "The tracer flies out and is gone")
	# A long automatic string: the first is a tracer, more follow by chance, never 7 apart.
	player.weapon.profile.fire_mode = 3
	var seen := 0
	var gap := 0
	var worst := 0
	var before := player.weapon.shots_fired
	for tick: int in range(120):
		var count := tracers().size()
		await H.step(self, 1, {"hold": ["fire"]})
		if player.weapon.shots_fired > before:
			before = player.weapon.shots_fired
			if tracers().size() > count:
				seen += 1
				gap = 0
			else:
				gap += 1
				worst = maxi(worst, gap)
		if player.weapon.ammo <= 0:
			break
	var rounds := player.weapon.shots_fired - 1
	check(rounds >= 20 and seen >= 3 and seen < rounds and worst <= Gunfire.TRACER_GAP, "%d automatic rounds mix in %d tracers, never more than %d apart (longest %d)" % [rounds, seen, Gunfire.TRACER_GAP, worst])
	await H.scenario(self, "lab_range", {"roster": false, "freeze": true})
	player.weapon.profile.recovered_model = "m4acarbine_sd"
	await H.step(self, 40)
	await H.step(self, 1, {"tap": ["fire"]})
	check(tracers().is_empty(), "A suppressed rifle fires no tracer")
	player.weapon.profile.recovered_model = "m4acarbine"
	await H.step(self, 60)

	# An enemy 20 m to the player's left fires bursts: a red mark on the left of the ring.
	var indicator: Control = session.hud.gunfire_indicator
	var left := player.global_position - player.global_basis.x * 20.0
	await H.scenario(self, "lab_range", {"roster": false, "freeze": true, "pitch": 0.0, "actors": [{"team": 1, "pos": [left.x, 0.0, left.z], "fire": 1.0, "name": "SHOOTER"}]})
	var red := false
	for tick: int in range(50):
		await H.step(self, 1)
		red = red or tracers().any(func(node: Node) -> bool: return not node.ally)
	var marks: Array = indicator.marks.values()
	check(marks.size() == 1 and indicator.bearing(marks[0].origin) < -1.2, "Enemy fire within earshot marks the ring on its side (bearing %.2f)" % (indicator.bearing(marks[0].origin) if not marks.is_empty() else 0.0))
	check(red, "The enemy's tracer burns red")
	await H.step(self, 150)
	check(not indicator.marks.is_empty(), "The mark holds while the enemy keeps firing")
	# Beyond the rifle's 100 m, or a teammate's fire, leaves no mark.
	var far := player.global_position - player.global_basis.x * 130.0
	await H.scenario(self, "lab_range", {"roster": false, "freeze": true, "actors": [{"team": 1, "pos": [far.x, 0.0, far.z], "fire": 1.0}, {"team": 0, "pos": [left.x, 0.0, left.z], "fire": 1.0}]})
	indicator.marks.clear()
	await H.step(self, 90)
	check(indicator.marks.is_empty(), "Enemy fire beyond its sound radius and a teammate's fire leave no mark")
	print("RESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
