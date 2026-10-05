extends RefCounted
## Original one-shot transitions, held at the last authored pose and reversed
## on release. The decoder's appended loop pose is never a lean endpoint.
const SECONDS := {"seal_stand": 0.4, "seal_crouch": 0.5, "seal_prone2llean": 0.8, "seal_prone2rlean": 0.65, "seal_p_prone2llean": 0.5, "seal_p_prone2rlean": 0.8}
var clip := ""
var time := 0.0
var amount := 0.0
var weight := 0.0
var context := ""
var clearance := 1.0

func reset() -> void:
	clip = ""
	time = 0.0
	amount = 0.0
	weight = 0.0
	context = ""
	clearance = 1.0

func update(motion: Node, stance: int, pistol: bool, requested: float, allowed: bool, delta: float) -> void:
	var prefix: String = ("seal_p_" if pistol else "seal_") + ["stand", "crouch", "prone"][stance]
	if prefix != context:
		amount = 0.0
		context = prefix
	if not allowed:
		amount = 0.0
	# A collision fraction limits how much pose is applied, not which moment
	# of the take is held: the root step is not linear in source time.
	if requested != 0.0:
		clearance = clampf(absf(requested), 0.0, 1.0)
	var target := signf(requested) if allowed else 0.0
	# Return through neutral before starting the opposite transition.
	if amount * target < 0.0:
		target = 0.0
	var side := signf(amount) if amount != 0.0 else signf(target)
	clip = prefix + ("2llean" if side < 0.0 else "2rlean")
	var duration: float = SECONDS.get(clip, SECONDS.get(prefix.replace("seal_p_", "seal_"), 0.5))
	amount = move_toward(amount, target, delta / duration)
	weight = smoothstep(0.0, 0.25, absf(amount)) * clearance
	if weight == 0.0:
		clip = ""
		time = 0.0
		return
	time = absf(amount) * (motion.get_animation(clip).length - 1.0 / 30.0)

func apply(motion: Node, pose: Array[Transform3D], blender: RefCounted, moving: bool) -> void:
	if weight == 0.0:
		return
	# Pistol crouch transitions omit the legs. Pair them with the matching
	# rifle transition at the same progress, not bind legs or an idle cycle.
	var base := clip.replace("seal_p_", "seal_") if clip.begins_with("seal_p_") and not motion.has_track(clip, "hips") else ""
	var base_time: float = absf(amount) * (motion.get_animation(base).length - 1.0 / 30.0) if base != "" else 0.0
	var layer: Array[Transform3D] = motion.sample(clip, time, base, base_time)
	var root: int = motion.rig.names.find("skel_root")
	var origin: Vector3 = motion.local_track(clip, 0.0, "skel_root", layer[root]).origin
	var offset: Vector3 = motion.local_track(clip, time, "skel_root", layer[root]).origin - origin
	# Unlike a looping gait, this stationary step must retain its root shift
	# to keep the planted foot in place. Discard only its archive-world origin.
	layer[root].origin.x += offset.x
	layer[root].origin.z += offset.z
	if moving:
		blender.blend_pose(motion, pose, layer, weight, true, clip)
	else:
		for index: int in range(pose.size()):
			pose[index] = pose[index].interpolate_with(layer[index], weight)
