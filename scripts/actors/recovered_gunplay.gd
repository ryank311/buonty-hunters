extends RefCounted
## Fire poses, recoil and reloads on the native rig. Combat owns shots and ammo.
const FIRE_SECONDS := {"seal_fp_stand": 1.0, "seal_pfp_stand": 1.0, "seal_fp_crouch": 5.0, "seal_pfp_crouch": 1.0, "seal_fp_prone": 1.0, "seal_pfp_prone": 1.0}
const READY_HOLD := 5.0
const RECOIL_SECONDS := 0.16
var fire_blend := 0.0
var fire_hold := 0.0
var fire_clock := 0.0
var fire_clip := ""
var recoil_clip := ""
var recoil_weight := 0.0
var reload_clip := ""
var reload_progress := 0.0
var reload_blend := 0.0
var reload_pose: Array[Transform3D] = []
var reload_socket := Transform3D.IDENTITY
var reload_upper_only := false
var socket := Transform3D.IDENTITY
var last_slot := -1
var last_shots := 0
var shot_age := RECOIL_SECONDS

func reset() -> void:
	fire_blend = 0.0
	fire_hold = 0.0
	fire_clock = 0.0
	fire_clip = ""
	recoil_clip = ""
	recoil_weight = 0.0
	reload_clip = ""
	reload_progress = 0.0
	reload_blend = 0.0
	reload_pose.clear()
	last_slot = -1
	last_shots = 0
	shot_age = RECOIL_SECONDS

func apply(motion: Node, pose: Array[Transform3D], base_clip: String, seconds: float, weapon: PracticeWeapon, stance: int, moving: bool, allowed: bool, focused: bool, pitch: float, delta: float, leaning: bool = false) -> void:
	# The visual child receives _ready before the player initializes its loadout.
	if weapon != null and weapon.profiles.is_empty():
		weapon = null
	var pistol: bool = weapon.profile.hold == "pistol" if weapon != null else base_clip.begins_with("seal_p_")
	var attachment := "pistol" if pistol else "rifle"
	socket = motion.weapon_track(base_clip, seconds, attachment)
	if weapon == null or not allowed or weapon.profile.kind != "firearm":
		reset()
		return
	if weapon.active_slot != last_slot or weapon.shots_fired < last_shots:
		reset()
		last_slot = weapon.active_slot
		last_shots = weapon.shots_fired
	shot_age += delta
	if weapon.shots_fired > last_shots:
		last_shots = weapon.shots_fired
		shot_age = weapon.recoil.since_shot
		fire_hold = READY_HOLD
	if focused and weapon.draw_remaining <= 0.0:
		fire_hold = READY_HOLD
	else:
		fire_hold = maxf(0.0, fire_hold - delta)
	var reloading := weapon.reload_remaining > 0.0
	var raised := fire_hold > 0.0 and not reloading and weapon.draw_remaining <= 0.0
	fire_blend = move_toward(fire_blend, 1.0 if raised else 0.0, delta / (0.1 if raised else 0.5))
	var fire_prefix := "seal_pfp_" if pistol else "seal_fp_"
	var candidate := fire_prefix + base_clip.trim_prefix("seal_p_").trim_prefix("seal_")
	var upper_only: bool = not motion.has_animation(candidate)
	fire_clip = fire_prefix + ["stand", "crouch", "prone"][stance] if upper_only else candidate
	var fire_length: float = motion.get_animation(fire_clip).length
	fire_clock += delta
	var fire_time: float = fmod(fire_clock, FIRE_SECONDS.get(fire_clip, fire_length)) * fire_length / float(FIRE_SECONDS.get(fire_clip, fire_length)) if not moving else seconds / motion.get_animation(base_clip).length * fire_length
	# Lean transitions already contain the raised weapon pose. Replacing that
	# torso with the ordinary fire stance would erase the recovered lean.
	if fire_blend > 0.0 and not leaning:
		blend_pose(motion, pose, motion.sample(fire_clip, fire_time), fire_blend, upper_only, fire_clip)
		socket = socket.interpolate_with(motion.weapon_track(fire_clip, fire_time, attachment), fire_blend)
	# The two authored recoil poses are rest and kick. Apply their local delta
	# above the hips so firing never replaces the stride or changes stance height.
	recoil_weight = 0.0
	recoil_clip = ("seal_p_prone_recoil" if stance == 2 else "seal_p_recoil") if pistol else ["seal_recoil", "seal_crouch_recoil", "seal_prone_recoil"][stance]
	if shot_age < RECOIL_SECONDS and not reloading and weapon.draw_remaining <= 0.0:
		var phase := clampf(shot_age / RECOIL_SECONDS, 0.0, 1.0)
		recoil_weight = (smoothstep(0.0, 0.18, phase) if phase < 0.18 else 1.0 - smoothstep(0.18, 1.0, phase)) * clampf(weapon.profile.weapon_kick * weapon.stability(), 0.0, 2.0)
		var rest: Array[Transform3D] = motion.sample(recoil_clip, 0.0)
		var kick: Array[Transform3D] = motion.sample(recoil_clip, 1.0 / 30.0)
		for index: int in range(pose.size()):
			if not upper_bone(motion.rig.names[index]):
				continue
			pose[index].origin += (kick[index].origin - rest[index].origin) * recoil_weight
			var rotation := rest[index].basis.inverse() * kick[index].basis
			pose[index].basis = pose[index].basis * Basis(Quaternion.IDENTITY.slerp(rotation.get_rotation_quaternion(), recoil_weight))
	# Pitch only, in model space, through the original aim helper. Do not infer
	# yaw from a hand axis: it twists the unraised run pose away from its source.
	if fire_blend > 0.0:
		var aim: int = motion.rig.names.find("aimnodes")
		var worlds: Array[Transform3D] = motion.worlds(pose)
		var parent: int = motion.rig.parents[aim]
		var axis: Vector3 = worlds[parent].basis.inverse() * Vector3.RIGHT
		var limit := deg_to_rad(25.0) if stance == 2 else deg_to_rad(65.0)
		pose[aim].basis = Basis(axis.normalized(), clampf(pitch, -limit, limit) * fire_blend) * pose[aim].basis
	# Reload follows the existing ammunition timer, including cancellation and
	# movement/stance changes. No animation callback can award ammunition.
	if reloading:
		var prefix := "seal_p_" if pistol else "seal_"
		var action := "reload_shotgun" if not pistol and weapon.profile.pellets > 1 else "reload"
		reload_clip = prefix + ("prone_" if stance == 2 else "mv_" if moving else "crouch_" if stance == 1 else "") + action
		reload_progress = clampf(1.0 - weapon.reload_remaining / weapon.profile.reload_seconds, 0.0, 1.0)
		var reload_time: float = reload_progress * (motion.get_animation(reload_clip).length - 1.0 / 30.0)
		reload_pose = motion.sample(reload_clip, reload_time)
		reload_socket = motion.weapon_track(reload_clip, reload_time, attachment)
		reload_upper_only = moving
	reload_blend = move_toward(reload_blend, 1.0 if reloading else 0.0, delta / 0.12)
	if reload_blend > 0.0 and not reload_pose.is_empty():
		blend_pose(motion, pose, reload_pose, reload_blend, reload_upper_only, reload_clip)
		socket = socket.interpolate_with(reload_socket, reload_blend)
	elif not reloading:
		reload_clip = ""

func upper_bone(name: String) -> bool:
	return name not in ["skel_root", "hips", "rthigh", "rcalf", "rfoot", "rtoe", "lthigh", "lcalf", "lfoot", "ltoe", "body"]

func blend_pose(motion: Node, pose: Array[Transform3D], layer: Array[Transform3D], weight: float, upper_only: bool, clip: String) -> void:
	# aimnodes cancels its own clip's hip yaw (a bladed fire stance turns the
	# hips 60 degrees). Over other legs, keep the layer's model-space facing
	# instead of its local value, or the torso twists by the hip difference.
	var base_worlds: Array[Transform3D] = []
	var layer_worlds: Array[Transform3D] = []
	if upper_only:
		base_worlds = motion.worlds(pose)
		layer_worlds = motion.worlds(layer)
	for index: int in range(pose.size()):
		var bone: String = motion.rig.names[index]
		if not motion.has_track(clip, bone) or (upper_only and not upper_bone(bone)):
			continue
		var target := layer[index]
		var parent: int = motion.rig.parents[index]
		if upper_only and parent >= 0 and not upper_bone(motion.rig.names[parent]):
			target = Transform3D(base_worlds[parent].basis.inverse() * layer_worlds[index].basis, pose[index].origin)
		pose[index] = pose[index].interpolate_with(target, smoothstep(0.0, 1.0, weight))
