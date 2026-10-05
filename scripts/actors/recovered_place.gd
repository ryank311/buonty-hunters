extends RefCounted
## Setting a claymore down on the original rig. Combat retains ownership of the charge.
## The pistol-carry variant suits equipment, which is held in the pistol posture. The
## right hand is lowest at 1.3 s, the original's placing timer (decomp 476883).
const CLIP := "seal_p_place_claymore"
const RELEASE_SECONDS := 1.3
var time := 0.0
var weight := 0.0
var clip_stance := 0
var last_pose: Array[Transform3D] = []

func reset() -> void:
	time = 0.0
	weight = 0.0
	last_pose.clear()

func begin(stance: int) -> float:
	time = 0.0
	clip_stance = stance
	return RELEASE_SECONDS

func duration(motion: Node) -> float:
	# The decoder's final sample wraps to frame zero. A one-shot must never play it.
	return motion.get_animation(CLIP).length - 1.0 / 30.0

func apply(motion: Node, pose: Array[Transform3D], proxy: SoldierProxy, stance: int, moving: bool, grounded: bool, delta: float, blender: RefCounted) -> void:
	var active := proxy.placing()
	if active:
		time = minf(proxy.place_time, duration(motion))
		last_pose = motion.sample(CLIP, time)
	weight = move_toward(weight, 1.0 if active else 0.0, delta / 0.15)
	if weight > 0.0 and not last_pose.is_empty():
		# Standing, the whole body kneels with the clip. Crouched or prone, the legs
		# stay as they are and only the arms and torso reach down.
		blender.blend_pose(motion, pose, last_pose, weight, moving or not grounded or stance != StanceController.Stance.STAND, CLIP)
	elif not active:
		reset()
