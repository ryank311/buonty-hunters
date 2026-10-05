extends RefCounted
## Original full-body locomotion on the original rig. No target skeleton or leg IK.
var active_clip: String = ""
var time: float = 0.0
var transition: float = 1.0
var from_pose: Array[Transform3D] = []
var last_pose: Array[Transform3D] = []
var was_grounded: bool = true
var was_diving: bool = false
var landing_time: float = -1.0

func reset() -> void:
	active_clip = ""
	time = 0.0
	transition = 1.0
	from_pose.clear()
	last_pose.clear()
	was_grounded = true
	was_diving = false
	landing_time = -1.0

func drive(skin: SoldierSkin, proxy: SoldierProxy, stance: int, speed: float, movement: Vector2, grounded: bool, _pitch: float, delta: float) -> void:
	var player: Node = skin.motion
	var prefix := "seal_p_" if proxy.weapon_slot == 1 else "seal_"
	var moving := speed > 0.15
	var backwards := movement.y > absf(movement.x)
	var sideways := absf(movement.x) > absf(movement.y) * 1.4
	var clip := prefix + "stand"
	if stance == StanceController.Stance.PRONE:
		clip = ("seal_prone_" + ("lstrafe" if movement.x < 0 else "rstrafe") if sideways else "seal_prone_crawl") if moving else prefix + "prone"
	elif stance == StanceController.Stance.CROUCH:
		clip = prefix + ("crouchwalk_bw" if backwards else "crouchwalk") if moving else prefix + "crouch"
		if moving and sideways:
			clip = prefix + ("crouchstrafe_left" if movement.x < 0 else "crouchstrafe_right")
			if not player.has_animation(clip):
				clip += "_fast"
	elif moving:
		clip = prefix + (("run_bw" if backwards else "run") if speed > 3 else ("walk_bw" if backwards else "walk"))
		if sideways:
			clip = prefix + ("lstrafe" if movement.x < 0 else "rstrafe") + ("_fast" if speed > 3 else "")
	var fixed_time := -1.0
	var diving := proxy.dive_blend > 0.1
	if grounded and not was_grounded and not was_diving and stance == 0:
		landing_time = 0.0
	if diving:
		clip = "seal_dive2prone"
		# The decoder appends the first pose at frameCount for looping. A dive
		# is a one-shot: stop at the last authored frame, then blend into prone.
		fixed_time = (1.0 if grounded else clampf(proxy.dive_phase, 0, 1)) * (player.get_animation(clip).length - 1.0 / 30.0)
		landing_time = -1.0
	elif not grounded:
		clip = "seal_jump"
		# Physics launches immediately; omit the source's grounded anticipation.
		# Frames 7..19 cover takeoff, flight and return without the wrap sample.
		fixed_time = lerpf(7.0 / 30.0, 19.0 / 30.0, clampf(proxy.jump_phase, 0, 1))
		landing_time = -1.0
	elif landing_time >= 0 and stance == 0:
		landing_time += delta
		if landing_time < player.get_animation("seal_land_soft").length - 1.0 / 30.0:
			clip = "seal_land_soft"
			fixed_time = landing_time
		else:
			landing_time = -1.0
	was_grounded = grounded
	was_diving = diving
	if clip != active_clip:
		from_pose = last_pose.duplicate()
		transition = 0.0
		active_clip = clip
		time = 0.0
		player.play(clip)
	var length: float = player.get_animation(clip).length
	time = clampf(fixed_time, 0, length) if fixed_time >= 0 else fmod(time + delta, length)
	var pose: Array[Transform3D] = player.sample(clip, time)
	# Capsule motion owns world displacement during jumps.
	if not grounded and not diving:
		var root: int = player.rig.names.find("skel_root")
		pose[root].origin.y = player.local_track(clip, 0, "skel_root", player.rig.locals[root]).origin.y
	transition = minf(1.0, transition + delta / 0.12)
	if not from_pose.is_empty() and transition < 1:
		for index: int in range(pose.size()):
			pose[index] = from_pose[index].interpolate_with(pose[index], smoothstep(0, 1, transition))
	last_pose = pose.duplicate()
	# Locomotion must match the Recovery Lab. Aim/weapon layers are a separate
	# integration pass; forcing a hand axis toward the view twists the torso.
	player.current_animation_position = time
	player.apply_pose(pose)
	skin.place_weapon(proxy, clip, time)
