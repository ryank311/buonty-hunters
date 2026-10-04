extends SceneTree

var failures: Array[String] = []
var session: Node3D
var hud: PrototypeHUD

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	print("PASS " if condition else "FAIL ", description)
	if not condition:
		failures.append(description)

func settle(count: int = 5) -> void:
	for i: int in range(count):
		await process_frame

func labels_in(node: Node) -> Array[Label]:
	var result: Array[Label] = []
	for child: Node in node.get_children():
		if child is Label:
			result.append(child)
		result.append_array(labels_in(child))
	return result

func _run() -> void:
	session = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	hud = session.hud
	await settle()
	for output_size: Vector2i in [Vector2i(1280,720), Vector2i(960,540), Vector2i(1024,768), Vector2i(1920,1080), Vector2i(2560,1080)]:
		root.size = output_size
		await settle()
		var viewport_rect := root.get_visible_rect()
		var margin := Vector2(ceilf(viewport_rect.size.x * 0.05), ceilf(viewport_rect.size.y * 0.05))
		var safe_rect := Rect2(margin - Vector2.ONE, viewport_rect.size - margin * 2 + Vector2.ONE * 2)
		var bounded := true
		var legible := true
		var separate := true
		var ids := ["Location", "Weapon", "Squad"]
		for id: String in ids:
			var panel: PanelContainer = hud.hud_panels[id]
			if not safe_rect.encloses(panel.get_global_rect()):
				print(id, " outside safe area: ", panel.get_global_rect(), " vs ",safe_rect)
				bounded = false
			for label: Label in labels_in(panel):
				var font := label.get_theme_font("font")
				var font_size := label.get_theme_font_size("font_size")
				var text_size := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
				if text_size.x > label.size.x + 1 or not panel.get_global_rect().encloses(label.get_global_rect()):
					print("Clipped ",label.text," at ", label.get_global_rect()," needs ",text_size)
					legible = false
			for other: String in ids:
				if id != other and panel.get_global_rect().intersects(hud.hud_panels[other].get_global_rect()):
					separate = false
		bounded = bounded and safe_rect.encloses(hud.minimap.get_global_rect())
		check(bounded, "%s: all core HUD elements inside the 5%% safe area" % output_size)
		check(legible, "%s: every core HUD label fits without clipping" % output_size)
		check(separate, "%s: HUD cards do not overlap" % output_size)
	var style: StyleBoxFlat = hud.hud_panels.Weapon.get_theme_stylebox("panel")
	check(style.bg_color.a <= 0.2 and style.border_width_left == 0, "Gameplay HUD uses faint backing without black borders")
	check(hud.hud_panels.Weapon.size.y < 155 and hud.hud_panels.Squad.size.y < 130, "Weapon and squad overlays remain compact")
	check(hud.minimap.size.is_equal_approx(Vector2(152,152)), "Circular minimap keeps a compact square footprint")
	check(hud.minimap.footprints.size() > 20, "Minimap contains authored level geometry")
	var center: Vector2 = hud.minimap.size * 0.5
	check(hud.minimap.map_point(session.player.position).is_equal_approx(center), "Minimap centers on the actual player position")
	var clipped := true
	for polygon: PackedVector2Array in hud.minimap.clipped_footprints():
		for point: Vector2 in polygon:
			clipped = clipped and point.distance_to(center) <= 73.05
	check(clipped, "All map geometry clips inside the circular rim")
	var north_before: Vector2 = hud.minimap.map_point(session.player.position + Vector3.FORWARD * 10)
	session.player.rotation.y += PI / 2.0
	var north_after: Vector2 = hud.minimap.map_point(session.player.position + Vector3.FORWARD * 10)
	check(north_before.distance_to(north_after) > 10, "Map rotates with the player's facing")
	session.player.rotation.y -= PI / 2.0
	var old_footprints: int = hud.minimap.footprints.size()
	session.load_level(true)
	await settle()
	check(hud.minimap.mapped_level == session.level and hud.minimap.footprints.size() != old_footprints, "Map rebuilds when switching levels")
	# Weapon identity, mode and ammo remain visible through swaps and reload states.
	session.player.weapon.equip(1)
	await settle()
	check(hud.weapon_label.text == "SERVICE PISTOL" and hud.mode_label.text == "SEMI" and hud.ammo_label.text == "12 / 36", "Pistol selection updates weapon, fire mode and ammunition")
	session.player.weapon.equip(0)
	session.player.weapon.draw_remaining = 0
	session.player.weapon.ammo = 7
	session.player.weapon.reload_remaining = 1.5
	await settle()
	check(hud.mode_label.text == "AUTO" and hud.ammo_label.text == "07 / 90" and hud.weapon_state_label.text.begins_with("RELOADING"), "Reload state preserves rifle mode and ammunition readout")
	session.player.health = 24
	await settle()
	check(hud.health_bar.value == 24 and hud.squad_health_bar.value == 24 and hud.health_label.text == "24 / 100", "Both health displays follow player state")
	check(hud.health_fill.bg_color == Color("e48871"), "Low health has a readable critical state")
	session.reset_player()
	await settle()
	check(hud.health_bar.value == 100 and hud.ammo_label.text == "30 / 90", "Reset restores health and ammo readouts")
	check(hud.squad_rows.size() == 5 and labels_in(hud.hud_panels.Squad).any(func(label: Label) -> bool: return label.text == "05  OPEN SLOT"), "Squad panel contains the player and four explicitly open slots")
	# A saved comparison option from older builds must not alter the fixed buffer.
	var legacy := ConfigFile.new()
	legacy.set_value("display", "retro", true)
	session.apply_settings_config(legacy)
	await settle()
	check(is_equal_approx(root.scaling_3d_scale,1.0) and root.get_visible_rect().size == Vector2(640,480), "Older half-resolution settings cannot change the shared 640x480 frame")
	check(hud.root.get_global_rect().size.is_equal_approx(root.get_visible_rect().size), "HUD and world occupy the same fixed-resolution frame")
	root.size = Vector2i(960,540)
	session.set_modal(true)
	for page: int in range(hud.pages.size()):
		hud.show_page(page)
		await settle()
		check(root.get_visible_rect().encloses(hud.menu_box.get_global_rect()), "Tuning page %d still fits at minimum window size" % (page + 1))
	print("\nRESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await settle(2)
	quit(0 if failures.is_empty() else 1)
