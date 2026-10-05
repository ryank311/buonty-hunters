extends SceneTree
## Exercise the recovered reticle through the actual loadout, aim and throw paths.
const H := preload("res://tools/agent/harness.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok:
		failures.append(description)

func _run() -> void:
	var session: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true})
	var player: PrototypePlayer = session.player
	var weapon: PracticeWeapon = player.weapon
	var reticle: SpreadReticle = session.hud.crosshair
	reticle.update_weapon(weapon, 1.0, false)
	check(reticle.family == "rifle" and reticle.ink == reticle.REST, "Primary starts with the recovered rifle reticle and neutral yellow arms")
	var disc_size: Vector2 = reticle.center_texture.get_size() * reticle.center_ring.scale * session.hud.root.scale
	check(disc_size.is_equal_approx(Vector2(64, 64 * 480.0 / 448.0)), "Original 64px rifle disc maps from 640x448 into our fixed 640x480 frame")
	var resting: float = reticle.mark_distance
	weapon.cycle_fire_mode()
	await H.step(self, 1)
	await H.step(self, 40, {"forward": 1.0, "hold": ["fire"]})
	reticle.update_weapon(weapon, 1.0 / 60.0, false)
	check(weapon.shots_fired > 0 and reticle.mark_distance > resting + 5.0 and reticle.center_ring.position.y < reticle.size.y * 0.5, "Actual running fire opens the arms and lifts the whole native reticle")
	await H.step(self, 120)
	reticle.update_weapon(weapon, 1.0, false)
	check(reticle.mark_distance < resting + 0.05 and reticle.center_ring.position.is_equal_approx(reticle.size * 0.5), "Stopping and recoil recovery return the native reticle to rest")
	await H.apply(self, {"weapon": "pistol"})
	reticle.update_weapon(weapon, 1.0, false)
	check(reticle.family == "sidearm" and reticle.center_texture.get_width() == 32 and reticle.arm_texture.get_width() == 16, "Pistol selection uses its smaller recovered disc and arms")
	await H.scenario(self, "lab_start", {"class": "breacher", "roster": false, "freeze": true})
	reticle.update_weapon(weapon, 1.0, false)
	var pellet_gap: float = weapon.accuracy.size * 0.5
	check(reticle.family == "shotgun" and is_equal_approx(reticle.target_spread, pellet_gap), "Shotgun selects quarter-circle arms with the native half-size displacement")
	await H.apply(self, {"weapon": "frag"})
	await H.step(self, 40, {"hold": ["fire"]})
	reticle.update_weapon(weapon, 0.1, false)
	check(reticle.family == "grenade" and not reticle.spread_marks[0].visible, "Equipment selects the grenade aiming cross without firearm arms")
	await H.scenario(self, "lab_start", {"class": "marksman", "hold": ["aim"], "roster": false, "freeze": true})
	reticle.update_weapon(weapon, 0.1, false)
	check(weapon.scoped and weapon.director.overlay.scope.visible and not reticle.visible, "Scope view shows its own mask and hides the third-person crosshair")
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true, "actors": [{"team": 1, "pos": [0, 0, 14], "name": "RETICLE_TARGET"}], "look_at": [0, 1.2, 14]})
	reticle.update_weapon(weapon, 0.1, false)
	var hit: Dictionary = weapon.query_aim()
	var target: Node3D = hit.get("collider")
	check(is_instance_valid(target) and reticle.ink == reticle.ENEMY, "An unobstructed living enemy under the real aim ray turns the arms red")
	if is_instance_valid(target):
		target.set_meta(&"team", 0)
		reticle.update_weapon(weapon, 0.1, false)
		check(reticle.ink == reticle.FRIEND, "A teammate under the same aim ray turns the arms green")
		target.set_meta(&"alive", false)
		reticle.update_weapon(weapon, 0.1, false)
		check(reticle.ink == reticle.REST, "An eliminated actor does not retain identification tint")
	# Block the safety ray at the muzzle, below the camera's clear line of sight.
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * 0.12
	collider.shape = box
	wall.add_child(collider)
	session.level.add_child(wall)
	wall.global_position = player.soldier.muzzle.global_position
	await physics_frame
	reticle.update_weapon(weapon, 0.1, false)
	check(weapon.blocked and reticle.pip_alpha > 0.0 and reticle.pip_offset.length() > 32.0, "Muzzle obstruction displays the recovered accuracy pip at the projected obstruction")
	check(absf(reticle.pip_offset.x) <= 200 and absf(reticle.pip_offset.y) <= 200, "Obstruction displacement stays inside the original 200px limits")
	wall.queue_free()
	await physics_frame
	reticle.update_weapon(weapon, 0.2, false)
	check(not weapon.blocked and is_zero_approx(reticle.pip_alpha), "Clearing the muzzle fades out the obstruction pip")
	reticle.update_weapon(weapon, 0.1, true)
	check(not reticle.visible, "Opening a modal hides all recovered reticle elements")
	print("\nRESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
