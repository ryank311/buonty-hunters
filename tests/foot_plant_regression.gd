extends SceneTree
## Feet must hold the ground, and a raised weapon must stay on target, whichever way the
## soldier moves.
##
## For each gait this drives the real player at a steady speed and measures how fast a
## planted foot moves over the floor, as a share of body speed: a foot that is down and
## still reads near zero, a body skating over its feet reads high. The recovered clips
## carry their own ground travel (the root track), and the driver in
## scripts/actors/recovered_locomotion.gd turns each cycle by distance covered. This fails
## when movement and animation drift apart again: a retuned speed that is no longer
## rate-matched, a clip played outside its band, root travel dropped from the library.
##
## Then, aiming, it moves in every direction and measures where the barrel points and how
## far the chest is turned from the hips. The original's strafes hold the weapon on aim
## themselves; laying the standing fire stance over them wrung the torso more than 100
## degrees round when strafing left.
const H = preload("res://tools/agent/harness.gd")
## The ball of each foot. It counts as planted within DOWN of the lowest it reaches in
## the sample; a backpedalling foot swings only three centimetres higher than that.
const FEET: Array[String] = ["ltoe", "rtoe"]
const DOWN := 0.015
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

func foot_points() -> Dictionary:
	var points: Dictionary = {}
	for bone: String in FEET:
		points[bone] = skin.skeleton.global_transform * skin.skeleton.get_bone_global_pose(skin.bone[bone]).origin
	return points

## Runs one gait down the lab's open lane and measures it. `yaw` turns the player so the
## travel is along the lane whichever way the input points.
func measure(input: Dictionary, yaw: float, stance: String = "stand", weapon: String = "primary", hold: Array = []) -> Dictionary:
	await H.scenario(self, "lab_start", {"roster": false, "yaw": yaw, "stance": stance, "weapon": weapon})
	var keys := input.duplicate()
	keys["hold"] = hold
	await H.step(self, 50, keys)
	var samples: Array[Dictionary] = []
	var speeds: Array[float] = []
	var clips: Dictionary = {}
	for tick: int in range(90):
		await H.step(self, 1, keys)
		samples.append(foot_points())
		speeds.append(Vector2(player.velocity.x, player.velocity.z).length())
		clips[skin.driver.active_clip] = true
	var speed := 0.0
	for value: float in speeds:
		speed += value / speeds.size()
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
	return {"speed": speed, "slip": slip, "share": slip / maxf(0.01, speed), "planted": planted, "clips": clips.keys(), "steady": speeds.min() > speed * 0.9}

## Aims while moving one way and reports the worst the barrel strays from straight ahead
## (degrees) and the most the chest is turned from the hips (degrees) over a stride.
func aim_while(input: Dictionary, weapon: String) -> Dictionary:
	await H.scenario(self, "lab_start", {"roster": false, "weapon": weapon, "pos": [0.0, 0.1, 10.0]})
	var keys := input.duplicate()
	keys["hold"] = ["aim"]
	await H.step(self, 40, keys)
	var motion: Node = skin.motion
	var hand: int = motion.rig.names.find("rhand")
	var hips: int = motion.rig.names.find("hips")
	var chest: int = motion.rig.names.find("spinehi")
	var stray := 0.0
	var twist := 0.0
	for tick: int in range(40):
		await H.step(self, 1, keys)
		var barrel: Vector3 = (motion.native_worlds[hand] * skin.driver.gunplay.socket).basis.x.normalized()
		stray = maxf(stray, rad_to_deg(barrel.angle_to(Vector3.FORWARD)))
		# Where each bone's bind-pose forward now points, flattened to the ground.
		var hip_facing: Vector3 = motion.native_worlds[hips].basis * (motion.rig.worlds[hips].basis.inverse() * Vector3.FORWARD)
		var chest_facing: Vector3 = motion.native_worlds[chest].basis * (motion.rig.worlds[chest].basis.inverse() * Vector3.FORWARD)
		twist = maxf(twist, absf(rad_to_deg(Vector2(hip_facing.x, hip_facing.z).angle_to(Vector2(chest_facing.x, chest_facing.z)))))
	return {"stray": stray, "twist": twist, "clip": skin.driver.active_clip, "raised": skin.driver.gunplay.fire_blend}

func _run() -> void:
	session = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	await H.scenario(self, "lab_start", {"roster": false})
	player = session.player
	skin = player.soldier.soldier_skin
	# Each gait: its input, the facing that sends it down the lane, and the most a planted
	# foot may slide as a share of body speed. The recovered clips are not perfectly
	# planted themselves (a foot rolls from heel to toe, and a crouched shuffle drags), so
	# each limit sits a little above what the source clip measures at its own travel speed.
	var gaits: Array = [
		["run", {"forward": 1.0}, 0.0, "stand", [], 0.16],
		["walk", {"forward": 1.0}, 0.0, "stand", ["walk"], 0.20],
		["backpedal", {"forward": -1.0}, 180.0, "stand", [], 0.30],
		["strafe right", {"right": 1.0}, 90.0, "stand", [], 0.22],
		["strafe left", {"right": -1.0}, -90.0, "stand", [], 0.22],
		["run diagonally", {"forward": 1.0, "right": 1.0}, 45.0, "stand", [], 0.22],
		["crouch walk", {"forward": 1.0}, 0.0, "crouch", [], 0.40],
		["crouch strafe left", {"right": -1.0}, -90.0, "crouch", [], 0.40],
	]
	for gait: Array in gaits:
		var result: Dictionary = await measure(gait[1], gait[2], gait[3], "primary", gait[4])
		check(result.steady and result.planted > 20 and result.share < gait[5], "%s: planted feet hold the ground (slide %.2f m/s at %.2f m/s, %.0f%% of body speed; limit %.0f%%; %s)" % [gait[0].capitalize(), result.slip, result.speed, result.share * 100.0, gait[5] * 100.0, ", ".join(result.clips)])
	var pistol: Dictionary = await measure({"forward": 1.0}, 0.0, "stand", "secondary")
	check(pistol.steady and pistol.share < 0.16, "Pistol run: the rifle leg cycle under the pistol upper body holds the ground too (%.0f%% of body speed)" % (pistol.share * 100.0))
	# Aiming on the move. A person can turn the chest about 45 degrees from the hips;
	# the standing fire stance itself is 38 over running legs.
	var directions: Array = [
		["forward", {"forward": 1.0}], ["back", {"forward": -1.0}],
		["left", {"right": -1.0}], ["right", {"right": 1.0}],
		["forward and left", {"forward": 1.0, "right": -1.0}], ["forward and right", {"forward": 1.0, "right": 1.0}],
		["back and left", {"forward": -1.0, "right": -1.0}], ["back and right", {"forward": -1.0, "right": 1.0}],
	]
	for weapon: String in ["primary", "secondary"]:
		var strayed: Array[String] = []
		var widest := 0.0
		var loosest := 0.0
		for direction: Array in directions:
			var aim: Dictionary = await aim_while(direction[1], weapon)
			widest = maxf(widest, aim.twist)
			loosest = maxf(loosest, aim.stray)
			if aim.raised < 0.99 or aim.stray > 15.0 or aim.twist > 50.0:
				strayed.append("%s: barrel %.0f deg off, chest %.0f deg from hips, %s" % [direction[0], aim.stray, aim.twist, aim.clip])
		check(strayed.is_empty(), "Aiming the %s while moving in any of eight directions keeps the barrel on target and the body untwisted (worst %.0f deg off aim, %.0f deg of twist%s)" % ["rifle" if weapon == "primary" else "pistol", loosest, widest, "" if strayed.is_empty() else "; " + "; ".join(strayed)])
	print("\nRESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
