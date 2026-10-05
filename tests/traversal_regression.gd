extends SceneTree
## Stepping, jumping and climbing against the original game's dynamics.rdr limits.
const H = preload("res://tools/agent/harness.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok:
		failures.append(description)

func box(level: Node, size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	body.position = at + Vector3.UP * size.y * 0.5
	level.add_child(body)
	return body

func _run() -> void:
	var session: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	var player: PrototypePlayer = session.player
	# Recovery Lab: the gazebo stands on two 0.2 m tiers that used to stop the player.
	await H.scenario(self, "recovery_plaza", {"roster": false, "freeze": true, "pos": [0.0, 0.05, 10.0], "yaw": 0.0, "pitch": 0.0})
	var forward := -player.global_basis.z
	var start := player.global_position
	var highest := 0.0
	for tick: int in range(70):
		await H.step(self, 1, {"forward": 1.0})
		highest = maxf(highest, player.global_position.y)
	var travelled := (player.global_position - start).dot(forward)
	check(highest > 0.35 and travelled > 3.5, "Walking onto the gazebo steps up both 0.2 m tiers (rose %.2f m, travelled %.2f m)" % [highest, travelled])
	check(absf(player.soldier.position.y) < 0.02, "The soldier's step easing settles back onto the body")

	# Jump: gravity 23.5 m/s^2 and a 0.39 m apex, 0.36 s in the air on flat ground.
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true})
	var ground := player.global_position.y
	await H.step(self, 1, {"tap": ["jump"]})
	var apex := 0.0
	var airborne := 0
	for tick: int in range(60):
		await H.step(self, 1)
		apex = maxf(apex, player.global_position.y - ground)
		if not player.is_on_floor():
			airborne += 1
	check(absf(apex - 0.39) < 0.015, "Jump apex matches the original's 0.39 m (%.3f m)" % apex)
	check(absf(airborne / 60.0 - 0.36) < 0.05, "Jump airtime matches the original's 0.36 s (%.2f s)" % (airborne / 60.0))

	# Climbs: boxes of each band, in an open part of the Movement Lab.
	var level: Node = session.level
	var cases := [
		[0.5, "step", ""],
		[1.0, "low", "climbcrate"],
		[1.8, "medium", "climb_medium"],
		[2.5, "high", "hang2climbup"],
		[3.2, "too high", ""],
	]
	for entry: Array in cases:
		await H.scenario(self, "lab_start", {"roster": false, "freeze": true})
		var origin := player.global_position
		forward = -player.global_basis.z
		var obstacle := box(level, Vector3(3.0, entry[0], 3.0), origin + forward * 2.2)
		await H.step(self, 2)
		if entry[1] == "step":
			for tick: int in range(40):
				await H.step(self, 1, {"forward": 1.0})
			check(player.global_position.y > origin.y + entry[0] - 0.05 and not player.traversal.active, "A %.1f m ledge is walked onto without a climb" % entry[0])
		else:
			for tick: int in range(30):
				await H.step(self, 1, {"forward": 1.0})
				if player.global_position.distance_to(origin) > 1.0:
					break
			await H.step(self, 1, {"tap": ["jump"]})
			var clips: Array[String] = []
			for tick: int in range(240):
				if player.traversal.active and not clips.has(player.soldier.traversal_clip):
					clips.append(player.soldier.traversal_clip)
				await H.step(self, 1)
				if not player.traversal.active and tick > 5:
					break
			if entry[1] == "too high":
				check(clips.is_empty() and player.global_position.y < origin.y + 1.0, "A %.1f m wall is above the original's 2.65 m climb and cannot be climbed" % entry[0])
			else:
				var on_top: bool = player.global_position.y > origin.y + entry[0] - 0.05 and player.is_on_floor()
				check(on_top and clips.any(func(c: String) -> bool: return c.ends_with(entry[2])), "A %.1f m ledge plays the original %s climb and ends standing on top %s (y %.2f)" % [entry[0], entry[1], clips, player.global_position.y - origin.y])
		obstacle.queue_free()
		await H.step(self, 1)

	# No room on top: a ledge under a low roof is not climbed into the roof.
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true})
	var base := player.global_position
	forward = -player.global_basis.z
	var low := box(level, Vector3(3.0, 1.0, 3.0), base + forward * 2.2)
	var roof := box(level, Vector3(3.0, 0.3, 3.0), base + forward * 2.2 + Vector3.UP * 1.6)
	for tick: int in range(30):
		await H.step(self, 1, {"forward": 1.0})
		if player.global_position.distance_to(base) > 1.0:
			break
	await H.step(self, 1, {"tap": ["jump"]})
	await H.step(self, 2)
	check(not player.traversal.active, "A ledge with less than crouching room on top is not climbed")
	low.queue_free()
	roof.queue_free()
	print("RESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
