extends BerryRagdollController
class_name BerryPlanetPlayer
## Active ragdoll that walks on spherical planet terrain.


const _MIN_DIR_LEN_SQ: float = 0.0001
const _SPAWN_ATTEMPTS: int = 12
const _SPAWN_RAY_MARGIN: float = 40.0
const _FALLBACK_PLANET_RADIUS: float = 18.0

@export var planet: Node3D
@export var gravity_strength: float = 9.8
@export var surface_align_speed: float = 10.0
@export var spawn_clearance: float = 1.2

var _planet: Planet
var _gravity_direction: Vector3 = Vector3.DOWN
var _spawned: bool = false


func respawn_random() -> void:
	_cache_planet_refs()
	_apply_spawn(_find_random_surface_spawn())


func _cache_planet_refs() -> void:
	if planet == null:
		planet = get_tree().get_first_node_in_group("planet") as Node3D
	if planet is Planet:
		_planet = planet as Planet


func _snap_to_ground_when_ready() -> void:
	_cache_planet_refs()
	if planet == null:
		push_warning("[BerryPlanetPlayer] No planet assigned.")
		return
	var spawn_data: Dictionary = _find_random_surface_spawn()
	for _attempt: int in range(_SPAWN_ATTEMPTS):
		await get_tree().physics_frame
		spawn_data = _find_random_surface_spawn()
		if spawn_data.get("from_raycast_hit", false):
			break
	_apply_spawn(spawn_data)


func _apply_spawn(spawn_data: Dictionary) -> void:
	var surface_up: Vector3 = spawn_data.get("surface_up", Vector3.UP)
	var forward: Vector3 = spawn_data.get("forward", Vector3.FORWARD)
	global_transform = Transform3D(Basis.looking_at(forward, surface_up), spawn_data.get("position", Vector3.ZERO))
	velocity = Vector3.ZERO
	_update_gravity_direction()
	_spawned = true


func _process(_delta: float) -> void:
	if get_tree().paused or not _spawned:
		return
	var yaw: float = _mouse_delta.x * mouse_sensitivity
	_mouse_delta = Vector2.ZERO
	if absf(yaw) > 0.0001:
		var surface_up: Vector3 = _get_up()
		if surface_up.length_squared() > _MIN_DIR_LEN_SQ:
			global_basis = Basis(surface_up, deg_to_rad(-yaw)) * global_basis


func _physics_process(delta: float) -> void:
	if planet == null or not _spawned:
		return

	_update_gravity_direction()
	up_direction = _get_up()

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var move_direction: Vector3 = (
		transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	).slide(_get_up())
	if move_direction.length_squared() > _MIN_DIR_LEN_SQ:
		move_direction = move_direction.normalized()
	else:
		move_direction = Vector3.ZERO

	var move_speed: float = run_speed if Input.is_action_pressed("run") else speed
	var radial_speed: float = velocity.dot(_gravity_direction)

	if move_direction.length_squared() > _MIN_DIR_LEN_SQ:
		velocity = move_direction * move_speed + _gravity_direction * radial_speed
		_align_up_to_planet(delta, move_direction)
	elif is_on_floor():
		velocity = Vector3.ZERO

	if not is_on_floor():
		velocity += _gravity_direction * gravity_strength * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity += _get_up() * jump_velocity

	_update_locomotion_anim()
	move_and_slide()


func _update_gravity_direction() -> void:
	var to_center: Vector3 = _get_planet_center() - global_position
	if to_center.length_squared() > _MIN_DIR_LEN_SQ:
		_gravity_direction = to_center.normalized()


func _get_up() -> Vector3:
	return -_gravity_direction


func _get_planet_center() -> Vector3:
	if _planet != null:
		return _planet.global_position + _planet.sphere_center
	if planet is Planet:
		var assigned_planet: Planet = planet as Planet
		return assigned_planet.global_position + assigned_planet.sphere_center
	if planet != null:
		return planet.global_position
	return Vector3.ZERO


func _align_up_to_planet(delta: float, facing_direction: Vector3) -> void:
	var surface_up: Vector3 = _get_up()
	if facing_direction.length_squared() < _MIN_DIR_LEN_SQ:
		return
	var target_basis: Basis = Basis.looking_at(facing_direction.normalized(), surface_up).orthonormalized()
	var alignment_blend: float = minf(1.0, surface_align_speed * delta)
	var current_rotation: Quaternion = global_transform.basis.get_rotation_quaternion()
	var target_rotation: Quaternion = target_basis.get_rotation_quaternion()
	if current_rotation.dot(target_rotation) < 0.0:
		target_rotation = -target_rotation
	global_transform.basis = Basis(current_rotation.slerp(target_rotation, alignment_blend))


func _find_random_surface_spawn() -> Dictionary:
	var spawn_data: Dictionary = {
		"position": Vector3.ZERO,
		"surface_up": Vector3.UP,
		"forward": Vector3.FORWARD,
		"from_raycast_hit": false,
	}
	var random_direction: Vector3 = Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
	).normalized()
	var planet_center: Vector3 = _get_planet_center()
	var planet_radius: float = (
		_planet.get_sphere_radius() if _planet != null else _FALLBACK_PLANET_RADIUS
	)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		planet_center + random_direction * (planet_radius + _SPAWN_RAY_MARGIN),
		planet_center - random_direction * (planet_radius + _SPAWN_RAY_MARGIN)
	)
	ray_query.collide_with_areas = false
	var raycast_hit: Dictionary = space.intersect_ray(ray_query)
	if not raycast_hit.is_empty() and not _is_planet_collider(raycast_hit.get("collider")):
		raycast_hit = {}
	if raycast_hit.is_empty():
		spawn_data.position = planet_center + random_direction * (planet_radius + spawn_clearance)
		spawn_data.surface_up = random_direction
		spawn_data.forward = _tangent_forward_on_plane(random_direction)
		return spawn_data

	var hit_position: Vector3 = raycast_hit.position
	var surface_up: Vector3 = (hit_position - planet_center).normalized()
	spawn_data.position = hit_position + surface_up * spawn_clearance
	spawn_data.surface_up = surface_up
	spawn_data.forward = _tangent_forward_on_plane(surface_up)
	spawn_data.from_raycast_hit = true
	return spawn_data


func _tangent_forward_on_plane(surface_up: Vector3) -> Vector3:
	var forward: Vector3 = Vector3.FORWARD.slide(surface_up)
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		forward = Vector3.RIGHT.slide(surface_up)
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		forward = surface_up.cross(Vector3.RIGHT)
	return forward.normalized() if forward.length_squared() > _MIN_DIR_LEN_SQ else Vector3.FORWARD


func _is_planet_collider(collider: Variant) -> bool:
	if planet == null or not (collider is Node):
		return false
	var node: Node = collider as Node
	return planet == node or planet.is_ancestor_of(node)
