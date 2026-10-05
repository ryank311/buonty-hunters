extends SceneTree
## Classes, the weapons they carry, equipment, elimination, spectating, and searching
## bodies. Stand-in soldiers (combat dummies) play the other players.

const H = preload("res://tools/agent/harness.gd")
const Combat = preload("res://scripts/combat/combat.gd")
const Roster = preload("res://scripts/combat/roster.gd")
var failures: Array[String] = []
var session: Node3D
var player: PrototypePlayer
var weapon: PracticeWeapon

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	print("PASS " if condition else "FAIL ", description)
	if not condition:
		failures.append(description)

func ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame

## Every scenario here starts without the level's default soldiers: the checks place
## their own and measure exact distances and counts.
func scenario(title: String, spec: Dictionary = {}) -> Dictionary:
	spec["roster"] = false
	return await H.scenario(self, title, spec)

func actor(title: String) -> Node3D:
	for candidate: Node in get_nodes_in_group(Combat.ACTOR_GROUP):
		if candidate != player and not candidate.is_queued_for_deletion() and Combat.name_of(candidate) == title:
			return candidate
	return null

func wall(centre: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	session.level.add_child(body)
	body.global_position = centre
	return body

func _run() -> void:
	session = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	player = session.player
	weapon = player.weapon
	await ticks(30)
	await _classes()
	await _firearms()
	await _sniper()
	await _equipment()
	await _claymore()
	await _elimination()
	await _bodies()
	await _roster()
	print("\nRESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await ticks(2)
	quit(0 if failures.is_empty() else 1)

func _classes() -> void:
	var expected := {
		"rifleman": ["M4A1", "M9", "FRAG GRENADE", "SMOKE GRENADE"],
		"marksman": ["M40A1", "MODEL 18", "CLAYMORE", "SMOKE GRENADE"],
		"breacher": ["870", "DE .50", "FLASHBANG", "FRAG GRENADE"],
		"pointman": ["HK5", "M9", "FLASHBANG", "CLAYMORE"],
	}
	var start: Dictionary = await scenario("lab_start")
	check(start["class"] == "rifleman" and start.carried.map(func(item: Dictionary) -> String: return item.name) == expected.rifleman, "A soldier starts as a rifleman: rifle, 9 mm pistol, frag, smoke")
	var wrong: Array[String] = []
	for id: String in expected:
		var state: Dictionary = await H.apply(self, {"class": id})
		if state.carried.map(func(item: Dictionary) -> String: return item.name) != expected[id] or state.weapon.slot != 0:
			wrong.append(id)
	check(wrong.is_empty(), "Each class carries its own primary, pistol, and equipment (%s)" % ("four classes" if wrong.is_empty() else ", ".join(wrong)))
	await H.apply(self, {"class": "breacher"})
	weapon.director.choose_class(1)
	await ticks(4)
	var chosen: Dictionary = H.state(self)
	check(chosen["class"] == "marksman" and chosen.player.pos[2] > 25.5 and chosen.weapon.ammo == 5, "Choosing a class respawns the player with that loadout")
	var fresh: Dictionary = await scenario("lab_start")
	check(fresh["class"] == "rifleman", "A fresh scenario returns to the default class")
	var item: Dictionary = await H.step(self, 6, {"tap": ["equip_item_1"]})
	check(item.weapon.name == "FRAG GRENADE" and item.weapon.ammo == 2, "The equipment keys select carried equipment (%s)" % item.weapon.name)

func _one_shot(spec: Dictionary) -> Dictionary:
	var state: Dictionary = await scenario("lab_range", spec)
	weapon.rng.seed = 20261003
	weapon.shoot(weapon.query_aim())
	await ticks(2)
	return H.state(self)

func _firearms() -> void:
	# Lab range: targets at 10, 25, and 50 metres report the damage of each hit.
	var rifle_near: Dictionary = await _one_shot({})
	var rifle_far: Dictionary = await _one_shot({"pos": [32.0, 0.1, 5.0], "look_at": "Targets/Target50"})
	check(is_equal_approx(rifle_near.weapon.last_damage, 34.0) and is_equal_approx(rifle_far.weapon.last_damage, 34.0), "The rifle keeps its 34 damage across the 50 m range (%.1f, %.1f)" % [rifle_near.weapon.last_damage, rifle_far.weapon.last_damage])
	var smg_near: Dictionary = await _one_shot({"class": "pointman"})
	var smg_mid: Dictionary = await _one_shot({"class": "pointman", "pos": [27.0, 0.1, 5.0], "look_at": "Targets/Target25"})
	var smg_far: Dictionary = await _one_shot({"class": "pointman", "pos": [32.0, 0.1, 5.0], "look_at": "Targets/Target50"})
	check(is_equal_approx(smg_near.weapon.last_damage, 22.0) and smg_mid.weapon.last_damage < 21.0 and smg_far.weapon.last_damage < 11.0 and smg_far.weapon.last_damage > 9.0, "The submachine gun hits for less and fades with distance (%.1f at 10 m, %.1f at 25 m, %.1f at 50 m)" % [smg_near.weapon.last_damage, smg_mid.weapon.last_damage, smg_far.weapon.last_damage])
	await scenario("lab_range", {"class": "pointman"})
	weapon.cycle_fire_mode()
	await H.step(self, 1)
	var burst: Dictionary = await H.step(self, 60, {"hold": ["fire"]})
	check(burst.weapon.shots >= 13 and burst.weapon.shots <= 14, "The submachine gun fires faster than the rifle (%d rounds in a second)" % burst.weapon.shots)
	await scenario("lab_range", {"class": "marksman", "weapon": "secondary"})
	var spray: Dictionary = await H.step(self, 60, {"hold": ["fire"]})
	check(spray.weapon.name == "MODEL 18" and spray.weapon.shots >= 16, "The machine pistol is automatic (%d rounds in a second)" % spray.weapon.shots)
	await scenario("lab_range", {"class": "breacher", "weapon": "secondary"})
	# Damage/cadence assertion: remove random dispersion. Native distribution has
	# its own deterministic statistical checks in recovered_accuracy_regression.
	weapon.profile.recovered_spread_scale = 0.0
	var heavy: Dictionary = await H.step(self, 60, {"hold": ["fire"]})
	check(heavy.weapon.name == "DE .50" and heavy.weapon.shots == 1 and heavy.weapon.last_damage > 50.0, "The heavy pistol fires once per pull and hits hard (%.0f)" % heavy.weapon.last_damage)
	# Shotgun: one shell is nine pellets in a wide cone.
	await scenario("lab_start", {"class": "breacher", "actors": [{"team": 1, "pos": [0.0, 0.0, 22.0], "name": "CLOSE"}], "look_at": [0.0, 1.1, 22.0]})
	weapon.rng.seed = 7
	weapon.shoot(weapon.query_aim(true))
	await ticks(2)
	var close := actor("CLOSE")
	var close_damage: float = close.max_health - close.health
	# Native hand/muzzle placement changes which pellets strike torso versus legs.
	# Require several pellets' damage without baking in the retired model's socket.
	check(weapon.ammo == 5 and weapon.shots_fired == 1 and weapon.hits == 1 and close_damage >= weapon.profile.damage * 4.0, "One shotgun shell consumes one round and delivers multiple pellets at 4 m (%.0f damage)" % close_damage)
	await scenario("lab_start", {"class": "breacher", "actors": [{"team": 1, "pos": [0.0, 0.0, 1.0], "name": "DISTANT"}], "look_at": [0.0, 1.1, 1.0]})
	weapon.rng.seed = 7
	weapon.shoot(weapon.query_aim(true))
	await ticks(2)
	var distant := actor("DISTANT")
	var distant_damage: float = distant.max_health - distant.health
	check(distant.alive and distant_damage < close_damage * 0.35, "The same shell does much less at 25 m (%.0f damage)" % distant_damage)
	# Hit regions: the rifle's 34 becomes 100 to the head and 25 to a leg.
	await scenario("lab_start", {"actors": [{"team": 1, "pos": [0.0, 0.0, 18.0], "name": "REGIONS"}]})
	var regions := actor("REGIONS")
	var head: float = regions.apply_damage(34.0, {"position": regions.global_position + Vector3.UP * 1.7})
	regions.reset_target()
	var leg: float = regions.apply_damage(34.0, {"position": regions.global_position + Vector3.UP * 0.4})
	check(is_equal_approx(head, 100.0) and is_equal_approx(leg, 25.0), "A head hit kills and a leg hit does less (%.0f, %.0f)" % [head, leg])

func _sniper() -> void:
	var scoped: Dictionary = await scenario("lab_range", {"class": "marksman", "pos": [32.0, 0.1, 5.0], "hold": ["aim"], "look_at": "Targets/Target50", "settle": 30})
	check(scoped.weapon.scoped and weapon.scope_camera.current and absf(weapon.scope_camera.fov - 20.0) < 0.5 and scoped.aim.hit == "Target50", "Focus aim with the sniper rifle looks through a scope (%.1f degree view on %s)" % [weapon.scope_camera.fov, scoped.aim.hit])
	check(player.look_scale < 0.4 and not player.soldier.visible, "The scope slows the look speed and hides the soldier (look x%.2f)" % player.look_scale)
	weapon.zoom(1)
	weapon.zoom(1)
	await ticks(40)
	check(absf(weapon.scope_camera.fov - 5.0) < 0.3 and weapon.zoom_caption() == "x12", "The scope zooms in steps (%s, %.1f degrees)" % [weapon.zoom_caption(), weapon.scope_camera.fov])
	weapon.zoom(-2)
	# The bullet has to fly there: nothing is hit on the tick it is fired.
	var target: Node3D = session.level.get_node("Targets/Target50")
	var line_height: float = weapon.aim_point.y
	weapon.rng.seed = 11
	weapon.shoot(weapon.query_aim(true))
	var in_flight: Dictionary = H.state(self)
	check(weapon.hits == 0 and in_flight.get("live", {}).get("bullet", 0) == 1 and weapon.ammo == 4, "A sniper round is a bullet in flight, not an instant hit")
	var flight := 0
	while weapon.hits == 0 and flight < 60:
		await physics_frame
		flight += 1
	var distance: float = weapon.view_origin().distance_to(target.global_position)
	check(weapon.hits == 1 and flight >= 7 and flight <= 10, "It arrives after its travel time (%.0f m in %d ticks at %.0f m/s)" % [distance, flight, weapon.profile.muzzle_velocity])
	var mark: Node3D = weapon.impact_decals.marks.back()
	var drop: float = line_height - mark.global_position.y
	check(drop > 0.05 and drop < 0.14, "Gravity pulls it below the line of sight (%.3f m low at 50 m)" % drop)
	check(is_equal_approx(weapon.last_damage, 95.0), "It hits for 95 at range (%.1f)" % weapon.last_damage)
	# Cover between the muzzle and the target stops the bullet on the way.
	await scenario("lab_range", {"class": "marksman", "pos": [32.0, 0.1, 5.0], "hold": ["aim"], "look_at": "Targets/Target50", "settle": 30})
	var cover := wall(Vector3(32.0, 1.0, -20.0), Vector3(4.0, 3.0, 0.3))
	await ticks(3)
	weapon.rng.seed = 11
	weapon.shoot(weapon.query_aim(true))
	await ticks(30)
	check(weapon.hits == 0 and weapon.impact_decals.marks.back().get_parent() == cover, "Cover in the bullet's path stops it")
	cover.queue_free()
	var released: Dictionary = await H.apply(self, {})
	await ticks(4)
	check(not weapon.scoped and player.camera_rig.camera.current and is_equal_approx(player.look_scale, 1.0) and not released.weapon.scoped, "Releasing aim returns to the third-person view")
	var hip: Dictionary = await scenario("lab_range", {"class": "marksman"})
	var aimed: Dictionary = await scenario("lab_range", {"class": "marksman", "hold": ["aim"], "settle": 20})
	check(hip.weapon.spread > 2.5 and aimed.weapon.spread < 0.1, "The sniper rifle is wild from the hip and exact through the scope (%.2f and %.2f degrees)" % [hip.weapon.spread, aimed.weapon.spread])
	var rifle_aim: Dictionary = await scenario("lab_range", {"hold": ["aim"], "settle": 20})
	check(not rifle_aim.weapon.scoped, "Weapons without a scope keep the third-person focus aim")

func _equipment() -> void:
	# Frag: thrown, fused, and line-of-sight aware.
	await scenario("lab_start", {"weapon": "frag"})
	var thrown: Dictionary = await H.step(self, 30, {"tap": ["fire"]})
	var grenade: Node3D = get_nodes_in_group(Combat.SPAWNED_GROUP).filter(func(node: Node) -> bool: return node.get("fuse") != null).front()
	check(thrown.weapon.ammo == 1 and thrown.live.get("throwable", 0) == 1 and grenade.global_position.z < 24.0, "Fire throws the selected grenade down range (%.1f m out after half a second)" % (26.0 - grenade.global_position.z))
	var landed: Dictionary = await H.step(self, 150, {})
	check(landed.live.get("throwable", 0) == 1 and grenade.resting, "It bounces and comes to rest before the fuse runs out (%d bounces)" % grenade.bounces)
	var after: Dictionary = await H.step(self, 60, {})
	check(after.get("live", {}).get("throwable", 0) == 0, "The fuse sets it off 3.5 seconds after the throw")
	await scenario("lab_start", {"actors": [
		{"team": 1, "pos": [0.0, 0.0, 15.0], "name": "OPEN"},
		{"team": 1, "pos": [3.0, 0.0, 12.0], "name": "COVERED"},
		{"team": 1, "pos": [0.0, 0.0, 0.0], "name": "FAR"},
	]})
	var shield := wall(Vector3(1.5, 1.0, 12.0), Vector3(0.3, 3.0, 4.0))
	await ticks(3)
	var frag: WeaponProfile = weapon.profiles[2]
	Combat.blast(self, Vector3(0.0, 0.1, 12.0), frag.effect_radius, frag.damage, {"source": player})
	check(not actor("OPEN").alive and is_equal_approx(actor("COVERED").health, 100.0) and is_equal_approx(actor("FAR").health, 100.0), "A frag kills in the open, and cover or distance protects (open %.0f, covered %.0f, far %.0f health)" % [actor("OPEN").health, actor("COVERED").health, actor("FAR").health])
	shield.queue_free()
	Combat.blast(self, player.global_position + Vector3(0.0, 0.1, -6.0), frag.effect_radius, frag.damage, {"source": player})
	check(player.health < 80.0 and player.health > 0.0, "The thrower's own grenade hurts them from 6 m (%.0f health left)" % player.health)
	# Smoke: a cloud that swells, hangs, and clears.
	await scenario("lab_start", {"weapon": "smoke"})
	await H.step(self, 4, {"tap": ["fire"]})
	var smoking: Dictionary = await H.step(self, 300, {"speed": 4})
	var cloud: Node3D = get_nodes_in_group(&"smoke_clouds").front() if smoking.get("live", {}).get("smoke_cloud", 0) == 1 else null
	check(cloud != null and cloud.density() > 0.95, "A smoke grenade becomes a full cloud a few seconds after it lands")
	# Not worth sitting through the whole cloud: skip to the end of its life.
	if cloud != null:
		cloud.age = cloud.seconds - 0.5
	var cleared: Dictionary = await H.step(self, 45, {})
	check(cleared.get("live", {}).get("smoke_cloud", 0) == 0, "The smoke clears when its time is up")
	# Flashbang: blinds who can see it, by distance and facing.
	await scenario("lab_start", {"class": "breacher", "actors": [{"team": 1, "pos": [0.0, 0.0, 19.0], "yaw": 180.0, "name": "WATCHER"}]})
	var bang: WeaponProfile = weapon.profiles[2]
	Combat.flash(self, Vector3(0.0, 1.0, 21.0), bang.effect_radius, bang.effect_seconds)
	await ticks(2)
	var facing: float = weapon.director.overlay.flash_left
	check(facing > 2.0 and actor("WATCHER").flashed > 1.5, "A flashbang in view whites out the screen and blinds soldiers nearby (%.1f s, %.1f s)" % [facing, actor("WATCHER").flashed])
	await scenario("lab_start", {"class": "breacher", "yaw": 180.0})
	weapon.director.overlay.flash_left = 0.0
	Combat.flash(self, Vector3(0.0, 1.0, 21.0), bang.effect_radius, bang.effect_seconds)
	await ticks(2)
	var away: float = weapon.director.overlay.flash_left
	check(away > 0.3 and away < facing * 0.5, "Looking away shortens it (%.1f s)" % away)
	await scenario("lab_start", {"class": "breacher"})
	weapon.director.overlay.flash_left = 0.0
	var blind := wall(Vector3(0.0, 1.5, 23.0), Vector3(6.0, 4.0, 0.3))
	await ticks(3)
	Combat.flash(self, Vector3(0.0, 1.0, 21.0), bang.effect_radius, bang.effect_seconds)
	await ticks(2)
	check(is_zero_approx(weapon.director.overlay.flash_left), "A wall between the soldier and the flash blocks it")
	blind.queue_free()

func _claymore() -> void:
	await scenario("lab_start", {"class": "pointman", "weapon": "claymore"})
	var placed: Dictionary = await H.step(self, 6, {"tap": ["fire"]})
	var mine: Node3D = get_nodes_in_group(Combat.SPAWNED_GROUP).filter(func(node: Node) -> bool: return node.has_method("detonate")).front()
	check(placed.weapon.ammo == 1 and placed.live.get("claymore", 0) == 1 and absf(mine.global_position.z - 25.1) < 0.1 and mine.global_position.y < 0.05, "A claymore is set on the ground a pace ahead, facing forward")
	# The soldier who set it and their teammates can stand in front of it.
	await H.apply(self, {"pos": [0.5, 0.1, 22.5], "actors": [{"team": 0, "pos": [-1.0, 0.0, 22.5], "name": "FRIEND"}]})
	var waiting: Dictionary = await H.step(self, 150, {})
	check(mine.is_armed() and waiting.live.get("claymore", 0) == 1 and is_equal_approx(player.health, 100.0), "Its owner and their teammates do not set it off")
	# An enemy pacing into the arc does. The friend standing in the blast is hurt too.
	await H.apply(self, {"pos": [0.0, 0.1, 28.0], "actors": [{"team": 1, "pos": [5.5, 0.0, 22.5], "travel": 4.5, "yaw": 180.0, "name": "INTRUDER"}]})
	var intruder := actor("INTRUDER")
	var safe: Dictionary = await H.step(self, 30, {})
	check(safe.live.get("claymore", 0) == 1 and intruder.alive, "An enemy outside the arc is ignored (%.1f m away)" % intruder.global_position.distance_to(mine.global_position))
	var tripped: Dictionary = await H.step(self, 600, {"speed": 4})
	check(tripped.get("live", {}).get("claymore", 0) == 0 and not intruder.alive, "An enemy who walks into the arc sets it off and dies")
	check(actor("FRIEND").health < 100.0 and is_equal_approx(player.health, 100.0), "The blast is a cone: the friend in front is hurt, the owner behind it is not (friend %.0f health)" % actor("FRIEND").health)

func _elimination() -> void:
	await scenario("lab_start", {"actors": [
		{"team": 0, "pos": [-3.0, 0.0, 22.0], "name": "ALPHA"},
		{"team": 0, "pos": [3.0, 0.0, 22.0], "name": "BRAVO"},
		{"team": 1, "pos": [0.0, 0.0, 10.0], "name": "HOSTILE"},
	]})
	var fell_at := player.global_position
	var down: Dictionary = await H.apply(self, {"health": 0})
	var director: Node = weapon.director
	check(not down.player.alive and director.dead and not player.controls_enabled and director.spectator.camera.current, "At zero health the player is eliminated and the view leaves them")
	check(down.watching == "ALPHA", "The view attaches to a living teammate first (%s)" % down.watching)
	var held: Dictionary = await H.step(self, 60, {"forward": 1.0, "hold": ["fire"]})
	check(player.global_position.distance_to(fell_at) < 0.05 and held.weapon.shots == 0 and player.stance.current == StanceController.Stance.PRONE, "The body stays where it fell and takes no input")
	await H.step(self, 90, {})
	var ragdoll: Node3D = director.ragdoll
	check(is_instance_valid(ragdoll) and not player.soldier.visible and ragdoll.settled and ragdoll.rest_position().distance_to(fell_at) < 1.0 and ragdoll.rest_position().y - fell_at.y < 0.4, "The soldier goes limp into a ragdoll that settles on the ground where they fell (%s, settled %s)" % [ragdoll.rest_position() - fell_at if is_instance_valid(ragdoll) else "none", ragdoll.settled if is_instance_valid(ragdoll) else false])
	var seen: Array[String] = []
	for index: int in range(4):
		var view: Dictionary = await H.step(self, 4, {"tap": ["lean_right"]})
		seen.append(view.watching)
	check(seen == ["BRAVO", "your body", "ALPHA", "BRAVO"], "Q and E cycle living teammates and the player's own body, never an enemy (%s)" % ", ".join(seen))
	actor("BRAVO").apply_damage(500.0)
	var moved_on: Dictionary = await H.step(self, 4, {})
	check(moved_on.watching != "BRAVO", "When the watched teammate falls the view moves on (%s)" % moved_on.watching)
	director.spectator.cycle(1)
	while not director.spectator.watching_own_body():
		director.spectator.cycle(1)
	var before: Basis = director.spectator.camera.global_basis
	director.spectator.look(Vector2(0.6, -0.2))
	await ticks(2)
	check(not before.is_equal_approx(director.spectator.camera.global_basis) and director.spectator.camera.global_position.distance_to(player.global_position) < 4.0, "Watching their own body, the player can look around it")
	session.set_modal(true)
	session.set_modal(false)
	await ticks(3)
	check(not player.controls_enabled, "Closing the pause menu does not bring an eliminated player back")
	session.reset_player()
	await ticks(4)
	var back: Dictionary = H.state(self)
	check(back.player.alive and player.controls_enabled and player.camera_rig.camera.current and is_equal_approx(player.health, 100.0) and not back.has("watching") and actor("BRAVO").alive, "A reset starts the next round: everyone alive, view back on the player")

func _bodies() -> void:
	await scenario("lab_start", {"actors": [
		{"team": 1, "class": "breacher", "pos": [0.0, 0.0, 24.6], "name": "FALLEN"},
		{"team": 0, "class": "marksman", "pos": [8.0, 0.0, 20.0], "name": "MATE"},
	]})
	var director: Node = weapon.director
	var fallen := actor("FALLEN")
	await ticks(3)
	check(director.body_in_reach == null, "A living soldier cannot be searched")
	fallen.apply_damage(500.0)
	var fell_at := fallen.global_position
	await ticks(3)
	check(not fallen.alive and fallen.global_position.is_equal_approx(fell_at) and director.body_in_reach == fallen, "A fallen soldier's body stays put and can be searched from beside it")
	var opened: Dictionary = await H.step(self, 4, {"tap": ["interact"]})
	check(director.loot_open and director.overlay.menu.visible and "870" in director.overlay.menu_text.text and "DE .50" in director.overlay.menu_text.text and not session.lap_running, "Interact opens a menu offering the body's primary and pistol")
	check(not player.controls_enabled, "The soldier stands still while searching")
	await H.step(self, 4, {"tap": ["ui_down"]})
	var took: Dictionary = await H.step(self, 4, {"tap": ["interact"]})
	check(player.controls_enabled, "Taking a weapon hands the controls back")
	check(took.carried[1].name == "DE .50" and took.carried[1].ammo == 7 and took.carried[0].name == "M4A1" and not director.loot_open, "Choosing the second option takes the pistol and closes the menu")
	check(fallen.carried[1].profile.display_name == "M9" and fallen.carried[1].ammo == 12, "The player's own pistol is left with the body")
	director.open_loot_menu()
	director.take_weapon(0)
	await ticks(2)
	var armed: Dictionary = H.state(self)
	check(armed.weapon.name == "870" and armed.weapon.ammo == 6 and armed.weapon.reserve == 24 and fallen.carried[0].profile.display_name == "M4A1", "Taking the primary swaps it into the player's hands with its ammunition")
	actor("MATE").apply_damage(500.0)
	var walked: Dictionary = await H.apply(self, {"pos": [8.0, 0.1, 21.2]})
	check(director.body_in_reach == actor("MATE"), "A teammate's body can be searched as well")
	director.open_loot_menu()
	director.take_weapon(0)
	await ticks(2)
	check(weapon.profiles[0].display_name == "M40A1" and actor("MATE").carried[0].profile.display_name == "870", "Weapons pass from body to body through the player")
	var left: Dictionary = await H.apply(self, {"pos": [0.0, 0.1, 10.0]})
	check(director.body_in_reach == null and not director.loot_open, "Out of reach there is nothing to search")
	var reset: Dictionary = await scenario("lab_start")
	check(reset.carried[0].name == "M4A1" and reset.carried[1].name == "M9", "A new round restores the class loadout")

## True when a standing soldier fits at `where`: floor underfoot and nothing solid around.
func _stands(where: Vector3) -> bool:
	var space := root.get_world_3d().direct_space_state
	var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(where + Vector3.UP * 0.6, where + Vector3.DOWN * 0.6, Combat.WORLD_MASK))
	var body := CapsuleShape3D.new()
	body.radius = 0.32
	body.height = 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body
	query.collision_mask = Combat.WORLD_MASK
	query.transform = Transform3D(Basis.IDENTITY, where + Vector3.UP * 0.95)
	return not floor_hit.is_empty() and absf(floor_hit.position.y - where.y) < 0.15 and space.intersect_shape(query, 1).is_empty()

func _roster() -> void:
	for lab: bool in [true, false]:
		var place := "Movement Lab" if lab else "Old Quarter"
		var state: Dictionary = await H.scenario(self, "lab_start" if lab else "town_spawn")
		var mates: Array = state.actors.filter(func(entry: Dictionary) -> bool: return entry.team == 0)
		var patrols := 0
		var misplaced: Array[String] = []
		for dummy: Node3D in session.level.get_node("Roster").get_children():
			patrols += int(dummy.travel > 0.0 and dummy.team != 0)
			# A patrol must have open floor along its whole beat.
			for side: float in [-1.0, 0.0, 1.0]:
				if not _stands(dummy.start.origin + dummy.start.basis.x * dummy.travel * side):
					misplaced.append(dummy.display_name)
					break
		check(mates.size() == 2 and state.actors.size() - mates.size() >= 3 and patrols == 1, "The %s starts with two teammates and enemies, one on patrol (%d soldiers)" % [place, state.actors.size()])
		check(misplaced.is_empty(), "Every soldier in the %s stands on open floor%s" % [place, "" if misplaced.is_empty() else ": " + ", ".join(misplaced)])
	await H.scenario(self, "lab_start")
	var hud: Node = session.hud
	var row: Node = hud.squad_rows[1]
	check(row.get_child(0).text == "02  ALPHA" and row.get_child(1).text == "OK", "The squad panel lists teammates (%s)" % row.get_child(0).text)
	actor("ALPHA").apply_damage(500.0)
	actor("TANGO 1").apply_damage(500.0)
	await ticks(3)
	check(row.get_child(1).text == "DOWN", "A fallen teammate shows as down")
	session.reset_player()
	await ticks(3)
	check(actor("ALPHA").alive and actor("TANGO 1").alive and row.get_child(1).text == "OK", "A reset stands the level's soldiers back up")
	await H.apply(self, {"weapon": "frag"})
	await ticks(3)
	check(hud.weapon_label.text == "FRAG GRENADE" and hud.ammo_label.text == "x 2" and hud.mode_label.text == "GEAR" and hud.ammo_caption.text == "CARRIED", "The HUD counts equipment instead of magazines (%s)" % hud.ammo_label.text)
	await H.apply(self, {"panel": "class"})
	check(weapon.director.class_open and not player.controls_enabled, "The class menu holds the soldier still")
	await H.step(self, 4, {"tap": ["ui_cancel"]})
	check(not weapon.director.class_open and player.controls_enabled, "Closing the class menu hands the controls back")
	var bare: Dictionary = await scenario("lab_start")
	check(not bare.has("actors"), "A scenario can remove the level's soldiers")
	var restored: Dictionary = await H.scenario(self, "lab_start")
	check(restored.get("actors", []).size() == Roster.LAB.size(), "The next reset brings them back")
