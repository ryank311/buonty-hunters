extends StaticBody3D

@export var travel: float = 0.0
var start_position: Vector3
var elapsed: float = 0.0
var flash_remaining: float = 0.0
var last_damage: float = 0.0
var damage_taken: float = 0.0
var material: StandardMaterial3D

func _ready() -> void:
	start_position = position
	material = StandardMaterial3D.new()
	material.albedo_color = Color("496b69")
	material.roughness = 1.0
	$MeshInstance3D.material_override = material

func _physics_process(delta: float) -> void:
	elapsed += delta
	position.x = start_position.x + sin(elapsed * 0.7) * travel
	flash_remaining = maxf(0.0, flash_remaining - delta)
	material.albedo_color = Color("d9af63") if flash_remaining > 0.0 else Color("496b69")

func register_hit() -> void:
	flash_remaining = 0.22

## Practice targets never fall; they report what each hit would have done.
func apply_damage(amount: float, _info: Dictionary = {}) -> float:
	last_damage = amount
	damage_taken += amount
	register_hit()
	return amount

func reset_target() -> void:
	elapsed = 0.0
	flash_remaining = 0.0
	last_damage = 0.0
	damage_taken = 0.0
	position = start_position
