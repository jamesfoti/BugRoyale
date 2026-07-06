extends Node3D
class_name Bird
## Single flock bird visual. Movement is driven by BirdFlock.


const CONE_HEIGHT: float = 0.42
const CONE_RADIUS: float = 0.13

var velocity: Vector3 = Vector3.ZERO
var attack_cooldown: float = 0.0

var _mesh: MeshInstance3D


func _ready() -> void:
	add_to_group("bird")
	_build_cone_visual()


func set_velocity(new_velocity: Vector3) -> void:
	velocity = new_velocity
	if velocity.length_squared() > 0.01:
		var forward: Vector3 = velocity.normalized()
		if absf(forward.dot(Vector3.UP)) > 0.95:
			forward = Vector3.FORWARD
		look_at(global_position + forward, Vector3.UP)


func tick_cooldown(delta: float) -> void:
	attack_cooldown = maxf(attack_cooldown - delta, 0.0)


func can_attack() -> bool:
	return attack_cooldown <= 0.0


func reset_attack_cooldown(duration: float) -> void:
	attack_cooldown = duration


func _build_cone_visual() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "Body"

	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = CONE_RADIUS
	cone.height = CONE_HEIGHT
	_mesh.mesh = cone

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.28, 0.24, 0.2)
	material.roughness = 0.72
	material.metallic = 0.05
	_mesh.material_override = material
	_mesh.rotation.x = -PI * 0.5
	_mesh.position.z = CONE_HEIGHT * 0.5
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mesh)
