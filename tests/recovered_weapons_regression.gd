extends SceneTree
## Every installed gun must survive Blender export with its native size and muzzle.
const Guns = preload("res://scripts/combat/recovered_weapons.gd")
const H = preload("res://tools/agent/harness.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok:
		failures.append(message)

func frames(count: int = 3) -> void:
	for i: int in range(count):
		await physics_frame
		await process_frame

func _run() -> void:
	var names := {}
	var occurrences := 0
	var broken: Array[String] = []
	for entry: Dictionary in Guns.catalogue():
		names[entry.source_name] = true
		occurrences += entry.occurrences.size()
		var packed := load(entry.path) as PackedScene
		if packed == null:
			broken.append(entry.id + ": missing scene")
			continue
		var model := packed.instantiate() as Node3D
		root.add_child(model)
		var low := Vector3.INF
		var high := -Vector3.INF
		var triangles := 0
		var textured := true
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			for surface: int in range(mesh.mesh.get_surface_count()):
				var material := mesh.get_active_material(surface) as BaseMaterial3D
				textured = textured and material != null and material.albedo_texture != null
				var arrays: Array = mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
				for vertex: Vector3 in vertices:
					var point := model.to_local(mesh.to_global(vertex))
					low = low.min(point)
					high = high.max(point)
		var marker := model.find_child("Muzzle", true, false) as Node3D
		var valid: bool = textured and triangles == entry.triangles and low.distance_to(Guns.vector(entry.bounds_min)) < 0.001 and high.distance_to(Guns.vector(entry.bounds_max)) < 0.001
		valid = valid and marker != null and model.to_local(marker.global_position).distance_to(Guns.vector(entry.muzzle)) < 0.0001
		if not valid:
			broken.append(entry.id)
		model.free()
	check(names.size() == 43 and occurrences == 1462, "All 43 gun designs retain all 1,462 archive occurrences")
	check(broken.is_empty(), "Every gun export retains textures, triangles, native bounds and firepoint: %s" % [broken])
	check(Guns.profile_for("at4") == null and Guns.profile_for("unknown") == null, "Unimplemented launchers and unknown IDs cannot silently become rifles")
	var session: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	await frames(12)
	await H.scenario(self, "recovery_start")
	var lab: Node = session.level
	lab.browser.set_open(true)
	lab.browser.set_mode(1)
	check(lab.browser.gun_box.visible and not lab.browser.character_box.visible and lab.browser.gun_picker.item_count == Guns.catalogue().size(), "Gun browser lists the whole collection separately from animations")
	lab.browser.gun_search.text = "glock"
	lab.browser._filter_guns()
	check(lab.browser.gun_picker.item_count == 1 and lab.guns[lab.weapon_index].id == "glock18", "Gun search loads the matching preview")
	lab.equip_gun()
	check(session.player.soldier.rifle_mesh.visible and not session.player.soldier.pistol_mesh.visible, "Starting a swap keeps the posed source visible until the native draw tick")
	lab.browser.set_open(false)
	await frames(35)
	var weapon: PracticeWeapon = session.player.weapon
	var skin: SoldierSkin = session.player.soldier.soldier_skin
	check(weapon.profile.recovered_model == "glock18" and weapon.active_slot == 1 and skin.weapon_ids.pistol == "glock18", "Equip installs the chosen recovered pistol in the sidearm slot")
	var valid_holds := true
	for id: String in ["m4acarbine", "remington700", "remington870", "mp5", "baretta_m9", "desert_eagle"]:
		var profile := Guns.profile_for(id)
		var slot := 1 if profile.hold == "pistol" else 0
		weapon.receive(slot, profile, 3, 7)
		weapon.equip(slot)
		for stance: String in ["stand", "crouch", "prone"]:
			await H.apply(self, {"stance": stance})
			await frames(30)
			var proxy: SoldierProxy = session.player.soldier
			var carrier: Node3D = proxy.pistol_mesh if slot == 1 else proxy.rifle_mesh
			valid_holds = valid_holds and skin.weapon_ids[profile.hold] == id and carrier.visible and carrier.scale.is_equal_approx(Vector3.ONE)
			valid_holds = valid_holds and proxy.muzzle.global_position.distance_to(carrier.to_global(Guns.vector(Guns.find(id).muzzle))) < 0.001
		valid_holds = valid_holds and weapon.ammo == 3 and weapon.reserve == 7
	check(valid_holds, "Rifle, sniper, shotgun, SMG and pistols keep native scale/muzzle in every stance without changing ammo")
	lab.browser.gun_search.text = "no-such-gun"
	lab.browser._filter_guns()
	check(lab.browser.gun_picker.disabled and lab.browser.equip_button.disabled, "An empty gun search disables selection and equip")
	await H.apply(self, {"level": "lab"})
	check(skin.weapon_ids.pistol == "desert_eagle", "Equipped model survives changing levels")
	print("\nRESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await frames()
	quit(0 if failures.is_empty() else 1)
