extends RefCounted
## Grenade motion on the original rig. Combat retains ownership of ammo and release.
## [held wind-up frame, release frame], measured from the native hand's forward swing.
## These are authored 30 Hz frames, not verified original gameplay event timestamps.
const FRAMES := {
	"seal_throwgrenade": Vector2(10, 13),
	"seal_tossgrenade": Vector2(16, 19),
	"seal_crouch_throwgrenade": Vector2(10, 14),
	"seal_prone_throwgrenade": Vector2(18, 20),
	"seal_prone_tossgrenade": Vector2(10, 14),
}
var clip := ""
var time := 0.0
var start_time := 0.0
var weight := 0.0
var clip_stance := 0
var last_pose: Array[Transform3D] = []
var from_pose: Array[Transform3D] = []
var transition := 1.0

func reset() -> void:
	clip = ""
	time = 0.0
	start_time = 0.0
	weight = 0.0
	last_pose.clear()
	from_pose.clear()
	transition = 1.0

static func select(style: int, stance: int) -> String:
	if stance == 1:
		return "seal_crouch_throwgrenade"
	return "seal_" + ("prone_" if stance == 2 else "") + ("tossgrenade" if style == 0 else "throwgrenade")

func hold(style: int, stance: int) -> void:
	var next := select(style, stance)
	if clip != next:
		from_pose = last_pose.duplicate()
		transition = 0.0
		clip = next
		clip_stance = stance
		time = 0.0

func begin(style: int, stance: int) -> float:
	hold(style, stance)
	start_time = minf(time, FRAMES[clip].x / 30.0)
	return FRAMES[clip].y / 30.0 - start_time

func duration(motion: Node) -> float:
	# The decoder's final sample wraps to frame zero. A throw must never play it.
	return motion.get_animation(clip).length - 1.0 / 30.0 - start_time

func apply(motion: Node, pose: Array[Transform3D], proxy: SoldierProxy, weapon: PracticeWeapon, stance: int, moving: bool, grounded: bool, delta: float, blender: RefCounted) -> void:
	var active := proxy.throwing() or proxy.throw_hold_style >= 0
	if active:
		if proxy.throwing():
			time = minf(start_time + proxy.throw_time, motion.get_animation(clip).length - 1.0 / 30.0)
			# Pose precedes combat in the tick: land exactly on the release pose when
			# combat will let go, even if the event falls between two physics ticks.
			if weapon.throw_release >= 0.0:
				time = minf(time, FRAMES[clip].y / 30.0)
		else:
			hold(proxy.throw_hold_style, stance)
			time = minf(time + delta, FRAMES[clip].x / 30.0)
		last_pose = motion.sample(clip, time)
		transition = minf(1.0, transition + delta / 0.10)
		if not from_pose.is_empty() and transition < 1.0:
			for index: int in range(last_pose.size()):
				last_pose[index] = from_pose[index].interpolate_with(last_pose[index], smoothstep(0, 1, transition))
	weight = move_toward(weight, 1.0 if active else 0.0, delta / 0.10)
	if weight > 0.0 and not last_pose.is_empty():
		# Keep walking/crawling legs and capsule-owned jump height. The native
		# model-space upper-body blend also prevents a sideways torso on strafes.
		blender.blend_pose(motion, pose, last_pose, weight, moving or not grounded or stance != clip_stance, clip)
	elif not active:
		reset()

## Predict the very same hand position for both the arc and the released grenade.
func release_point(motion: Node, base: Array[Transform3D], style: int, stance: int, moving: bool, grounded: bool, committed: bool, blender: RefCounted) -> Vector3:
	var take := clip if committed and clip != "" else select(style, stance)
	var pose: Array[Transform3D] = base.duplicate()
	if pose.is_empty():
		pose = motion.sample("seal_" + ["stand", "crouch", "prone"][stance], 0.0)
	blender.blend_pose(motion, pose, motion.sample(take, FRAMES[take].y / 30.0), 1.0, moving or not grounded or (committed and stance != clip_stance), take)
	return motion.worlds(pose)[motion.rig.names.find("rhand")].origin
