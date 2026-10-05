extends SceneTree
const Guns := preload("res://scripts/combat/recovered_weapons.gd")
const Tuning := preload("res://scripts/combat/weapon_tuning.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok:
		failures.append(description)

func frames(count: int = 4) -> void:
	for i: int in range(count):
		await physics_frame
		await process_frame

func _run() -> void:
	Tuning.overrides.clear()
	var session: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	await frames()
	session.set_modal(true)
	var hud: PrototypeHUD = session.hud
	var menu: VBoxContainer = hud.weapon_tuning_menu
	var w: PracticeWeapon = session.player.weapon
	hud.show_page(3)
	await frames()
	check(hud.pages.size() == 6 and hud.page_buttons[3].text == "Debug tuning" and not hud.page_buttons.any(func(b: Button) -> bool: return b.text in ["Rifle recoil", "Pistol recoil", "Accuracy"]), "One Debug tuning tab replaces all three old weapon pages")
	check(menu.weapon_picker.item_count == w.profiles.size() and menu.weapon_picker.text.contains("M4A1") and menu.editors.has("recovered_spread_scale") and not menu.editors.has("vertical_kick"), "Tuning lists carried items and only the recoil/spread controls used by the recovered gun")
	menu.editors.recovered_recoil_scale.value = 1.4
	menu.editors.recovered_spread_scale.value = 0.6
	menu.editors.rounds_per_minute.value = 300
	menu.editors.damage.value = 47
	check(is_equal_approx(w.profile.recovered_recoil_scale, 1.4) and is_equal_approx(w.profile.recovered_spread_scale, 0.6) and is_equal_approx(w.fire_interval(), 0.16) and w.profile.damage == 47, "Recoil, spread, damage and rate edits affect the actual equipped profile and native cadence")
	check(Guns.find("m4acarbine").id == "m4acarbine" and is_equal_approx(float(w.profile.recovered_stats.fire_wait), 0.12), "Tuning leaves recovered source records unchanged")
	menu.weapon_picker.select(1)
	menu.weapon_picker.item_selected.emit(1)
	menu.editors.damage.value = 41
	check(menu.weapon_picker.text.contains("M9") and w.profiles[1].damage == 41 and w.profiles[0].damage == 47, "Pistol controls edit the pistol independently of the primary")
	menu.weapon_picker.select(2)
	menu.weapon_picker.item_selected.emit(2)
	check(menu.editors.has("throw_speed") and menu.editors.has("fuse_seconds") and not menu.editors.has("recovered_recoil_scale"), "Grenades expose throw, fuse and effect tuning instead of firearm recoil")
	menu.editors.fuse_seconds.value = 2.75
	menu.editors.effect_radius.value = 9.5
	menu.save_button.pressed.emit()
	check(menu.feedback.text.contains("QA session"), "Save reports that automated QA cannot overwrite the user's real settings")
	var config := ConfigFile.new()
	var encoded: String = session.settings_config().encode_to_text()
	check(config.parse(encoded) == OK, "Saved debug settings round-trip through ConfigFile serialization")
	var selected_ak := Guns.profile_for("ak47")
	w.receive(0, selected_ak, 30, 90)
	check(w.profiles[0].damage == 34 and is_equal_approx(w.profiles[0].recovered_recoil_scale, 1.0), "Choosing a different primary does not inherit the previous gun's tuning")
	session.reset_tuning()
	session.apply_settings_config(config)
	check(w.profiles[0].damage == 47 and w.profiles[1].damage == 41 and is_equal_approx(w.profiles[2].fuse_seconds, 2.75) and is_equal_approx(w.profiles[2].effect_radius, 9.5), "Loading saved settings restores gun-specific and equipment tuning")
	check(Guns.profile_for("m4acarbine").damage == 47 and Guns.profile_for("ak47").damage == 34, "Re-selecting a saved gun restores its overrides without changing other guns")
	var other := Guns.profile_for("sig_commando", 67)
	w.receive(0, other, 30, 90)
	menu.slot = 0
	hud.refresh_settings()
	check(menu.edited_profile == other and menu.weapon_picker.text.contains("552SD") and menu.editors.damage.value == other.damage, "Replacing a carried gun refreshes the editor to the exact selected source variant")
	# Saved M4 values must not leak into an AK occupying that inventory slot at load.
	session.apply_settings_config(config)
	check(other.damage == 34, "Loading per-gun settings never applies old slot-based values to another gun")
	var smoke: WeaponProfile = load("res://resources/weapons/smoke.tres").duplicate()
	Tuning.apply(smoke)
	w.receive(2, smoke, 1, 0)
	w.receive(3, smoke.duplicate(), 1, 0)
	menu.slot = 2
	menu.refresh()
	menu.editors.effect_seconds.value = 23
	check(w.profiles[2].effect_seconds == 23 and w.profiles[3].effect_seconds == 23, "Duplicate equipment slots share their type's tuning so saving cannot overwrite one with stale values")
	menu.reset_selected()
	check(w.profiles[2].effect_seconds == 18 and w.profiles[3].effect_seconds == 18 and Guns.profile_for("m4acarbine").damage == 47, "Reset this weapon restores only that type and keeps other saved guns")
	session.set_modal(false)
	w.equip(1)
	await frames(30)
	session.set_modal(true)
	hud.show_page(3)
	check(menu.slot == 1 and menu.weapon_picker.text.contains("in hand"), "Opening debug tuning starts with the weapon currently in hand")
	await frames()
	check(root.get_visible_rect().encloses(hud.menu_box.get_global_rect()), "Scrollable tuning and Save controls fit the fixed-resolution menu")
	print("\nRESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
