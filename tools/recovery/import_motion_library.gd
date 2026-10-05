extends SceneTree
## Extract reusable, skeleton-relative libraries from the Blender exports.
## Run with tools/dev godot --headless --path . --script res://tools/recovery/import_motion_library.gd

func _initialize() -> void:
	var catalogue: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/recovered/catalogue.json"))
	var durations: Dictionary = {}
	for motion: Dictionary in catalogue.motions:
		durations[motion.name] = motion.duration
	for entry: Array in [["recovered_motion_library", "original"], ["soldier_recovered", "soldier"]]:
		var scene := load("res://art/models/%s.glb" % entry[0]) as PackedScene
		assert(scene != null)
		var model := scene.instantiate()
		var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var player := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var library := AnimationLibrary.new()
		var names: Array[String] = []
		var parents: Array[int] = []
		var rests: Array[Transform3D] = []
		for bone: int in range(skeleton.get_bone_count()):
			names.append(skeleton.get_bone_name(bone))
			parents.append(skeleton.get_bone_parent(bone))
			rests.append(skeleton.get_bone_rest(bone))
		for animation_name: String in player.get_animation_list():
			if animation_name == "RESET":
				continue
			var animation := player.get_animation(animation_name).duplicate() as Animation
			var name := animation_name.get_file()
			# Godot consumes an _loop suffix as an import instruction. Restore the
			# original catalogue name so search and gameplay lookups remain exact.
			if not durations.has(name) and durations.has(name + "_loop"):
				name += "_loop"
			assert(durations.has(name), "Unexpected clip name: " + name)
			assert(absf(animation.length - durations[name]) < 0.001, "Duration changed: " + name)
			animation.loop_mode = Animation.LOOP_NONE
			for track: int in range(animation.get_track_count() - 1, -1, -1):
				var path := animation.track_get_path(track)
				if path.get_subname_count() != 1 or not names.has(String(path.get_subname(0))):
					animation.remove_track(track)
					continue
				animation.track_set_path(track, NodePath(".:" + String(path.get_subname(0))))
			assert(animation.get_track_count() > 0)
			library.add_animation(name, animation)
		library.set_meta("bone_names", names)
		library.set_meta("bone_parents", parents)
		library.set_meta("bone_rests", rests)
		assert(library.get_animation_list().size() == 402)
		var result := ResourceSaver.save(library, "res://resources/recovered/%s.res" % entry[1])
		assert(result == OK)
		print("MOTIONS %s: %d clips, %d bones" % [entry[1], library.get_animation_list().size(), names.size()])
		model.free()
	quit()
