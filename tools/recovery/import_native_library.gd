extends SceneTree
## Runtime tracks retain the archive's axes; Blender bone-axis changes are handled
## per imported rig, never by changing the recovered mesh or its proportions.

func transform(values: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(values[0], values[1], values[2]), Vector3(values[4], values[5], values[6]), Vector3(values[8], values[9], values[10])), Vector3(values[12], values[13], values[14]))

func _initialize() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://previous/recovery/staging/characters/native_runtime.json"))
	var library := AnimationLibrary.new()
	for rig: Dictionary in data.rigs.values():
		for key: String in ["locals", "worlds"]:
			var matrices: Array[Transform3D] = []
			for value: Array in rig[key]:
				matrices.append(transform(value))
			rig[key] = matrices
	library.set_meta("rigs", data.rigs)
	for clip: Dictionary in data.motions:
		var animation := Animation.new()
		animation.length = clip.duration
		for part: Dictionary in clip.parts:
			var position := animation.add_track(Animation.TYPE_POSITION_3D)
			var rotation := animation.add_track(Animation.TYPE_ROTATION_3D)
			animation.track_set_path(position, NodePath(".:" + part.name))
			animation.track_set_path(rotation, NodePath(".:" + part.name))
			for frame: int in range(part.translations.size() / 3):
				var value := Vector3(part.translations[frame * 3], part.translations[frame * 3 + 1], part.translations[frame * 3 + 2]) * float(data.scale)
				animation.position_track_insert_key(position, frame / 30.0, value)
			for frame: int in range(part.rotations.size() / 4):
				var value := Quaternion(part.rotations[frame * 4], part.rotations[frame * 4 + 1], part.rotations[frame * 4 + 2], part.rotations[frame * 4 + 3]).normalized()
				animation.rotation_track_insert_key(rotation, frame / 30.0, value)
		library.add_animation(clip.name, animation)
	assert(library.get_animation_list().size() == 402)
	assert(ResourceSaver.save(library, "res://resources/recovered/native.res") == OK)
	print("NATIVE: 402 unretargeted clips, %d calibrated rigs" % data.rigs.size())
	quit()
