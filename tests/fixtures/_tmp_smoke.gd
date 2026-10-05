extends Node3D
func _ready() -> void:
	var cloud := preload("res://scripts/combat/smoke_cloud.gd").new()
	add_child(cloud)
	cloud.start(5.0, 40.0)
