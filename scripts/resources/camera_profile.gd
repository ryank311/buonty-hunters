class_name CameraProfile
extends Resource

@export_range(50.0, 80.0) var field_of_view: float = 60.0
@export_range(1.5, 5.0) var distance: float = 3.0
@export_range(-0.6, 0.6) var shoulder_offset: float = 0.0
@export_range(0.0, 1.4) var height_offset: float = 0.85
@export var mouse_sensitivity: float = 0.0025
@export var pad_sensitivity: float = 2.5
@export var pad_deadzone: float = 0.18
@export var pad_aim_multiplier: float = 0.6
@export_range(0.0, 1.0) var vibration: float = 0.45
@export var invert_y: bool = false
@export_range(0.0, 0.5) var hud_opacity: float = 0.18
