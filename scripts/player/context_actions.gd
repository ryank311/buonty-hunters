extends Node
## One selection drives both the original action icons and the action button.
## Revalidate on press: stale prompts can never operate an out-of-reach target.
const Combat = preload("res://scripts/combat/combat.gd")
var player: PrototypePlayer
var offers: Array[Dictionary] = []
var selected: int = 0
var chosen_id: String = ""

func _physics_process(_delta: float) -> void:
	refresh()

func available() -> bool:
	var director: Node = player.weapon.director
	return player.controls_enabled and player.health > 0 and not player.get_parent().modal and not director.loot_open and not director.class_open and not player.traversal.active and not player.diving and player.dive_recovery <= 0.0 and player.is_on_floor()

func refresh() -> void:
	offers.clear()
	if not available():
		chosen_id = ""
		selected = 0
		return
	var camera := player.camera_rig.camera
	var center := player.get_viewport().get_visible_rect().size * 0.5
	var origin := camera.project_ray_origin(center)
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(center) * 12.0, player.collision_mask, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty() and hit.collider.has_method("offer"):
		var offer: Dictionary = hit.collider.offer(player, hit.position)
		if not offer.is_empty():
			offers.append(offer)
	var director: Node = player.weapon.director
	var body: Node3D = director.body_in_reach
	if is_instance_valid(body) and _body_visible(body):
		offers.append({"kind": "body", "target": body, "label": "SEARCH BODY", "icon": "action_pickup_item.png", "enabled": true, "reason": ""})
	if player.stance.current != StanceController.Stance.PRONE:
		var ledge := Traversal.find_ledge(player, player.movement)
		if not ledge.is_empty():
			var room: bool = player.traversal.landing_stance(player, player.stance, ledge) >= 0
			offers.append({"kind": "climb", "label": "CLIMB", "icon": "action_climb.png", "enabled": room, "reason": "NO ROOM ABOVE" if not room else ""})
	selected = 0
	for index: int in range(offers.size()):
		if _id(offers[index]) == chosen_id:
			selected = index
	if not offers.is_empty():
		chosen_id = _id(offers[selected])
	else:
		chosen_id = ""

func _body_visible(body: Node3D) -> bool:
	var offset := body.global_position - player.global_position
	if offset.length() > player.weapon.director.SEARCH_REACH:
		return false
	if Vector2(offset.x, offset.z).length() > 0.6 and (-player.global_basis.z).dot(offset.normalized()) < 0.25:
		return false
	var from := player.global_position + Vector3.UP * 0.8
	var to := body.global_position + Vector3.UP * 0.25
	var ray := PhysicsRayQueryParameters3D.create(from, to, 1, [player.get_rid()])
	return player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _id(offer: Dictionary) -> String:
	var target: Object = offer.get("target")
	return offer.kind + str(target.get_instance_id() if is_instance_valid(target) else 0)

func cycle(direction: int) -> bool:
	refresh()
	if offers.size() < 2:
		return false
	selected = posmod(selected + direction, offers.size())
	chosen_id = _id(offers[selected])
	return true

func activate() -> bool:
	refresh()
	if offers.is_empty() or not offers[selected].enabled:
		return false
	var offer: Dictionary = offers[selected]
	match offer.kind:
		"door":
			return offer.target.activate()
		"body":
			player.weapon.director.body_in_reach = offer.target
			player.weapon.director.open_loot_menu()
			return true
		"climb":
			return player.try_climb()
	return false

func button_hint() -> String:
	var pads := Input.get_connected_joypads()
	var device := Input.get_joy_name(pads[0]).to_lower() if not pads.is_empty() else ""
	return "F / X" if "nintendo" in device or "switch" in device else "F / △" if "sony" in device or "dualsense" in device or "dualshock" in device else "F / Y"
