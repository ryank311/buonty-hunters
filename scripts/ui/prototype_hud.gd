class_name PrototypeHUD
extends CanvasLayer

const INK := Color("dce3d2")
const MUTED := Color("a6b4ad")
const GOLD := Color("d5bd7f")
const MAP_SCRIPT := preload("res://scripts/ui/tactical_map.gd")
# Preserve the authored HUD proportions while rasterizing the entire game at
# 640x480. The window upscales this finished frame, including all UI.
const LAYOUT_SIZE := Vector2(1024, 768)
var minimap: Control
var session: Node3D
var root := Control.new()
var ammo_label: Label
var weapon_label: Label
var controls_label: Label
var stats_label: Label
var mode_label: Label
var weapon_state_label: Label
var health_label: Label
var health_bar: ProgressBar
var health_fill: StyleBoxFlat
var weapon_icon: Control
var hud_panels: Dictionary = {}
var ammo_caption: Label
var round_label: Label
var player_name_label: Label
var notice_label: Label
var debug_label: Label
var crosshair: Control
var context_hud: Control
var menu: Control
var menu_box: VBoxContainer
var sliders: Dictionary = {}
var values: Dictionary = {}
var invert_toggle: CheckButton
var notice_time: float = 0.0
var pages: Array[VBoxContainer] = []
var page_buttons: Array[Button] = []
var page_controls: Array[Array] = []
var common_controls: Array[Control] = []
var focus_order: Array[Control] = []
var current_page: int = 0
var slider_parent: VBoxContainer
var loadout_menu: VBoxContainer
var weapon_tuning_menu: VBoxContainer

func initialize(owner_session: Node3D) -> void:
	session = owner_session
	add_child(root)
	root.size = LAYOUT_SIZE
	root.scale = get_viewport().get_visible_rect().size / LAYOUT_SIZE
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.8))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)
	root.theme = theme
	_build_hud()
	_build_menu()
	root.resized.connect(_layout_hud)
	_layout_hud.call_deferred()
	set_menu(false)

func _card(id: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = id
	root.add_child(panel)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.17, 0.24, 0.23, 0.18)
	style.border_color = Color("75806a")
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	hud_panels[id] = panel
	return box

func _text(parent: Node, text: String, font_size: int = 18, color: Color = INK) -> Label:
	var label := _label(parent, text, Vector2.ZERO, font_size, color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label

func _bar(parent: Node, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	parent.add_child(bar)
	bar.custom_minimum_size.y = height
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.08,0.12,0.09,0.20)
	background.border_color = Color("839379")
	background.set_border_width_all(0)
	bar.add_theme_stylebox_override("background", background)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("96bf78")
	fill.set_content_margin_all(1)
	bar.add_theme_stylebox_override("fill", fill)
	return bar

func _label(parent: Node, text: String, position: Vector2, font_size: int = 16, color: Color = INK) -> Label:
	var label := Label.new()
	parent.add_child(label)
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _build_hud() -> void:
	minimap = MAP_SCRIPT.new()
	minimap.name = "CircularMap"
	root.add_child(minimap)
	minimap.initialize(session)
	var weapon := _card("Weapon")
	var weapon_title := HBoxContainer.new()
	weapon.add_child(weapon_title)
	weapon_label = _text(weapon_title, "M4A1", 16, INK)
	mode_label = _text(weapon_title, "AUTO", 15, GOLD)
	mode_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	mode_label.custom_minimum_size.x = 60
	weapon_icon = Control.new()
	weapon.add_child(weapon_icon)
	weapon_icon.custom_minimum_size = Vector2(124, 42)
	weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_icon.draw.connect(_draw_weapon_icon)
	var ammo_row := HBoxContainer.new()
	weapon.add_child(ammo_row)
	ammo_row.add_theme_constant_override("separation", 8)
	ammo_label = _text(ammo_row, "30 / 90", 22, INK)
	ammo_caption = _text(ammo_row, "3 MAGS", 16, INK)
	ammo_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	weapon_state_label = _text(weapon, "", 15, GOLD)
	weapon_state_label.visible = false
	var status := _card("Player")
	round_label = _text(status, "ROUND  00:00", 18, INK)
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	player_name_label = _text(status, "", 16, INK)
	player_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	health_label = _text(status, "100 / 100", 13, INK)
	health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	health_bar = _bar(status, 4)
	health_fill = health_bar.get_theme_stylebox("fill") as StyleBoxFlat
	var notice := _card("Notice")
	notice_label = _text(notice, "", 17, GOLD)
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var debug := _card("Diagnostics")
	debug_label = _text(debug, "", 16)
	debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_label = _text(debug, "", 16)
	controls_label = _text(root, "START / %s  OPTIONS" % PlayerInput.function_key_hint(1), 14, INK)
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair = preload("res://scripts/ui/spread_reticle.gd").new()
	root.add_child(crosshair)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	context_hud = preload("res://scripts/ui/context_hud.gd").new()
	root.add_child(context_hud)
	context_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _layout_hud() -> void:
	var viewport_size := root.size
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		return
	var margin := Vector2(ceilf(viewport_size.x * 0.05), ceilf(viewport_size.y * 0.05))
	var left_width := minf(252, viewport_size.x * 0.28)
	var right_width := minf(236, viewport_size.x * 0.26)
	_set_card_rect("Weapon", Vector2(margin.x, 0), Vector2(left_width, 0))
	_set_card_rect("Player", Vector2(viewport_size.x - margin.x - right_width, 0), Vector2(right_width, 0))
	for id: String in ["Weapon", "Player"]:
		var panel: PanelContainer = hud_panels[id]
		panel.position.y = viewport_size.y - margin.y - panel.size.y
	minimap.size = Vector2(152,152)
	minimap.position = Vector2(viewport_size.x - margin.x - minimap.size.x, margin.y)
	var notice_width := minf(600, viewport_size.x - margin.x * 2 - 340)
	_set_card_rect("Notice", Vector2((viewport_size.x - notice_width) * 0.5, margin.y + 6), Vector2(notice_width, 0))
	_set_card_rect("Diagnostics", Vector2(margin.x, margin.y + 65), Vector2(300, 0))
	var recovery: bool = session.current_level == "recovery"
	var control_height := 64.0 if recovery else 22.0
	controls_label.position = Vector2((viewport_size.x - 250) * 0.5, viewport_size.y - margin.y - control_height)
	controls_label.size = Vector2(250, control_height)
	controls_label.visible = (session.debug_visible or recovery) and not session.modal
	for id: String in hud_panels:
		var style: StyleBoxFlat = hud_panels[id].get_theme_stylebox("panel")
		style.bg_color.a = session.player.camera_settings.hud_opacity if id in ["Weapon", "Player", "Diagnostics"] else 0.0

func _set_card_rect(id: String, position: Vector2, size: Vector2) -> void:
	var panel: PanelContainer = hud_panels[id]
	panel.position = position
	panel.size = Vector2(size.x, maxf(size.y, panel.get_combined_minimum_size().y))

func _draw_weapon_icon() -> void:
	var color := Color("d9dfce")
	var kind: String = session.player.weapon.profile.kind
	if kind == "claymore":
		weapon_icon.draw_rect(Rect2(34, 9, 56, 20), color)
		weapon_icon.draw_line(Vector2(45, 29), Vector2(39, 41), color, 3)
		weapon_icon.draw_line(Vector2(79, 29), Vector2(85, 41), color, 3)
	elif kind != "firearm":
		weapon_icon.draw_circle(Vector2(62, 27), 13, color)
		weapon_icon.draw_rect(Rect2(56, 6, 12, 10), color)
		weapon_icon.draw_line(Vector2(68, 8), Vector2(82, 20), color, 3)
	elif session.player.weapon.active_slot == 0:
		weapon_icon.draw_colored_polygon(PackedVector2Array([Vector2(5,18), Vector2(25,20), Vector2(30,14), Vector2(68,14), Vector2(73,18), Vector2(100,18), Vector2(100,23), Vector2(69,23), Vector2(66,27), Vector2(30,27), Vector2(25,24), Vector2(5,30)]), color)
		weapon_icon.draw_rect(Rect2(100, 19, 20, 3), color)
		weapon_icon.draw_colored_polygon(PackedVector2Array([Vector2(42,25), Vector2(53,25), Vector2(50,39), Vector2(39,37)]), color)
		weapon_icon.draw_line(Vector2(62,14), Vector2(62,8), color, 3)
		weapon_icon.draw_line(Vector2(97,18), Vector2(97,12), color, 3)
	else:
		weapon_icon.draw_colored_polygon(PackedVector2Array([Vector2(27,10), Vector2(96,10), Vector2(96,23), Vector2(56,23), Vector2(50,41), Vector2(31,41), Vector2(37,23), Vector2(27,23)]), color)
		weapon_icon.draw_rect(Rect2(54,24,14,8), color, false, 2)


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	parent.add_child(button)
	button.text = text
	button.custom_minimum_size.y = 37
	button.pressed.connect(callback)
	_bind_focus(button)
	return button

func _bind_focus(control: Control) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.8, 0.7, 0.4, 0.08)
	style.border_color = GOLD
	style.set_border_width_all(2)
	control.add_theme_stylebox_override("focus", style)
	control.focus_mode = Control.FOCUS_ALL
	control.gui_input.connect(func(event: InputEvent) -> void:
		# Up/down always selects a setting; left/right adjusts its value.
		if event.is_action_pressed("ui_up", true) or event.is_action_pressed("ui_down", true):
			var index := focus_order.find(control)
			if index >= 0:
				var direction := -1 if event.is_action_pressed("ui_up", true) else 1
				focus_order[posmod(index + direction, focus_order.size())].grab_focus()
			control.accept_event()
	)

func _page(title: String) -> void:
	var page := VBoxContainer.new()
	menu_box.add_child(page)
	page.custom_minimum_size.y = 255
	page.add_theme_constant_override("separation", 7)
	pages.append(page)
	page_controls.append([])
	slider_parent = page
	_label(page, title, Vector2.ZERO, 16, GOLD)

func _build_menu() -> void:
	menu = Control.new()
	root.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	menu.add_child(shade)
	shade.color = Color(0.025, 0.04, 0.035, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	menu.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	center.add_child(panel)
	panel.custom_minimum_size = Vector2(730, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("192621")
	style.set_content_margin_all(22)
	style.border_color = Color("68745c")
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	menu_box = VBoxContainer.new()
	panel.add_child(menu_box)
	menu_box.add_theme_constant_override("separation", 8)
	_label(menu_box, "FIELD TEST / TUNING", Vector2.ZERO, 23, GOLD)
	_label(menu_box, "Paused · LB / RB change page · ↑ / ↓ select · ← / → adjust · A confirm · B back", Vector2.ZERO, 13, MUTED)
	var tabs := HBoxContainer.new()
	menu_box.add_child(tabs)
	for title: String in ["Movement", "Camera", "Controller", "Debug tuning", "Maps", "Loadout"]:
		var index := page_buttons.size()
		page_buttons.append(_button(tabs, title, func() -> void: show_page(index)))
	_page("Grounded movement")
	_slider("run_speed", "Run speed (m/s)", 2.5, 7.0, 0.1)
	_slider("acceleration", "Acceleration (m/s²)", 10.0, 60.0, 1.0)
	_slider("braking", "Braking (m/s²)", 10.0, 70.0, 1.0)
	_slider("body_weight", "Body weight / compression", 0.0, 2.0, 0.1)
	_slider("prone_speed", "Prone crawl speed (m/s)", 0.3, 1.6, 0.05)
	_label(slider_parent, "Lower acceleration builds speed more gradually.\nBody weight controls stride loading and landing compression.", Vector2.ZERO, 14, MUTED)
	_page("Third-person view")
	_slider("field_of_view", "Vertical field of view", 50.0, 80.0, 1.0)
	_slider("distance", "Camera distance (m)", 1.8, 4.5, 0.1)
	_slider("shoulder_offset", "Camera side offset (m)", -0.5, 0.5, 0.05)
	_slider("height_offset", "Camera height above stance (m)", 0.0, 1.4, 0.05)
	_slider("mouse_sensitivity", "Mouse sensitivity", 0.001, 0.006, 0.0001)
	_slider("hud_opacity", "HUD backing opacity", 0.0, 0.5, 0.02)
	_label(slider_parent, "Fixed 640 × 480 / 4:3 · Window size only scales the image", Vector2.ZERO, 14, MUTED)
	_page("Controller response")
	_slider("pad_sensitivity", "Look speed (rad/s)", 1.0, 5.0, 0.1)
	_slider("pad_deadzone", "Stick dead zone", 0.05, 0.35, 0.01)
	_slider("pad_aim_multiplier", "Focused aim sensitivity", 0.2, 1.0, 0.05)
	_slider("vibration", "Vibration strength", 0.0, 1.0, 0.05)
	invert_toggle = CheckButton.new()
	slider_parent.add_child(invert_toggle)
	invert_toggle.text = "Invert vertical look"
	invert_toggle.toggled.connect(func(value: bool) -> void: session.player.camera_settings.invert_y = value)
	_bind_focus(invert_toggle)
	page_controls.back().append(invert_toggle)
	_page("Debug tuning · your current weapons and equipment")
	weapon_tuning_menu = preload("res://scripts/ui/debug_weapon_tuning.gd").new()
	slider_parent.add_child(weapon_tuning_menu)
	weapon_tuning_menu.initialize(self)
	_build_map_page()
	_page("Loadout & character · A / click opens a list")
	loadout_menu = preload("res://scripts/ui/debug_loadout.gd").new()
	slider_parent.add_child(loadout_menu)
	loadout_menu.initialize(self)
	var row := HBoxContainer.new()
	menu_box.add_child(row)
	common_controls.append(_button(row, "Resume / Start", func() -> void: session.set_modal(false)))
	common_controls.append(_button(row, "Old Quarter", func() -> void: session.load_level(false); session.set_modal(false)))
	common_controls.append(_button(row, "Movement Lab", func() -> void: session.load_level(true); session.set_modal(false)))
	common_controls.append(_button(row, "Recovery Lab", func() -> void: session.load_recovery(); session.set_modal(false)))
	common_controls.append(_button(row, "Reset / refill", func() -> void: session.reset_player(); session.set_modal(false)))
	var bottom := HBoxContainer.new()
	menu_box.add_child(bottom)
	common_controls.append(_button(bottom, "Next spawn", func() -> void: session.next_spawn(); session.set_modal(false)))
	common_controls.append(_button(bottom, "Choose class", func() -> void: session.set_modal(false); session.player.weapon.director.open_class_menu()))
	common_controls.append(_button(bottom, "Restore all defaults", func() -> void: session.reset_tuning()))
	common_controls.append(_button(bottom, "Quit", func() -> void: session._save_settings(); get_tree().quit()))
	_label(menu_box, "C / B: tap crouch · hold prone · hold while running forward to dive\nX / R reload · D-pad ← rifle / → pistol / ↑ spawn / ↓ reset · Stick: walk → jog → sprint · Shift walk", Vector2.ZERO, 13, MUTED)
	show_page(0, false)
	refresh_settings()

## Multiplayer disc maps installed by tools/recovery/prepare_level.py.
func _build_map_page() -> void:
	_page("Multiplayer maps · original geometry, sky, lighting and fog")
	var scroll := ScrollContainer.new()
	slider_parent.add_child(scroll)
	scroll.custom_minimum_size = Vector2(0, 222)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	var grid := GridContainer.new()
	scroll.add_child(grid)
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var maps := RecoveredMap.catalogue()
	if maps.is_empty():
		_label(grid, "No multiplayer maps installed yet", Vector2.ZERO, 14, MUTED)
	for entry: Dictionary in maps:
		var id: String = entry.id
		var button := _button(grid, entry.name, func() -> void: session.load_map(id); session.set_modal(false))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 30
		button.add_theme_font_size_override("font_size", 13)
		button.tooltip_text = "%s · %s" % [id, entry.mode]
		page_controls.back().append(button)

func _settings_for(key: String) -> Resource:
	if "/" in key:
		return session.player.weapon.profiles[0 if key.begins_with("rifle/") else 1]
	return session.player.movement if key in ["run_speed", "acceleration", "braking", "body_weight", "prone_speed"] else session.player.camera_settings

func _slider(key: String, title: String, minimum: float, maximum: float, step: float) -> void:
	var row := HBoxContainer.new()
	slider_parent.add_child(row)
	var label := _label(row, title, Vector2.ZERO, 15)
	label.custom_minimum_size.x = 230
	var slider := HSlider.new()
	row.add_child(slider)
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.custom_minimum_size = Vector2(280, 24)
	sliders[key] = slider
	_bind_focus(slider)
	page_controls.back().append(slider)
	var value_label := _label(row, "", Vector2.ZERO, 14, GOLD)
	value_label.custom_minimum_size.x = 75
	values[key] = value_label
	slider.value_changed.connect(func(value: float) -> void:
		_settings_for(key).set(key.get_slice("/", 1) if "/" in key else key, value)
		value_label.text = "%.4f" % value if key == "mouse_sensitivity" else "%.2f" % value
	)

func refresh_settings() -> void:
	for key: String in sliders:
		var value: float = _settings_for(key).get(key.get_slice("/", 1) if "/" in key else key)
		sliders[key].set_value_no_signal(value)
		values[key].text = "%.4f" % value if key == "mouse_sensitivity" else "%.2f" % value
	invert_toggle.set_pressed_no_signal(session.player.camera_settings.invert_y)
	if loadout_menu != null:
		loadout_menu.refresh()
	if weapon_tuning_menu != null:
		weapon_tuning_menu.refresh()

func show_page(index: int, focus: bool = true) -> void:
	close_menu_popup()
	if loadout_menu != null:
		loadout_menu.refresh()
	if weapon_tuning_menu != null:
		weapon_tuning_menu.refresh()
	current_page = posmod(index, pages.size())
	focus_order.clear()
	for button: Button in page_buttons:
		focus_order.append(button)
	for page: int in range(pages.size()):
		pages[page].visible = page == current_page
		page_buttons[page].modulate = GOLD if page == current_page else INK
	for control: Control in page_controls[current_page]:
		focus_order.append(control)
	focus_order.append_array(common_controls)
	for i: int in range(focus_order.size()):
		var control := focus_order[i]
		control.focus_neighbor_top = control.get_path_to(focus_order[posmod(i - 1, focus_order.size())])
		control.focus_neighbor_bottom = control.get_path_to(focus_order[(i + 1) % focus_order.size()])
		control.focus_previous = control.focus_neighbor_top
		control.focus_next = control.focus_neighbor_bottom
		if control is HSlider:
			control.focus_neighbor_left = NodePath(".")
			control.focus_neighbor_right = NodePath(".")
	if focus:
		page_controls[current_page][0].grab_focus()

func change_page(direction: int) -> void:
	show_page(current_page + direction)

func close_menu_popup() -> bool:
	for control: Control in focus_order:
		if is_instance_valid(control) and control is OptionButton and control.get_popup().visible:
			control.get_popup().hide()
			return true
	return false

func set_menu(value: bool) -> void:
	if not value:
		close_menu_popup()
	menu.visible = value
	if value:
		weapon_tuning_menu.refresh(true)
		refresh_settings()
		show_page(current_page)
	else:
		get_viewport().gui_release_focus()

func notify(text: String) -> void:
	notice_label.text = text
	notice_time = 4.0

func update_display(delta: float) -> void:
	var player: PrototypePlayer = session.player
	var recovery: bool = session.current_level == "recovery"
	controls_label.text = "TAB  CHARACTER / MOTION BROWSER\n%s CLIP  ·  %s PAUSE\n%s COLLISION  ·  %s STEP" % [PlayerInput.function_key_hint(6), PlayerInput.function_key_hint(7), PlayerInput.function_key_hint(8), PlayerInput.function_key_hint(9)] if recovery else "START / %s  OPTIONS" % PlayerInput.function_key_hint(1)
	minimap.visible = not recovery
	player_name_label.text = preload("res://scripts/combat/combat.gd").name_of(player)
	weapon_label.text = player.weapon.profile.display_name
	# Grenades and claymores are counted, not loaded from magazines.
	var equipment: bool = player.weapon.profile.kind != "firearm"
	mode_label.text = "GEAR" if equipment else player.weapon.mode_caption()
	mode_label.tooltip_text = "B / L3: change firing mode"
	ammo_label.text = "x %d" % player.weapon.ammo if equipment else "%02d / %02d" % [player.weapon.ammo, player.weapon.reserve]
	ammo_caption.text = "CARRIED" if equipment else "%d MAGS" % ceili(float(player.weapon.reserve) / player.weapon.profile.magazine_size)
	var pad := not Input.get_connected_joypads().is_empty()
	if player.weapon.reload_remaining > 0.0:
		weapon_state_label.text = "RELOADING  %.1f s" % player.weapon.reload_remaining
	elif player.weapon.draw_remaining > 0.0:
		weapon_state_label.text = "READYING" if equipment else "DRAWING  %s" % ("PISTOL" if player.weapon.active_slot == 1 else "RIFLE")
	elif player.weapon.ammo == 0:
		weapon_state_label.text = "NONE LEFT" if equipment else "EMPTY  ·  %s RELOAD" % ("X" if pad else "R")
	else:
		weapon_state_label.text = ""
	weapon_state_label.visible = not weapon_state_label.text.is_empty()
	health_label.text = "%d / %d" % [player.health, player.max_health]
	health_bar.max_value = player.max_health
	health_bar.value = player.health
	var health_fraction := player.health / maxf(1, player.max_health)
	var health_color := Color("e48871") if health_fraction <= 0.25 else (Color("d5bd7f") if health_fraction <= 0.5 else Color("96bf78"))
	health_fill.bg_color = health_color
	stats_label.text = "%.1f m/s  ·  %d hits" % [Vector2(player.velocity.x, player.velocity.z).length(), player.weapon.hits]
	var elapsed := int(session.elapsed)
	round_label.text = "ROUND  %02d:%02d" % [elapsed / 60, elapsed % 60]
	notice_time = maxf(0.0, notice_time - delta)
	hud_panels.Notice.visible = notice_time > 0 and not session.modal
	hud_panels.Notice.modulate.a = minf(notice_time, 1.0)
	hud_panels.Diagnostics.visible = session.debug_visible and not session.modal
	debug_label.text = "%.0f FPS\nPosition  %.1f / %.1f / %.1f\nCamera  %.2f m  |  FOV %.0f°\nGrounded  %s\nR3 / %s  Hide diagnostics" % [Engine.get_frames_per_second(), player.position.x, player.position.y, player.position.z, player.camera_rig.arm.get_hit_length(), player.camera_rig.camera.fov, player.is_on_floor(), PlayerInput.function_key_hint(3)]
	_layout_hud()
	minimap.refresh()
	if session.lap_running or session.last_lap > 0.0:
		debug_label.text += "\nLAP  %.2f s" % (session.lap_time if session.lap_running else session.last_lap)
	weapon_icon.queue_redraw()
	crosshair.update_weapon(player.weapon, delta, session.modal)
	context_hud.update_actions(player.interactions, delta)
