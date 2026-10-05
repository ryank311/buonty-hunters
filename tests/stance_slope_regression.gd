extends SceneTree
## Stances on sloped ground. The graybox levels are flat; the recovered maps are not, and
## a soldier must be able to go prone, dive, turn, and get back up on a ramp, and when
## prone must lie along the surface at its angle.
##
## The room checks once treated the ground itself as an obstacle: the prone check with
## any slope over about 1.6 degrees under the body, the standing check over about 22.
## This builds its own 25 degree ramp so that the lab's layout does not matter.
const H = preload("res://tools/agent/harness.gd")
const SLOPE := 25.0
var failures: Array[String] = []
var session: Node
var player: PrototypePlayer

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok:
		failures.append(description)

## Height of the ground under a point, or NAN.
func ground(x: float, z: float) -> float:
	var hit := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 12.0, z), Vector3(x, -2.0, z), 1, [player.get_rid()]))
	return NAN if hit.is_empty() else float(hit.position.y)

## A slab in the lab's lane that rises toward -z at SLOPE degrees.
func build_ramp() -> void:
	var ramp := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 0.5, 14.0)
	shape.shape = box
	ramp.add_child(shape)
	ramp.rotation.x = deg_to_rad(SLOPE)
	ramp.position = Vector3(0.0, 2.0, 12.0)
	session.level.add_child(ramp)

## Stands the player on the ramp's middle facing `yaw` (0 is uphill) and lets them settle.
func stand_on_ramp(yaw: float, z: float = 12.0) -> void:
	await H.apply(self, {"pos": [0.0, ground(0.0, z) + 0.05, z], "yaw": yaw, "stance": "stand"})
	await H.step(self, 12)

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
func drawn_angle(skin: SoldierSkin) -> float:
	var head: Vector3 = skin.skeleton.global_transform * skin.skeleton.get_bone_global_pose(skin.bone["head"]).origin
	var toe: Vector3 = skin.skeleton.global_transform * skin.skeleton.get_bone_global_pose(skin.bone["ltoe"]).origin
	return rad_to_deg(atan2(head.y - toe.y, Vector2(head.x - toe.x, head.z - toe.z).length()))

func _run() -> void:
	session = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	await H.scenario(self, "lab_start", {"roster": false})
	player = session.player
	var skin: SoldierSkin = player.soldier.soldier_skin
	# Level ground: lying down leaves the body level, as it always was.
	await H.step(self, 30, {"hold": ["crouch"]})
	await H.step(self, 40)
	var level := resting()
	check(player.stance.current == 2 and absf(level.pitch) < 0.5 and absf(level.roll) < 0.5, "On level ground a held crouch lies prone and level (%.1f deg)" % level.pitch)
	var level_angle := drawn_angle(skin)
	build_ramp()
	await physics_frame
	await H.scenario(self, "lab_start", {"roster": false})
	# Facing up the slope.
	await stand_on_ramp(0.0)
	await H.step(self, 30, {"hold": ["crouch"]})
	check(player.stance.current == 2, "A held crouch goes prone on a %.0f degree slope (%s)" % [SLOPE, session.hud.notice_label.text])
	await H.step(self, 50)
	var up := resting()
	check(absf(up.pitch - SLOPE) < 2.0 and absf(up.roll) < 2.0 and up.gap < 0.04 and up.box < 0.5 and player.is_on_floor(), "Prone facing uphill lies along the slope, head up, resting on it (pitch %.1f deg, %.2f m off the ground)" % [up.pitch, up.gap])
	var tilted := drawn_angle(skin) - level_angle
	check(absf(tilted - SLOPE) < 3.0, "The soldier drawn on screen is tilted by the slope, toes to head (%.1f deg more than on level ground)" % tilted)
	# Turning while prone sweeps the long body; the slope must not stop it.
	var before := player.rotation.y
	await H.step(self, 60, {"turn": 60.0})
	check(absf(angle_difference(before, player.rotation.y)) > deg_to_rad(40.0), "A prone soldier can turn on the slope (%.0f deg in a second)" % rad_to_deg(absf(angle_difference(before, player.rotation.y))))
	# Across and down the slope.
	await stand_on_ramp(90.0)
	await H.step(self, 30, {"hold": ["crouch"]})
	await H.step(self, 50)
	var across := resting()
	check(player.stance.current == 2 and absf(absf(across.roll) - SLOPE) < 2.0 and absf(across.pitch) < 2.0 and across.gap < 0.04, "Prone across the slope rolls onto it (roll %.1f deg)" % across.roll)
	await stand_on_ramp(180.0)
	await H.step(self, 30, {"hold": ["crouch"]})
	await H.step(self, 50)
	var down := resting()
	check(player.stance.current == 2 and absf(down.pitch + SLOPE) < 2.0 and down.gap < 0.04, "Prone facing downhill lies head down (pitch %.1f deg)" % down.pitch)
	# Getting back up, and jumping, on a slope steeper than the old standing check allowed.
	var crouched: Dictionary = await H.step(self, 20, {"tap": ["crouch"]})
	var stood: Dictionary = await H.step(self, 20, {"tap": ["jump"]})
	var jump: Dictionary = await H.step(self, 40, {"tap": ["jump"], "trace": 2})
	var rise := 0.0
	for sample: Array in jump.trace:
		rise = maxf(rise, sample[2] - jump.trace[0][2])
	check(crouched.player.stance == "crouch" and stood.player.stance == "stand" and rise > 0.25, "From prone on the slope the soldier rises to a crouch, stands, and jumps (%.2f m)" % rise)
	await H.step(self, 30)
	var settled := resting()
	check(absf(settled.pitch) < 1.0 and absf(settled.roll) < 1.0, "Standing again, the body is upright (%.1f deg)" % settled.pitch)
	# Running up the slope, a held crouch dives.
	await stand_on_ramp(0.0, 16.5)
	await H.step(self, 30, {"forward": 1.0})
	var dived := false
	for tick: int in range(40):
		await H.step(self, 1, {"forward": 1.0, "hold": ["crouch"]})
		dived = dived or player.diving
	await H.step(self, 70)
	var landed := resting()
	check(dived and player.stance.current == 2 and absf(landed.pitch - SLOPE) < 3.0 and landed.gap < 0.05, "Running up the slope, a held crouch dives and lands lying on it (pitch %.1f deg%s)" % [landed.pitch, "" if dived else "; " + session.hud.notice_label.text])
	# Something standing in the way still refuses.
	var crate := StaticBody3D.new()
	var crate_shape := CollisionShape3D.new()
	var crate_box := BoxShape3D.new()
	crate_box.size = Vector3.ONE
	crate_shape.shape = crate_box
	crate.add_child(crate_shape)
	crate.position = Vector3(20.0, 0.5, 21.0)
	session.level.add_child(crate)
	await physics_frame
	await H.apply(self, {"pos": [20.0, 0.1, 22.0], "yaw": 0.0, "stance": "stand"})
	await H.step(self, 12)
	await H.step(self, 30, {"hold": ["crouch"]})
	check(player.stance.current == 0 and "room" in session.hud.notice_label.text, "A crate where the body would lie still refuses prone (%s)" % session.hud.notice_label.text)
	print("\nRESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
