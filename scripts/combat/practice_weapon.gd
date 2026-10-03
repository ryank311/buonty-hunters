class_name PracticeWeapon
extends Node3D

signal target_hit
const DEFAULTS := [preload("res://resources/weapons/rifle.tres"), preload("res://resources/weapons/pistol.tres")]
var player: PrototypePlayer
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
var hit_flash: float = 0.0
var blocked: bool = false
var shots_fired: int = 0
var hits: int = 0
var muzzle_timer: float = 0.0
var fire_was_down: bool = false
var require_trigger_release: bool = false
var empty_notified: bool = false
var recoil := RecoilState.new()
var rng := RandomNumberGenerator.new()
var aim_point := Vector3.ZERO
var hit_point := Vector3.ZERO
var sound := AudioStreamPlayer3D.new()
var impact_decals := preload("res://scripts/combat/impact_decals.gd").new()

func initialize(owner_player: PrototypePlayer) -> void:
	player = owner_player
	reset_profiles()
	add_child(sound)
	sound.stream = preload("res://audio/rifle.wav")
	sound.volume_db = -13.0
	sound.max_distance = 120.0
	add_child(impact_decals)
	rng.randomize()
	reset()

func reset_profiles() -> void:
	profiles.clear()
	for defaults: WeaponProfile in DEFAULTS:
		profiles.append(defaults.duplicate())

func reset() -> void:
	impact_decals.clear()
	active_slot = 0
	for slot: int in range(profiles.size()):
		magazines[slot] = profiles[slot].magazine_size
		reserves[slot] = profiles[slot].starting_reserve
	cooldown = 0.0
	reload_remaining = 0.0
	draw_remaining = 0.0
	hit_flash = 0.0
	shots_fired = 0
	hits = 0
	muzzle_timer = 0.0
	blocked = false
	fire_was_down = false
	require_trigger_release = false
	empty_notified = false
	recoil.reset()
	if player:
		player.soldier.set_weapon(0)
		player.soldier.flash.visible = false
		player.camera_rig.set_recoil(Vector2.ZERO)

func equip(slot: int) -> bool:
	if slot == active_slot or slot < 0 or slot >= profiles.size():
		return false
	# The loaded rounds stay in each gun. An interrupted reload transfers nothing.
	reload_remaining = 0.0
	active_slot = slot
	draw_remaining = profile.draw_seconds
	cooldown = maxf(cooldown, draw_remaining)
	muzzle_timer = 0.0
	player.soldier.flash.visible = false
	empty_notified = false
	require_trigger_release = true
	player.soldier.set_weapon(slot)
	player.message.emit("%s • %d loaded / %d reserve" % [profile.display_name, ammo, reserve])
	return true

func stability() -> float:
	var stance_factor: float = [1.0, 0.80, 0.50][player.stance.current]
	return stance_factor * (0.75 if player.aiming else 1.0)

func running_fraction() -> float:
	if player.stance.current != StanceController.Stance.STAND:
		return 0.0
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	return clampf((speed - player.movement.walk_speed) / maxf(0.1, player.movement.run_speed - player.movement.walk_speed), 0.0, 1.0)

func spread_degrees() -> float:
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var walking := clampf(speed / maxf(0.1,player.movement.walk_speed),0.0,1.0)
	var movement_spread := lerpf(profile.walk_spread * walking,profile.run_spread,pow(running_fraction(),1.4))
	return (profile.base_spread + movement_spread + recoil.bloom) * stability()

func shot_direction() -> Vector3:
	# The UI and the real hitscan shot use the same cone half-angle.
	var camera := player.camera_rig.camera
	var angle := rng.randf() * TAU
	var radius := sqrt(rng.randf()) * tan(deg_to_rad(spread_degrees()))
	return (-camera.global_basis.z + camera.global_basis.x * cos(angle) * radius + camera.global_basis.y * sin(angle) * radius).normalized()

func query_aim(with_spread: bool = false) -> Dictionary:
	# Hitscan resolves immediately: camera chooses aim, then the muzzle resolves the first obstruction.
	var camera := player.camera_rig.camera
	var space := player.get_world_3d().direct_space_state
	var camera_origin := camera.global_position
	var direction := -camera.global_basis.z
	if with_spread:
		direction = shot_direction()
	var endpoint := camera_origin + direction * profile.range_metres
	var view_query := PhysicsRayQueryParameters3D.create(camera_origin, endpoint, 1 | 4, [player.get_rid()])
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
	var muzzle_query := PhysicsRayQueryParameters3D.create(muzzle_origin, muzzle_end, 1 | 4, [player.get_rid()])
	muzzle_query.hit_from_inside = true
	var result := space.intersect_ray(muzzle_query)
	hit_point = result.get("position", aim_point)
	blocked = not result.is_empty() and hit_point.distance_to(aim_point) > 0.3 and hit_point.distance_to(muzzle_origin) < 2.0
	return result

func tick(delta: float, fire: bool, reload_requested: bool) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	draw_remaining = maxf(0.0, draw_remaining - delta)
	hit_flash = maxf(0.0, hit_flash - delta)
	muzzle_timer = maxf(0.0, muzzle_timer - delta)
	recoil.tick(delta, profile)
	player.camera_rig.set_recoil(recoil.offset)
	player.soldier.flash.visible = muzzle_timer > 0.0
	if not fire:
		require_trigger_release = false
	var fresh_press := fire and not fire_was_down
	fire_was_down = fire
	if reload_requested and player.can_fire() and draw_remaining <= 0.0 and ammo < profile.magazine_size and reserve > 0 and reload_remaining <= 0.0:
		reload_remaining = profile.reload_seconds
	if reload_remaining > 0.0:
		reload_remaining = maxf(0.0, reload_remaining - delta)
		if reload_remaining <= 0.0:
			var loaded := mini(profile.magazine_size - ammo, reserve)
			ammo += loaded
			reserve -= loaded
			empty_notified = false
	query_aim()
	var wants_shot := fire and player.can_fire() and (profile.automatic or fresh_press) and not require_trigger_release
	if wants_shot and cooldown <= 0.00001 and reload_remaining <= 0.0 and draw_remaining <= 0.0:
		if ammo > 0:
			shoot(query_aim(true))
		elif not empty_notified:
			empty_notified = true
			player.message.emit("Empty • X / R reload • D-pad %s / %d to switch" % ["right" if active_slot == 0 else "left", 2 if active_slot == 0 else 1])

func shoot(result: Dictionary) -> void:
	if not player.can_fire() or ammo <= 0 or reload_remaining > 0.0 or draw_remaining > 0.0 or cooldown > 0.00001:
		return
	ammo -= 1
	shots_fired += 1
	cooldown = 60.0 / profile.rounds_per_minute
	muzzle_timer = 0.045
	if DisplayServer.get_name() != "headless":
		sound.pitch_scale = 1.25 if active_slot == 1 else 1.0
		sound.play()
	player.soldier.flash.visible = true
	if not result.is_empty():
		impact_decals.add_impact(result, profile.impact_diameter)
		var target: Object = result.get("collider")
		if target and target.has_method("register_hit"):
			target.register_hit()
			hits += 1
			hit_flash = 0.16
			target_hit.emit()
	recoil.kick(profile, stability(), running_fraction())
	player.camera_rig.set_recoil(recoil.offset)
	PlayerInput.vibrate(player.camera_settings.vibration * (1.0 if active_slot == 1 else 0.7))
