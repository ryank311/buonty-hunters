extends SceneTree
## Exercise actual takeoffs/equips and the visible native rig, not the hidden proxy.
const H = preload("res://tools/agent/harness.gd")
var failures: Array[String] = []
var session: Node
var player: PrototypePlayer
var skin: SoldierSkin

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok:
		failures.append(description)

func angle(a: Transform3D, b: Transform3D) -> float:
	return a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion())

func _run() -> void:
	session = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true})
	player = session.player
	skin = player.soldier.soldier_skin
	var driver: RefCounted = skin.driver
	var root_id: int = skin.motion.rig.names.find("skel_root")
	var thigh: int = skin.motion.rig.names.find("lthigh")
	for weapon: String in ["primary", "secondary"]:
		for walk: bool in [false, true]:
			await H.scenario(self, "lab_start", {"roster": false, "freeze": true, "weapon": weapon})
			var input := {"forward": 1.0, "hold": ["walk"] if walk else []}
			await H.step(self, 40, input)
			input["tap"] = ["jump"]
			await H.step(self, 12, input)
			var clip := "seal_p_runningjump_launch" if weapon == "secondary" else "seal_runningjump_launch"
			var reference: Array[Transform3D] = skin.motion.sample(clip, driver.time)
			var native_leg: bool = angle(driver.last_pose[thigh], reference[thigh]) < 0.002
			check(not player.is_on_floor() and driver.active_clip == clip and native_leg and absf(driver.last_pose[root_id].origin.y - driver.airborne_root_height) < 0.001, "%s %s jump plays the recovered launch on the native legs without extra root lift" % [weapon, "walk" if walk else "run"])
			var before: float = driver.time
			await H.step(self, 8)
			check(driver.active_clip == clip and driver.time > before, "Releasing movement in flight keeps the %s %s takeoff" % [weapon, "walk" if walk else "run"])
			await H.step(self, 70)
			check(player.is_on_floor() and driver.active_clip == ("seal_p_stand" if weapon == "secondary" else "seal_stand"), "%s %s jump lands and finishes its recovery" % [weapon, "walk" if walk else "run"])
	# A flight longer than the authored launch switches to the recovered falling take.
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true, "tuning": {"movement": {"gravity": 8.0, "jump_height": 4.0}}})
	await H.step(self, 40, {"forward": 1.0})
	await H.step(self, 85, {"forward": 1.0, "tap": ["jump"]})
	var air_end: float = skin.motion.get_animation("seal_runningjump_in_air").length - 1.0 / 30.0
	check(not player.is_on_floor() and driver.active_clip == "seal_runningjump_in_air" and absf(driver.time - air_end) < 0.001 and absf(driver.last_pose[root_id].origin.y - driver.airborne_root_height) < 0.001, "Long moving jumps advance into the airborne take and hold its last authored frame")
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true})
	await H.apply(self, {"pos": [0, 3, 26], "settle": 4})
	check(not player.soldier.jump_active and driver.active_clip == "seal_runningjump_in_air", "Falling without a jump does not invent a takeoff")
	for context: Array in [["stand", false], ["crouch", false], ["prone", false], ["stand", true], ["crouch", true], ["prone", true]]:
		await _swap_case(context[0], context[1])
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true, "ammo": 12})
	await H.step(self, 15, {"tap": ["reload"]})
	await H.step(self, 3, {"tap": ["equip_pistol"]})
	var reversal_phase: float = driver.swap.source_phase
	await H.step(self, 4, {"tap": ["equip_rifle"]})
	check(driver.swap.reverse and driver.swap.source_phase < reversal_phase and player.weapon.reload_remaining == 0.0 and player.weapon.magazines[0] == 12, "A rapid reverse swap turns back from the current pose and cancels reload without transferring ammunition")
	await H.step(self, 35)
	check(driver.swap.weight == 0.0 and player.soldier.rifle_mesh.visible and not player.soldier.pistol_mesh.visible, "Rapid swaps finish with only the selected firearm visible")
	# Equipment shares the recovered stow/draw takes, not grenade throwing poses.
	await H.step(self, 4, {"tap": ["equip_item_1"]})
	check(driver.swap.clip == "seal_rifle2handsfree" and not player.weapon.held_item.visible, "Equipping a grenade stows the rifle before showing the held item")
	await H.step(self, 30)
	check(player.weapon.held_item.visible and not player.soldier.rifle_mesh.visible and not player.soldier.pistol_mesh.visible, "Equipment draw ends with the item visible and firearms hidden")
	await H.step(self, 4, {"tap": ["equip_pistol"]})
	check(driver.swap.clip == "seal_pistol2handsfree" and driver.swap.reverse and not player.weapon.held_item.visible, "Returning from equipment reverses the pistol stow take")
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true})
	await H.step(self, 40, {"forward": 1.0})
	await H.step(self, 8, {"forward": 1.0, "tap": ["jump"]})
	await H.step(self, 4, {"forward": 1.0, "tap": ["equip_pistol"]})
	check(not player.is_on_floor() and driver.swap.clip == "seal_mv_rifle2pistol" and angle(driver.last_pose[thigh], driver.last_base_pose[thigh]) < 0.002, "An airborne weapon swap preserves the jump's legs")
	check(driver.active_clip == "seal_p_runningjump_launch", "An airborne weapon change updates the launch's weapon hold without restarting its clock")
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true})
	check(driver.swap.clip == "" and player.weapon.draw_from == null and player.soldier.rifle_mesh.visible and not player.soldier.pistol_mesh.visible, "Respawn clears the swap and restores the selected weapon")
	player.weapon.receive(0, player.weapon.profile.duplicate(), 17, 40)
	await H.step(self, 4)
	check(driver.swap.clip == "seal_swaprifle" and player.weapon.ammo == 17 and player.weapon.reserve == 40, "Taking a replacement primary plays the recovered rifle exchange without changing received ammo")
	await H.step(self, 35)
	await H.step(self, 3, {"tap": ["fire"]})
	var muzzle: Vector3 = player.soldier.rifle_mesh.to_global(player.soldier.soldier_skin.weapon_muzzles.long)
	check(player.weapon.shots_fired == 1 and muzzle.distance_to(player.soldier.muzzle.global_position) < 0.001, "Firing resumes after the draw with the muzzle attached to the visible weapon")
	print("RESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _swap_case(stance: String, moving: bool) -> void:
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true, "stance": stance})
	var input := {"forward": 1.0 if moving else 0.0}
	await H.step(self, 40, input)
	input["tap"] = ["equip_pistol"]
	await H.step(self, 4, input)
	var swap: RefCounted = skin.driver.swap
	var expected := "seal_" + ("prone_" if stance == "prone" else "mv_" if moving else "crouch_" if stance == "crouch" else "") + "rifle2pistol"
	var forearm: int = skin.motion.rig.names.find("rforearm")
	var thigh: int = skin.motion.rig.names.find("lthigh")
	var reference: Array[Transform3D] = skin.motion.sample(expected, swap.time)
	var legs_ok: bool = not moving or angle(skin.driver.last_pose[thigh], skin.driver.last_base_pose[thigh]) < 0.002
	check(swap.clip == expected and not swap.reverse and angle(skin.driver.last_pose[forearm], reference[forearm]) < 0.002 and legs_ok, "%s %s swap deforms the native arms and preserves moving legs" % [stance, "moving" if moving else "stationary"])
	var ammo := player.weapon.ammo
	player.weapon.shoot({})
	check(player.weapon.ammo == ammo and player.soldier.rifle_mesh.visible and not player.soldier.pistol_mesh.visible, "%s %s swap keeps the outgoing rifle visible and blocks firing during the draw" % [stance, "moving" if moving else "stationary"])
	var hand: Transform3D = skin.motion.native_worlds[skin.motion.rig.names.find("rhand")]
	var held: Transform3D = player.soldier.weapon_pivot.transform * player.soldier.rifle_mesh.transform
	var grip: Transform3D = hand * skin.motion.weapon_track("seal_" + stance, 0.0, "rifle") * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3.ZERO)
	check(held.origin.distance_to(grip.origin) < 0.001 and angle(held, grip) < 0.002, "%s %s swap keeps the visible rifle on its calibrated hand grip" % [stance, "moving" if moving else "stationary"])
	input.erase("tap")
	await H.step(self, 8, input)
	check(not player.soldier.rifle_mesh.visible and player.soldier.pistol_mesh.visible, "%s %s swap shows the pistol after stowing the rifle" % [stance, "moving" if moving else "stationary"])
	await H.step(self, 20, input)
	input["tap"] = ["equip_rifle"]
	await H.step(self, 4, input)
	check(swap.clip == expected and swap.reverse and player.soldier.pistol_mesh.visible and not player.soldier.rifle_mesh.visible, "%s %s return to rifle reverses the recovered transition" % [stance, "moving" if moving else "stationary"])
	input.erase("tap")
	await H.step(self, 30, input)
	check(swap.weight == 0.0 and player.soldier.rifle_mesh.visible and not player.soldier.pistol_mesh.visible, "%s %s swap returns to the active rifle pose" % [stance, "moving" if moving else "stationary"])
