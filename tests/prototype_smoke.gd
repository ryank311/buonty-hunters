extends SceneTree
## The game starts and its basics work: both graybox levels load, the player moves,
## jumps, changes stance, shoots, and the menu pauses. Part of the core tier
## (tests/core.txt), so it stays short and checks behaviour, not tuning: speeds, jump
## height, and magazine sizes are read from the profiles the player tunes.

var failures: Array[String] = []
var session: Node3D
var player: PrototypePlayer

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	print("PASS " if condition else "FAIL ", description)
	if not condition:
		failures.append(description)

func frames(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame

func place(position: Vector3, yaw: float = 0.0) -> void:
	player.reset_at(Transform3D(Basis(Vector3.UP, yaw), position))
	await frames(12)

func walk(direction: Vector2, count: int) -> void:
	player.test_command = {"move": direction}
	await frames(count)
	player.test_command = {}

## Holds forward until the player stands at `height`, however fast they run.
func climb(height: float, limit: int = 400) -> void:
	player.test_command = {"move": Vector2(0,-1)}
	for tick: int in range(limit):
		if player.position.y >= height and player.is_on_floor():
			break
		await frames(1)
	player.test_command = {}

func _run() -> void:
	session = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	player = session.player
	await frames(30)
	check(player.is_on_floor(), "Town spawn settles on floor")
	check(session.level.get_node("Spawns").get_child_count() == 10, "Town has ten team spawn markers")
	check(player.global_position.y > -0.05, "Town spawn does not fall through geometry")
	session.load_level(true)
	await frames(15)
	check(session.in_lab, "Switch to movement lab")
	await place(Vector3(0, 0.1, 25))
	var start := player.position
	await walk(Vector2(0,-1), 60)
	var forward_distance := start.distance_to(player.position)
	var run_speed: float = player.movement.run_speed
	check(forward_distance > run_speed * 0.7 and forward_distance < run_speed and absf(player.velocity.length() - run_speed) < 0.05, "Weighted acceleration reaches the run speed within a second (%.2f m covered at %.1f m/s)" % [forward_distance, run_speed])
	await place(Vector3(0, 0.1, 25))
	start = player.position
	await walk(Vector2(1,-1), 60)
	var diagonal_distance := start.distance_to(player.position)
	check(diagonal_distance <= forward_distance + 0.03, "Diagonal input gives no speed bonus (%.3f m)" % diagonal_distance)
	await frames(20)
	check(Vector2(player.velocity.x, player.velocity.z).length() < 0.01, "Releasing input brakes to rest")
	await place(Vector3(0, 0.1, 25))
	player.test_command = {"jump": true}
	await frames(1)
	player.test_command = {}
	var peak: float = player.position.y
	for index: int in range(65):
		await frames(1)
		peak = maxf(peak, player.position.y)
	var jump_height: float = player.movement.jump_height
	check(absf(peak - jump_height) < jump_height * 0.15 and player.is_on_floor(), "Jump reaches its set height and lands (%.2f m of %.2f m)" % [peak, jump_height])
	check(player.request_stance(1), "Crouch transition succeeds in open space")
	player.global_position = Vector3(-10, 0.08, 2)
	await frames(15)
	check(not player.request_stance(0), "Low ceiling rejects standing")
	check(player.stance.current == 1 and player.collider.shape == player.stance.shapes[1], "Rejected stance preserves crouch collider")
	check(player.request_stance(2), "Prone transition fits beneath crouch ceiling")
	player.global_position = Vector3(-10, 0.08, -7)
	await frames(15)
	check(not player.request_stance(1), "Prone tunnel rejects crouching")
	await place(Vector3(10.4, 0.1, 26.0))
	check(player.request_stance(2), "Prone fits parallel to wall")
	check(not player.turn(PI/2.0), "Prone rotation cannot sweep body through wall")
	await place(Vector3(-27,0.1,18.5))
	await climb(3.1)
	check(player.position.y > 3.0, "Stair ramp connects to landing (%s)" % player.position)
	# Camera obstruction behind a standing player.
	await place(Vector3(9,0.1,21.8))
	await frames(15)
	check(player.camera_rig.arm.get_hit_length() < 1.5, "Camera retracts at wall (%.2f m)" % player.camera_rig.arm.get_hit_length())
	await place(Vector3(0,0.1,25))
	await frames(30)
	check(player.camera_rig.arm.get_hit_length() > 2.7, "Camera recovers in open space")
	# Aim at the ten metre target and resolve the actual two-ray shot.
	await place(Vector3(23,0.1,5))
	player.camera_rig.pitch = -0.03
	await frames(20)
	var target: Node3D = session.level.get_node("Targets/Target10")
	var desired_point := target.global_position
	player.camera_rig.camera.look_at(desired_point, Vector3.UP)
	var hit := player.weapon.query_aim()
	check(hit.get("collider") == target, "Camera and muzzle rays reach visible target")
	player.weapon.shoot(hit)
	var magazine: int = player.weapon.profile.magazine_size
	check(player.weapon.ammo == magazine - 1 and player.weapon.hits == 1, "Practice shot consumes one round and registers one hit")
	player.weapon.tick(0.01, false, true)
	check(player.weapon.reload_remaining > 0.0, "Reload begins")
	player.weapon.tick(player.weapon.profile.reload_seconds + 0.1, false, false)
	check(player.weapon.ammo == magazine, "Reload completes with a full magazine")
	player.weapon.reset()
	player.weapon.cycle_fire_mode()
	player.weapon.tick(1.0 / 60.0, false, false)
	for tick: int in range(60):
		player.weapon.tick(1.0 / 60.0, true, false)
	var held: int = player.weapon.shots_fired
	check(held >= 5 and player.weapon.ammo == magazine - held, "A held trigger on automatic keeps firing (%d rounds in a second)" % held)
	player.weapon.reset()
	# A waist-high slab between body and muzzle must block a camera-visible target.
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 1
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 1.32, 0.15)
	shape_node.shape = shape
	blocker.add_child(shape_node)
	session.add_child(blocker)
	blocker.global_position = Vector3(23,0.66,4.55)
	await frames(3)
	hit = player.weapon.query_aim()
	check(hit.get("collider") == blocker and player.weapon.blocked, "Nearby cover blocks a muzzle even with a visible target")
	blocker.queue_free()
	await frames(2)
	session.set_modal(true)
	await frames(2)
	var menu_rect: Rect2 = session.hud.menu_box.get_global_rect()
	check(root.get_visible_rect().encloses(menu_rect), "Tuning controls fit within the viewport")
	start = player.position
	var moving_target: Node3D = session.level.get_node("Targets/MovingTarget")
	var target_before := moving_target.position
	await walk(Vector2(0,-1), 10)
	check(player.position.is_equal_approx(start), "Tuning menu freezes player movement")
	check(moving_target.position.is_equal_approx(target_before), "Tuning menu freezes moving targets")
	session.set_modal(false)
	await frames(10)
	check(not moving_target.position.is_equal_approx(target_before), "Moving targets resume after closing menu")
	for index: int in range(10):
		session.reset_player()
		await frames(2)
	check(player.stance.current == 0 and player.weapon.ammo == magazine and player.velocity.length() < 1.0, "Repeated resets restore stance and ammunition")
	session.load_level(false)
	await frames(10)
	await place(Vector3(-5,0.1,-26), PI)
	await climb(3.1)
	check(player.position.y > 3.0, "Town stair reaches balcony (%s)" % player.position)
	var all_spawns_clear := true
	for marker: Marker3D in session.level.get_node("Spawns").get_children():
		await place(marker.global_position, marker.rotation.y)
		all_spawns_clear = all_spawns_clear and player.is_on_floor() and player.stance.has_clearance(player, 0, player.rotation.y)
	check(all_spawns_clear, "All ten spawn slots have valid standing clearance")
	print("\nRESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
