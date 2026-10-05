extends SceneTree
## Every gun fires its own recovered muzzle flash (resources/recovered/muzzle_flashes.json).
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
	var player: PrototypePlayer = session.player
	# The original FireAnimName of each gun the game carries, through its zAnim.
	var expected := {"m4acarbine": "flash_fire_hider", "baretta_m9": "flash_fire_small", "glock18": "flash_fire_med",
		"mp5": "flash_fire_med", "desert_eagle": "flash_fire_hider", "remington870": "shotgun_fire",
		"remington700": "flash_fire_big", "ak47": "flash_fire_break_big", "m4acarbine_sd": "", "mp5sd": ""}
	var wrong: Array[String] = []
	for model: String in expected:
		if RecoveredMuzzleFlash.flash_for(model) != expected[model]:
			wrong.append("%s -> %s" % [model, RecoveredMuzzleFlash.flash_for(model)])
	check(wrong.is_empty(), "Each gun maps to its original flash; suppressed guns have none %s" % [wrong])
	for path: String in ["res://resources/weapons/rifle.tres", "res://resources/weapons/pistol.tres", "res://resources/weapons/smg.tres", "res://resources/weapons/shotgun.tres", "res://resources/weapons/sniper.tres", "res://resources/weapons/heavy_pistol.tres", "res://resources/weapons/auto_pistol.tres"]:
		var profile: WeaponProfile = load(path)
		check(RecoveredMuzzleFlash.flash_for(profile.recovered_model) != "", "%s (%s) has a recovered flash" % [path.get_file(), profile.recovered_model])

	await H.scenario(self, "lab_range", {"roster": false, "freeze": true})
	var flash: RecoveredMuzzleFlash = player.soldier.flash
	await H.step(self, 1, {"tap": ["fire"]})
	var spec: Dictionary = flash.spec
	check(flash.visible and flash.shown != null and String(flash.shown.name) == "muzzle_flash_hider" and flash.light.visible, "A rifle shot shows the M4's flash-hider flame and muzzle light")
	check(spec.sizes.has(flash.size) and spec.rolls.any(func(r: float) -> bool: return is_equal_approx(r, flash.shown.rotation.z)), "The flame takes one of its original sizes and rolls")
	var forward: Vector3 = -player.soldier.muzzle.global_basis.z
	var tip: Vector3 = flash.shown.global_transform * (Vector3.FORWARD * 0.5)
	check((tip - flash.shown.global_position).normalized().dot(forward) > 0.95, "The flame points out of the barrel")
	await H.step(self, 8)
	check(not flash.visible and not flash.light.visible, "The flash and its light are gone after the original 0.07 s")
	await H.apply(self, {"weapon": "secondary"})
	await H.step(self, 30)
	await H.step(self, 1, {"tap": ["fire"]})
	check(flash.visible and String(flash.shown.name) == "muzzle_flash_m4" and flash.spec.sizes.max() <= 0.4, "A pistol shot shows the M9's small flame")
	print("RESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
