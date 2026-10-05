extends SceneTree
## Exercise actual input and the visible native rig, including the low-speed
## parts of a pull that used to choose idle and restart the animation.
const H = preload("res://tools/agent/harness.gd")
const Prone = preload("res://scripts/actors/recovered_prone.gd")
var failures: Array[String] = []
var session: Node
var player: PrototypePlayer
var skin: SoldierSkin

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok:
		failures.append(description)

func pose_error(a: Array[Transform3D], b: Array[Transform3D]) -> float:
	var worst := 0.0
	for index: int in range(a.size()):
		worst = maxf(worst, a[index].origin.distance_to(b[index].origin))
		worst = maxf(worst, a[index].basis.get_rotation_quaternion().angle_to(b[index].basis.get_rotation_quaternion()))
	return worst

func place(stance: String = "stand", weapon: String = "primary") -> void:
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true, "stance": stance, "weapon": weapon, "pitch": 0.0})

func _run() -> void:
	session = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	await place()
	player = session.player
	skin = player.soldier.soldier_skin
	var motion: Node = skin.motion
	var driver: RefCounted = skin.driver
	var head: int = motion.rig.names.find("head")
	var root_id: int = motion.rig.names.find("skel_root")
	for weapon: String in ["primary", "secondary"]:
		for stance: String in ["stand", "crouch", "prone"]:
			for side: float in [-1.0, 1.0]:
				await place(stance, weapon)
				var keys := {"hold": ["lean_left" if side < 0.0 else "lean_right", "aim"]}
				await H.step(self, 65, keys)
				var clip := ("seal_p_" if weapon == "secondary" else "seal_") + stance + ("2llean" if side < 0.0 else "2rlean")
				var end: float = motion.get_animation(clip).length - 1.0 / 30.0
				var base: String = clip.replace("seal_p_", "seal_") if weapon == "secondary" and stance == "crouch" else ""
				var expected: Array[Transform3D] = motion.sample(clip, end, base, motion.get_animation(base).length - 1.0 / 30.0 if base != "" else 0.0)
				var offset: Vector3 = motion.local_track(clip, end, "skel_root", expected[root_id]).origin - motion.local_track(clip, 0.0, "skel_root", expected[root_id]).origin
				expected[root_id].origin.x += offset.x
				expected[root_id].origin.z += offset.z
				var error := pose_error(driver.last_pose, expected)
				check(driver.lean.clip == clip and absf(driver.lean.time - end) < 0.0001 and error < 0.002, "%s maps to its last native frame, including root and fallback legs (error %.5f)" % [clip, error])
				check(side * motion.native_worlds[head].origin.x > 0.1 and player.soldier.transform.is_equal_approx(Transform3D.IDENTITY), "%s leans the correct way without an extra proxy tilt" % clip)
				await H.step(self, 90, keys)
				check(pose_error(driver.last_pose, expected) < 0.002, "%s holds without looping back to neutral" % clip)
				await H.step(self, 60)
				check(driver.lean.clip == "" and driver.lean.amount == 0.0, "%s returns to neutral on release" % clip)
	await place()
	await H.step(self, 40, {"hold": ["lean_left"]})
	var previous: Vector3 = motion.native_worlds[head].origin
	var largest := 0.0
	for tick: int in range(60):
		await H.step(self, 1, {"hold": ["lean_right"]})
		largest = maxf(largest, previous.distance_to(motion.native_worlds[head].origin))
		previous = motion.native_worlds[head].origin
	check(driver.lean.clip == "seal_stand2rlean" and largest < 0.15, "Reversing lean passes through neutral without a pose snap (%.3f m)" % largest)
	await H.step(self, 40, {"forward": 1.0, "hold": ["lean_right", "aim"]})
	check(player.camera_rig.actual_lean == 0.0 and driver.lean.weight == 0.0, "Moving cancels the camera and native lean")
	await place()
	await H.step(self, 40, {"hold": ["lean_right", "aim"]})
	await H.step(self, 5, {"tap": ["fire"], "hold": ["lean_right", "aim"]})
	check(driver.lean.weight > 0.99 and driver.gunplay.recoil_weight > 0.0 and motion.native_worlds[head].origin.x > 0.5, "Firing adds recoil without replacing the lean")
	await H.step(self, 1, {"tap": ["jump"], "hold": ["lean_right"]})
	check(driver.active_clip == "seal_jump" and driver.lean.weight == 0.0, "Jumping clears the grounded lean layer")
	await place()
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.1, 2.4, 3.0)
	collision.shape = shape
	wall.add_child(collision)
	session.add_child(wall)
	wall.position = player.position + Vector3(0.65, 1.2, 0.0)
	await H.step(self, 70, {"hold": ["lean_right"]})
	check(player.camera_rig.actual_lean > 0.0 and player.camera_rig.actual_lean < 0.5 and motion.native_worlds[head].origin.x < 0.48, "Cover limits the actual lean pose, not the non-linear source frame time")
	wall.queue_free()
	await process_frame
	# Three complete source strides. Each side has its own distance and timing;
	# comparing an arbitrary old 1.15-second interval hides or invents drift.
	for side: float in [-1.0, 1.0]:
		await place("prone")
		var rate: float = player.movement.prone_speed * player.movement.prone_strafe_multiplier
		var count := roundi(3.0 * Prone.cycle_distance(motion, side) / rate * 60.0)
		var start := player.position
		var slow := INF
		var fast := 0.0
		var synced := true
		var source_error := 0.0
		var clip := Prone.clip_for(side)
		for tick: int in range(count):
			await H.step(self, 1, {"right": side})
			slow = minf(slow, absf(player.velocity.x))
			fast = maxf(fast, absf(player.velocity.x))
			synced = synced and driver.active_clip == clip and absf(driver.time / motion.get_animation(clip).length - player.prone_strafe_phase) < 0.00001
			if driver.transition >= 1.0:
				var expected: Array[Transform3D] = motion.sample(clip, driver.time)
				Prone.extract_hip_travel(motion, expected, clip)
				source_error = maxf(source_error, pose_error(driver.last_base_pose, expected))
		var average := absf(player.position.x - start.x) / (count / 60.0)
		check(synced and source_error < 0.002, "%s stays on the exact physics phase through every slow reach (pose error %.5f)" % [clip, source_error])
		check(slow < rate * 0.2 and fast > rate * 2.0 and absf(average - rate) < 0.01, "%s uses native pulls and preserves average travel (%.3f–%.3f m/s, mean %.3f, target %.3f)" % [clip, slow, fast, average, rate])
		var stopping := player.position
		await H.step(self, 20)
		check(player.position.distance_to(stopping) < 0.005 and driver.active_clip == "seal_prone", "Releasing %s stops travel and settles to prone" % clip)
		# Send a stick value just beyond its deadzone, yielding 15% movement.
		var stick: float = player.camera_settings.pad_deadzone + 0.15 * (1.0 - player.camera_settings.pad_deadzone)
		await H.step(self, 30, {"right": side * stick})
		check(driver.active_clip == clip and player.prone_strafe_phase > 0.0, "Slow stick input keeps %s selected below the old idle threshold" % clip)
		await H.step(self, 1, {"right": -side})
		check(driver.active_clip == Prone.clip_for(-side) and player.prone_strafe_phase < 0.03, "Reversing prone direction starts the matching reach")
		var previous_hand: Vector3 = motion.native_worlds[motion.rig.names.find("lhand")].origin
		var hand_step := 0.0
		for tick: int in range(20):
			await H.step(self, 1, {"right": -side})
			var hand: Vector3 = motion.native_worlds[motion.rig.names.find("lhand")].origin
			hand_step = maxf(hand_step, hand.distance_to(previous_hand))
			previous_hand = hand
		check(hand_step < 0.15, "Reversing %s blends the native reaching hand without a snap (%.3f m)" % [clip, hand_step])
		await place("prone")
		await H.step(self, 45, {"right": side, "hold": ["aim"]})
		check(driver.gunplay.fire_blend > 0.99 and pose_error(driver.last_pose, driver.last_base_pose) < 0.002, "Aiming preserves %s's authored pulling arm and body rhythm" % clip)
	print("RESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
