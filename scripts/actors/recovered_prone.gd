extends RefCounted
## The source root plus hip travel supplies each side's reach/pull rhythm.
## Integrate it over a physics tick so tuning the cadence or using a stick does
## not change the average crawl speed or skip a short pull between samples.
static var travel: Dictionary = {}
static var distances: Dictionary = {}

static func clip_for(side: float) -> String:
	return "seal_prone_lstrafe" if side < 0.0 else "seal_prone_rstrafe"

static func curve(motion: Node, side: float) -> PackedFloat32Array:
	var clip := clip_for(side)
	if not travel.has(clip):
		var count := roundi(motion.get_animation(clip).length * 30.0)
		var first: Vector3 = motion.local_track(clip, 0.0, "skel_root", Transform3D.IDENTITY).origin
		var last: Vector3 = motion.local_track(clip, (count - 1) / 30.0, "skel_root", Transform3D.IDENTITY).origin
		# The final decoded root key repeats frame zero; extrapolate the original
		# constant root step across that seam, while the hip cycle closes normally.
		var root_step := (last.x - first.x) / (count - 1)
		var cumulative := PackedFloat32Array([0.0])
		for frame: int in range(count):
			var a: Vector3 = motion.local_track(clip, frame / 30.0, "hips", Transform3D.IDENTITY).origin
			var b: Vector3 = motion.local_track(clip, (frame + 1) / 30.0, "hips", Transform3D.IDENTITY).origin
			cumulative.append(cumulative[-1] + maxf(0.0, signf(side) * (root_step + b.x - a.x)))
		var distance := cumulative[-1]
		distances[clip] = distance
		for index: int in range(cumulative.size()):
			cumulative[index] /= distance
		travel[clip] = cumulative
	return travel[clip]

static func cycle_distance(motion: Node, side: float) -> float:
	curve(motion, side)
	return distances[clip_for(side)]

static func distance_at(points: PackedFloat32Array, phase: float) -> float:
	var cycle := floorf(phase)
	var frame := (phase - cycle) * (points.size() - 1)
	var index := mini(floori(frame), points.size() - 2)
	return cycle + lerpf(points[index], points[index + 1], frame - index)

static func speed_scale(motion: Node, side: float, start: float, finish: float) -> float:
	var points := curve(motion, side)
	return (distance_at(points, finish) - distance_at(points, start)) / (finish - start)

static func extract_hip_travel(motion: Node, pose: Array[Transform3D], clip: String) -> void:
	# That lateral body shift now belongs to swept CharacterBody movement.
	# Leaving it in the skin too would apply the pull twice, then slide backward
	# during recovery. All relative limb transforms and vertical bob stay native.
	var hips: int = motion.rig.names.find("hips")
	pose[hips].origin.x = motion.local_track(clip, 0.0, "hips", pose[hips]).origin.x
