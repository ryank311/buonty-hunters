extends SceneTree
## Bullet impacts play the original per-surface bullet_hit_* effects; recovered maps
## carry their collision surfaces; water splashes and never blocks.
const H = preload("res://tools/agent/harness.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok:
		failures.append(description)

func impacts() -> Array:
	return root.find_children("*", "Node3D", true, false).filter(func(node: Node) -> bool: return node is ImpactFX)

func _run() -> void:
	check(ImpactFX.effect_for("stone") == "bullet_hit_stone" and ImpactFX.effect_for("plaster") == "bullet_hit_stone" and ImpactFX.effect_for("dirt") == "bullet_hit_dirt", "Surfaces map to their original effects (plaster plays stone's)")
	check(ImpactFX.effect_for("water") == "bullet_hit_water" and ImpactFX.effect_for("wood_thick") == "bullet_hit_wood_thick" and ImpactFX.effect_for("metal_thin") == "bullet_hit_metal_thin", "Water, wood and metal have their own effects")
	check(ImpactFX.effect_for("invisible_di") == "" and ImpactFX.effect_for("action") == "", "Bullets pass through invisible walls with no effect")
	var session: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	var player: PrototypePlayer = session.player
	await H.scenario(self, "lab_wall_camera", {"roster": false, "freeze": true, "pitch": -5.0})
	await H.step(self, 2, {"tap": ["fire"]})
	var fx := impacts()
	check(fx.size() == 1 and fx[0].effect == "bullet_hit_stone" and fx[0].get_child_count() >= 4, "A shot at a lab wall puffs the stone impact's layers")
	await H.step(self, 120)
	check(impacts().is_empty(), "The impact clears itself")

	await H.apply(self, {"level": "map:MP72"})
	var surfaces := {}
	for body: Node in session.level.find_children("*", "StaticBody3D", true, false):
		if body.has_meta(&"surface"):
			surfaces[body.get_meta(&"surface")] = true
	check(surfaces.has("asphalt") and surfaces.has("wood_thick") and surfaces.has("metal_thick") and surfaces.size() >= 10, "Crossroads collision carries its original surfaces (%d)" % surfaces.size())
	# Fish Hook's shoreline: a shot into the water splashes at its surface.
	await H.apply(self, {"level": "map:MP71"})
	var water: Array = session.level.find_children("*", "StaticBody3D", true, false).filter(func(body: Node) -> bool: return body.get_meta(&"surface", "") == "water")
	check(not water.is_empty() and water.all(func(body: StaticBody3D) -> bool: return body.collision_layer == ImpactFX.WATER_LAYER and body.collision_mask == 0), "Water is its own body, off the movement and bullet layers")
	if not water.is_empty():
		var faces: PackedVector3Array = water[0].get_child(0).shape.get_faces()
		var top: Vector3 = water[0].global_transform * ((faces[0] + faces[1] + faces[2]) / 3.0)
		for node: Node in impacts():
			node.free()
		ImpactFX.play_shot(player, top + Vector3(0.0, 3.0, 0.5), {"position": top + Vector3(0.0, -2.0, 0.0), "normal": Vector3.UP, "collider": null})
		fx = impacts()
		check(fx.size() == 1 and fx[0].effect == "bullet_hit_water" and absf(fx[0].global_position.y - top.y) < 1.0, "A shot into water splashes at its surface")
	print("RESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
