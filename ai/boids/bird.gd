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
## Set by the flock: height above the ground at a position, and the up direction there (radial on
## the celestial body), so shot-down birds fall the right way and land on the terrain.
var altitude: Callable
var up: Callable

var _dead: bool = false
var _fall_time: float = 0.0
var _landed_time: float = -1.0

@onready var _damageable: Damageable = $Damageable


func _ready() -> void:
	add_to_group("bird")
	_damageable.died.connect(_on_died)


func is_dead() -> bool:
	return _dead


## Moves the bird and points it along its velocity in a single transform write (each write is a
## physics-server update, so the flock does one per bird per tick instead of two).
func set_motion(new_position: Vector3, new_velocity: Vector3) -> void:
	velocity = new_velocity
	var heading: Basis = global_basis
	if velocity.length_squared() > 0.01:
		var forward: Vector3 = velocity.normalized()
		if absf(forward.dot(Vector3.UP)) > 0.95:
			forward = Vector3.FORWARD
		heading = Basis.looking_at(forward, Vector3.UP)
	global_transform = Transform3D(heading, new_position)


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
	var up_here: Vector3 = up.call(global_position) if up.is_valid() else Vector3.UP
	velocity -= up_here * FALL_GRAVITY * delta
	global_position += velocity * delta
	rotate_object_local(Vector3.RIGHT, deg_to_rad(FALL_SPIN_DEGREES_PER_SECOND) * delta)
	var height: float = altitude.call(global_position) if altitude.is_valid() else INF
	if height <= 0.1 or _fall_time >= MAX_FALL_SECONDS:
		if height < 0.1:
			global_position += up_here * (0.1 - height)
		_landed_time = 0.0
