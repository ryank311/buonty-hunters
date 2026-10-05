extends SceneTree
const H = preload("res://tools/agent/harness.gd")
var failures: Array[String] = []
var session: Node
var player: PrototypePlayer

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok:
		failures.append(description)

func box(size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	session.level.add_child(body)
	body.position = position
	return body

func _run() -> void:
	session = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	player = session.player
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true})
	var context: Node = player.interactions
	var origin := player.position
	var obstacle := box(Vector3(3, 1, 3), origin + Vector3(0, 0.5, -2.2))
	await H.step(self, 5)
	context.refresh()
	check(context.offers.size() == 1 and context.offers[0].kind == "climb" and context.offers[0].enabled, "Reachable ledge offers the recovered climb action")
	session.hud.update_display(0.1)
	check(session.hud.context_hud.visible and session.hud.context_hud.hint.contains("CLIMB"), "HUD describes the selected executable action")
	await H.step(self, 1, {"tap": ["interact"]})
	check(player.traversal.active and player.soldier.traversal_clip == "seal_climbcrate", "Action button starts the recovered low climb")
	await H.step(self, 180)
	check(player.position.y > origin.y + 0.95 and not player.traversal.active, "Context climb finishes on top of the ledge")
	obstacle.queue_free()
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true})
	origin = player.position
	obstacle = box(Vector3(3, 1, 3), origin + Vector3(0, 0.5, -2.2))
	var roof := box(Vector3(3, 0.3, 3), origin + Vector3(0, 1.75, -2.2))
	await H.step(self, 3)
	context.refresh()
	check(context.offers.size() == 1 and not context.offers[0].enabled, "Climb prompt shares execution's headroom check")
	await H.step(self, 3, {"tap": ["interact"]})
	check(not player.traversal.active, "Unavailable action cannot climb into a ceiling")
	roof.queue_free()
	obstacle.queue_free()
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true})
	await H.step(self, 3, {"tap": ["interact"]})
	check(not session.lap_running, "An action press without a target cannot start the lap timer")
	# Every multiplayer map with a native door: both original surfaces must move.
	var total := 0
	for id: String in ["MP1", "MP2", "MP51", "MP6", "MP71", "MP73", "MP81", "MP82", "MP83"]:
		await H.apply(self, {"level": "map:" + id, "roster": false, "freeze": true})
		var entries: Array = JSON.parse_string(FileAccess.get_file_as_string("res://resources/recovered/actions/%s.json" % id.to_lower())).doors
		var found := 0
		var valid := true
		for door: Node3D in get_nodes_in_group("context_doors"):
			if not session.level.is_ancestor_of(door):
				continue
			found += 1
			valid = valid and door.render_triangles > 0 and door.collision_triangles > 0 and door.leaf_box.size.y > 0.5
			check(door.render_triangles > 0 and door.collision_triangles > 0, "%s/%s restores visual/collision ownership (%d/%d triangles)" % [id, door.name, door.render_triangles, door.collision_triangles])
		total += found
		check(valid and found == entries.size(), "%s installs all %d native doors" % [id, entries.size()])
	check(total == 43, "All 43 multiplayer door actions are installed")
	await H.apply(self, {"level": "map:MP2", "roster": false, "freeze": true})
	var door: Node3D = session.level.get_node("bdoor_4")
	var center: Vector3 = door.global_transform * door.leaf_box.get_center()
	var normal: Vector3 = door.global_basis.x.normalized()
	var feet: Vector3 = center + normal * 1.8
	feet.y = door.global_position.y + 0.02
	await H.apply(self, {"pos": [feet.x, feet.y, feet.z], "look_at": [center.x, center.y, center.z], "settle": 15, "freeze": true})
	context.refresh()
	check(not context.offers.is_empty() and context.offers[0].kind == "door" and context.offers[0].label == "OPEN DOOR", "Aimed-at in-range Frostfire door offers OPEN DOOR")
	var closed_transform: Transform3D = door.transform
	await H.step(self, 1, {"tap": ["interact"]})
	check(door.opened and door.busy and not session.lap_running, "One action press opens the door and is consumed")
	# Keep the player out of the swing for this cycle and inspect the old doorway ray.
	player.position = feet + normal * 1.0
	await H.step(self, 70)
	check(not door.busy and absf(door.basis.get_rotation_quaternion().angle_to(closed_transform.basis.get_rotation_quaternion()) - deg_to_rad(100)) < 0.001, "Frostfire door completes its native 100-degree swing")
	var ray := PhysicsRayQueryParameters3D.create(center + normal, center - normal, 1)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
	check(hit.is_empty(), "Opening leaves a clear passage without duplicate static collision")
	player.position = feet
	player.basis = Basis.looking_at(-normal, Vector3.UP)
	await H.step(self, 38, {"forward": 1.0})
	check((player.position - center).dot(normal) < -0.5, "The player can walk through the opened native doorway")
	player.position = feet + normal * 1.0
	door.activate()
	await H.step(self, 70)
	check(not door.opened and not door.busy and door.transform.is_equal_approx(closed_transform), "Closing restores the exact original hinge transform")
	hit = player.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and hit.collider == door, "Closing restores a solid door in the original passage")
	var blocker := box(Vector3(0.5, 1.6, 0.5), center)
	blocker.collision_layer = 2  # The same layer as a soldier occupying the swing.
	await H.step(self, 2)
	door.activate()
	await H.step(self, 15)
	check(door.blocked and door.busy and door.transform.is_equal_approx(closed_transform), "Door waits when the swing would intersect a soldier")
	blocker.queue_free()
	await H.step(self, 70)
	check(not door.blocked and not door.busy and door.opened, "Door resumes its swing when the soldier clears it")
	door.activate()
	await H.step(self, 70)
	await H.apply(self, {"pos": [feet.x, feet.y, feet.z], "look_at": [center.x, center.y, center.z], "settle": 15})
	door.spec.initial = 99
	context.refresh()
	check(not context.offers.is_empty() and not context.offers[0].enabled and context.offers[0].reason == "LOCKED" and not context.activate(), "Recovered valve 99 displays a disabled locked action")
	door.spec.initial = 0
	# The action must also work through the actual controller event mapping.
	# Real device events are ignored while the harness has the tree frozen.
	paused = false
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_Y
	button.pressed = true
	Input.parse_input_event(button)
	Input.flush_buffered_events()
	await H.step(self, 2)
	button = button.duplicate()
	button.pressed = false
	Input.parse_input_event(button)
	Input.flush_buffered_events()
	paused = true
	check(door.opened and door.busy and not session.lap_running, "Controller Y executes the selected door action without a timer side effect")
	player.position = feet + normal * 1.0
	await H.step(self, 70)
	door.activate()
	await H.step(self, 70)
	# Reach revalidation and modal exclusion.
	await H.apply(self, {"pos": [feet.x, feet.y, feet.z], "look_at": [center.x, center.y, center.z], "settle": 15})
	context.refresh()
	player.position += normal * 8.0
	check(not context.activate() and not door.opened, "A stale prompt cannot operate a door after moving out of reach")
	session.set_modal(true)
	session.hud.update_display(0.1)
	check(not session.hud.context_hud.visible and not context.activate(), "Pause menu hides and disables world actions")
	session.set_modal(false)
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true, "actors": [{"team": 1, "pos": [0.8, 0, 25.5], "dead": true, "name": "BODY"}]})
	await H.step(self, 5)
	context.refresh()
	check(not context.offers.is_empty() and context.offers[0].kind == "body", "Body search shares the recovered pickup prompt")
	obstacle = box(Vector3(3, 1, 3), player.position + Vector3(0, 0.5, -2.2))
	await H.step(self, 3)
	check(context.offers.size() == 2, "Nearby body and ledge share one context selection")
	await H.step(self, 3, {"tap": ["context_next"]})
	check(context.offers[context.selected].kind == "climb", "Tab selects the alternate climb action")
	var spawn_before: int = session.spawn_index
	paused = false
	button = InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_DPAD_UP
	button.pressed = true
	Input.parse_input_event(button)
	Input.flush_buffered_events()
	await H.step(self, 2)
	button = button.duplicate()
	button.pressed = false
	Input.parse_input_event(button)
	Input.flush_buffered_events()
	paused = true
	check(context.offers[context.selected].kind == "body" and session.spawn_index == spawn_before, "D-pad selects the body without triggering the debug spawn shortcut")
	await H.step(self, 3, {"tap": ["interact"]})
	check(player.weapon.director.loot_open, "Selected body search opens the existing weapon-exchange menu")
	print("RESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
