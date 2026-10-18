extends AnimatableBody3D
class_name Bird
## Single flock bird. Movement is driven by BirdFlock, which also draws every bird's cone
## in one MultiMeshInstance3D. Shots hit its sphere (collision layer 4, which the player body
## ignores) and damage its Damageable; at zero health it tumbles to the ground and is removed.

signal killed(bird: Bird)

const FALL_GRAVITY: float = 22.0
const FALL_SPIN_DEGREES_PER_SECOND: float = 540.0
## Seconds a dead bird stays on the ground before it disappears.
const GROUND_LINGER_SECONDS: float = 1.5
const MAX_FALL_SECONDS: float = 6.0

var velocity: Vector3 = Vector3.ZERO
var attack_cooldown: float = 0.0
## Returns the ground height under a position; set by the flock so falling birds land on terrain.
var ground_height: Callable

var _dead: bool = false
var _fall_time: float = 0.0
var _landed_time: float = -1.0

@onready var _damageable: Damageable = $Damageable


func _ready() -> void:
	add_to_group("bird")
	_damageable.died.connect(_on_died)


func is_dead() -> bool:
	return _dead


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
	return not _dead and attack_cooldown <= 0.0


func reset_attack_cooldown(duration: float) -> void:
	attack_cooldown = duration


func _on_died() -> void:
	_dead = true
	# Later shots pass through the falling body.
	collision_layer = 0
	velocity = Vector3(velocity.x * 0.4, minf(velocity.y, 0.0), velocity.z * 0.4)
	killed.emit(self)


func _physics_process(delta: float) -> void:
	if not _dead:
		return
	if _landed_time >= 0.0:
		_landed_time += delta
		if _landed_time >= GROUND_LINGER_SECONDS:
			queue_free()
		return
	_fall_time += delta
	velocity.y -= FALL_GRAVITY * delta
	global_position += velocity * delta
	rotate_object_local(Vector3.RIGHT, deg_to_rad(FALL_SPIN_DEGREES_PER_SECOND) * delta)
	var floor_y: float = ground_height.call(global_position) if ground_height.is_valid() else -INF
	if global_position.y <= floor_y + 0.1 or _fall_time >= MAX_FALL_SECONDS:
		global_position.y = maxf(global_position.y, floor_y + 0.1)
		_landed_time = 0.0
