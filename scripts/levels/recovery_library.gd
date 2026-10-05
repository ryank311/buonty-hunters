extends RefCounted
## Shared data stays loaded once; players bind relative to their own skeleton.

const CATALOGUE := "res://resources/recovered/catalogue.json"
const ORIGINAL := "res://resources/recovered/native.res"

static func catalogue() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(CATALOGUE))

static func attach(model: Node3D, library: AnimationLibrary = null) -> Node:
	for old: Node in model.find_children("*", "AnimationPlayer", true, false):
		old.get_parent().remove_child(old)
		old.queue_free()
	var player := preload("res://scripts/actors/native_motion_player.gd").new()
	player.name = "RecoveredAnimation"
	model.add_child(player)
	player.bind(model, library if library != null else load(ORIGINAL))
	return player
