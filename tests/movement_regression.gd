extends SceneTree
## How the soldier meets the ground. Three things here broke without anyone seeing it in
## a diff, which is why they are tested rather than just looked at:
##
##   - Feet hold the ground. The recovered clips carry their own ground travel, and
##     scripts/actors/recovered_locomotion.gd turns each stride by distance covered. A
##     speed or clip change that is not rate-matched makes the body skate over its feet.
##   - A raised weapon stays on target whichever way the soldier moves. Laying the
##     standing fire stance over a left strafe once wrung the torso 108 degrees round.
##   - Stances work on sloped ground, and a prone soldier lies along the surface. The
##     room checks once took the ground itself for an obstacle.
##
## Speeds come from the movement profile, so retuning feel does not fail this suite.
const H = preload("res://tools/agent/harness.gd")
## The ball of each foot. It counts as planted within DOWN of the lowest it reaches in
## the sample; a backpedalling foot swings only three centimetres higher than that.
const FEET: Array[String] = ["ltoe", "rtoe"]
const DOWN := 0.015
const SLOPE := 25.0
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

func ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame

## Holds movement and actions down as a player's hands would, until let_go().
func hold(input: Dictionary) -> void:
	H._axis("move_forward", "move_back", float(input.get("forward", 0.0)))
	H._axis("move_right", "move_left", float(input.get("right", 0.0)))
	for action: String in input.get("hold", []):
		H._send(action, true)

func let_go(input: Dictionary) -> void:
	H._axis("move_forward", "move_back", 0.0)
	H._axis("move_right", "move_left", 0.0)
	for action: String in input.get("hold", []):
		H._send(action, false)
	await ticks(2)

func bone(title: String) -> Vector3:
	return skin.skeleton.global_transform * skin.skeleton.get_bone_global_pose(skin.bone[title]).origin

## Runs one gait down the lab's open lane and measures how fast a planted foot moves over
## the floor, as a share of body speed. `yaw` turns the player so the travel is along the
## lane whichever way the input points.
func slide(input: Dictionary, yaw: float, stance: String = "stand", weapon: String = "primary") -> Dictionary:
	await H.scenario(self, "lab_start", {"roster": false, "yaw": yaw, "stance": stance, "weapon": weapon, "settle": 2})
	hold(input)
	await ticks(40)
	var samples: Array[Dictionary] = []
	var speed := 0.0
	var slowest := INF
	for tick: int in range(60):
		await physics_frame
		samples.append({"ltoe": bone("ltoe"), "rtoe": bone("rtoe")})
		var now := Vector2(player.velocity.x, player.velocity.z).length()
		speed += now / 60.0
		slowest = minf(slowest, now)
	var clip: String = skin.driver.active_clip
	await let_go(input)
	var slipped := 0.0
	var planted := 0
	for foot: String in FEET:
		var floor_height := INF
		for sample: Dictionary in samples:
			floor_height = minf(floor_height, sample[foot].y)
		for index: int in range(samples.size() - 1):
			var now: Vector3 = samples[index][foot]
			var next: Vector3 = samples[index + 1][foot]
			if now.y - floor_height > DOWN or next.y - floor_height > DOWN:
				continue
			slipped += Vector2(next.x - now.x, next.z - now.z).length() * 60.0
			planted += 1
	var slip := slipped / maxf(1.0, planted)
	return {"speed": speed, "slip": slip, "share": slip / maxf(0.01, speed), "planted": planted, "clip": clip, "steady": slowest > speed * 0.9}

## Aims while moving one way and reports the worst the barrel strays from straight ahead
## and the most the chest is turned from the hips, in degrees, over a stride.
func aim_while(input: Dictionary, weapon: String) -> Dictionary:
	await H.scenario(self, "lab_start", {"roster": false, "weapon": weapon, "pos": [0.0, 0.1, 10.0], "settle": 2})
	var keys := input.duplicate()
	keys["hold"] = ["aim"]
	hold(keys)
	await ticks(30)
	var motion: Node = skin.motion
	var hand: int = motion.rig.names.find("rhand")
	var hips: int = motion.rig.names.find("hips")
	var chest: int = motion.rig.names.find("spinehi")
	var stray := 0.0
	var twist := 0.0
	for tick: int in range(36):
		await physics_frame
		var barrel: Vector3 = (motion.native_worlds[hand] * skin.driver.gunplay.socket).basis.x.normalized()
		stray = maxf(stray, rad_to_deg(barrel.angle_to(Vector3.FORWARD)))
		# Where each bone's bind-pose forward now points, flattened to the ground.
		var hip_facing: Vector3 = motion.native_worlds[hips].basis * (motion.rig.worlds[hips].basis.inverse() * Vector3.FORWARD)
		var chest_facing: Vector3 = motion.native_worlds[chest].basis * (motion.rig.worlds[chest].basis.inverse() * Vector3.FORWARD)
		twist = maxf(twist, absf(rad_to_deg(Vector2(hip_facing.x, hip_facing.z).angle_to(Vector2(chest_facing.x, chest_facing.z)))))
	var result := {"stray": stray, "twist": twist, "clip": skin.driver.active_clip, "raised": skin.driver.gunplay.fire_blend}
	await let_go(keys)
	return result

## Height of the ground under a point, or NAN.
func ground(x: float, z: float) -> float:
	var hit := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 12.0, z), Vector3(x, -2.0, z), 1, [player.get_rid()]))
	return NAN if hit.is_empty() else float(hit.position.y)

func box(size: Vector3, position: Vector3, tilt: float = 0.0) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var form := BoxShape3D.new()
	form.size = size
	shape.shape = form
	body.add_child(shape)
	body.rotation.x = deg_to_rad(tilt)
	body.position = position
	session.level.add_child(body)

## Stands the player on the ramp facing `yaw` (0 is uphill) and lets them settle.
func stand_on_ramp(yaw: float, z: float = 12.0) -> void:
	await H.apply(self, {"pos": [0.0, ground(0.0, z) + 0.05, z], "yaw": yaw, "stance": "stand", "settle": 6})

## Goes prone the way a player does, by holding crouch, and waits for the body to settle.
func lie_down() -> void:
	await H.step(self, 26, {"hold": ["crouch"]})
	await ticks(36)

## How the body is resting: the pitch and roll of its tilt in degrees, and how far its
## origin is off the ground.
func resting() -> Dictionary:
	return {
		"pitch": rad_to_deg(asin((player.resting.basis * Vector3.FORWARD).y)),
		"roll": rad_to_deg(asin((player.resting.basis * Vector3.RIGHT).y)),
		"gap": absf(player.global_position.y - ground(player.global_position.x, player.global_position.z)),
		"box": rad_to_deg(player.collider.basis.get_rotation_quaternion().angle_to(player.resting.basis.get_rotation_quaternion())),
	}

## The angle of the soldier as drawn, from the toes up to the head, in degrees. A prone
## soldier holds the head up to aim, so this is a few degrees even on level ground.
func drawn_angle() -> float:
	var head := bone("head")
	var toe := bone("ltoe")
	return rad_to_deg(atan2(head.y - toe.y, Vector2(head.x - toe.x, head.z - toe.z).length()))

func _run() -> void:
	session = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	await H.scenario(self, "lab_start", {"roster": false})
	player = session.player
	skin = player.soldier.soldier_skin

	# Feet. Each gait: its input, the facing that sends it down the lane, the stance, and
	# the most a planted foot may slide as a share of body speed. The recovered clips are
	# not perfectly planted themselves (a foot rolls from heel to toe, a crouched shuffle
	# drags), so each limit sits above what the source clip measures at its own speed;
	# before the gaits were rate-matched these read 23 to 88 percent.
	var gaits: Array = [
		["run", {"forward": 1.0}, 0.0, "stand", 0.16],
		["walk", {"forward": 1.0, "hold": ["walk"]}, 0.0, "stand", 0.20],
		["backpedal", {"forward": -1.0}, 180.0, "stand", 0.30],
		["strafe right", {"right": 1.0}, 90.0, "stand", 0.22],
		["strafe left", {"right": -1.0}, -90.0, "stand", 0.22],
		["run diagonally", {"forward": 1.0, "right": 1.0}, 45.0, "stand", 0.22],
		["crouch walk", {"forward": 1.0}, 0.0, "crouch", 0.40],
	]
	var skating: Array[String] = []
	var worst := 0.0
	for gait: Array in gaits:
		var result: Dictionary = await slide(gait[1], gait[2], gait[3])
		worst = maxf(worst, result.share)
		if not result.steady or result.planted < 12 or result.share > gait[4]:
			skating.append("%s slides %.2f m/s at %.2f m/s, %.0f%% (limit %.0f%%, %s)" % [gait[0], result.slip, result.speed, result.share * 100.0, gait[4] * 100.0, result.clip])
	check(skating.is_empty(), "Planted feet hold the ground running, walking, backing up, strafing, on a diagonal, and crouched (worst slide %.0f%% of body speed%s)" % [worst * 100.0, "" if skating.is_empty() else "; " + "; ".join(skating)])
	var pistol: Dictionary = await slide({"forward": 1.0}, 0.0, "stand", "secondary")
	check(pistol.steady and pistol.share < 0.16, "With a pistol the rifle's leg cycle holds the ground under the pistol upper body (%.0f%%, %s)" % [pistol.share * 100.0, pistol.clip])

	# Aiming on the move. A person can turn the chest about 45 degrees from the hips;
	# the standing fire stance itself is 38 over running legs.
	var directions: Array = [
		["forward", {"forward": 1.0}, "primary"], ["back", {"forward": -1.0}, "primary"],
		["left", {"right": -1.0}, "primary"], ["right", {"right": 1.0}, "primary"],
		["forward and left", {"forward": 1.0, "right": -1.0}, "primary"], ["back and right", {"forward": -1.0, "right": 1.0}, "primary"],
		["left with a pistol", {"right": -1.0}, "secondary"], ["forward and right with a pistol", {"forward": 1.0, "right": 1.0}, "secondary"],
	]
	var strayed: Array[String] = []
	var widest := 0.0
	var loosest := 0.0
	for direction: Array in directions:
		var aim: Dictionary = await aim_while(direction[1], direction[2])
		widest = maxf(widest, aim.twist)
		loosest = maxf(loosest, aim.stray)
		if aim.raised < 0.99 or aim.stray > 15.0 or aim.twist > 50.0:
			strayed.append("%s: barrel %.0f deg off, chest %.0f deg from hips, %s" % [direction[0], aim.stray, aim.twist, aim.clip])
	check(strayed.is_empty(), "Aiming while moving in any direction keeps the barrel on target and the body untwisted (worst %.0f deg off aim, %.0f deg of twist%s)" % [loosest, widest, "" if strayed.is_empty() else "; " + "; ".join(strayed)])

	# Level ground: lying down leaves the body level, exactly.
	await H.scenario(self, "lab_start", {"roster": false, "settle": 2})
	await lie_down()
	var level := resting()
	var level_angle := drawn_angle()
	check(player.stance.current == 2 and player.soldier.transform.is_equal_approx(Transform3D.IDENTITY), "On level ground a held crouch lies prone and level (%.1f deg)" % level.pitch)

	# A ramp of our own in the lane, rising toward -z, so the lab's layout does not matter.
	box(Vector3(8.0, 0.5, 14.0), Vector3(0.0, 2.0, 12.0), SLOPE)
	await physics_frame
	await stand_on_ramp(0.0)
	await lie_down()
	var up := resting()
	var tilted := drawn_angle() - level_angle
	check(player.stance.current == 2 and absf(up.pitch - SLOPE) < 2.0 and absf(up.roll) < 2.0 and up.gap < 0.04 and up.box < 0.5 and absf(tilted - SLOPE) < 3.0, "Prone on a %.0f degree slope lies along it, head uphill, resting on the surface, and is drawn that way (pitch %.1f deg, drawn %.1f deg, %.2f m off the ground; %s)" % [SLOPE, up.pitch, tilted, up.gap, session.hud.notice_label.text])
	var before := player.rotation.y
	await H.step(self, 40, {"turn": 60.0})
	check(absf(angle_difference(before, player.rotation.y)) > deg_to_rad(25.0), "A prone soldier can turn on the slope (%.0f deg)" % rad_to_deg(absf(angle_difference(before, player.rotation.y))))
	await stand_on_ramp(90.0)
	await lie_down()
	var across := resting()
	await stand_on_ramp(180.0)
	await lie_down()
	var down := resting()
	check(absf(absf(across.roll) - SLOPE) < 2.0 and absf(across.pitch) < 2.0 and across.gap < 0.04 and absf(down.pitch + SLOPE) < 2.0 and down.gap < 0.04, "Across the slope the body rolls onto it, and facing downhill it lies head down (roll %.1f deg, pitch %.1f deg)" % [across.roll, down.pitch])
	# Getting back up, and jumping, on a slope steeper than the old standing check allowed.
	var crouched: Dictionary = await H.step(self, 16, {"tap": ["crouch"]})
	var stood: Dictionary = await H.step(self, 16, {"tap": ["jump"]})
	var jump: Dictionary = await H.step(self, 36, {"tap": ["jump"], "trace": 2})
	var rise := 0.0
	for sample: Array in jump.trace:
		rise = maxf(rise, sample[2] - jump.trace[0][2])
	await ticks(20)
	check(crouched.player.stance == "crouch" and stood.player.stance == "stand" and rise > 0.2 and absf(resting().pitch) < 1.0, "From prone on the slope the soldier rises to a crouch, stands upright, and jumps (%.2f m)" % rise)
	# Running up the slope, a held crouch dives.
	await stand_on_ramp(0.0, 16.5)
	hold({"forward": 1.0})
	await ticks(24)
	hold({"forward": 1.0, "hold": ["crouch"]})
	var dived := false
	for tick: int in range(34):
		await physics_frame
		dived = dived or player.diving
	await let_go({"hold": ["crouch"]})
	await ticks(60)
	var landed := resting()
	check(dived and player.stance.current == 2 and absf(landed.pitch - SLOPE) < 3.0 and landed.gap < 0.05, "Running up the slope, a held crouch dives and lands lying on it (pitch %.1f deg%s)" % [landed.pitch, "" if dived else "; " + session.hud.notice_label.text])
	# Something standing where the body would go still refuses.
	box(Vector3.ONE, Vector3(20.0, 0.5, 21.0))
	await physics_frame
	await H.apply(self, {"pos": [20.0, 0.1, 22.0], "yaw": 0.0, "stance": "stand", "settle": 6})
	await H.step(self, 26, {"hold": ["crouch"]})
	check(player.stance.current == 0 and "room" in session.hud.notice_label.text, "A crate where the body would lie still refuses prone (%s)" % session.hud.notice_label.text)

	print("\nRESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
