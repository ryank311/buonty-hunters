extends SceneTree
## Every installed recovered map loads with its original ambience, grounds the
## player at each spawn, and hands the default environment back when left.
const H = preload("res://tools/agent/harness.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok:
		failures.append(description)

func _run() -> void:
	var session: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true})
	var default_environment: Environment = session.get_node("Environment").environment
	var default_sun: Transform3D = session.get_node("Sun").transform
	var maps := RecoveredMap.catalogue()
	check(maps.size() == 22 and maps.all(func(entry: Dictionary) -> bool: return entry.mode == "Multiplayer" and entry.id.begins_with("MP")), "All 22 recovered multiplayer maps are installed")
	check(DirAccess.get_files_at(RecoveredMap.LEVELS).size() == 22, "Runtime level descriptions contain only the 22 multiplayer maps")
	var original_level: Node = session.level
	session.load_map("M51")
	check(session.level == original_level and session.current_level == "lab", "A retired campaign map request preserves the active level")
	for entry: Dictionary in maps:
		var title := "%s (%s)" % [entry.name, entry.id]
		await H.apply(self, {"level": "map:" + entry.id})
		var level: Node = session.level
		check(session.current_level == "map:" + entry.id and session.level_title() == entry.name.to_upper(), "%s loads through the session" % title)
		var environment: Environment = session.get_node("Environment").environment
		var fog: Dictionary = entry.ambience.fog
		check(environment != default_environment and environment.fog_enabled == fog.enabled and is_equal_approx(environment.fog_depth_end, fog.end), "%s applies its original fog (%.0f-%.0f m)" % [title, fog.begin, fog.end])
		var sky: Node = level.get_node_or_null("Sky")
		if entry.sky != null:
			var shaded := sky != null
			for mesh: MeshInstance3D in (sky.find_children("*", "MeshInstance3D", true, false) if sky != null else []):
				shaded = shaded and mesh.get_surface_override_material(0) is ShaderMaterial
			check(shaded, "%s draws its recovered sky dome with the sky shader" % title)
		var shapes := level.find_children("*", "CollisionShape3D", true, false)
		check(not shapes.is_empty() and shapes.all(func(shape: CollisionShape3D) -> bool: return shape.shape.backface_collision), "%s has two-sided recovered collision" % title)
		var spawns: Node = level.get_node("Spawns")
		var grounded := 0
		var report: Array[String] = []
		for index: int in range(spawns.get_child_count()):
			session.spawn_index = index
			session.reset_player()
			await H.step(self, 30)
			var player: PrototypePlayer = session.player
			var expected: Vector3 = spawns.get_child(index).global_position
			if player.is_on_floor() and absf(player.global_position.y - expected.y) < 0.6:
				grounded += 1
			else:
				report.append("%s at y %.2f (spawn %.2f)" % [spawns.get_child(index).name, player.global_position.y, expected.y])
		check(spawns.get_child_count() > 0 and grounded == spawns.get_child_count(), "%s grounds the player at all %d spawns %s" % [title, spawns.get_child_count(), report])
	await H.apply(self, {"level": "lab"})
	check(session.get_node("Environment").environment == default_environment and session.get_node("Sun").transform.is_equal_approx(default_sun), "Leaving a recovered map restores the default environment and sun")
	print("RESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
