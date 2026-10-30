class_name CelestialBodyPlayer
extends FighterBody
## Walks on spherical terrain: the pilot's yaw turns the body, forward/back moves along the
## view. Every intent comes from the FighterController (keyboard, bot or network); the mouse
## reaches the body only as the snapshot's yaw_delta.

const _INPUT_DEADZONE: float = 0.01
const _SPAWN_ATTEMPTS: int = 12
const _SPAWN_RAY_MARGIN: float = 40.0
const _FALLBACK_BODY_RADIUS: float = 18.0

@export var celestial_body: Node3D
@export var speed: float = 5.0
@export var run_speed: float = 8.0
@export var jump_velocity: float = 4.5
@export var gravity_strength: float = 9.8
@export var surface_align_speed: float = 10.0
@export var mouse_sensitivity: float = 0.0025
@export var spawn_clearance: float = 1.2

@export_group("Flight")
## Set by the class stats (CharacterSkin.apply_class_stats) for flying bugs.
@export var can_fly: bool = false
@export var fly_speed: float = 7.0
@export var fly_run_speed: float = 11.0
@export var fly_vertical_speed: float = 5.0

var _gravity_direction: Vector3 = Vector3.DOWN
var _celestial_body: CelestialBody
var _flying: bool = false

@onready var _orbit_camera: OrbitCamera = get_node_or_null("OrbitCamera") as OrbitCamera


func is_flying() -> bool:
	return _flying


func get_surface_up() -> Vector3:
	return _get_up()


func _ready() -> void:
	super()
	_cache_body_refs()
	if auto_spawn:
		call_deferred("_spawn_on_body")


func _unhandled_input(event: InputEvent) -> void:
	_handle_ui_input(event)


func _physics_process(delta: float) -> void:
	if celestial_body == null or not _spawned or not _in_play:
		return
	sample_input(delta)

	_update_gravity_direction()
	up_direction = _get_up()
	if _intent.yaw_delta != 0.0:
		_apply_yaw(_intent.yaw_delta)

	if _terrain_focus or is_ui_blocking():
		_apply_focus_physics(delta)
		if _terrain_focus:
			_align_up_to_body(delta, _get_flat_forward())
		move_and_slide()
		_update_animation(Vector3.ZERO)
		return

	var movement_direction: Vector3 = _get_movement_direction()
	if _flying:
		_apply_flight(movement_direction)
	else:
		_apply_movement(delta, movement_direction)

	var facing_direction: Vector3 = _get_facing_direction(movement_direction)
	if movement_direction.length_squared() > _MIN_DIR_LEN_SQ:
		if _intent.move.y > _INPUT_DEADZONE and _orbit_camera != null:
			_orbit_camera.recenter_yaw(delta)
		_align_up_to_body(delta, facing_direction)
	elif not _is_camera_orbiting():
		_orthonormalize_basis()
	move_and_slide()
	_update_animation(movement_direction)


func _apply_movement(delta: float, movement_direction: Vector3) -> void:
	var move_speed: float = run_speed if _intent.run else speed
	var radial_speed: float = velocity.dot(_gravity_direction)

	if movement_direction.length_squared() > _MIN_DIR_LEN_SQ:
		velocity = movement_direction * move_speed + _gravity_direction * radial_speed
	elif is_on_floor():
		velocity = Vector3.ZERO

	if not is_on_floor():
		velocity += _gravity_direction * gravity_strength * delta

	if _intent.jump_pressed and is_on_floor() and not _skin.is_waving():
		velocity += _get_up() * jump_velocity
	elif _intent.jump_pressed and can_fly and not is_on_floor():
		# Take off: keep horizontal speed, cancel any falling speed.
		_flying = true
		velocity -= _gravity_direction * maxf(velocity.dot(_gravity_direction), 0.0)


## Flight: no gravity; forward/back move along the surface, hold Jump to rise, Descend to sink.
## Touching down without rising lands.
func _apply_flight(movement_direction: Vector3) -> void:
	var horizontal_speed: float = fly_run_speed if _intent.run else fly_speed
	var vertical: float = 0.0
	if _intent.jump_held:
		vertical += fly_vertical_speed
	if _intent.descend_held:
		vertical -= fly_vertical_speed
	velocity = movement_direction * horizontal_speed + _get_up() * vertical
	if is_on_floor() and vertical <= 0.0:
		_flying = false


func _apply_focus_physics(delta: float) -> void:
	var radial_speed: float = velocity.dot(_gravity_direction)
	if is_on_floor():
		velocity = Vector3.ZERO
	else:
		velocity = _gravity_direction * radial_speed
		velocity += _gravity_direction * gravity_strength * delta


## Turns the body about its up by the pilot's yaw for this frame.
func _apply_yaw(radians: float) -> void:
	var surface_up: Vector3 = _get_up()
	if surface_up.length_squared() > _MIN_DIR_LEN_SQ:
		global_basis = Basis(surface_up, radians) * global_basis


func _is_camera_orbiting() -> bool:
	return _intent.orbiting


func _update_gravity_direction() -> void:
	var to_center: Vector3 = _get_body_center() - global_position
	if to_center.length_squared() > _MIN_DIR_LEN_SQ:
		_gravity_direction = to_center.normalized()


func _get_up() -> Vector3:
	return -_gravity_direction


func _get_body_center() -> Vector3:
	if _celestial_body != null:
		return _celestial_body.global_position + _celestial_body.sphere_center
	if celestial_body is CelestialBody:
		var assigned_body: CelestialBody = celestial_body as CelestialBody
		return assigned_body.global_position + assigned_body.sphere_center
	if celestial_body != null:
		return celestial_body.global_position
	return Vector3.ZERO


func _get_flat_forward() -> Vector3:
	var surface_up: Vector3 = _get_up()
	var forward: Vector3 = (-global_transform.basis.z).slide(surface_up)
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		forward = global_transform.basis.x.slide(surface_up)
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		forward = surface_up.cross(Vector3.RIGHT)
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		forward = surface_up.cross(Vector3.FORWARD)
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		return Vector3.ZERO
	return forward.normalized()


func _get_movement_direction() -> Vector3:
	var forward_backward_input: float = _intent.move.y
	if absf(forward_backward_input) < _INPUT_DEADZONE:
		return Vector3.ZERO
	var forward: Vector3 = get_view_flat_forward()
	if forward == Vector3.ZERO:
		return Vector3.ZERO
	return forward * forward_backward_input


func _get_facing_direction(movement_direction: Vector3) -> Vector3:
	# Shooter stance: aiming or firing squares the body up to the view.
	var firing: bool = (
		_shooter != null and _shooter.has_method("is_firing") and _shooter.call("is_firing")
	)
	if _intent.aiming or firing:
		var view_forward: Vector3 = get_view_flat_forward()
		if view_forward != Vector3.ZERO:
			return view_forward
	if movement_direction.length_squared() < _MIN_DIR_LEN_SQ:
		return _get_flat_forward()
	# Backpedal: keep facing the view so body rotation does not spin the camera.
	if _intent.move.y < -_INPUT_DEADZONE:
		var view_forward: Vector3 = get_view_flat_forward()
		if view_forward != Vector3.ZERO:
			return view_forward
	return movement_direction.normalized()


func _align_up_to_body(delta: float, facing_direction: Vector3) -> void:
	var surface_up: Vector3 = _get_up()
	if facing_direction.length_squared() < _MIN_DIR_LEN_SQ:
		return

	var target_basis: Basis = (
		Basis.looking_at(facing_direction.normalized(), surface_up).orthonormalized()
	)
	var alignment_blend: float = minf(1.0, surface_align_speed * delta)
	var current_rotation: Quaternion = global_transform.basis.get_rotation_quaternion()
	var target_rotation: Quaternion = target_basis.get_rotation_quaternion()
	if current_rotation.dot(target_rotation) < 0.0:
		target_rotation = -target_rotation
	global_transform.basis = Basis(current_rotation.slerp(target_rotation, alignment_blend))


func _orthonormalize_basis() -> void:
	global_transform.basis = global_transform.basis.orthonormalized()


func _cache_body_refs() -> void:
	if celestial_body == null:
		celestial_body = get_tree().get_first_node_in_group("celestial_body") as Node3D
	if celestial_body is CelestialBody:
		_celestial_body = celestial_body as CelestialBody


func respawn_random() -> void:
	_cache_body_refs()
	_apply_spawn(_find_random_surface_spawn())


## Stands the bug on the sphere at a spot: its up is the radial through the spot.
func _place_at(position_on_map: Vector3) -> void:
	_cache_body_refs()
	var spawn_data: SpawnData = SpawnData.new()
	spawn_data.position = position_on_map
	var radial: Vector3 = position_on_map - _get_body_center()
	spawn_data.surface_up = (
		radial.normalized() if radial.length_squared() > _MIN_DIR_LEN_SQ else Vector3.UP
	)
	spawn_data.forward = _tangent_forward_on_plane(spawn_data.surface_up)
	spawn_data.from_raycast_hit = true
	_apply_spawn(spawn_data)


func _spawn_on_body() -> void:
	_cache_body_refs()
	if celestial_body == null:
		push_warning("[CelestialBodyPlayer] No celestial_body assigned.")
		return

	var spawn_data: SpawnData = SpawnData.new()
	for _attempt: int in _SPAWN_ATTEMPTS:
		await get_tree().physics_frame
		spawn_data = _find_random_surface_spawn()
		if spawn_data.from_raycast_hit:
			break

	_apply_spawn(spawn_data)


func _apply_spawn(spawn_data: SpawnData) -> void:
	global_transform = Transform3D(
		Basis.looking_at(spawn_data.forward, spawn_data.surface_up), spawn_data.position
	)
	velocity = Vector3.ZERO
	_terrain_focus = false
	_flying = false
	_anim_state = ""
	_update_gravity_direction()
	if _orbit_camera != null:
		_orbit_camera.rotation = Vector3(_orbit_camera.rotation.x, 0.0, _orbit_camera.rotation.z)
	_skin.set_state("idle")
	_spawned = true


func _find_random_surface_spawn() -> SpawnData:
	var spawn_data: SpawnData = SpawnData.new()
	var random_direction: Vector3 = (
		Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
		)
		. normalized()
	)
	var body_center: Vector3 = _get_body_center()
	var body_radius: float = (
		_celestial_body.get_sphere_radius() if _celestial_body != null else _FALLBACK_BODY_RADIUS
	)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		body_center + random_direction * (body_radius + _SPAWN_RAY_MARGIN),
		body_center - random_direction * (body_radius + _SPAWN_RAY_MARGIN)
	)
	ray_query.collide_with_areas = false
	var raycast_hit: Dictionary = space.intersect_ray(ray_query)
	if not raycast_hit.is_empty() and not _is_body_collider(raycast_hit.get("collider")):
		raycast_hit = {}
	if raycast_hit.is_empty():
		spawn_data.position = body_center + random_direction * (body_radius + spawn_clearance)
		spawn_data.surface_up = random_direction
		spawn_data.forward = _tangent_forward_on_plane(random_direction)
		spawn_data.from_raycast_hit = false
		return spawn_data

	var surface_up: Vector3 = raycast_hit.normal
	spawn_data.position = raycast_hit.position + surface_up * spawn_clearance
	spawn_data.surface_up = surface_up
	spawn_data.forward = _tangent_forward_on_plane(surface_up)
	spawn_data.from_raycast_hit = true
	return spawn_data


func _is_body_collider(collider: Variant) -> bool:
	if celestial_body == null or not (collider is Node):
		return false
	var node: Node = collider as Node
	return celestial_body == node or celestial_body.is_ancestor_of(node)


func _tangent_forward_on_plane(surface_up: Vector3) -> Vector3:
	var forward: Vector3 = surface_up.cross(Vector3.FORWARD)
	if forward.length_squared() < 0.01:
		forward = surface_up.cross(Vector3.RIGHT)
	return forward.normalized()


func _update_animation(movement_direction: Vector3) -> void:
	var skin: CharacterSkin = _skin
	if skin.is_waving():
		return

	var vertical_speed: float = velocity.dot(_get_up())
	if _flying:
		_set_anim_state(skin, "fly")
	elif not is_on_floor():
		_set_anim_state(skin, "jump" if vertical_speed > 0.05 else "fall")
	elif movement_direction.length_squared() > _MIN_DIR_LEN_SQ:
		_set_anim_state(skin, "run" if _intent.run else "walk")
	else:
		_set_anim_state(skin, "idle")


class SpawnData:
	var position: Vector3 = Vector3.ZERO
	var surface_up: Vector3 = Vector3.UP
	var forward: Vector3 = Vector3.FORWARD
	var from_raycast_hit: bool = false
