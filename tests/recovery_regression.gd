extends SceneTree
## Exercises the actual Blender -> glTF -> Godot pilot: clips, skin, solid floors,
## inspection controls, traversal and a wall that blocked the original PS2 probes.

const H = preload("res://tools/agent/harness.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	print("PASS " if condition else "FAIL ", description)
	if not condition:
		failures.append(description)

func frames(count: int) -> void:
	for i: int in range(count):
		await physics_frame
		await process_frame

func _run() -> void:
	var session: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	await frames(12)
	var state: Dictionary = await H.scenario(self, "recovery_start", {"settle": 30})
	var lab: Node = session.level
	check(state.level == "recovery" and state.player.on_floor, "Showcase spawn stands on recovered ground")
	check(lab.animation_names.size() == 402 and lab.target_animation.get_animation_list().size() == 402, "All 402 recovered clips exist on both rigs")
	var skeleton: Skeleton3D = lab.character.find_children("*", "Skeleton3D", true, false)[0]
	check(skeleton.get_bone_count() == 26, "All 26 recovered skeleton parts survived import")
	var textured := 0
	var worst_weight_error := 0.0
	# Worn accessories are rigid meshes; this check audits the skinned body only.
	for node: Node in lab.character.model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface: int in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			if material != null and material.albedo_texture != null:
				textured += 1
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var stride: int = weights.size() / vertices.size()
			for v: int in range(vertices.size()):
				var sum := 0.0
				for influence: int in range(stride):
					sum += weights[v * stride + influence]
				worst_weight_error = maxf(worst_weight_error, absf(1.0 - sum))
	check(textured == 7 and worst_weight_error < 0.001, "Seven textured character surfaces retain normalized skin weights")
	var weapon_textures := 0
	for node: Node in lab.weapon.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface: int in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			if material != null and material.albedo_texture != null:
				weapon_textures += 1
	check(weapon_textures == 2, "M4 imports both recovered texture bindings")
	lab.set_clip(1)
	lab.set_playback_paused(true)
	lab.animation.seek(0.0, true)
	await frames(2)
	var foot_index := skeleton.find_bone("lfoot")
	var before := skeleton.get_bone_global_pose(foot_index).origin
	var root_before := skeleton.get_bone_global_pose(0).origin
	lab.animation.seek(0.3, true)
	await frames(2)
	var after := skeleton.get_bone_global_pose(foot_index).origin
	var root_after := skeleton.get_bone_global_pose(0).origin
	check(before.distance_to(after) > 0.05, "Recovered walk animates the foot (%.3f m)" % before.distance_to(after))
	check(Vector2(root_before.x, root_before.z).distance_to(Vector2(root_after.x, root_after.z)) < 0.001, "Inspection walk keeps root travel in place")
	var held: float = lab.animation.current_animation_position
	await frames(8)
	check(is_equal_approx(held, lab.animation.current_animation_position), "Pause holds the animation pose")
	lab.step_animation()
	check(is_equal_approx(lab.animation.current_animation_position - held, 1.0 / 30.0), "Frame step advances one recovered 30 Hz frame")
	for index: int in range(4):
		lab.set_clip(index)
		check(lab.animation.current_animation == lab.animation_names[index], "Clip can be selected: %s" % lab.CLIPS[index])
	lab.set_collision_visible(true)
	check(lab.collision_overlay.visible and lab.collision_overlay.mesh.get_surface_count() == 1, "Collision overlay contains recovered edges")
	lab.set_collision_visible(false)
	check(not lab.collision_overlay.visible, "Collision overlay can be hidden")
	for spawn: String in ["Showcase", "Plaza", "NorthStreet"]:
		var placed: Dictionary = await H.apply(self, {"spawn": spawn, "settle": 45})
		check(placed.player.on_floor and absf(placed.player.pos[1]) < 0.1, "%s settles on the original plaza floor" % spawn)
	await H.apply(self, {"spawn": "NorthStreet", "settle": 15})
	var route: Dictionary = await H.walk_to(self, [[8, -8], [-8, -8], [-8, 8], [0, 8]])
	check(route.walk.arrived and route.player.on_floor, "A route around the gazebo stays on recovered collision")
	await H.apply(self, {"pos": [-8, 0.1, -8], "yaw": 90, "settle": 20})
	var bumped: Dictionary = await H.step(self, 180, {"forward": 1.0, "speed": 4})
	check(bumped.player.pos[0] > -16.0 and bumped.player.pos[0] < -10.0, "Recovered building wall stops the player at x=%.2f" % bumped.player.pos[0])
	check(lab.get_node("Roster").get_child_count() == 0, "Inspection area stays free of the prototype combat roster")
	await H.scenario(self, "lab_start")
	check(session.in_lab and session.current_level == "lab" and session.hud.minimap.visible, "Leaving recovery restores the normal lab and HUD")
	print("\nRESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
