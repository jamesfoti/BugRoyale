extends Node3D
class_name Bird
## Single flock bird. Movement is driven by BirdFlock, which also draws every bird's cone
## in one MultiMeshInstance3D.


var velocity: Vector3 = Vector3.ZERO
var attack_cooldown: float = 0.0


func _ready() -> void:
	add_to_group("bird")


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
