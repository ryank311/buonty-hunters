class_name PracticeWeapon
extends Node3D

signal target_hit
const Combat := preload("res://scripts/combat/combat.gd")
const Loadouts := preload("res://scripts/combat/loadouts.gd")
const BULLET := preload("res://scripts/combat/bullet.gd")
const THROWABLE := preload("res://scripts/combat/throwable.gd")
const CLAYMORE := preload("res://scripts/combat/claymore.gd")
## Given while a claymore of the soldier's is down; it sets them all off.
const REMOTE := preload("res://resources/weapons/claymore_remote.tres")
## The original's limits: four charges down per soldier, the remote reaches 500 units,
## and a claymore is not set down while moving faster than 3.2 units/s.
const MAX_CLAYMORES := 4
const REMOTE_RANGE := 50.0
const PLACE_STILL_SPEED := 0.32
const DETONATOR_CLICK := preload("res://audio/claymore/detonator_click.wav")
const PLACE_SOUND := preload("res://audio/claymore/place_charge.wav")
const DIRECTOR := preload("res://scripts/combat/combat_director.gd")
const THROW_ARC := preload("res://scripts/combat/throw_arc.gd")
const Guns := preload("res://scripts/combat/recovered_weapons.gd")
const Accuracy := preload("res://scripts/combat/recovered_accuracy.gd")
## Holding the throw this long reaches full strength.
const THROW_CHARGE_SECONDS := 1.1
## Strength at which a throw stops being a lob, and at which it becomes a full throw.
const LOB_BELOW := 0.3
const FULL_FROM := 0.9
## An analog trigger sets the strength by how far it is squeezed. Easing off counts once
## the trigger has rested this long; until then it is taken as the start of letting go.
const SQUEEZE_SETTLE_SECONDS := 0.12
## A trigger moving less than this in a tick is being held, not moved.
const SQUEEZE_STILL := 0.015
const ITEM_COLOURS := {"frag": Color("3f4a33"), "smoke": Color("8a8d86"), "flash": Color("c9cfd4"), "claymore": Color("4d5a3a")}
var player: PrototypePlayer
# The class decides what is carried: slot 0 the primary, slot 1 the pistol, then equipment.
var soldier_class: Resource = Loadouts.CLASSES[0]
var profiles: Array[WeaponProfile] = []
var active_slot: int = 0
var magazines: Array[int] = [30, 12]
var reserves: Array[int] = [90, 36]
var profile: WeaponProfile:
	get: return profiles[active_slot]
var ammo: int:
	get: return magazines[active_slot]
	set(value): magazines[active_slot] = value
var reserve: int:
	get: return reserves[active_slot]
	set(value): reserves[active_slot] = value
var cooldown: float = 0.0
var reload_remaining: float = 0.0
var draw_remaining: float = 0.0
## The native swap layer follows this draw, including rapid re-equips and pickups.
var draw_from: WeaponProfile
var draw_serial := 0
var hit_flash: float = 0.0
var blocked: bool = false
var shots_fired: int = 0
var hits: int = 0
var last_damage: float = 0.0
var damage_dealt: float = 0.0
var muzzle_timer: float = 0.0
var fire_was_down: bool = false
var require_trigger_release: bool = false
var empty_notified: bool = false
var recoil := RecoilState.new()
var accuracy := Accuracy.new()
var rounds_in_pull: int = 0
var last_look := Vector2.ZERO
var scope_dropped: bool = false
var rng := RandomNumberGenerator.new()
var aim_point := Vector3.ZERO
var hit_point := Vector3.ZERO
var weapon_audio := preload("res://scripts/combat/recovered_weapon_audio.gd").new()
var impact_decals := preload("res://scripts/combat/impact_decals.gd").new()
# Scoped weapons look through their own camera at the eye while focus aim is held.
var scoped: bool = false
var zoom_index: int = 0
var scope_camera := Camera3D.new()
var held_item := MeshInstance3D.new()
var item_mesh := SphereMesh.new()
var smoke_model: Node3D
var claymore_model: Node3D
var detonator_model: Node3D
## Seconds until the kneeling soldier's claymore is on the ground, or -1.
var place_release: float = -1.0
var gear_sound := AudioStreamPlayer3D.new()
var item_paint := StandardMaterial3D.new()
var director: Node
var pad_cycle: bool = false
## Grenade throwing: the strength built while the button is held (-1 when not holding),
## and once let go, the throw in motion and the seconds until the hand releases it.
var throw_charge: float = -1.0
## Whether fire last came from an analog trigger, and that trigger's travel: where it is,
## and how long since it last moved toward a harder squeeze.
var fire_analog: bool = false
var squeeze: float = 0.0
var squeeze_rested: float = 0.0
var throw_style: int = 0
var throw_strength: float = 0.0
var throw_release: float = -1.0
var throw_arc: MeshInstance3D

func initialize(owner_player: PrototypePlayer) -> void:
	player = owner_player
	reset_profiles()
	weapon_audio.initialize(self)
	add_child(impact_decals)
	scope_camera.top_level = true
	scope_camera.near = 0.05
	add_child(scope_camera)
	item_mesh.radius = 0.07
	item_mesh.height = 0.15
	item_mesh.radial_segments = 8
	item_mesh.rings = 4
	held_item.mesh = item_mesh
	held_item.material_override = item_paint
	held_item.position = Vector3(0.0, 0.0, -0.06)
	player.soldier.weapon_pivot.add_child(held_item)
	smoke_model = preload("res://art/models/recovered_smoke_grenade.glb").instantiate()
	held_item.add_child(smoke_model)
	smoke_model.hide()
	claymore_model = preload("res://art/models/recovered_claymore.glb").instantiate()
	# Carried by its top edge, face out.
	claymore_model.position = Vector3(0.0, -0.3, 0.0)
	held_item.add_child(claymore_model)
	claymore_model.hide()
	detonator_model = preload("res://art/models/recovered_detonator.glb").instantiate()
	# Turned so the clacker's body sits under the fingers of the native hand.
	detonator_model.rotation_degrees.y = 90.0
	held_item.add_child(detonator_model)
	detonator_model.hide()
	gear_sound.bus = &"World"
	gear_sound.unit_size = 4.0
	gear_sound.max_distance = 30.0
	add_child(gear_sound)
	throw_arc = THROW_ARC.new()
	add_child(throw_arc)
	director = DIRECTOR.new()
	add_child(director)
	director.initialize(self)
	rng.randomize()
	reset()

func reset_profiles() -> void:
	profiles.clear()
	for defaults: WeaponProfile in soldier_class.weapons():
		var loaded := defaults.duplicate() as WeaponProfile
		Guns.apply_stats(loaded)
		preload("res://scripts/combat/weapon_tuning.gd").apply(loaded)
		profiles.append(loaded)
	magazines.resize(profiles.size())
	reserves.resize(profiles.size())

## Takes a class by index, id ("marksman"), or resource. The loadout changes at once;
## callers that want a clean start respawn the player afterwards.
func set_class(value: Variant) -> void:
	var chosen: Resource = value if value is Resource else (Loadouts.by_id(value) if value is String else Loadouts.CLASSES[clampi(int(value), 0, Loadouts.CLASSES.size() - 1)])
	if chosen == null:
		return
	soldier_class = chosen
	reset_profiles()
	reset()

func reset() -> void:
	weapon_audio.reset()
	impact_decals.clear()
	if is_inside_tree():
		Combat.clear_spawned(get_tree())
	active_slot = 0
	_cancel_place()
	_remove_remote()
	for slot: int in range(profiles.size()):
		magazines[slot] = profiles[slot].magazine_size
		reserves[slot] = profiles[slot].starting_reserve
	cooldown = 0.0
	reload_remaining = 0.0
	draw_remaining = 0.0
	draw_from = null
	draw_serial += 1
	hit_flash = 0.0
	shots_fired = 0
	hits = 0
	last_damage = 0.0
	damage_dealt = 0.0
	muzzle_timer = 0.0
	blocked = false
	fire_was_down = false
	require_trigger_release = false
	empty_notified = false
	pad_cycle = false
	_cancel_throw()
	recoil.reset()
	_reset_accuracy()
	if player:
		set_scope(false)
		_show_weapon()
		player.soldier.flash.visible = false
		player.camera_rig.set_recoil(Vector2.ZERO)
		if director:
			director.on_reset()

func equip(slot: int) -> bool:
	# On a controller the pistol button steps on through the equipment once the pistol is out.
	if slot == 1 and pad_cycle and active_slot >= 1:
		slot = active_slot + 1 if active_slot + 1 < profiles.size() else 1
	pad_cycle = false
	if slot == active_slot or slot < 0 or slot >= profiles.size():
		return false
	# The loaded rounds stay in each gun. An interrupted reload transfers nothing.
	reload_remaining = 0.0
	weapon_audio.cancel_reload()
	set_scope(false)
	_cancel_throw()
	_cancel_place()
	draw_from = profile
	draw_serial += 1
	active_slot = slot
	recoil.reset()
	_reset_accuracy()
	draw_remaining = profile.draw_seconds
	cooldown = maxf(cooldown, draw_remaining)
	muzzle_timer = 0.0
	player.soldier.flash.visible = false
	empty_notified = false
	require_trigger_release = true
	_show_weapon()
	if profile.kind == "firearm":
		player.message.emit("%s • %d loaded / %d reserve" % [profile.display_name, ammo, reserve])
	else:
		player.message.emit("%s • %d carried" % [profile.display_name, ammo])
	return true

## Puts another weapon in a slot, as when one is taken from a body.
func receive(slot: int, taken: WeaponProfile, loaded: int, spare: int) -> void:
	if slot == active_slot:
		# Return/cancel a held grenade before replacing the old slot's inventory.
		_cancel_throw()
		_cancel_place()
		weapon_audio.cancel_reload()
		draw_from = profile
		draw_serial += 1
	profiles[slot] = taken
	if taken.recovered_stats.is_empty():
		Guns.apply_stats(taken)
	magazines[slot] = loaded
	reserves[slot] = spare
	if slot == active_slot:
		recoil.reset()
		_reset_accuracy()
		reload_remaining = 0.0
		set_scope(false)
		draw_remaining = taken.draw_seconds
		cooldown = maxf(cooldown, draw_remaining)
		require_trigger_release = true
	# Refresh the carried model too when a menu changes the inactive gun.
	_show_weapon()
	player.message.emit("Took %s • %d loaded / %d reserve" % [taken.display_name, loaded, spare])

func _show_weapon() -> void:
	# Recovered weapons keep their source dimensions and native attachment transform.
	var soldier := player.soldier
	var firearm := profile.kind == "firearm"
	var long_gun := profile.hold == "long"
	soldier.set_weapon(0 if long_gun else 1)
	soldier.rifle_mesh.visible = firearm and long_gun
	soldier.pistol_mesh.visible = firearm and not long_gun
	if soldier.soldier_skin != null:
		for carried: WeaponProfile in profiles:
			if carried.kind == "firearm":
				soldier.soldier_skin.set_weapon_model(soldier, carried.recovered_model, carried.hold)
	if soldier.soldier_skin == null:
		soldier.rifle_mesh.scale = profile.visual_scale if long_gun else Vector3.ONE
		soldier.pistol_mesh.scale = Vector3.ONE if long_gun else profile.visual_scale
		soldier.muzzle.position.z = -profile.muzzle_length
	held_item.visible = not firearm and ammo > 0
	held_item.mesh = null if profile.kind in ["smoke", "claymore", "detonator"] else item_mesh
	smoke_model.visible = profile.kind == "smoke"
	claymore_model.visible = profile.kind == "claymore"
	detonator_model.visible = profile.kind == "detonator"
	if not firearm:
		item_paint.albedo_color = ITEM_COLOURS.get(profile.kind, Color.DIM_GRAY)
	if soldier.soldier_skin != null and draw_remaining > 0.0 and draw_from != null:
		# Keep the already-posed source visible until the next native pose tick.
		# The target carrier may still have its previous (or initial) transform.
		soldier.rifle_mesh.visible = draw_from.kind == "firearm" and draw_from.hold == "long"
		soldier.pistol_mesh.visible = draw_from.kind == "firearm" and draw_from.hold == "pistol"
		held_item.hide()

func stability() -> float:
	var stance_factor: float = [1.0, 0.80, 0.50][player.stance.current]
	return stance_factor * (0.75 if player.aiming else 1.0)

func running_fraction() -> float:
	if player.stance.current != StanceController.Stance.STAND:
		return 0.0
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	return clampf((speed - player.movement.walk_speed) / maxf(0.1, player.movement.run_speed - player.movement.walk_speed), 0.0, 1.0)

func spread_degrees() -> float:
	if native_accuracy():
		return accuracy.spread_degrees(scoped)
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var walking := clampf(speed / maxf(0.1,player.movement.walk_speed),0.0,1.0)
	var movement_spread := lerpf(profile.walk_spread * walking,profile.run_spread,pow(running_fraction(),1.4))
	var unaimed := 0.0 if player.aiming else profile.unaimed_spread
	return (profile.base_spread + unaimed + movement_spread + recoil.bloom) * stability()

func shot_direction() -> Vector3:
	if native_accuracy():
		return accuracy.direction(aim_direction(), scoped, magnification(), Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)))
	# The UI and the real shot use the same cone half-angle; pellets add their own.
	var firing_basis := player.camera_rig.aim_basis()
	var angle := rng.randf() * TAU
	var radius := sqrt(rng.randf()) * tan(deg_to_rad(spread_degrees() + profile.pellet_spread))
	return (-firing_basis.z + firing_basis.x * cos(angle) * radius + firing_basis.y * sin(angle) * radius).normalized()

func native_accuracy() -> bool:
	if profile.recovered_stats.is_empty():
		return false
	accuracy.bind(profile, player.stance.current)
	return true

func _reset_accuracy() -> void:
	accuracy = Accuracy.new()
	rounds_in_pull = 0
	scope_dropped = false
	if player:
		last_look = Vector2(player.rotation.y, player.camera_rig.pitch)
		player.camera_rig.set_recoil(Vector2.ZERO)
		native_accuracy()

func fire_mode() -> int:
	return profile.fire_mode if not profile.recovered_stats.is_empty() else 3 if profile.automatic else 1

func mode_caption() -> String:
	return ["SAFE", "SEMI", "BURST", "AUTO"][fire_mode()]

func fire_interval() -> float:
	if profile.recovered_stats.is_empty():
		return 60.0 / profile.rounds_per_minute
	return 60.0 / maxf(profile.rounds_per_minute, 1.0) * (0.8 if fire_mode() >= 2 else 1.0)

func cycle_fire_mode() -> bool:
	if scoped or profile.kind != "firearm" or profile.recovered_stats.is_empty():
		return false
	var modes: Array = profile.recovered_stats.modes
	if modes.size() < 2:
		return false
	profile.fire_mode = int(modes[(modes.find(profile.fire_mode) + 1) % modes.size()])
	rounds_in_pull = 0
	require_trigger_release = true
	player.message.emit("%s • %s • B / L3 change mode" % [profile.display_name, mode_caption()])
	return true

func magnification() -> float:
	return tan(deg_to_rad(player.camera_rig.profile.field_of_view * 0.5)) / tan(deg_to_rad(scope_camera.fov * 0.5)) if scoped else 1.0

func aim_direction() -> Vector3:
	return -scope_camera.global_basis.z if scoped and not profile.recovered_stats.is_empty() else player.camera_rig.aim_direction()

func view_origin() -> Vector3:
	return scope_camera.global_position if scoped else player.camera_rig.camera.global_position

func query_aim(with_spread: bool = false) -> Dictionary:
	# Hitscan resolves immediately: camera chooses aim, then the muzzle resolves the first obstruction.
	var space := player.get_world_3d().direct_space_state
	var camera_origin := view_origin()
	var direction := aim_direction()
	if native_accuracy():
		direction = accuracy.direction(direction, scoped, magnification())
	if with_spread:
		direction = shot_direction()
	var endpoint := camera_origin + direction * profile.range_metres
	var view_query := PhysicsRayQueryParameters3D.create(camera_origin, endpoint, Combat.SHOT_MASK, [player.get_rid()])
	view_query.hit_from_inside = true
	var view_hit := space.intersect_ray(view_query)
	aim_point = view_hit.get("position", endpoint)
	var muzzle_origin := player.soldier.muzzle.global_position
	var chest_origin := player.global_position + Vector3.UP * (StanceController.HEIGHTS[player.stance.current] * 0.68)
	var safety_query := PhysicsRayQueryParameters3D.create(chest_origin, muzzle_origin, 1, [player.get_rid()])
	safety_query.hit_from_inside = true
	var safety_hit := space.intersect_ray(safety_query)
	if not safety_hit.is_empty():
		blocked = true
		hit_point = safety_hit.position
		return safety_hit
	# Include the camera-selected face inside the second ray. Ending exactly on the
	# first ray's floating-point intersection can miss it from a different muzzle angle.
	var muzzle_end := aim_point
	if not view_hit.is_empty():
		muzzle_end += muzzle_origin.direction_to(aim_point) * 0.02
	var muzzle_query := PhysicsRayQueryParameters3D.create(muzzle_origin, muzzle_end, Combat.SHOT_MASK, [player.get_rid()])
	muzzle_query.hit_from_inside = true
	var result := space.intersect_ray(muzzle_query)
	hit_point = result.get("position", aim_point)
	blocked = not result.is_empty() and hit_point.distance_to(aim_point) > 0.3 and hit_point.distance_to(muzzle_origin) < 2.0
	return result

func tick(delta: float, fire: bool, reload_requested: bool) -> void:
	# When the interval runs out part-way through a tick of sustained automatic fire, the
	# overshoot carries into the next interval, so a rate that does not divide the tick
	# rate still averages out exactly. A weapon that was already ready carries nothing.
	var cycling := cooldown > 0.0 and fire and fire_mode() >= 2
	cooldown -= delta
	if cooldown < 0.0 and not cycling:
		cooldown = 0.0
	draw_remaining = maxf(0.0, draw_remaining - delta)
	hit_flash = maxf(0.0, hit_flash - delta)
	muzzle_timer = maxf(0.0, muzzle_timer - delta)
	player.soldier.flash.advance(delta)
	recoil.tick(delta, profile)
	if native_accuracy():
		var look := Vector2(player.rotation.y, player.camera_rig.pitch)
		var change := Vector2(angle_difference(last_look.x, look.x), look.y - last_look.y)
		last_look = look
		var rate := change / maxf(delta, 0.0001) if change.length() < PI * 0.25 else Vector2.ZERO
		var effort := PlayerInput.move_vector(player.camera_settings.pad_deadzone).length() * (0.2 if scoped else 1.0) + rate.length() * delta * 0.1
		accuracy.tick(delta, player.velocity, rate, not player.is_on_floor(), scoped, effort)
		player.camera_rig.set_recoil(Vector2.ZERO)
	else:
		player.camera_rig.set_recoil(recoil.offset)
	if not fire:
		require_trigger_release = false
		rounds_in_pull = 0
		scope_dropped = false
	var fresh_press := fire and not fire_was_down
	fire_was_down = fire
	_sync_remote()
	for item: int in range(3):
		if Input.is_action_just_pressed("equip_item_%d" % (item + 1), true):
			equip(2 + item)
	pad_cycle = false
	_update_scope(delta)
	if Input.is_action_just_pressed("fire_mode", true):
		cycle_fire_mode()
	if profile.kind != "firearm":
		_tick_equipment(fresh_press, fire, delta)
		return
	if reload_requested and player.can_fire() and draw_remaining <= 0.0 and ammo < profile.magazine_size and reserve > 0 and reload_remaining <= 0.0:
		reload_remaining = profile.reload_seconds
		weapon_audio.reload(profile)
		rounds_in_pull = 0
		require_trigger_release = fire
	if reload_remaining > 0.0:
		reload_remaining = maxf(0.0, reload_remaining - delta)
		if reload_remaining <= 0.0:
			var loaded := mini(profile.magazine_size - ammo, reserve)
			ammo += loaded
			reserve -= loaded
			empty_notified = false
	query_aim()
	if fire and not player.can_fire():
		require_trigger_release = true
	var limit: int = 1 if fire_mode() == 1 else 3 if fire_mode() == 2 else 10000
	var wants_shot := fire and player.can_fire() and rounds_in_pull < limit and (fire_mode() >= 2 or fresh_press) and not require_trigger_release
	if wants_shot and cooldown <= 0.00001 and reload_remaining <= 0.0 and draw_remaining <= 0.0:
		if ammo > 0:
			if scoped and rounds_in_pull > 0 and native_accuracy():
				scope_dropped = true
				set_scope(false)
			shoot(query_aim(true))
		elif not empty_notified:
			empty_notified = true
			player.message.emit("Empty • X / R reload • D-pad %s / %d to switch" % ["right" if active_slot == 0 else "left", 2 if active_slot == 0 else 1])

func shoot(result: Dictionary) -> void:
	if profile.kind != "firearm" or not player.can_fire() or ammo <= 0 or reload_remaining > 0.0 or draw_remaining > 0.0 or cooldown > 0.00001:
		return
	ammo -= 1
	shots_fired += 1
	rounds_in_pull += 1
	cooldown = fire_interval() + minf(cooldown, 0.0)
	muzzle_timer = 0.045
	weapon_audio.fire(profile)
	player.soldier.flash.fire(profile.recovered_model)
	var muzzle: Vector3 = player.soldier.muzzle.global_position
	Gunfire.fired(player, muzzle, result.get("position", muzzle + aim_direction() * Gunfire.TRACER_REACH), profile.recovered_model, 0)
	if profile.muzzle_velocity > 0.0:
		_fire_bullet(result)
	else:
		# One shell is one hit, however many of its pellets land.
		var struck := resolve_hit(result, profile, _muzzle_distance(result))
		for pellet: int in range(1, profile.pellets):
			var pellet_hit := query_aim(true)
			struck = resolve_hit(pellet_hit, profile, _muzzle_distance(pellet_hit)) or struck
		if struck:
			_count_hit()
	if native_accuracy():
		accuracy.fired(rounds_in_pull, scoped, rng.randf())
		recoil.visual_kick = minf(recoil.visual_kick + profile.weapon_kick, 2.5)
		recoil.since_shot = 0.0
	else:
		recoil.kick(profile, stability(), running_fraction())
		player.camera_rig.set_recoil(recoil.offset)
	PlayerInput.vibrate(player.camera_settings.vibration * (1.0 if profile.hold == "pistol" else 0.7))

func _muzzle_distance(result: Dictionary) -> float:
	return player.soldier.muzzle.global_position.distance_to(result.position) if result.has("position") else 0.0

func _count_hit() -> void:
	hits += 1
	hit_flash = 0.16
	target_hit.emit()

## Marks the surface and hurts whatever was struck. True when it was something that
## registers hits: a soldier or a practice target.
func resolve_hit(result: Dictionary, shot: WeaponProfile, distance: float) -> bool:
	if result.is_empty():
		return false
	var target: Object = result.get("collider")
	var soldier_struck: bool = target is Node and target.is_in_group(Combat.ACTOR_GROUP)
	if not soldier_struck:
		impact_decals.add_impact(result, shot.impact_diameter)
	# The original's per-surface bullet_hit_* puff, leaning along the round's travel.
	ImpactFX.play_shot(player, player.soldier.muzzle.global_position, result)
	if target == null or not (target.has_method("apply_damage") or target.has_method("register_hit")):
		return false
	var dealt := Combat.hurt(target, Combat.damage_at(shot, distance), {"position": result.position, "source": player, "weapon": shot.display_name})
	last_damage = dealt
	damage_dealt += dealt
	if dealt > 0.0 and director:
		director.overlay.show_damage(dealt, soldier_struck and not Combat.is_alive(target))
	return true

func _fire_bullet(result: Dictionary) -> void:
	# Cover pressed against the muzzle stops the round at once, as it does for hitscan.
	if blocked:
		if resolve_hit(result, profile, _muzzle_distance(result)):
			_count_hit()
		return
	# query_aim(true) has just chosen aim_point along the sight line, spread included.
	# The bullet leaves along that line and then gravity takes over.
	var origin := scope_camera.global_position if scoped else player.soldier.muzzle.global_position
	var bullet := BULLET.new()
	Combat.spawn(_spawn_parent(), bullet)
	bullet.launch(self, profile, origin, origin.direction_to(aim_point), [player.get_rid()])

func bullet_arrived(result: Dictionary, shot: WeaponProfile, travelled: float, _seconds: float) -> void:
	if resolve_hit(result, shot, travelled):
		_count_hit()

# --- Scope ------------------------------------------------------------------

func zoom_caption() -> String:
	return "x%d" % roundi(player.camera_rig.profile.field_of_view / profile.scope_fovs[zoom_index]) if scoped else ""

func set_scope(value: bool) -> void:
	if value == scoped:
		return
	scoped = value
	if value:
		if native_accuracy():
			accuracy.scope_kick = 0.0
			accuracy.kick_rising = false
			accuracy.exertion = minf(1.0, accuracy.exertion + 0.5)
		zoom_index = clampi(zoom_index, 0, profile.scope_fovs.size() - 1)
		_place_scope_camera()
		scope_camera.fov = profile.scope_fovs[zoom_index]
		scope_camera.make_current()
	else:
		player.look_scale = 1.0
		if not (director and director.dead):
			player.camera_rig.camera.make_current()
	if director:
		director.overlay.set_scope(scoped, zoom_caption())
		director.hud_reticle(not scoped and not director.dead)

func zoom(step: int) -> void:
	if not scoped:
		return
	zoom_index = clampi(zoom_index + step, 0, profile.scope_fovs.size() - 1)
	director.overlay.set_scope(true, zoom_caption())

func _place_scope_camera() -> void:
	var aim := player.camera_rig.aim_basis()
	if native_accuracy():
		aim *= Basis(Vector3.RIGHT, accuracy.scope_kick * profile.recovered_recoil_scale)
	var eye := player.global_position + Vector3.UP * StanceController.EYE_HEIGHTS[player.stance.current] + player.global_basis.x * player.camera_rig.actual_lean * 0.2
	scope_camera.global_transform = Transform3D(aim, eye - aim.z * 0.25)

func _update_scope(delta: float) -> void:
	set_scope(player.aiming and not scope_dropped and profile.scope_fovs.size() > 0 and draw_remaining <= 0.0 and reload_remaining <= 0.0 and player.can_fire())
	if not scoped:
		return
	_place_scope_camera()
	scope_camera.fov = lerpf(scope_camera.fov, profile.scope_fovs[zoom_index], 1.0 - exp(-14.0 * delta))
	# Looking through the scope hides the soldier and slows the look speed to match the zoom.
	player.soldier.visible = false
	player.look_scale = tan(deg_to_rad(scope_camera.fov * 0.5)) / tan(deg_to_rad(player.camera_rig.profile.field_of_view * 0.5))

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_DPAD_RIGHT:
		pad_cycle = true
	# A pad's trigger is the one fire input with travel; a mouse button or key has none.
	# Only a press decides, so a trigger twitching at rest cannot take over a held button.
	if event.is_action_pressed("fire", true):
		fire_analog = event is InputEventJoypadMotion
	if not scoped:
		return
	# While scoped the wheel, +/-, and D-pad up/down zoom instead of their usual jobs.
	var step := 0
	if event.is_action_pressed("zoom_in") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_DPAD_UP):
		step = 1
	elif event.is_action_pressed("zoom_out") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_DPAD_DOWN):
		step = -1
	if step != 0:
		zoom(step)
		get_viewport().set_input_as_handled()

# --- Equipment ----------------------------------------------------------------

## Movement runs before the weapon tick. Include a throw starting this tick so
## a running approach is already walking when the grenade is drawn back.
func sizing_throw(delta: float) -> bool:
	if not Input.is_action_pressed("fire") or not player.can_fire():
		return false
	if throw_charge >= 0.0:
		return true
	return profile.kind in ["frag", "smoke", "flash"] and ammo > 0 and not fire_was_down and not require_trigger_release and _equipment_ready(delta)

func _equipment_ready(delta: float = 0.0) -> bool:
	return player.can_fire() and cooldown <= delta + 0.00001 and draw_remaining <= delta and throw_release < 0.0 and place_release < 0.0

func _tick_equipment(fresh_press: bool, fire: bool, delta: float) -> void:
	query_aim()
	if place_release >= 0.0:
		_tick_place(delta)
		return
	if throw_release >= 0.0:
		throw_release -= delta
		if throw_release <= 0.00001:
			_throw()
	# The grenade stays in hand through the wind-up and is gone from the release until
	# the follow-through ends.
	held_item.visible = draw_remaining <= 0.0 and (throw_release >= 0.0 or (ammo > 0 and not player.soldier.throwing()))
	if throw_charge >= 0.0:
		if not player.can_fire():
			_cancel_throw()
		elif fire:
			# The arc shows where the grenade goes if let go now. A button builds strength
			# by being held; a trigger sets it by how far it is squeezed.
			if fire_analog:
				throw_charge = _squeezed(Input.get_action_strength("fire"), delta)
			else:
				throw_charge = minf(1.0, throw_charge + delta / THROW_CHARGE_SECONDS)
			var style := throw_style_for(throw_charge, player.soldier.throw_hold_style if fire_analog else -1)
			player.soldier.hold_throw(style)
			var launch := throw_launch(throw_charge, style)
			throw_arc.show_flight(THROW_ARC.predict(player.get_world_3d(), launch.origin, launch.velocity), view_origin())
		else:
			_commit_throw()
		return
	if not fresh_press or require_trigger_release or not _equipment_ready():
		return
	if profile.kind == "detonator":
		_detonate_claymores()
		return
	if ammo <= 0:
		if not empty_notified:
			empty_notified = true
			player.message.emit("No %s left" % profile.display_name.to_lower())
		return
	if profile.kind == "claymore":
		_begin_place()
		return
	throw_charge = 0.0
	squeeze = 0.0
	squeeze_rested = 0.0

## The strength an analog trigger at `travel` (0 to 1) asks for. A harder squeeze counts
## at once. A lighter one counts only after the trigger has rested there, because letting
## go passes through every lighter squeeze on the way: the throw is the squeeze that was
## being held, not whatever the trigger read as it came up.
func _squeezed(travel: float, delta: float) -> float:
	if travel > squeeze + SQUEEZE_STILL:
		squeeze_rested = SQUEEZE_SETTLE_SECONDS
	elif travel < squeeze - SQUEEZE_STILL:
		squeeze_rested = 0.0
	else:
		squeeze_rested += delta
	squeeze = travel
	return travel if squeeze_rested >= SQUEEZE_SETTLE_SECONDS else maxf(throw_charge, travel)

## The throw a hold of `strength` makes: a lob when brief, a full throw at the top, and
## between them a sidearm sling on the run or an overhand throw otherwise. `held` is the
## throw already drawn back into, if any: a squeeze hovering at a boundary keeps it.
func throw_style_for(strength: float, held: int = -1) -> int:
	var margin := 0.04
	var lob_below := LOB_BELOW + (margin if held == SoldierProxy.Throw.LOB else -margin if held >= 0 else 0.0)
	var full_from := FULL_FROM - (margin if held == SoldierProxy.Throw.FULL else -margin if held >= 0 else 0.0)
	if strength < lob_below:
		return SoldierProxy.Throw.LOB
	if strength >= full_from:
		return SoldierProxy.Throw.FULL
	return SoldierProxy.Throw.SIDEARM if running_fraction() > 0.5 else SoldierProxy.Throw.OVERHAND

## Where a throw of `strength` leaves the hand and how fast: {"origin", "velocity"}.
## Stronger throws fly faster and flatter; every throw rises above the aim line.
func throw_launch(strength: float, style: int) -> Dictionary:
	var speed := lerpf(profile.throw_speed_min, profile.throw_speed, strength)
	var lift := lerpf(35.0, 20.0, smoothstep(0.0, 0.45, strength)) + 4.0 * smoothstep(0.85, 1.0, strength) - (6.0 if style == SoldierProxy.Throw.SIDEARM else 0.0)
	var aim := player.camera_rig.aim_direction()
	var pitch := clampf(asin(clampf(aim.y, -1.0, 1.0)) + deg_to_rad(lift), deg_to_rad(-30.0), deg_to_rad(70.0))
	var flat := Vector3(aim.x, 0.0, aim.z).normalized()
	var skin := player.soldier.soldier_skin
	var moving := Vector2(player.velocity.x, player.velocity.z).length() > (0.02 if player.stance.current == 2 else 0.15)
	var release: Vector3 = skin.driver.grenade.release_point(skin.motion, skin.driver.last_base_pose, style, player.stance.current, moving, player.is_on_floor(), player.soldier.throwing(), skin.driver.gunplay)
	var origin := player.soldier.global_transform * release
	# Never release on the far side of a wall the soldier is pressed against.
	var chest := player.global_position + Vector3.UP * (StanceController.HEIGHTS[player.stance.current] * 0.68)
	var wall := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(chest, origin, Combat.WORLD_MASK, [player.get_rid()]))
	if not wall.is_empty():
		origin = chest
	return {"origin": origin, "velocity": (flat * cos(pitch) + Vector3.UP * sin(pitch)) * speed + player.velocity * 0.5}

func _commit_throw() -> void:
	# A trigger throws the throw it was drawn back into, so the arc shown is the arc flown.
	throw_style = throw_style_for(throw_charge, player.soldier.throw_hold_style if fire_analog else -1)
	throw_strength = throw_charge
	throw_charge = -1.0
	throw_arc.hide_flight()
	ammo -= 1
	throw_release = player.soldier.begin_throw(throw_style)
	cooldown = maxf(60.0 / profile.rounds_per_minute, player.soldier.throw_duration)

func _cancel_throw() -> void:
	# A grenade still in the hand (a switch mid wind-up) goes back on the belt.
	if throw_release >= 0.0:
		ammo += 1
	throw_charge = -1.0
	throw_release = -1.0
	if throw_arc:
		throw_arc.hide_flight()
	if player:
		player.soldier.cancel_throw()

func _spawn_parent() -> Node:
	var level: Variant = player.get_parent().get("level") if player.get_parent() else null
	return level if level != null and is_instance_valid(level) else player.get_parent()

func _throw() -> void:
	# The hand lets go: the grenade flies the arc that was shown, from the release point.
	throw_release = -1.0
	var launch := throw_launch(throw_strength, throw_style)
	var grenade := THROWABLE.new()
	Combat.spawn(_spawn_parent(), grenade)
	grenade.launch(player, profile, launch.origin, launch.velocity)

# --- Claymores and the remote -------------------------------------------------

func _begin_place() -> void:
	if _claymores_down().size() >= MAX_CLAYMORES:
		player.message.emit("Unable to deploy: max equipment items placed (%d)" % MAX_CLAYMORES)
		return
	if _ground_speed() > PLACE_STILL_SPEED:
		player.message.emit("Stand still to place a claymore")
		return
	place_release = player.soldier.begin_place()
	cooldown = player.soldier.place_duration

func _tick_place(delta: float) -> void:
	held_item.visible = draw_remaining <= 0.0
	# Moving off or being stopped takes the claymore back up before it is down.
	if not player.can_fire() or _ground_speed() > PLACE_STILL_SPEED:
		_cancel_place()
		return
	place_release -= delta
	if place_release <= 0.00001:
		place_release = -1.0
		_place_claymore()

## Only a claymore not yet down is taken back; once it is, the kneel plays out.
func _cancel_place() -> void:
	if place_release < 0.0:
		return
	place_release = -1.0
	cooldown = 0.0
	if player:
		player.soldier.cancel_place()

func _ground_speed() -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()

func _place_claymore() -> void:
	# Under the right hand as it reaches the ground, facing the way the soldier faces,
	# so the blast goes away from them.
	var forward := -player.global_basis.z
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	var hand := player.global_position + forward * 0.5
	var skin := player.soldier.soldier_skin
	if skin != null and not skin.motion.native_worlds.is_empty():
		hand = player.soldier.global_transform * skin.motion.native_worlds[skin.motion.rig.names.find("rhand")].origin
	var query := PhysicsRayQueryParameters3D.create(hand + Vector3.UP * 0.5, hand + Vector3.DOWN * 2.0, Combat.WORLD_MASK, [player.get_rid()])
	var ground := player.get_world_3d().direct_space_state.intersect_ray(query)
	# As in the original: nothing is placed on ground more than a metre below the feet.
	if ground.is_empty() or ground.position.y < player.global_position.y - 1.0:
		player.message.emit("No ground here to set a claymore on")
		return
	ammo -= 1
	var mine := CLAYMORE.new()
	Combat.spawn(_spawn_parent(), mine)
	mine.place(player, profile, Transform3D(Basis.looking_at(forward, Vector3.UP), ground.position))
	_play_gear(PLACE_SOUND)
	# The remote comes up as soon as the claymore is down.
	_sync_remote()
	equip(_remote_slot())

func _detonate_claymores() -> void:
	cooldown = 60.0 / profile.rounds_per_minute
	_play_gear(DETONATOR_CLICK)
	var fired := 0
	for mine: Node3D in _claymores_down():
		if mine.global_position.distance_to(player.global_position) <= REMOTE_RANGE:
			mine.detonate()
			fired += 1
	if fired == 0:
		player.message.emit("No claymore within %d m of the remote" % REMOTE_RANGE)
		return
	PlayerInput.vibrate(player.camera_settings.vibration)
	_sync_remote()
	# Back to the claymores, or the rifle when none are left.
	if active_slot == _remote_slot():
		var claymores := _slot_of("claymore")
		equip(claymores if claymores >= 0 and magazines[claymores] > 0 else 0)

## The soldier's claymores still waiting to be set off.
func _claymores_down() -> Array:
	if not is_inside_tree():
		return []
	return get_tree().get_nodes_in_group(CLAYMORE.GROUP).filter(func(mine: Node) -> bool: return mine.belongs_to(player) and not mine.is_queued_for_deletion())

func _slot_of(kind: String) -> int:
	for slot: int in range(profiles.size()):
		if profiles[slot].kind == kind:
			return slot
	return -1

func _remote_slot() -> int:
	return _slot_of("detonator")

## The remote is carried exactly while a claymore of the soldier's is down, after the
## class's own slots, and counts how many are.
func _sync_remote() -> void:
	var down := _claymores_down().size()
	var slot := _remote_slot()
	if down > 0 and slot < 0:
		profiles.append(REMOTE.duplicate() as WeaponProfile)
		magazines.append(down)
		reserves.append(0)
	elif down == 0 and slot >= 0:
		_remove_remote()
	elif slot >= 0:
		magazines[slot] = down

func _remove_remote() -> void:
	var slot := _remote_slot()
	if slot < 0:
		return
	if active_slot == slot:
		var claymores := _slot_of("claymore")
		equip(claymores if claymores >= 0 and magazines[claymores] > 0 else 0)
	profiles.remove_at(slot)
	magazines.remove_at(slot)
	reserves.remove_at(slot)
	if active_slot > slot:
		active_slot -= 1

func _play_gear(stream: AudioStream) -> void:
	gear_sound.global_position = player.global_position + Vector3.UP * 0.5
	gear_sound.stream = stream
	if DisplayServer.get_name() != "headless":
		gear_sound.play()
