extends SceneTree
## Expected transforms are computed from the decoded archive, before Blender.
const Library = preload("res://scripts/levels/recovery_library.gd")

func _initialize() -> void:
	_run.call_deferred()

func matrix(values: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(values[0], values[1], values[2]), Vector3(values[4], values[5], values[6]), Vector3(values[8], values[9], values[10])), Vector3(values[12], values[13], values[14]))

func _run() -> void:
	var path := "res://tests/fixtures/recovered_fidelity.json"
	if OS.get_cmdline_user_args().has("--all-recovered"):
		path = "res://previous/recovery/staging/characters/all_fidelity.json"
	var samples: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	var library: AnimationLibrary = load(Library.ORIGINAL)
	var model: Node3D
	var player: Node
	var current_path := ""
	var worst_position := 0.0
	var worst_basis := 0.0
	var worst_case := ""
	for sample: Dictionary in samples:
		if sample.model != current_path:
			if model != null:
				model.free()
			model = load(sample.model).instantiate()
			root.add_child(model)
			player = Library.attach(model, library)
			current_path = sample.model
		player.play(sample.clip)
		player.seek(sample.time, true)
		var skeleton: Skeleton3D = player.skeleton
		for index: int in range(sample.names.size()):
			var id := skeleton.find_bone(sample.names[index])
			var actual := skeleton.get_bone_global_pose(id) * skeleton.get_bone_global_rest(id).affine_inverse()
			var expected := matrix(sample.deform[index])
			var error := actual.origin.distance_to(expected.origin)
			if error > worst_position:
				worst_position = error
				worst_case = "%s / %s / %s" % [sample.model, sample.clip, sample.names[index]]
			worst_basis = maxf(worst_basis, maxf(actual.basis.x.distance_to(expected.basis.x), maxf(actual.basis.y.distance_to(expected.basis.y), actual.basis.z.distance_to(expected.basis.z))))
	model.free()
	var ok := worst_position < 0.002 and worst_basis < 0.002
	print("PASS " if ok else "FAIL ", "%d archive pose samples preserve native skin deformation (%.6f m, axes %.6f): %s" % [samples.size(), worst_position, worst_basis, worst_case])
	print("RESULT: %d failure(s)" % (0 if ok else 1))
	quit(0 if ok else 1)
