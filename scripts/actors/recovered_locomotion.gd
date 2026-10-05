extends RefCounted
## Original full-body locomotion on the original rig. No target skeleton or leg IK.
##
## Gaits play the way the original game played them. Every moving clip carries its
## ground travel in its root track. A clip plays while the body's speed is inside its
## motion.rdr band, two clips share an overlap, and the forward and strafe sets share a
## diagonal. The cycle is turned by distance covered, never by the clock, so a planted
## foot stays where it was put at any speed the controller moves the body.
# motion.rdr playback values are cycle seconds for these stationary motions.
# The raw key durations remain unchanged for archive inspection in Recovery Lab.
const IDLE_SECONDS := {"seal_stand": 6.0, "seal_p_stand": 5.0, "seal_crouch": 5.0, "seal_p_crouch": 5.0, "seal_prone": 3.0, "seal_p_prone": 3.0}
# The SEAL's standing sets with motion.rdr's transition_speed_A and _B in metres a
# second: [clip, slowest, fastest]. Crouched and prone movement has one clip a direction.
const FORWARD: Array = [["seal_walk_alert", 0.0, 4.0], ["seal_jog_alert", 2.0, 6.15], ["seal_run", 4.01, 6.5]]
const BACKWARD: Array = [["seal_walk_bw", 0.0, 2.8], ["seal_run_bw", 2.0, 3.7]]
const RIGHT: Array = [["seal_rstrafe", 0.0, 2.8], ["seal_rstrafe_fast", 1.0, 5.0], ["seal_run_90r", 3.0, 6.5]]
const LEFT: Array = [["seal_lstrafe", 0.0, 2.3], ["seal_lstrafe_fast", 0.9, 4.5], ["seal_run_90l", 2.5, 6.5]]
## Ground each clip's root covers in one cycle, read once from the library.
static var travels: Dictionary = {}
const Prone = preload("res://scripts/actors/recovered_prone.gd")
var gunplay := preload("res://scripts/actors/recovered_gunplay.gd").new()
var lean := preload("res://scripts/actors/recovered_lean.gd").new()
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
## What is playing: an idle or one-shot clip's name, or a gait. A change cross-fades.
var play: String = ""
## The leg clips of the gait with their shares, [[clip, weight], ...]; empty when still.
var mix: Array = []
## Where the legs are in their cycle (0 to 1), how fast it turns (cycles a second), and
## the ground one cycle covers (metres). cadence x stride is the body's speed.
var phase: float = 0.0
var cadence: float = 0.0
var stride: float = 0.0

func reset() -> void:
	active_clip = ""
	play = ""
	mix = []
	phase = 0.0
	cadence = 0.0
	stride = 0.0
	time = 0.0
	base_time = 0.0
	transition = 1.0
	from_pose.clear()
	last_pose.clear()
	last_base_pose.clear()
	gunplay.reset()
	lean.reset()
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

## Metres the clip's root travels over the ground in one cycle: x to the right, y back.
static func travel(player: Node, clip: String) -> Vector2:
	if not travels.has(clip):
		var covered := Vector2.ZERO
		var keys := roundi(player.get_animation(clip).length * 30.0)
		if keys > 1 and player.has_track(clip, "skel_root"):
			# The last key repeats the first to close the loop, so the travel is read up
			# to the key before it and scaled to the whole cycle.
			var first: Vector3 = player.local_track(clip, 0.0, "skel_root", Transform3D.IDENTITY).origin
			var last: Vector3 = player.local_track(clip, (keys - 1) / 30.0, "skel_root", Transform3D.IDENTITY).origin
			covered = Vector2(last.x - first.x, last.z - first.z) * keys / (keys - 1.0)
		travels[clip] = covered
	return travels[clip]

## The clips of one set that play at `speed` with their shares, [[clip, weight], ...]:
## the one whose band holds the speed, or two splitting an overlap between them.
static func pick(clips: Array, speed: float) -> Array:
	var inside: Array = []
	for entry: Array in clips:
		if speed >= entry[1] and speed <= entry[2]:
			inside.append(entry)
	if inside.is_empty():
		# Under every band the slowest clip plays, and over every band the fastest.
		return [[clips[clips.size() - 1][0] if speed > clips[clips.size() - 1][2] else clips[0][0], 1.0]]
	if inside.size() == 1:
		return [[inside[0][0], 1.0]]
	var overlap_from := maxf(inside[0][1], inside[1][1])
	var overlap_to := minf(inside[0][2], inside[1][2])
	var later := clampf((speed - overlap_from) / maxf(0.001, overlap_to - overlap_from), 0.0, 1.0)
	return [[inside[0][0], 1.0 - later], [inside[1][0], later]]

## The pistol counterpart of a rifle gait clip, or "" when the rifle clip is all there is.
static func pistol_clip(player: Node, clip: String) -> String:
	var counterpart := clip.replace("seal_", "seal_p_").replace("_alert", "")
	for candidate: String in [counterpart, counterpart.trim_suffix("_fast")]:
		if player.has_animation(candidate):
			return candidate
	return ""

## The leg clips for moving this way at this speed, with their shares.
## `movement` is the body's own velocity: x to the right, y back.
static func gait(player: Node, stance: int, movement: Vector2, speed: float) -> Array:
	var backwards := movement.y > absf(movement.x)
	var sideways := absf(movement.x) > absf(movement.y) * 1.4
	if stance == StanceController.Stance.PRONE:
		return [[("seal_prone_lstrafe" if movement.x < 0 else "seal_prone_rstrafe") if sideways else "seal_prone_crawl", 1.0]]
	if stance == StanceController.Stance.CROUCH:
		if sideways:
			return [["seal_crouchstrafe_left" if movement.x < 0 else "seal_crouchstrafe_right_fast", 1.0]]
		return [["seal_crouchwalk_bw" if backwards else "seal_crouchwalk", 1.0]]
	var along: Array = pick(BACKWARD if movement.y > 0.0 else FORWARD, speed)
	var across: Array = pick(LEFT if movement.x < 0.0 else RIGHT, speed)
	# Share the legs between the two sets so the blended stride points the way the body
	# is going: all forward set straight ahead, all strafe set straight sideways.
	var ahead := absf(movement.y) * _reach(player, across)
	var aside := absf(movement.x) * _reach(player, along)
	var strafe := aside / (ahead + aside) if ahead + aside > 0.0 else 0.0
	var legs: Array = []
	for entry: Array in along:
		if entry[1] * (1.0 - strafe) > 0.02:
			legs.append([entry[0], entry[1] * (1.0 - strafe)])
	for entry: Array in across:
		if entry[1] * strafe > 0.02:
			legs.append([entry[0], entry[1] * strafe])
	return legs

static func _reach(player: Node, picked: Array) -> float:
	var covered := 0.0
	for entry: Array in picked:
		covered += travel(player, entry[0]).length() * entry[1]
	return covered

func drive(skin: SoldierSkin, proxy: SoldierProxy, stance: int, speed: float, movement: Vector2, grounded: bool, pitch: float, delta: float, focused: bool = false, lean_input: float = 0.0, strafe_phase: float = -1.0, strafe_intent: float = 0.0) -> void:
	var player: Node = skin.motion
	var pistol := proxy.weapon_slot == 1
	var prefix := "seal_p_" if pistol else "seal_"
	var prone_strafe := stance == StanceController.Stance.PRONE and strafe_phase >= 0.0 and absf(strafe_intent) > 0.05
	# Intent keeps a side crawl selected through its slow reach/recovery phases.
	var moving := prone_strafe or speed > (0.02 if stance == StanceController.Stance.PRONE else 0.15)
	var clip: String = prefix + ["stand", "crouch", "prone"][stance]
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
		# As in the original, only a landing at rest plays the landing: one that
		# comes down moving runs straight on, rather than sliding through a crouch.
		if not moving and landing_time < player.get_animation("seal_land_soft").length - 1.0 / 30.0:
			clip = "seal_land_soft"
			fixed_time = landing_time
		else:
			landing_time = -1.0
	was_grounded = grounded
	was_diving = diving
	var stepping := not mix.is_empty()
	mix = gait(player, stance, movement, speed) if moving and fixed_time < 0.0 else []
	if prone_strafe and fixed_time < 0.0:
		mix = [[Prone.clip_for(strafe_intent), 1.0]]
	# Within the standing gait the legs change by blending, so only its start and end,
	# a change of stance clip, or a change of weapon hold is a new play.
	var playing: String = clip if mix.is_empty() else "gait " + prefix + ("standing" if stance == 0 else str(mix[0][0]))
	if playing != play:
		from_pose = last_base_pose.duplicate()
		transition = 0.0
		play = playing
		# One gait hands its place in the stride to the next, as the original does.
		if mix.is_empty() or not stepping:
			phase = 0.0
			time = 0.0
			base_time = 0.0
	var pose: Array[Transform3D] = []
	if not mix.is_empty():
		pose = _step(player, pistol, movement, delta, strafe_phase if prone_strafe else -1.0)
	else:
		cadence = 0.0
		stride = 0.0
		if clip != active_clip:
			active_clip = clip
			player.play(clip)
		# A still pistol clip can carry only the upper body. The original layered
		# it over the rifle pose, so the base clip owns the clock and the layer
		# follows at the same phase.
		var base := base_clip(player, clip) if fixed_time < 0 else ""
		var length: float = player.get_animation(clip).length
		if base != "":
			var cycle: float = player.get_animation(base).length
			base_time = fmod(base_time + delta, cycle)
			time = base_time / cycle * length
		else:
			var rate: float = length / IDLE_SECONDS[clip] if IDLE_SECONDS.has(clip) else 1.0
			time = clampf(fixed_time, 0, length) if fixed_time >= 0 else fmod(time + delta * rate, length)
		pose = player.sample(clip, time, base, base_time)
	clip = active_clip
	if clip in ["seal_prone_lstrafe", "seal_prone_rstrafe"] and prone_strafe:
		Prone.extract_hip_travel(player, pose, clip)
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
	var allowed := grounded and not diving and landing_time < 0
	var lean_allowed := allowed and (weapon == null or (weapon.reload_remaining <= 0.0 and weapon.draw_remaining <= 0.0))
	lean.apply(player, pose, gunplay, stance, pistol, lean_input, moving, lean_allowed, delta)
	gunplay.apply(player, pose, clip, time, weapon, stance, moving, allowed, focused or lean.weight > 0.0, pitch, delta, lean.weight > 0.0)
	if lean.weight > 0.0 and gunplay.reload_blend == 0.0:
		gunplay.socket = gunplay.socket.interpolate_with(player.weapon_track(lean.clip, lean.time, "pistol" if pistol else "rifle"), lean.weight)
	last_pose = pose.duplicate()
	player.current_animation_position = time
	player.apply_pose(pose)
	skin.place_weapon(proxy, clip, time, gunplay.socket)

## Advances the gait by the ground covered this tick and returns its blended pose.
func _step(player: Node, pistol: bool, movement: Vector2, delta: float, strafe_phase: float = -1.0) -> Array[Transform3D]:
	# Each entry: the clip that moves the legs, the pistol upper body layered on it
	# ("" for none), and its share. A whole-body pistol clip moves the legs itself.
	var entries: Array = []
	var covered := Vector2.ZERO
	for entry: Array in mix:
		var legs: String = entry[0]
		var layer: String = pistol_clip(player, legs) if pistol else ""
		if layer != "" and player.has_track(layer, "hips"):
			legs = layer
			layer = ""
		entries.append([legs, layer, entry[1]])
		covered += travel(player, legs) * entry[1]
	# A raised fire pose with legs of its own (the backpedals and crouch walks) takes
	# the stride over as it blends in.
	if gunplay.fire_blend > 0.0 and player.has_animation(gunplay.fire_clip) and player.has_track(gunplay.fire_clip, "lthigh"):
		var raised := travel(player, gunplay.fire_clip)
		if raised.length() > 0.05:
			covered = covered.lerp(raised, smoothstep(0.0, 1.0, gunplay.fire_blend))
	# The clip with the largest share leads: the weapon and the fire poses follow it.
	var lead: Array = entries[0]
	for entry: Array in entries:
		if entry[2] > lead[2]:
			lead = entry
	# The clip already leading keeps the lead through an even split, so it cannot flicker.
	for entry: Array in entries:
		if active_clip != "" and active_clip in [entry[0], entry[1]] and entry[2] > lead[2] - 0.15:
			lead = entry
	var shown: String = lead[1] if lead[1] != "" else lead[0]
	if shown != active_clip:
		active_clip = shown
		player.play(shown)
	stride = covered.length()
	# Cycles a second that carry the legs as far as the body goes. Moving against the
	# clip's travel turns it backwards: the original crawls backwards this way.
	cadence = movement.dot(covered) / (stride * stride) if stride > 0.05 else 1.0 / player.get_animation(lead[0]).length
	# Side crawl physics already integrates the authored root + hip pull curve.
	# Use that exact phase; advancing again from its pulsed speed causes drift.
	if strafe_phase >= 0.0:
		cadence = fposmod(strafe_phase - phase, 1.0) / delta
		phase = strafe_phase
	else:
		phase = fposmod(phase + cadence * delta, 1.0)
	time = phase * player.get_animation(shown).length
	base_time = phase * player.get_animation(lead[0]).length
	var pose: Array[Transform3D] = []
	var share := 0.0
	for entry: Array in entries:
		var seconds: float = phase * player.get_animation(entry[0]).length
		var sampled: Array[Transform3D] = player.sample(entry[1], phase * player.get_animation(entry[1]).length, entry[0], seconds) if entry[1] != "" else player.sample(entry[0], seconds)
		share += entry[2]
		if pose.is_empty():
			pose = sampled
		else:
			for index: int in range(pose.size()):
				pose[index] = pose[index].interpolate_with(sampled[index], entry[2] / share)
	return pose
