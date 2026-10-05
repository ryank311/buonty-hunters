extends RefCounted
## Original full-body locomotion on the original rig. No target skeleton or leg IK.
# motion.rdr playback values are cycle seconds for these stationary motions.
# The raw key durations remain unchanged for archive inspection in Recovery Lab.
const IDLE_SECONDS := {"seal_stand": 6.0, "seal_p_stand": 5.0, "seal_crouch": 5.0, "seal_p_crouch": 5.0, "seal_prone": 3.0, "seal_p_prone": 3.0}
var gunplay := preload("res://scripts/actors/recovered_gunplay.gd").new()
var active_clip: String = ""
var time: float = 0.0
var base_time: float = 0.0
var transition: float = 1.0
var from_pose: Array[Transform3D] = []
var last_pose: Array[Transform3D] = []
var last_base_pose: Array[Transform3D] = []
var was_grounded: bool = true
var was_diving: bool = false
var landing_time: float = -1.0

func reset() -> void:
	active_clip = ""
	time = 0.0
	base_time = 0.0
	transition = 1.0
	from_pose.clear()
	last_pose.clear()
	last_base_pose.clear()
	gunplay.reset()
	was_grounded = true
	was_diving = false
	landing_time = -1.0

## The rifle clip whose legs carry a partial pistol clip, or "" for a full-body clip.
static func base_clip(player: Node, clip: String) -> String:
	if not clip.begins_with("seal_p_") or player.has_track(clip, "hips"):
		return ""
	var base := clip.replace("seal_p_", "seal_")
	for candidate: String in [base, base + "_fast"]:
		if player.has_animation(candidate):
			return candidate
	return ""

func drive(skin: SoldierSkin, proxy: SoldierProxy, stance: int, speed: float, movement: Vector2, grounded: bool, pitch: float, delta: float, focused: bool = false) -> void:
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
		from_pose = last_base_pose.duplicate()
		transition = 0.0
		active_clip = clip
		time = 0.0
		base_time = 0.0
		player.play(clip)
	# Pistol movement clips carry only the upper body. The original layered
	# them over the rifle gait, so the base clip owns the clock (feet keep
	# their cadence) and the layer follows at the same phase.
	var base := base_clip(player, clip) if fixed_time < 0 else ""
	var length: float = player.get_animation(clip).length
	if base != "":
		var cycle: float = player.get_animation(base).length
		base_time = fmod(base_time + delta, cycle)
		time = base_time / cycle * length
	else:
		var rate: float = length / IDLE_SECONDS[clip] if IDLE_SECONDS.has(clip) else 1.0
		time = clampf(fixed_time, 0, length) if fixed_time >= 0 else fmod(time + delta * rate, length)
	var pose: Array[Transform3D] = player.sample(clip, time, base, base_time)
	# Capsule motion owns world displacement during jumps.
	if not grounded and not diving:
		var root: int = player.rig.names.find("skel_root")
		pose[root].origin.y = player.local_track(clip, 0, "skel_root", player.rig.locals[root]).origin.y
	transition = minf(1.0, transition + delta / 0.12)
	if not from_pose.is_empty() and transition < 1:
		for index: int in range(pose.size()):
			pose[index] = from_pose[index].interpolate_with(pose[index], smoothstep(0, 1, transition))
	last_base_pose = pose.duplicate()
	var weapon := proxy.get_parent().get_node_or_null("Weapon") as PracticeWeapon
	gunplay.apply(player, pose, clip, time, weapon, stance, moving, grounded and not diving and landing_time < 0, focused, pitch, delta)
	last_pose = pose.duplicate()
	player.current_animation_position = time
	player.apply_pose(pose)
	skin.place_weapon(proxy, clip, time, gunplay.socket)
