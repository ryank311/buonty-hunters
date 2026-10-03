extends SceneTree

var failures: Array[String] = []
var checks := 0
var session: Node3D
var player: PrototypePlayer
var weapon: PracticeWeapon

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	print("PASS " if condition else "FAIL ", description)
	if not condition:
		failures.append(description)

func frames(count: int = 1) -> void:
	for i: int in range(count):
		await physics_frame
		await process_frame

func ray(from: Vector3, to: Vector3) -> Dictionary:
	return player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1 | 4))

func box_at(point: Vector3, rotation_basis: Basis = Basis.IDENTITY) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(2, 2, 2)
	body.add_child(shape)
	session.add_child(body)
	body.global_transform = Transform3D(rotation_basis, point)
	return body

func _run() -> void:
	session = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	player = session.player
	weapon = player.weapon
	session.load_level(true)
	player.reset_at(Transform3D(Basis.IDENTITY, Vector3(23, 0.1, 5)))
	await frames(20)
	player.controls_enabled = false
	var target: Node3D = session.level.get_node("Targets/Target10")
	var all_stances_hit := true
	for slot: int in [0,1]:
		weapon.equip(slot)
		for stance: int in [0,1,2]:
			player.stance.current = stance
			player.soldier.pose(stance,0,Vector2.ZERO,-0.03,0,2.0)
			player.camera_rig.camera.look_at(target.global_position,Vector3.UP)
			all_stances_hit = all_stances_hit and weapon.query_aim().get("collider") == target
	check(all_stances_hit, "Camera-selected surface remains hittable from both weapons in every stance")
	weapon.reset()
	player.stance.current = 0
	player.soldier.pose(0,0,Vector2.ZERO,-0.03,0,2.0)
	player.camera_rig.camera.look_at(target.global_position, Vector3.UP)
	var hit := weapon.query_aim()
	check(hit.get("collider") == target, "Actual camera/muzzle hitscan reaches the practice target")
	weapon.shoot(hit)
	check(weapon.hits == 1 and target.flash_remaining > 0 and weapon.ammo == 29, "Target hit and ammo resolve in the firing call without travel time")
	check(weapon.impact_decals.marks.size() == 1, "Firing creates a bullet mark in the same call")
	if weapon.impact_decals.marks.is_empty():
		quit(1)
		return
	var first: MeshInstance3D = weapon.impact_decals.marks[0]
	check(first.get_parent() == target, "Bullet mark belongs to the struck surface")
	check(first.global_position.distance_to(hit.position + hit.normal * ImpactDecals.SURFACE_OFFSET) < 0.0001, "Mark sits just above the actual ray intersection")
	check(first.global_basis.z.dot(hit.normal) > 0.999, "Mark faces outward along the hit normal")
	weapon.tick(1.0, false, false)
	await frames(2)
	check(is_instance_valid(first) and first.visible and not player.soldier.flash.visible, "Bullet hole persists after the muzzle flash ends")
	weapon.equip(1)
	weapon.tick(1.0, false, false)
	check(is_instance_valid(first) and weapon.impact_decals.marks.size() == 1, "Weapon switching preserves existing bullet holes")
	player.camera_rig.camera.look_at(target.global_position, Vector3.UP)
	weapon.shoot(weapon.query_aim())
	check(weapon.hits == 2 and weapon.ammo == 11 and weapon.impact_decals.marks.size() == 2, "Pistol shares instant hit registration and persistent marks")
	check(weapon.profiles[1].impact_diameter < weapon.profiles[0].impact_diameter, "Rifle and pistol have independently sized impacts")
	weapon.shoot(hit)
	check(weapon.impact_decals.marks.size() == 2, "Cooldown prevents extra impact marks")
	weapon.cooldown = 0
	weapon.ammo = 0
	weapon.shoot(hit)
	check(weapon.impact_decals.marks.size() == 2, "An empty magazine cannot create an impact")
	weapon.ammo = 1
	weapon.reload_remaining = 1
	weapon.shoot(hit)
	check(weapon.impact_decals.marks.size() == 2, "Reloading cannot create an impact")
	weapon.reload_remaining = 0
	weapon.shoot({})
	check(weapon.ammo == 0 and weapon.impact_decals.marks.size() == 2, "A miss consumes a round without leaving a floating mark")
	weapon.reset()
	await frames(2)
	check(not is_instance_valid(first) and get_nodes_in_group("bullet_impacts").is_empty(), "Practice reset removes every impact")
	var chest := player.global_position + Vector3.UP * StanceController.HEIGHTS[0] * 0.68
	var blocker := box_at(chest.lerp(player.soldier.muzzle.global_position,0.5))
	(blocker.get_child(0) as CollisionShape3D).shape.size = Vector3(0.2,0.2,0.12)
	await frames(2)
	player.camera_rig.camera.look_at(target.global_position,Vector3.UP)
	hit = weapon.query_aim()
	check(hit.get("collider") == blocker and weapon.blocked, "Near cover wins over the camera's distant aim point")
	weapon.shoot(hit)
	check(weapon.hits == 0 and weapon.impact_decals.marks.size() == 1 and weapon.impact_decals.marks[0].get_parent() == blocker, "Obstructed fire marks the cover without damaging the target behind it")
	blocker.queue_free()
	weapon.reset()
	await frames(2)
	var surface := box_at(Vector3(100, 10, 100))
	await frames(2)
	for normal: Vector3 in [Vector3.BACK, Vector3.RIGHT, Vector3.UP, Vector3.DOWN]:
		hit = ray(surface.position + normal * 4, surface.position)
		var mark: MeshInstance3D = weapon.impact_decals.add_impact(hit, 0.11)
		check(mark != null and mark.global_basis.z.dot(normal) > 0.999, "Wall/floor/ceiling impact aligns to %s" % normal)
	var tilted := box_at(Vector3(110, 10, 100), Basis.from_euler(Vector3(0.4, 0.6, 0.2)))
	await frames(2)
	var edge := tilted.to_global(Vector3(0.995, 0.995, 1.0))
	var outward := tilted.global_basis.z
	hit = ray(edge + outward * 3, edge - outward)
	var clipped: MeshInstance3D = weapon.impact_decals.add_impact(hit, 0.3)
	check(clipped != null and clipped.global_basis.z.dot(outward) > 0.999, "Rotated surface receives an aligned mark at its corner")
	var inside := clipped != null
	var valid_uv := clipped != null
	if clipped:
		var arrays := clipped.mesh.surface_get_arrays(0)
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			var local := tilted.to_local(clipped.to_global(vertex) - outward * ImpactDecals.SURFACE_OFFSET)
			inside = inside and absf(local.x) <= 1.0001 and absf(local.y) <= 1.0001 and absf(local.z) <= 1.0001
		for uv: Vector2 in arrays[Mesh.ARRAY_TEX_UV]:
			valid_uv = valid_uv and uv.x >= -0.0001 and uv.x <= 1.0001 and uv.y >= -0.0001 and uv.y <= 1.0001
	check(inside, "Impact mesh clips at cover edges instead of hanging in space")
	check(valid_uv, "Clipped bullet-hole texture keeps valid coordinates")
	var mover: Node3D = session.level.get_node("Targets/MovingTarget")
	hit = ray(mover.global_position + Vector3(0, 0, 2), mover.global_position)
	var moving_mark: MeshInstance3D = weapon.impact_decals.add_impact(hit, 0.11)
	var local_mark := moving_mark.transform
	var original_point := moving_mark.global_position
	await frames(20)
	check(moving_mark.transform.is_equal_approx(local_mark) and moving_mark.global_position.distance_to(original_point) > 0.01, "Marks stay attached while a target moves")
	hit = ray(surface.position + Vector3.BACK * 4, surface.position)
	check(weapon.impact_decals.add_impact({"collider": surface, "position": surface.position, "normal": Vector3.ZERO}, 0.1) == null, "An inside-solid hit with no normal creates no invalid decal")
	weapon.impact_decals.clear()
	first = weapon.impact_decals.add_impact(hit, 0.11)
	for i: int in range(ImpactDecals.MAX_MARKS + 10):
		weapon.impact_decals.add_impact(hit, 0.11)
	check(weapon.impact_decals.marks.size() == ImpactDecals.MAX_MARKS and first.is_queued_for_deletion(), "Impact budget retires the oldest marks at 128")
	await frames(2)
	check(get_nodes_in_group("bullet_impacts").size() == ImpactDecals.MAX_MARKS, "Retired marks are freed from the scene tree")
	surface.queue_free()
	await frames(2)
	hit = ray(tilted.position + outward * 4, tilted.position)
	weapon.impact_decals.add_impact(hit, 0.11)
	check(weapon.impact_decals.marks.size() == 1, "Destroyed surfaces clean up their marks without stale references")
	session.load_level(false)
	await frames(3)
	check(weapon.impact_decals.marks.is_empty() and get_nodes_in_group("bullet_impacts").is_empty(), "Changing levels clears the impact budget and scene nodes")
	print("\nRESULT: %d checks, %d failure(s)" % [checks, failures.size()])
	session.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
