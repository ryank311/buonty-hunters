extends Node
## What happens to the local player around the weapons: being eliminated and watching
## the rest of the round, searching a body for its guns, and choosing a class.
##
## Round rules it implements:
##   - A soldier whose health reaches zero is out until the next reset. The body stays
##     where it fell.
##   - The eliminated player watches living teammates or their own body, never enemies.
##   - Anyone standing at a body can take its primary or its pistol; their own weapon
##     of that kind is left with the body in exchange.
##   - Players choose a class, not individual weapons. Choosing one respawns them.

const Combat := preload("res://scripts/combat/combat.gd")
const Loadouts := preload("res://scripts/combat/loadouts.gd")
const OVERLAY := preload("res://scripts/combat/combat_overlay.gd")
const Roster := preload("res://scripts/combat/roster.gd")
const SPECTATOR := preload("res://scripts/combat/spectator.gd")
const RAGDOLL := preload("res://scripts/actors/soldier_ragdoll.gd")
const SEARCH_REACH := 2.2
const LOOK_SPEED := 0.003
var weapon: Node
var player: Node3D
var overlay: Node
var spectator: Node3D
var dead: bool = false
var body_in_reach: Node3D
var loot_open: bool = false
var class_open: bool = false
var choice: int = 0
var ragdoll: Node3D

func initialize(owner_weapon: Node) -> void:
	weapon = owner_weapon
	player = owner_weapon.player
	player.add_to_group(Combat.ACTOR_GROUP)
	player.set_meta(&"team", 0)
	player.set_meta(&"alive", true)
	player.set_meta(&"display_name", "YOU")
	overlay = OVERLAY.new()
	add_child(overlay)
	spectator = SPECTATOR.new()
	add_child(spectator)

func session() -> Node:
	return player.get_parent()

func menu_blocks_input() -> bool:
	var owner_session := session()
	return owner_session != null and owner_session.get("modal") == true

func _physics_process(delta: float) -> void:
	if menu_blocks_input():
		# The pause menu took over (it also opens when the window loses focus).
		if class_open or loot_open:
			close_menus()
		return
	if player.has_meta(&"flashed"):
		overlay.flash(player.get_meta(&"flashed"))
		player.remove_meta(&"flashed")
	if not dead and player.health <= 0.0:
		die()
	if dead:
		# Closing the pause menu re-enables controls; an eliminated player stays out.
		player.controls_enabled = false
		var stick := PlayerInput.look_vector(player.camera_settings.pad_deadzone)
		spectator.look(stick * player.camera_settings.pad_sensitivity * delta)
		spectator.update(delta)
		overlay.show_status("ELIMINATED  ·  watching %s\nQ / E or LB / RB switch view  ·  Backspace respawn" % spectator.caption())
		return
	_find_body()
	if loot_open and body_in_reach == null:
		close_menus()
	if class_open or loot_open:
		overlay.show_prompt("")
	else:
		overlay.show_prompt("F / Y  search body  ·  %s" % Combat.name_of(body_in_reach) if body_in_reach else "")

func _input(event: InputEvent) -> void:
	if menu_blocks_input():
		return
	if dead:
		if event.is_action_pressed("lean_left") or event.is_action_pressed("lean_right"):
			spectator.cycle(-1 if event.is_action_pressed("lean_left") else 1)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			spectator.look(event.screen_relative * LOOK_SPEED)
		return
	if class_open or loot_open:
		var count: int = Loadouts.CLASSES.size() if class_open else 2
		if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
			choice = posmod(choice + (-1 if event.is_action_pressed("ui_up") else 1), count)
			_show_menu()
		elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
			if class_open:
				choose_class(choice)
			else:
				take_weapon(choice)
		elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") or event.is_action_pressed("class_menu"):
			close_menus()
		else:
			return
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("class_menu"):
		open_class_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and body_in_reach != null:
		open_loot_menu()
		# The same button starts the lap timer; searching the body takes precedence.
		get_viewport().set_input_as_handled()

# --- Elimination and spectating ---------------------------------------------

func die() -> void:
	if dead:
		return
	dead = true
	close_menus()
	player.set_meta(&"alive", false)
	weapon.set_scope(false)
	player.controls_enabled = false
	var carried: Vector3 = player.velocity
	player.velocity = Vector3.ZERO
	# Leave the body lying where it was, low to the ground.
	player.stance.current = StanceController.Stance.PRONE
	player.stance.apply(player.collider)
	player.soldier.flash.visible = false
	# The animated soldier goes limp: a physics body takes over from the last pose,
	# thrown by the killing blow and carrying the speed the player died at.
	var info: Dictionary = player.get_meta(&"last_hit_info", {})
	var owner_session := session()
	ragdoll = RAGDOLL.new()
	Combat.spawn(owner_session.level if owner_session != null and owner_session.get("level") is Node3D else player.get_parent(), ragdoll)
	ragdoll.build(player.soldier, RAGDOLL.impact(player, info, info.get("damage", 34.0)) if not info.is_empty() else {}, carried)
	player.soldier.visible = false
	hud_reticle(false)
	overlay.show_prompt("")
	spectator.begin(player)

## Called by the weapon whenever the player is reset: the next round starts alive.
func on_reset() -> void:
	close_menus()
	player.set_meta(&"alive", true)
	# A level that has just loaded gets its stand-in soldiers here.
	var owner_session := session()
	if owner_session != null and owner_session.get("level") is Node3D:
		Roster.ensure(owner_session.level, owner_session.in_lab)
	if player.has_meta(&"last_hit_info"):
		player.remove_meta(&"last_hit_info")
	if not dead:
		return
	dead = false
	if is_instance_valid(ragdoll):
		ragdoll.queue_free()
	player.soldier.visible = true
	spectator.end()
	overlay.show_status("")
	player.controls_enabled = not menu_blocks_input()
	player.camera_rig.camera.make_current()
	hud_reticle(true)

func hud_reticle(shown: bool) -> void:
	# The HUD sets the reticle's visibility itself every frame, so fade it out instead.
	var hud: Variant = session().get("hud") if session() else null
	if hud != null and hud.get("crosshair") != null:
		hud.crosshair.modulate.a = 1.0 if shown else 0.0

# --- Searching a body ---------------------------------------------------------

func _find_body() -> void:
	body_in_reach = null
	var nearest := SEARCH_REACH
	for actor: Node in get_tree().get_nodes_in_group(Combat.ACTOR_GROUP):
		if actor == player or not actor is Node3D or Combat.is_alive(actor) or not actor.has_method("swap_weapon"):
			continue
		var distance: float = actor.global_position.distance_to(player.global_position)
		if distance < nearest:
			nearest = distance
			body_in_reach = actor

func open_loot_menu() -> void:
	if body_in_reach == null:
		return
	loot_open = true
	choice = 0
	player.controls_enabled = false
	_show_menu()

## Swaps the player's primary (slot 0) or pistol (slot 1) with the body's.
func take_weapon(slot: int) -> void:
	if body_in_reach == null:
		return
	var given := {"profile": weapon.profiles[slot], "ammo": weapon.magazines[slot], "reserve": weapon.reserves[slot]}
	var taken: Dictionary = body_in_reach.swap_weapon(slot, given)
	weapon.receive(slot, taken.profile, taken.ammo, taken.reserve)
	close_menus()

# --- Choosing a class ---------------------------------------------------------

func open_class_menu() -> void:
	class_open = true
	loot_open = false
	choice = maxi(0, Loadouts.CLASSES.find(weapon.soldier_class))
	player.controls_enabled = false
	_show_menu()

## Classes change at the spawn, so choosing one starts the player over.
func choose_class(index: int) -> void:
	close_menus()
	weapon.set_class(index)
	if session() != null and session().has_method("reset_player"):
		session().reset_player()

func close_menus() -> void:
	if (loot_open or class_open) and not dead:
		# The soldier stands still while a menu is up, and stays so until the button
		# that closed it is let go: confirming with A must not also jump.
		player.controls_enabled = not menu_blocks_input()
		player.input_armed = false
	loot_open = false
	class_open = false
	overlay.hide_menu()

func _show_menu() -> void:
	var lines: Array = []
	if class_open:
		for loadout: Resource in Loadouts.CLASSES:
			lines.append("%s  ·  %s" % [loadout.display_name, loadout.summary])
		overlay.show_menu("CHOOSE A CLASS", lines, choice, "↑ ↓ choose  ·  F / Enter / pad A confirm and respawn  ·  Esc / pad B close")
	elif loot_open and body_in_reach != null:
		for item: Dictionary in body_in_reach.carried:
			lines.append("Take %s  ·  %d / %d" % [item.profile.display_name, item.ammo, item.reserve])
		overlay.show_menu("SEARCH BODY  ·  %s" % Combat.name_of(body_in_reach), lines, choice, "↑ ↓ choose  ·  F / Enter / pad A take  ·  Esc / pad B leave")
