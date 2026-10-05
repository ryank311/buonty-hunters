extends SceneTree
const Guns := preload("res://scripts/combat/recovered_weapons.gd")
const Accuracy := preload("res://scripts/combat/recovered_accuracy.gd")
const Audio := preload("res://scripts/combat/recovered_weapon_audio.gd")
const H := preload("res://tools/agent/harness.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok:
		failures.append(description)

func _run() -> void:
	var missing: Array[String] = []
	for entry: Dictionary in Guns.catalogue():
		if entry.playable:
			var p := Guns.profile_for(entry.id)
			if p.recovered_stats.is_empty() or p.recovered_stats.stances.size() != 3 or p.fire_mode == 0:
				missing.append(entry.id)
	check(missing.is_empty(), "All 65 playable mesh variants resolve stance tables and legal modes: %s" % [missing])
	check(Guns.profile_catalogue().records.size() == 86, "All 86 original records are retained with provenance and raw tokens")
	var audio_missing: Array[String] = []
	for name: String in Audio.catalogue().sounds:
		for index: int in range(3):
			var stream := Audio.stream_for(name, index)
			if stream == null or stream.get_length() <= 0.0:
				audio_missing.append(name)
	check(Audio.catalogue().records.size() == 42 and audio_missing.is_empty(), "All 42 gun records have loadable recovered audio, including every sequencer variant: %s" % [audio_missing])
	var m4 := Guns.profile_for("m4acarbine")
	check(m4.display_name == "M4A1" and Audio.event_name(m4) == ".M4A1" and Audio.event_name(m4, "reload") == ".M4A1_RLD" and m4.sound_pitch == 1.0, "M4A1 uses its real name and original firing/reload events without prototype pitch shifting")
	check(Audio.event_name(m4, "fire", 9) == ".M4A1_M" and Audio.event_name(m4, "fire", 50) == ".M4A1_F" and Audio.event_name(Guns.profile_for("sig_commando", 67)) == ".SIG_552_SIL" and Audio.event_name(Guns.profile_for("sig_commando", 67), "fire", 9) == "", "Distance reports and suppressed shared-mesh variants follow the original sound references")
	check(m4.recovered_stats.modes == [1, 2, 3] and m4.fire_mode == 2, "M4 enables semi/burst/auto and defaults to burst")
	check(Guns.profile_for("glock18").recovered_stats.modes == [1, 3] and Guns.profile_for("m60e").recovered_stats.modes == [3], "Explicit mode flags retain Glock auto despite MaxFireMode 1; M60 is auto only")
	check(Guns.profile_for("m16a2").recovered_stats.modes == [1, 2], "M16 has semi and burst, without automatic fire")
	check(Guns.profile_for("sp10_gyuraz").recovered_stats.id == 13 and Guns.profile_for("sig_commando", 67).recovered_stats.name == "552SD", "Gyurza mesh override and shared-model record selection are explicit")
	var a := Accuracy.new()
	a.bind(m4, 0)
	check(a.size == 1 and a.table().TargetMax == 26, "Standing M4 starts at the source 1px minimum, capped at 26px")
	a.fired(1, false, 0)
	check(is_equal_approx(a.size, 8) and is_equal_approx(a.knock.y, -4.8), "First M4 round adds 7px spread and 12 × 0.4px knock")
	a.fired(2, false, 0)
	check(is_equal_approx(a.knock.y, -16.8), "Second round applies the full 12px knock")
	a.tick(0.1, Vector3.ZERO, Vector2.ZERO, false, false, 0)
	check(is_equal_approx(a.knock.y, -9.8) and is_equal_approx(a.size, 10), "Recovery is 70px/s knock and 50px/s constriction")
	a.size = 1
	a.fired(4, false, 0)
	check(is_equal_approx(a.size, 8.07), "Burst growth uses weapon-wide Acc fields and the source count-plus-one scalar")
	for i: int in range(120):
		a.tick(1.0 / 60.0, Vector3(0, 0, 3), Vector2.ZERO, false, false, 0)
	check(is_equal_approx(a.size, 900.0 / 65.0), "A 3m/s walk settles at 30² / 65 native pixels")
	for i: int in range(120):
		a.tick(1.0 / 60.0, Vector3.ZERO, Vector2(0.5, 0), false, false, 0)
	check(a.size == 26, "Turning alone can reach the source spread maximum")
	a.bind(m4, 1)
	check(a.table().ReticuleKnock == 9 and a.table().TargetDilateUponMovementMult == 13, "Crouching uses its own knock and movement multiplier")
	a.bind(m4, 2)
	check(a.table().ReticuleKnock == 8 and a.table().TargetMax == 24 and a.table().KnockEntryStrength == 0.4, "Prone table inherits omitted entry strength and uses its own cap")
	a.knock = Vector2.ZERO
	a.size = 10
	var corner := a.direction(Vector3.FORWARD, false, 1.0, Vector2.ONE)
	check(is_equal_approx(corner.x / -corner.z, 10 * a.TANGENT.y * 0.707) and is_equal_approx(corner.x, corner.y), "Source square sampling reaches both-axis corners, without a second shotgun cone")
	var inner := a.direction(Vector3.FORWARD, false, 1.0, Vector2(0.5, 0))
	check(is_equal_approx(inner.x / -inner.z, corner.x / -corner.z * 0.25), "Uniform half-axis input becomes quarter-radius via u × abs(u)")
	a.sway = Vector2(10, 12)
	var scoped := a.direction(Vector3.FORWARD, true, 3.0, Vector2.ONE)
	check(scoped.is_equal_approx(a.direction(Vector3.FORWARD, true, 3.0, -Vector2.ONE)) and is_equal_approx(scoped.x / -scoped.z, -10 * a.TANGENT.x / 3.0), "Scoped shots have no random cone and divide sway by magnification")
	a.fired(1, true, 0)
	a.tick(0.1, Vector3.ZERO, Vector2.ZERO, false, true, 0)
	check(is_equal_approx(a.scope_kick, 0.05), "Scoped first-round kick rises at the recovered 0.5 rad/s")
	var session: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true})
	var w: PracticeWeapon = session.player.weapon
	var camera_before: Basis = session.player.camera_rig.camera.global_basis
	await H.step(self, 60, {"hold": ["fire"]})
	check(w.shots_fired == 3 and w.mode_caption() == "BURST", "Holding default M4 trigger fires exactly three rounds")
	check(w.weapon_audio.last_fire == ".M4A1" and w.weapon_audio.shots_played == 3, "Successful shots dispatch the equipped gun's recovered report once per round")
	check(camera_before.is_equal_approx(session.player.camera_rig.camera.global_basis), "Unscoped source recoil leaves the actual camera orientation unchanged")
	await H.step(self, 1)
	await H.step(self, 1, {"hold": ["fire"]})
	check(w.shots_fired == 4 and w.accuracy.knock.y < 0, "A new pull fires immediately and raises the native reticle")
	await H.step(self, 20)
	check(w.shots_fired == 4, "Releasing early cancels the remaining burst rounds")
	await H.step(self, 2, {"tap": ["fire_mode"]})
	check(w.fire_mode() == 3 and is_equal_approx(w.fire_interval(), 0.096), "B / L3 action selects automatic, using FireWait × 0.8")
	await H.step(self, 60, {"hold": ["fire"]})
	check(w.shots_fired >= 14 and w.shots_fired <= 15, "Native 625rpm automatic cadence is maintained across physics ticks")
	await H.step(self, 1)
	w.equip(1)
	await H.step(self, 30)
	w.equip(0)
	await H.step(self, 30)
	check(w.fire_mode() == 3, "Selected mode survives a weapon swap")
	w.cycle_fire_mode()
	check(w.fire_mode() == 1 and is_equal_approx(w.fire_interval(), 0.12), "Mode cycle returns to semi with the full source FireWait")
	await H.step(self, 1)
	var before_semi := w.shots_fired
	await H.step(self, 30, {"hold": ["fire"]})
	var count := w.shots_fired
	check(count == before_semi + 1, "Semi fires one round while held")
	w.cycle_fire_mode()
	await H.step(self, 30, {"hold": ["fire"]})
	check(w.shots_fired == count, "Changing mode during a held trigger cannot manufacture a fresh pull")
	await H.step(self, 1)
	await H.step(self, 1, {"hold": ["fire"]})
	var before_reload := w.shots_fired
	await H.step(self, 180, {"hold": ["fire"], "tap": ["reload"]})
	check(w.shots_fired == before_reload and w.ammo == w.profile.magazine_size, "Reload interrupts a burst and does not resume it while the trigger stays held")
	check(w.weapon_audio.reloads_played == 1 and w.weapon_audio.last_reload == ".M4A1_RLD", "Reload starts the recovered event once, independently of the held trigger")
	w.ammo -= 1
	await H.step(self, 1, {"tap": ["reload"]})
	w.equip(1)
	check(w.weapon_audio.last_reload == "" and not w.weapon_audio.reload_output.playing and w.reload_remaining == 0.0, "Swapping cancels both the reload action and its audio")
	await H.scenario(self, "lab_start", {"class": "marksman", "roster": false, "freeze": true, "hold": ["aim"]})
	check(w.scoped and not w.cycle_fire_mode(), "Scope view refuses fire-mode switching")
	print("\nRESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
