extends SceneTree
const H := preload("res://tools/agent/harness.gd")
var failures: Array[String] = []
var session: Node
var hud: PrototypeHUD
var page: VBoxContainer

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

func choose(slot: int, key: String, value: Variant) -> void:
	for index: int in range(page.choices[slot].size()):
		if page.choices[slot][index].get(key) == value:
			page.pickers[slot].select(index)
			page.pickers[slot].item_selected.emit(index)
			return
	check(false, "Missing loadout option %s = %s" % [key, value])

func tap(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await frames(2)

func _run() -> void:
	session = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	await H.scenario(self, "lab_start", {"roster": false})
	hud = session.hud
	page = hud.loadout_menu
	var w: PracticeWeapon = session.player.weapon
	var skin: SoldierSkin = session.player.soldier.soldier_skin
	session.set_modal(true)
	var tab := hud.page_buttons.size() - 1
	hud.page_buttons[tab].pressed.emit()
	await frames()
	check(hud.page_buttons[tab].text == "Loadout" and page.is_visible_in_tree(), "Debug menu exposes the Loadout page")
	check(page.choices[0].size() == 32 and page.choices[1].size() == 10, "Primary and pistol selectors cover all 42 recovered firearm records without geometry duplicates")
	var valid := true
	for slot: int in range(2):
		for choice: Dictionary in page.choices[slot]:
			var entry: Dictionary = page.Guns.find(choice.model)
			valid = valid and entry.playable and entry.hold == ("long" if slot == 0 else "pistol")
	check(valid, "Primary and pistol slots exclude the wrong weapon type and unimplemented launchers")
	check(page.pickers[0].text == "M4A1" and page.pickers[1].text == "M9", "Opening the page reflects the carried guns")
	var position: Vector3 = session.player.position
	w.magazines[1] = 4
	choose(0, "record", 67)
	check(w.profiles[0].recovered_stats.id == 67 and w.profiles[0].recovered_model == "sig_commando" and w.magazines[0] == w.profiles[0].magazine_size, "Selecting 552SD installs the correct shared-mesh profile and refills the primary")
	check(w.magazines[1] == 4 and session.player.position == position and session.modal, "Selecting a gun preserves other-slot ammunition, position and the open menu")
	choose(1, "record", 14)
	check(w.profiles[1].recovered_model == "glock18" and w.profiles[1].fire_mode == 3 and skin.weapon_ids.pistol == "glock18", "Pistol selection updates the inactive held model and original automatic mode")
	var all_equipment := true
	for kind: String in ["frag", "smoke", "flash", "claymore"]:
		choose(3, "kind", kind)
		all_equipment = all_equipment and w.profiles[3].kind == kind and w.magazines[3] == w.profiles[3].magazine_size
	check(all_equipment, "Equipment selectors install and refill frag, smoke, flashbang and claymore")
	w.equip(2)
	w.throw_charge = 0.5
	w._commit_throw()
	choose(2, "kind", "smoke")
	check(w.throw_release < 0 and w.throw_charge < 0 and not session.player.soldier.throwing() and w.ammo == 1 and w.profile.kind == "smoke", "Replacing a grenade during its wind-up cancels the old throw without inflating the new supply")
	check(page.character_picker.item_count == 202, "Character selector contains every recovered model")
	var old_path: String = skin.model_path
	page.character_search.text = "scuba"
	check(page.character_picker.item_count > 0 and skin.model_path == old_path, "Searching characters filters without swapping automatically")
	var character_index: int = page.character_picker.get_item_id(0)
	var chosen_path: String = session.recovered_characters[character_index].path
	var ammo := w.ammo
	page.character_picker.select(0)
	page.character_picker.item_selected.emit(0)
	check(skin.model_path == chosen_path and skin.skeleton.get_bone_count() == 26 and session.player.position == position and w.ammo == ammo, "Character selection swaps the playable native rig without resetting position or ammo")
	page.character_search.text = "no such recovered character"
	check(page.character_picker.disabled and skin.model_path == chosen_path, "An empty character search disables selection and keeps the current model")
	page.character_search.clear()
	check(page.character_picker.get_selected_id() == character_index, "Clearing the search restores selection to the active character")
	session.set_modal(false)
	await frames(40)
	session.load_level(false)
	await frames(8)
	session.reset_player()
	check(w.profiles[0].recovered_stats.id == 67 and w.profiles[1].recovered_stats.id == 14 and w.profiles[2].kind == "smoke" and w.profiles[3].kind == "claymore" and skin.model_path == chosen_path, "Custom loadout and character survive level changes and respawn")
	session.set_modal(true)
	hud.show_page(tab)
	await frames()
	check(root.gui_get_focus_owner() == page.pickers[0], "Controller focus starts on the primary selector")
	await tap(JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner() == page.pickers[1], "D-pad navigation reaches the pistol selector")
	# Popup cancellation must consume Back before it closes the whole debug menu.
	page.pickers[1].show_popup()
	await frames()
	await tap(JOY_BUTTON_B)
	check(session.modal and not page.pickers[1].get_popup().visible, "Back closes an open weapon list while keeping the debug menu open")
	w.set_class("breacher")
	hud.refresh_settings()
	check(page.pickers[0].text == "870" and page.pickers[1].text == "DE .50" and skin.model_path == chosen_path, "Changing class refreshes selectors while retaining the chosen character")
	check(root.get_visible_rect().encloses(hud.menu_box.get_global_rect()), "Loadout and character controls fit inside the fixed game frame")
	print("\nRESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
