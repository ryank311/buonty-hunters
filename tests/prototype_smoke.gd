extends SceneTree

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

func follow_route(title: String, points: Array[Vector2]) -> void:
	await place(Vector3(points[0].x, 0.1, points[0].y))
	var ticks: int = 0
	var completed: bool = true
	for goal: Vector2 in points.slice(1):
		var arrived: bool = false
		for step: int in range(900):
			var offset := Vector3(goal.x, player.position.y, goal.y) - player.position
			if offset.length() < 0.35:
				arrived = true
				break
			player.rotation.y = atan2(-offset.x, -offset.z)
			player.test_command = {"move": Vector2(0,-1)}
			await frames(1)
			ticks += 1
		if not arrived:
			print("Blocked at ", player.position, " approaching ", goal)
			completed = false
			break
	player.test_command = {}
	check(completed, "%s route traversable (%.2f simulated seconds)" % [title, ticks / 60.0])

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
	# The original covered 5.90 m in its first second from rest (59.04 source units).
	check(forward_distance > 5.8 and forward_distance < 6.0, "Weighted acceleration reaches the run speed (%.3f m / first second)" % forward_distance)
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
	check(peak > 0.32 and peak < 0.46 and player.is_on_floor(), "Jump reaches the original 0.39 m apex and lands (%.3f m)" % peak)
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
	await walk(Vector2(0,-1), 170)
	check(player.position.y > 3.0 and player.position.z < 9.8, "Stair ramp connects to landing (%s)" % player.position)
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
	check(player.weapon.ammo == 29 and player.weapon.hits == 1, "Practice shot consumes one round and registers one hit")
	player.weapon.tick(0.01, false, true)
	check(player.weapon.reload_remaining > 0.0, "Reload begins")
	player.weapon.tick(2.5, false, false)
	check(player.weapon.ammo == 30, "Reload completes with a full magazine")
	player.weapon.reset()
	for tick: int in range(60):
		player.weapon.tick(1.0 / 60.0, true, false)
	check(player.weapon.shots_fired == 10 and player.weapon.ammo == 20, "Automatic cadence is ten rounds per second")
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
	check(player.stance.current == 0 and player.weapon.ammo == 30 and player.velocity.length() < 1.0, "Repeated resets restore stance and ammunition")
	session.load_level(false)
	await frames(10)
	# Long enough to climb and stand on the balcony, not so long as to run off its far edge.
	await place(Vector3(-5,0.1,-26), PI)
	await walk(Vector2(0,-1), 135)
	check(player.position.y > 3.0 and player.position.z > -15.1, "Town west stair reaches balcony (%s)" % player.position)
	await place(Vector3(17,0.1,-26), PI)
	await walk(Vector2(0,-1), 135)
	check(player.position.y > 3.0 and player.position.z > -15.1, "Town east stair reaches balcony (%s)" % player.position)
	var all_spawns_clear := true
	for marker: Marker3D in session.level.get_node("Spawns").get_children():
		await place(marker.global_position, marker.rotation.y)
		all_spawns_clear = all_spawns_clear and player.is_on_floor() and player.stance.has_clearance(player, 0, player.rotation.y)
	check(all_spawns_clear, "All ten spawn slots have valid standing clearance")
	await follow_route("Market", [Vector2(-46,9), Vector2(-40,9), Vector2(-40,-13), Vector2(-17,-13), Vector2(-17,-1), Vector2(-9,-1), Vector2(-1,-1), Vector2(8,0), Vector2(11,8), Vector2(15,14), Vector2(43,14), Vector2(46,10)])
	await follow_route("Courtyard", [Vector2(-46,9), Vector2(-40,9), Vector2(-40,-13), Vector2(-29,-13), Vector2(-29,-36), Vector2(18,-36), Vector2(33,-36), Vector2(33,-14), Vector2(40,-14), Vector2(40,10), Vector2(46,10)])
	await follow_route("Service Passage", [Vector2(-46,9), Vector2(-40,22), Vector2(-26.5,22), Vector2(-26.5,38), Vector2(7,38), Vector2(7,17), Vector2(14,17), Vector2(43,17), Vector2(46,10)])
	print("\nRESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
