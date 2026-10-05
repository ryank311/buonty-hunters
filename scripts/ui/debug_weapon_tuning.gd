extends VBoxContainer
## Only controls that affect the selected carried item are exposed here.
const Tuning := preload("res://scripts/combat/weapon_tuning.gd")
const Guns := preload("res://scripts/combat/recovered_weapons.gd")
var hud: Node
var page_index: int
var weapon_picker: OptionButton
var fields: VBoxContainer
var feedback: Label
var save_button: Button
var defaults_button: Button
var editors: Dictionary = {}
var controls: Array[Control] = []
var slot: int = -1
var edited_profile: WeaponProfile

func initialize(owner_hud: Node) -> void:
	hud = owner_hud
	page_index = hud.pages.size() - 1
	add_theme_constant_override("separation", 8)
	weapon_picker = OptionButton.new()
	add_child(weapon_picker)
	weapon_picker.fit_to_longest_item = false
	weapon_picker.custom_minimum_size.y = 34
	weapon_picker.item_selected.connect(func(index: int) -> void:
		slot = index
		refresh()
		hud.show_page(page_index, false)
		weapon_picker.grab_focus()
	)
	hud._bind_focus(weapon_picker)
	var scroll := ScrollContainer.new()
	add_child(scroll)
	scroll.custom_minimum_size.y = 220
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	fields = VBoxContainer.new()
	scroll.add_child(fields)
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("separation", 7)
	var buttons := HBoxContainer.new()
	add_child(buttons)
	save_button = hud._button(buttons, "Save changes", save_changes)
	defaults_button = hud._button(buttons, "Reset this weapon", reset_selected)
	feedback = Label.new()
	add_child(feedback)
	feedback.add_theme_font_size_override("font_size", 13)
	feedback.add_theme_color_override("font_color", hud.MUTED)
	feedback.text = "Edits apply immediately. Save keeps them for this weapon across launches."
	refresh(true)

func refresh(follow_hand: bool = false) -> void:
	var weapon: PracticeWeapon = hud.session.player.weapon
	if follow_hand or slot < 0 or slot >= weapon.profiles.size():
		slot = weapon.active_slot
	weapon_picker.clear()
	for index: int in range(weapon.profiles.size()):
		var profile := weapon.profiles[index]
		var title: String = profile.recovered_stats.get("name", profile.display_name)
		var role: String = ["Primary", "Pistol", "Equipment 1", "Equipment 2"][index] if index < 4 else "Equipment"
		weapon_picker.add_item("%s · %s%s" % [role, title, " · in hand" if index == weapon.active_slot else ""])
	weapon_picker.select(slot)
	if edited_profile != weapon.profiles[slot]:
		edited_profile = weapon.profiles[slot]
		_build_fields()
	for key: String in editors:
		editors[key].set_value_no_signal(_value(key))

func _build_fields() -> void:
	for child: Node in fields.get_children():
		fields.remove_child(child)
		child.queue_free()
	editors.clear()
	controls = [weapon_picker]
	var keys: Array[String] = []
	if edited_profile.kind == "firearm":
		if not edited_profile.recovered_stats.is_empty():
			keys.append_array(["recovered_recoil_scale", "recovered_spread_scale", "weapon_kick"])
		else:
			keys.append_array(["vertical_kick", "horizontal_kick", "recovery_delay", "recovery_speed", "max_climb", "base_spread", "walk_spread", "run_spread", "spread_per_shot", "max_bloom", "unaimed_spread", "pellet_spread", "weapon_kick"])
		keys.append_array(["rounds_per_minute", "damage", "magazine_size", "starting_reserve", "reload_seconds", "draw_seconds", "range_metres", "falloff_start", "falloff_end", "minimum_damage", "pellets", "impact_diameter", "muzzle_velocity", "bullet_gravity", "sound_pitch"])
	elif edited_profile.kind == "detonator":
		keys.append("draw_seconds")
	elif edited_profile.kind == "claymore":
		# Placed and set off by remote: no fuse, no lingering effect, not thrown.
		keys.append_array(["magazine_size", "draw_seconds", "damage", "effect_radius"])
	else:
		keys.append_array(["magazine_size", "draw_seconds", "rounds_per_minute", "damage", "fuse_seconds", "effect_radius", "effect_seconds", "throw_speed_min", "throw_speed"])
	for key: String in keys:
		_editor(key, Tuning.FIELDS[key])
	for index: int in range(edited_profile.scope_fovs.size()):
		_editor("scope_%d" % index, ["Scope %d field of view (°)" % (index + 1), 1, 100, 0.5])
	controls.append_array([save_button, defaults_button])
	hud.page_controls[page_index] = controls

func _editor(key: String, definition: Array) -> void:
	var row := HBoxContainer.new()
	fields.add_child(row)
	var label := Label.new()
	row.add_child(label)
	label.text = definition[0]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 15)
	var edit := SpinBox.new()
	row.add_child(edit)
	edit.custom_minimum_size = Vector2(155, 28)
	edit.min_value = definition[1]
	edit.max_value = definition[2]
	edit.step = definition[3]
	edit.set_value_no_signal(_value(key))
	edit.value_changed.connect(_changed.bind(key))
	if key == "rounds_per_minute" and not edited_profile.recovered_stats.is_empty():
		edit.tooltip_text = "Semi uses this rate; recovered burst and auto fire at 1.25× this rate."
	elif key in ["magazine_size", "starting_reserve"]:
		edit.tooltip_text = "New capacity/supply is used on the next refill. Reducing capacity trims the loaded rounds."
	var focus := edit.get_line_edit()
	hud._bind_focus(focus)
	focus.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventJoypadButton and (event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")):
			edit.value += edit.step * (-1 if event.is_action_pressed("ui_left") else 1)
			focus.accept_event()
	)
	controls.append(focus)
	editors[key] = edit

func _value(key: String) -> float:
	return edited_profile.scope_fovs[int(key.trim_prefix("scope_"))] if key.begins_with("scope_") else float(edited_profile.get(key))

func _changed(value: float, key: String) -> void:
	if key.begins_with("scope_"):
		edited_profile.scope_fovs[int(key.trim_prefix("scope_"))] = value
	else:
		edited_profile.set(key, roundi(value) if edited_profile.get(key) is int else value)
	if key == "magazine_size":
		var weapon: PracticeWeapon = hud.session.player.weapon
		weapon.magazines[slot] = mini(weapon.magazines[slot], edited_profile.magazine_size)
	Tuning.capture(edited_profile)
	_sync_carried()
	feedback.text = "Applied · Save changes to keep this weapon's tuning."

func _sync_carried() -> void:
	# Two equipment slots may carry the same grenade type. They share its tuning.
	var weapon: PracticeWeapon = hud.session.player.weapon
	for index: int in range(weapon.profiles.size()):
		var profile := weapon.profiles[index]
		if profile != edited_profile and Tuning.key(profile) == Tuning.key(edited_profile):
			Tuning.apply(profile)
			weapon.magazines[index] = mini(weapon.magazines[index], profile.magazine_size)

func save_changes() -> void:
	for edit: SpinBox in editors.values():
		# Only the field being typed can have uncommitted text. Other SpinBoxes
		# may still be waiting for their deferred text refresh after a gun change.
		if edit.get_line_edit().has_focus():
			edit.apply()
	Tuning.capture(edited_profile)
	var error: Error = hud.session._save_settings()
	feedback.text = "Saved weapon tuning." if error == OK else "Applied for this QA session; saved settings are disabled." if error == ERR_UNAVAILABLE else "Could not save: %s" % error_string(error)

func reset_selected() -> void:
	Tuning.overrides.erase(Tuning.key(edited_profile))
	var defaults: WeaponProfile
	if not edited_profile.recovered_stats.is_empty():
		defaults = Guns.profile_for(edited_profile.recovered_model, int(edited_profile.recovered_stats.id))
	elif edited_profile.kind in ["frag", "smoke", "flash", "claymore"]:
		defaults = load("res://resources/weapons/%s.tres" % edited_profile.kind).duplicate()
	elif edited_profile.kind == "detonator":
		defaults = load("res://resources/weapons/claymore_remote.tres").duplicate()
	else:
		defaults = hud.session.player.weapon.soldier_class.weapons()[slot]
	for key: String in Tuning.FIELDS:
		edited_profile.set(key, defaults.get(key))
	edited_profile.scope_fovs = defaults.scope_fovs.duplicate()
	var weapon: PracticeWeapon = hud.session.player.weapon
	weapon.magazines[slot] = mini(weapon.magazines[slot], edited_profile.magazine_size)
	Tuning.capture(edited_profile)
	refresh()
	_sync_carried()
	feedback.text = "Weapon defaults restored · Save changes to keep them."
