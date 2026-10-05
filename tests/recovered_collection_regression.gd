extends SceneTree
## Whole-collection checks and playable characters on their original rigs.
const H = preload("res://tools/agent/harness.gd")
const Library = preload("res://scripts/levels/recovery_library.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok:
		failures.append(description)

func frames(count: int = 3) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame

func tap(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await frames()
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await frames()

func _run() -> void:
	var data := Library.catalogue()
	check(data.characters.size() == 202 and data.motions.size() == 402, "Catalogue preserves all distinct characters and motions")
	check(data.counts.source_characters == 560 and data.counts.source_motions == 1178 and data.counts.partial_motions == 50, "Original occurrences and partial-body coverage remain recorded")
	var broken: Array[String] = []
	for entry: Dictionary in data.characters:
		var packed := load(entry.path) as PackedScene
		if packed == null:
			broken.append(entry.name + ": scene")
			continue
		var model := packed.instantiate()
		var skeletons := model.find_children("*", "Skeleton3D", true, false)
		var valid: bool = skeletons.size() == 1 and skeletons[0].get_bone_count() == 26
		for node: Node in model.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			valid = valid and mesh.skin != null
			for surface: int in range(mesh.mesh.get_surface_count()):
				var material := mesh.get_active_material(surface) as BaseMaterial3D
				valid = valid and material != null and material.albedo_texture != null
				var arrays := mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var stride: int = weights.size() / vertices.size()
				valid = valid and stride in [4, 8]
				for vertex: int in range(vertices.size()):
					var sum := 0.0
					for influence: int in range(stride):
						sum += weights[vertex * stride + influence]
					valid = valid and vertices[vertex].is_finite() and absf(sum - 1.0) < 0.002
		if not valid:
			broken.append(entry.name)
		model.free()
	check(broken.is_empty(), "All 202 exports retain their skeleton, normalized weights and texture bindings: %s" % [broken])
	var session: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	await frames(12)
	await H.scenario(self, "recovery_start")
	var lab: Node = session.level
	var source: Skeleton3D = lab.character.find_children("*", "Skeleton3D", true, false)[0]
	var target: Skeleton3D = lab.retargeted.find_children("*", "Skeleton3D", true, false)[0]
	lab.set_playback_paused(true)
	var finite := true
	var synchronized := true
	var durations := true
	for entry: Dictionary in data.motions:
		if not lab.animation.has_animation(entry.name) or not lab.target_animation.has_animation(entry.name):
			durations = false
			continue
		durations = durations and absf(lab.animation.get_animation(entry.name).length - entry.duration) < 0.001 and absf(lab.target_animation.get_animation(entry.name).length - entry.duration) < 0.001
	check(durations, "Every original clip name and 30 Hz duration survives the Blender/Godot pipeline")
	for clip: int in range(lab.animation_names.size()):
		lab.set_clip(clip)
		for phase: float in [0.0, 0.37, 0.81]:
			lab.seek_animation(lab.animation.current_animation_length * phase)
			synchronized = synchronized and is_equal_approx(lab.animation.current_animation_position, lab.target_animation.current_animation_position)
			for skeleton: Skeleton3D in [source, target]:
				for bone: int in range(skeleton.get_bone_count()):
					var pose := skeleton.get_bone_global_pose(bone)
					finite = finite and pose.origin.is_finite() and pose.basis.x.is_finite() and absf(pose.basis.determinant()) > 0.9
	check(finite and synchronized, "All 402 clips sample valid poses on both rigs at three synchronized times")
	check(target.get_bone_count() == 26 and target.find_bone("rhand") >= 0, "The playable preview uses the original 26-part skeleton")
	lab.set_clip(lab.animation_names.find("seal_walk"))
	var before := target.get_bone_global_pose(target.find_bone("lfoot")).origin
	lab.seek_animation(0.3)
	check(before.distance_to(target.get_bone_global_pose(target.find_bone("lfoot")).origin) > 0.05, "Original walking motion animates the recovered player model")
	await tap(KEY_TAB)
	check(lab.browser.opened and not session.player.controls_enabled and not session.hud.root.visible, "Tab opens an interactive browser and stops gameplay input")
	lab.set_clip(lab.animation_names.find("seal_walk"))
	lab.seek_animation(0.7)
	await frames()
	lab.set_clip(lab.animation_names.find("civ_walk"))
	lab.seek_animation(0.23)
	await frames()
	check(is_equal_approx(lab.animation.current_animation_position, 0.23), "Changing to a shorter clip keeps the requested paused preview time")
	lab.set_clip(lab.animation_names.find("seal_walk"))
	lab.browser.model_search.text = "SAS_01"
	lab.browser.model_search.text_changed.emit("SAS_01")
	check(lab.browser.model_picker.item_count == 1, "Character filter offers only the full-detail SAS model")
	var selected: int = lab.browser.model_picker.get_item_id(0)
	lab.browser.model_picker.item_selected.emit(0)
	await frames()
	check(lab.character_index == selected and lab.animation.current_animation == "seal_walk", "Selecting another character keeps the shared motion playing")
	var position: Vector3 = session.player.position
	var ammo: int = session.player.weapon.ammo
	for button: Button in lab.browser.panel.find_children("*", "Button", true, false):
		if button.text == "Use selected character for player":
			button.pressed.emit()
	check(session.player.soldier.soldier_skin.model_path == session.recovered_characters[selected].path and session.player.position == position and session.player.weapon.ammo == ammo, "Use selected character changes the playable model without resetting position or ammunition")
	lab.browser.motion_search.text = "reload"
	lab.browser.motion_search.text_changed.emit("reload")
	check(lab.browser.visible_motions.size() > 10 and lab.browser.visible_motions.all(func(name: String) -> bool: return name.contains("reload")), "Motion search finds rifle, pistol and equipment reloads")
	await tap(KEY_ESCAPE)
	check(not lab.browser.opened and session.player.controls_enabled and session.hud.root.visible, "Closing the browser restores the HUD and player controls")
	var skin: SoldierSkin = session.player.soldier.soldier_skin
	await tap(KEY_TAB)
	await H.scenario(self, "lab_start")
	check(session.player.controls_enabled and session.hud.root.visible and session.player.soldier.visible, "Leaving the lab with its browser open restores the player and HUD")
	check(skin.model_path == session.recovered_characters[selected].path, "Character choice survives level changes and respawn")
	await H.step(self, 45, {"forward": 1})
	check(skin.driver.active_clip == "seal_run" and session.player.is_on_floor(), "The playable original character uses full-body recovered running on the existing controller")
	check(skin.skeleton.get_bone_count() == 26 and skin.model.scale.is_equal_approx(Vector3.ONE), "Gameplay keeps original rig proportions without rescaling the character")
	await H.apply(self, {"stance": "crouch"})
	await H.step(self, 30, {"forward": 1})
	check(skin.driver.active_clip == "seal_crouchwalk", "Crouch movement selects the recovered crouch walk")
	await H.apply(self, {"stance": "prone"})
	await H.step(self, 30)
	check(skin.driver.active_clip == "seal_prone", "Prone uses the original full-body prone clip")
	var original_path := skin.model_path
	await tap(KEY_BRACKETRIGHT)
	check(skin.model_path != original_path, "Right bracket switches the playable recovered character")
	await tap(KEY_BRACKETLEFT)
	check(skin.model_path == original_path, "Left bracket switches back to the previous character")
	var all_playable := true
	for index: int in range(session.recovered_characters.size()):
		session.set_player_character(index)
		session.player.soldier.pose(0, 0, Vector2.ZERO, 0, 0, 1.0 / 60.0)
		all_playable = all_playable and skin.skeleton.get_bone_count() == 26 and skin.motion.current_animation == "seal_stand"
	check(all_playable, "Every selectable full-detail character can replace the player and use its original animation rig")
	print("\nRESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await frames()
	quit(0 if failures.is_empty() else 1)
