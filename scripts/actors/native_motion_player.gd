extends Node
## Samples original local transforms, then converts only the imported bone axes.
## Meshes, bind positions, weights and original body proportions stay intact.

var skeleton: Skeleton3D
var library: AnimationLibrary
var rig: Dictionary
var ids: Array[int] = []
var corrections: Array[Transform3D] = []
var to_skeleton := Transform3D.IDENTITY
var native_worlds: Array[Transform3D] = []
var current_animation: String = ""
var current_animation_position: float = 0.0
var current_animation_length: float = 0.0
var speed_scale: float = 1.0
static var tracks: Dictionary = {}

func bind(model: Node3D, animations: AnimationLibrary) -> void:
	library = animations
	rig = library.get_meta("rigs")[model.scene_file_path]
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	var offset := Transform3D.IDENTITY
	var node: Node3D = skeleton
	while node != model:
		offset = node.transform * offset
		node = node.get_parent()
	to_skeleton = offset.affine_inverse()
	for index: int in range(rig.names.size()):
		var id := skeleton.find_bone(rig.names[index])
		assert(id >= 0, "Missing recovered bone: " + rig.names[index])
		ids.append(id)
		corrections.append(rig.worlds[index].affine_inverse() * offset * skeleton.get_bone_global_rest(id))

func get_animation_list() -> PackedStringArray:
	return library.get_animation_list()

func has_animation(clip: String) -> bool:
	return library.has_animation(clip)

func get_animation(clip: String) -> Animation:
	return library.get_animation(clip)

func play(clip: String) -> void:
	assert(has_animation(clip), "Missing recovered clip: " + clip)
	current_animation = clip
	current_animation_length = get_animation(clip).length
	current_animation_position = 0.0

func seek(seconds: float, _update: bool = true) -> void:
	current_animation_position = clampf(seconds, 0, current_animation_length)
	apply_pose(sample(current_animation, current_animation_position))

func _tracks(clip: String) -> Dictionary:
	if not tracks.has(clip):
		var indexed: Dictionary = {}
		var animation := get_animation(clip)
		for track: int in range(animation.get_track_count()):
			var bone := String(animation.track_get_path(track).get_subname(0))
			if not indexed.has(bone):
				indexed[bone] = [-1, -1]
			indexed[bone][0 if animation.track_get_type(track) == Animation.TYPE_POSITION_3D else 1] = track
		tracks[clip] = indexed
	return tracks[clip]

func local_track(clip: String, seconds: float, bone: String, fallback: Transform3D) -> Transform3D:
	var indexed := _tracks(clip)
	if not indexed.has(bone):
		return fallback
	var animation := get_animation(clip)
	var pair: Array = indexed[bone]
	return Transform3D(Basis(animation.rotation_track_interpolate(pair[1], seconds)), animation.position_track_interpolate(pair[0], seconds))

func has_track(clip: String, bone: String) -> bool:
	return _tracks(clip).has(bone)

## Bones the clip leaves untracked come from the base clip, then the bind pose.
## Partial clips (pistol locomotion tracks only spinelo upward) layer this way.
func sample(clip: String, seconds: float, base: String = "", base_seconds: float = 0.0) -> Array[Transform3D]:
	var pose: Array[Transform3D] = []
	for index: int in range(rig.names.size()):
		var fallback: Transform3D = rig.locals[index]
		if base != "":
			fallback = local_track(base, base_seconds, rig.names[index], fallback)
		var value := local_track(clip, seconds, rig.names[index], fallback)
		if rig.names[index] == "skel_root":
			value.origin.x = rig.locals[index].origin.x
			value.origin.z = rig.locals[index].origin.z
		pose.append(value)
	return pose

func worlds(pose: Array[Transform3D]) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for index: int in range(pose.size()):
		result.append((result[rig.parents[index]] if rig.parents[index] >= 0 else Transform3D.IDENTITY) * pose[index])
	return result

func apply_pose(pose: Array[Transform3D]) -> void:
	native_worlds = worlds(pose)
	for index: int in range(pose.size()):
		skeleton.set_bone_global_pose(ids[index], to_skeleton * native_worlds[index] * corrections[index])

func attachment(clip: String, seconds: float, name: String) -> Transform3D:
	return native_worlds[rig.names.find("rhand")] * weapon_track(clip, seconds, name)

func weapon_track(clip: String, seconds: float, name: String) -> Transform3D:
	# Some original rifle clips use the older generic attachment name.
	var key := name if _tracks(clip).has(name) else "weapon"
	return local_track(clip, seconds, key, Transform3D.IDENTITY)
