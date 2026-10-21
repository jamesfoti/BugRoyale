extends CharacterBody3D
class_name GroundPlayer
## Shared third-person bug controller for flat worlds (open, boxed-in and terrarium terrain).
## Camera-relative movement. Walking is always upright (steep slopes act as walls); holding forward
## into a steep wall for a moment (or pressing Climb) grabs it: the body's up becomes the surface
## normal and gravity sticks it on, ledges wrap, and cresting onto flat ground pulls up and walks
## on. Jump (or Climb) lets go. Flying classes (see CharacterSkin) take off with Jump in mid-air.
## Subclasses supply the terrain lookup and spawn point.

const _MIN_DIR_LEN_SQ: float = 0.0001
const _INPUT_DEADZONE: float = 0.01
const _SPAWN_ATTEMPTS: int = 12
const _SPAWN_RAY_HEIGHT: float = 80.0
## Height of the collision capsule's center above the feet.
const _BODY_CENTER_HEIGHT: float = 0.6
const DESCEND_ACTION: StringName = &"descend"
const CLIMB_ACTION: StringName = &"climb"

@export var terrain: Node3D
@export var speed: float = 5.0
@export var run_speed: float = 8.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.0025
@export var spawn_clearance: float = 1.2

@export_group("Climbing")
## Surfaces at least this steep (degrees from straight up) can be climbed.
@export_range(10.0, 90.0, 1.0) var climb_min_angle_degrees: float = 40.0
## Climbing ends (the bug pulls up and walks) on ground within this angle of flat.
@export_range(0.0, 45.0, 1.0) var upright_ground_angle_degrees: float = 25.0
## How quickly the body turns to match a new surface.
@export var surface_align_speed: float = 9.0
## How far in front of the bug the Climb key (optional shortcut) looks for a surface to grab.
@export var climb_reach: float = 1.2
## Seconds of holding forward against a steep wall before the bug starts climbing it.
@export var climb_push_seconds: float = 0.3
@export var climb_speed: float = 3.5
## Climbing speed while holding Run.
@export var climb_run_speed: float = 5.0
## Gravity multiplier pulling the bug into the surface it is climbing.
@export var climb_stick_strength: float = 2.0
## Seconds a climber may lose contact (e.g. cresting a ledge) before it falls off.
@export var climb_grace_seconds: float = 0.25
## How quickly the surface up eases toward the ground under the bug (higher = snappier).
@export var surface_follow_speed: float = 8.0
## Spread of the rays that average the ground normal.
@export var surface_sample_radius: float = 0.3

@export_group("Flight")
## Set by the class stats (CharacterSkin.apply_class_stats) for flying bugs.
@export var can_fly: bool = false
@export var fly_speed: float = 7.0
@export var fly_run_speed: float = 11.0
@export var fly_vertical_speed: float = 5.0

## The selected character is installed under VisualRoot on ready.
@onready var _skin: CharacterSkin = CharacterSkin.install_selected($VisualRoot)
@onready var _visual_root: Node3D = $VisualRoot
@onready var _orbit_camera: OrbitCamera = $OrbitCamera
@onready var _camera: Camera3D = $OrbitCamera/Camera3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _anim_state: String = ""
var _want_jump: bool = false
var _spawned: bool = false
var _terrain_focus: bool = false
var _visual_rest_basis: Basis = Basis.IDENTITY
## Up of the surface the bug is attached to (world up on normal ground).
var _surface_up: Vector3 = Vector3.UP
var _climbing: bool = false
var _detached_time: float = 0.0
var _last_move_direction: Vector3 = Vector3.ZERO
var _flying: bool = false
var _want_climb_toggle: bool = false
var _wall_push_time: float = 0.0


func is_terrain_focus_active() -> bool:
	return _terrain_focus


func exit_terrain_focus() -> void:
	_set_terrain_focus(false)


func is_climbing() -> bool:
	return _climbing


func is_flying() -> bool:
	return _flying


func _ready() -> void:
	_visual_rest_basis = _visual_root.transform.basis
	_cache_terrain_refs()
	call_deferred("_spawn_on_terrain")
	call_deferred("_connect_terrain_hud")


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if _is_item_menu_open():
		if event.is_action_pressed("item_menu"):
			_toggle_item_menu()
			get_viewport().set_input_as_handled()
		return
	if _terrain_focus and event.is_action_pressed("ui_cancel"):
		_set_terrain_focus(false)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("terrain_focus"):
		if not _terrain_focus and not _is_terrain_edit_active():
			return
		_set_terrain_focus(not _terrain_focus)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("jump"):
		_want_jump = true
	if event.is_action_pressed(CLIMB_ACTION):
		_want_climb_toggle = true
	if event.is_action_pressed("item_menu"):
		_toggle_item_menu()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if terrain == null or not _spawned:
		return

	if _terrain_focus:
		_want_jump = false
		_want_climb_toggle = false
		_apply_idle_physics(delta)
		_align_visual_to_facing(delta, _get_flat_forward())
		_finish_physics_step(delta)
		_update_animation(Vector3.ZERO)
		return

	if _is_item_menu_open():
		_want_jump = false
		_want_climb_toggle = false
		_apply_idle_physics(delta)
		_finish_physics_step(delta)
		_update_animation(Vector3.ZERO)
		return

	var movement_direction: Vector3 = _get_movement_direction()
	if _want_climb_toggle:
		_want_climb_toggle = false
		_toggle_climb()
		if _climbing:
			# Grabbing a wall mid-flight ends the flight.
			_flying = false
	if _flying:
		_apply_flight(delta, movement_direction)
	else:
		_update_surface(delta, movement_direction)
		_apply_movement(delta, movement_direction)

	if movement_direction.length_squared() > _MIN_DIR_LEN_SQ:
		_last_move_direction = movement_direction
	if _is_aiming_or_firing():
		# Shooter stance: the body squares up to the camera so the gun points where the
		# crosshair does, whichever way the legs are going.
		_align_visual_to_facing(delta, _get_camera_flat_forward())
	elif movement_direction.length_squared() > _MIN_DIR_LEN_SQ:
		_align_visual_to_facing(delta, movement_direction)
	_finish_physics_step(delta)
	_update_animation(movement_direction)


func _is_aiming_or_firing() -> bool:
	if _orbit_camera.is_aiming():
		return true
	var shooter: Node = get_node_or_null("ShooterTest")
	return shooter != null and shooter.has_method("is_firing") and shooter.call("is_firing")


## Turns the body toward the current surface up, then moves.
func _finish_physics_step(delta: float) -> void:
	up_direction = _surface_up
	_align_body_to_surface(delta)
	move_and_slide()


# --- Surface tracking (climbing) -------------------------------------------------------------

func _update_surface(delta: float, movement_direction: Vector3) -> void:
	if not _climbing:
		# Walking is always upright; steep slopes act as walls. Holding forward into one for a
		# moment (no key needed) starts climbing it.
		_surface_up = _ease_direction(_surface_up, Vector3.UP, surface_follow_speed * delta)
		var pushed_wall: Vector3 = _find_wall_pushed_forward(movement_direction)
		if pushed_wall == Vector3.ZERO:
			_wall_push_time = 0.0
			return
		_wall_push_time += delta
		if _wall_push_time >= climb_push_seconds:
			_start_climb(pushed_wall)
		return

	var target_up: Vector3 = _surface_up
	if is_on_floor():
		_detached_time = 0.0
		var ground_normal: Vector3 = _sample_surface_normal(get_floor_normal())
		if _angle_degrees(ground_normal, Vector3.UP) <= upright_ground_angle_degrees:
			# Reached walkable ground (e.g. crested the top of a wall): pull up and walk on.
			_detach()
			target_up = Vector3.UP
		else:
			target_up = ground_normal
			# Pushing into a connecting surface (inside corner, overhang) transfers onto it.
			var wall_normal: Vector3 = _find_wall_to_climb(movement_direction)
			if wall_normal != Vector3.ZERO:
				target_up = wall_normal
	else:
		# Lost contact while climbing: follow a curving surface or wrap over a ledge.
		var surface_hit: Dictionary = _probe_surface(movement_direction)
		if not surface_hit.is_empty():
			_detached_time = 0.0
			target_up = surface_hit.normal
		else:
			_detached_time += delta
			if _detached_time > climb_grace_seconds:
				_detach()
	# Ease toward the target so bumpy surfaces don't jerk the body (and camera) around.
	_surface_up = _ease_direction(_surface_up, target_up, surface_follow_speed * delta)


## Climb key: grab a steep surface within reach (works mid-jump too), or let go if climbing.
func _toggle_climb() -> void:
	if _climbing:
		_detach()
		return
	var center: Vector3 = global_position + _surface_up * _BODY_CENTER_HEIGHT
	var directions: Array[Vector3] = [_get_flat_forward(), _get_camera_flat_forward()]
	if _last_move_direction.length_squared() > _MIN_DIR_LEN_SQ:
		directions.push_front(_last_move_direction.normalized())
	for direction: Vector3 in directions:
		for height: float in [0.0, 0.4, -0.3]:
			var from: Vector3 = center + _surface_up * height
			var hit: Dictionary = _cast(from, from + direction * climb_reach)
			if hit.is_empty() or _angle_degrees(hit.normal, Vector3.UP) < climb_min_angle_degrees:
				continue
			_start_climb(hit.normal)
			return


func _start_climb(surface_normal: Vector3) -> void:
	_climbing = true
	_detached_time = 0.0
	_wall_push_time = 0.0
	# Snap the movement frame to the wall now; the body and camera turn to it smoothly.
	_surface_up = surface_normal
	velocity = -surface_normal * 2.0


## Normal of a steep wall the player is holding forward into (Vector3.ZERO if none).
func _find_wall_pushed_forward(movement_direction: Vector3) -> Vector3:
	if Input.get_axis("move_backward", "move_forward") < 0.5:
		return Vector3.ZERO
	for collision_index: int in get_slide_collision_count():
		var normal: Vector3 = get_slide_collision(collision_index).get_normal()
		if _angle_degrees(normal, Vector3.UP) < climb_min_angle_degrees:
			continue
		if movement_direction.dot(-normal) < 0.5:
			continue
		return normal
	return Vector3.ZERO


## Averages the ground normal under five points around the body, so small bumps on rough terrain
## don't each swing the body's up.
func _sample_surface_normal(contact_normal: Vector3) -> Vector3:
	var up: Vector3 = _surface_up
	var tangent: Vector3 = up.cross(Vector3.RIGHT)
	if tangent.length_squared() < 0.01:
		tangent = up.cross(Vector3.FORWARD)
	tangent = tangent.normalized()
	var bitangent: Vector3 = up.cross(tangent).normalized()
	var center: Vector3 = global_position + up * _BODY_CENTER_HEIGHT
	var normal_sum: Vector3 = contact_normal
	for offset: Vector3 in [Vector3.ZERO, tangent, -tangent, bitangent, -bitangent]:
		var from: Vector3 = center + offset * surface_sample_radius
		var hit: Dictionary = _cast(from, from - up * (_BODY_CENTER_HEIGHT + 0.6))
		if not hit.is_empty():
			normal_sum += hit.normal
	return normal_sum.normalized() if normal_sum.length_squared() > _MIN_DIR_LEN_SQ else contact_normal


## Normal of a steep surface the player is pushing into (Vector3.ZERO if none).
func _find_wall_to_climb(movement_direction: Vector3) -> Vector3:
	if movement_direction.length_squared() < _MIN_DIR_LEN_SQ:
		return Vector3.ZERO
	for collision_index: int in get_slide_collision_count():
		var normal: Vector3 = get_slide_collision(collision_index).get_normal()
		if _angle_degrees(normal, _surface_up) < climb_min_angle_degrees:
			continue
		if movement_direction.dot(-normal) < 0.3:
			continue
		return normal
	return Vector3.ZERO


func _probe_surface(movement_direction: Vector3) -> Dictionary:
	var center: Vector3 = global_position + _surface_up * _BODY_CENTER_HEIGHT
	# Straight "down" relative to the surface (follows gentle curves).
	var hit: Dictionary = _cast(center, center - _surface_up * (_BODY_CENTER_HEIGHT + 0.5))
	if not hit.is_empty():
		return hit
	# Ledge wrap: from just past the old surface plane, look back the way we came.
	var travel: Vector3 = movement_direction if movement_direction.length_squared() > _MIN_DIR_LEN_SQ else _last_move_direction
	if travel.length_squared() < _MIN_DIR_LEN_SQ:
		return {}
	var past_edge: Vector3 = center - _surface_up * (_BODY_CENTER_HEIGHT + 0.25)
	return _cast(past_edge, past_edge - travel.normalized() * 1.2)


func _cast(from: Vector3, to: Vector3) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(query)


func _detach() -> void:
	_climbing = false
	_detached_time = 0.0


func _align_body_to_surface(delta: float) -> void:
	var current_up: Vector3 = global_basis.y.normalized()
	if current_up.is_equal_approx(_surface_up):
		return
	# Shortest rotation from the body's up to the surface up keeps the facing (and camera) stable.
	var full_turn: Quaternion = Quaternion(current_up, _surface_up.normalized())
	var step: Quaternion = Quaternion.IDENTITY.slerp(full_turn, minf(1.0, surface_align_speed * delta))
	global_basis = (Basis(step) * global_basis).orthonormalized()


## Rotates unit vector `from` toward `to` by a fraction of the way (weight clamped to 0..1).
## Avoids Vector3.slerp on (nearly) equal or opposite vectors, where its rotation axis degenerates.
static func _ease_direction(from: Vector3, to: Vector3, weight: float) -> Vector3:
	var t: float = clampf(weight, 0.0, 1.0)
	var alignment: float = from.dot(to)
	if alignment > 0.99999 or t >= 1.0:
		return to.normalized()
	if alignment < -0.999:
		return from.lerp(to, t).normalized() if not from.lerp(to, t).is_zero_approx() else from
	return from.slerp(to, t).normalized()


static func _angle_degrees(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(a.angle_to(b))


# --- Movement ---------------------------------------------------------------------------------

func _apply_movement(delta: float, movement_direction: Vector3) -> void:
	var running: bool = Input.is_action_pressed("run")
	var move_speed: float = run_speed if running else speed
	if _climbing:
		move_speed = climb_run_speed if running else climb_speed
	var up: Vector3 = _surface_up
	var vertical_speed: float = velocity.dot(up)
	var planar: Vector3 = Vector3.ZERO
	if movement_direction.length_squared() > _MIN_DIR_LEN_SQ:
		planar = movement_direction * move_speed
	elif not is_on_floor():
		planar = velocity - up * vertical_speed
	if is_on_floor() and vertical_speed < 0.0:
		vertical_speed = 0.0
	if _climbing and vertical_speed > 0.0:
		# A climber never leaves its surface on its own (cresting a slope would otherwise launch
		# it like a ramp); only a jump detaches it.
		vertical_speed = 0.0
	if _climbing and not is_on_floor():
		# Briefly lost contact (bump, ledge): pull firmly back onto the surface.
		vertical_speed = minf(vertical_speed, -3.0)

	velocity = planar + up * vertical_speed
	if not is_on_floor():
		if _climbing:
			velocity -= up * _gravity * climb_stick_strength * delta
		else:
			velocity += Vector3.DOWN * _gravity * delta

	if _want_jump and not _get_skin().is_waving():
		if is_on_floor():
			velocity += up * jump_velocity
			if _climbing:
				_detach()
		elif can_fly:
			_start_flight()
	_want_jump = false
	floor_snap_length = 0.45 if _climbing else 0.1


func _apply_idle_physics(delta: float) -> void:
	if _flying:
		velocity = Vector3.ZERO
		return
	if is_on_floor():
		velocity = Vector3.ZERO
	elif _climbing:
		velocity -= _surface_up * _gravity * climb_stick_strength * delta
	else:
		velocity += Vector3.DOWN * _gravity * delta


# --- Flight -----------------------------------------------------------------------------------

func _start_flight() -> void:
	_flying = true
	_climbing = false
	_surface_up = Vector3.UP
	velocity.y = maxf(velocity.y, 0.0)


func _apply_flight(_delta: float, movement_direction: Vector3) -> void:
	_surface_up = Vector3.UP
	var horizontal_speed: float = fly_run_speed if Input.is_action_pressed("run") else fly_speed
	var vertical: float = 0.0
	if Input.is_action_pressed("jump"):
		vertical += fly_vertical_speed
	if InputMap.has_action(DESCEND_ACTION) and Input.is_action_pressed(DESCEND_ACTION):
		vertical -= fly_vertical_speed
	velocity = movement_direction * horizontal_speed + Vector3.UP * vertical
	_want_jump = false
	# Touching down without climbing lands the wasp.
	if is_on_floor() and vertical <= 0.0:
		_flying = false


# --- Directions -------------------------------------------------------------------------------

func _get_flat_forward() -> Vector3:
	var forward: Vector3 = (-_visual_root.global_basis.z).slide(_surface_up)
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		forward = _visual_root.global_basis.x.slide(_surface_up)
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		return Vector3.FORWARD
	return forward.normalized()


func _get_camera_flat_forward() -> Vector3:
	var forward: Vector3 = (-_camera.global_basis.z).slide(_surface_up)
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		# Camera looking straight along the up axis: use its up vector instead.
		forward = _camera.global_basis.y.slide(_surface_up)
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		return _get_flat_forward()
	return forward.normalized()


func _get_camera_flat_right() -> Vector3:
	var forward: Vector3 = _get_camera_flat_forward()
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		return Vector3.ZERO
	return forward.cross(_surface_up).normalized()


func _get_movement_direction() -> Vector3:
	var forward_backward_input: float = Input.get_axis("move_backward", "move_forward")
	var left_right_input: float = Input.get_axis("move_left", "move_right")
	if absf(forward_backward_input) < _INPUT_DEADZONE and absf(left_right_input) < _INPUT_DEADZONE:
		return Vector3.ZERO
	var forward: Vector3 = _get_camera_flat_forward()
	var right: Vector3 = _get_camera_flat_right()
	if forward.length_squared() < _MIN_DIR_LEN_SQ and right.length_squared() < _MIN_DIR_LEN_SQ:
		return Vector3.ZERO
	var direction: Vector3 = forward * forward_backward_input + right * left_right_input
	if direction.length_squared() < _MIN_DIR_LEN_SQ:
		return Vector3.ZERO
	return direction.normalized()


## Turns the visual model (not the body) to face a direction lying in the surface plane.
func _align_visual_to_facing(delta: float, facing_direction: Vector3) -> void:
	if facing_direction.length_squared() < _MIN_DIR_LEN_SQ:
		return
	var local_facing: Vector3 = (global_basis.inverse() * facing_direction).slide(Vector3.UP)
	if local_facing.length_squared() < _MIN_DIR_LEN_SQ:
		return
	var target_basis: Basis = Basis.looking_at(local_facing.normalized(), Vector3.UP).orthonormalized()
	var alignment_blend: float = minf(1.0, 10.0 * delta)
	var current_rotation: Quaternion = _visual_root.basis.get_rotation_quaternion()
	var target_rotation: Quaternion = (target_basis * _visual_rest_basis).get_rotation_quaternion()
	if current_rotation.dot(target_rotation) < 0.0:
		target_rotation = -target_rotation
	_visual_root.basis = Basis(current_rotation.slerp(target_rotation, alignment_blend))


func _is_camera_orbiting() -> bool:
	return _orbit_camera.is_orbiting()


# --- Terrain and spawning (subclasses override the terrain-specific parts) -------------------

func _cache_terrain_refs() -> void:
	pass


## Returns {"position": Vector3, "from_raycast_hit": bool}.
func _find_random_surface_spawn() -> Dictionary:
	return {"position": Vector3(0.0, spawn_clearance, 0.0), "from_raycast_hit": false}


func _is_terrain_collider(collider: Variant) -> bool:
	if terrain == null or not (collider is Node):
		return false
	var node: Node = collider as Node
	return terrain == node or terrain.is_ancestor_of(node)


## Random spawn on a surface node that provides get_world_extents() and get_surface_height_at():
## raycasts down at a random spot, falling back to the surface height function.
func _raycast_spawn_over(surface: Node3D) -> Dictionary:
	var spawn_data: Dictionary = {"position": Vector3(0.0, spawn_clearance, 0.0), "from_raycast_hit": false}
	if surface == null:
		return spawn_data
	var world_extents: Vector3 = surface.get_world_extents()
	var random_offset: Vector3 = Vector3(
		randf_range(-world_extents.x * 0.4, world_extents.x * 0.4),
		0.0,
		randf_range(-world_extents.z * 0.4, world_extents.z * 0.4)
	)
	var column: Vector3 = surface.global_position + random_offset
	var raycast_hit: Dictionary = _cast(
		column + Vector3.UP * _SPAWN_RAY_HEIGHT, column - Vector3.UP * _SPAWN_RAY_HEIGHT
	)
	if raycast_hit.is_empty() or not _is_terrain_collider(raycast_hit.get("collider")):
		var fallback_height: float = surface.get_surface_height_at(column)
		spawn_data.position = Vector3(column.x, fallback_height + spawn_clearance, column.z)
		return spawn_data
	spawn_data.position = raycast_hit.position + Vector3.UP * spawn_clearance
	spawn_data.from_raycast_hit = true
	return spawn_data


func respawn_random() -> void:
	_cache_terrain_refs()
	_apply_spawn(_find_random_surface_spawn())


func _spawn_on_terrain() -> void:
	_cache_terrain_refs()
	if terrain == null:
		push_warning("[%s] No terrain assigned." % get_class())
		return

	var spawn_data: Dictionary = _find_random_surface_spawn()
	for _attempt: int in _SPAWN_ATTEMPTS:
		await get_tree().physics_frame
		spawn_data = _find_random_surface_spawn()
		if spawn_data.get("from_raycast_hit", false):
			break

	_apply_spawn(spawn_data)


func _apply_spawn(spawn_data: Dictionary) -> void:
	global_position = spawn_data.get("position", Vector3.ZERO)
	global_rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	_surface_up = Vector3.UP
	up_direction = Vector3.UP
	_climbing = false
	_flying = false
	_want_climb_toggle = false
	_want_jump = false
	_terrain_focus = false
	_anim_state = ""
	_orbit_camera.rotation = Vector3(_orbit_camera.rotation.x, 0.0, _orbit_camera.rotation.z)
	_get_skin().set_state("idle")
	_spawned = true


# --- Animation --------------------------------------------------------------------------------

func _get_skin() -> CharacterSkin:
	return _skin


func _set_anim_state(skin: CharacterSkin, state_name: String) -> void:
	if _anim_state == state_name:
		return
	_anim_state = state_name
	skin.set_state(state_name)


func _update_animation(movement_direction: Vector3) -> void:
	var skin: CharacterSkin = _get_skin()
	if skin.is_waving():
		return

	if _flying:
		_set_anim_state(skin, "fly")
	elif not is_on_floor():
		_set_anim_state(skin, "jump" if velocity.dot(_surface_up) > 0.05 else "fall")
	elif movement_direction.length_squared() > _MIN_DIR_LEN_SQ:
		_set_anim_state(skin, "run" if Input.is_action_pressed("run") else "walk")
	else:
		_set_anim_state(skin, "idle")


# --- Terrain editing and items ----------------------------------------------------------------

func _set_terrain_focus(enabled: bool) -> void:
	if _terrain_focus == enabled:
		return
	_terrain_focus = enabled
	velocity = Vector3.ZERO
	_want_jump = false
	if _terrain_focus:
		Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _is_terrain_edit_active() -> bool:
	var terrain_brush: TerrainBrush = (
		get_tree().get_first_node_in_group("terrain_brush") as TerrainBrush
	)
	return terrain_brush != null and terrain_brush.get_edit_mode() != TerrainBrush.EditMode.OFF


func _is_item_menu_open() -> bool:
	var player_item_menu: PlayerItemMenu = (
		get_tree().get_first_node_in_group("player_item_menu") as PlayerItemMenu
	)
	return player_item_menu != null and player_item_menu.is_open()


func _connect_terrain_hud() -> void:
	var terrain_hud_layer: CanvasLayer = (
		get_tree().get_first_node_in_group("terrain_hud") as CanvasLayer
	)
	if terrain_hud_layer == null:
		return
	if terrain_hud_layer.has_signal("terrain_edit_mode_changed"):
		terrain_hud_layer.terrain_edit_mode_changed.connect(_on_terrain_edit_mode_changed)
	if terrain_hud_layer.has_method("get_item_menu"):
		var player_item_menu: PlayerItemMenu = terrain_hud_layer.get_item_menu()
		if player_item_menu != null:
			player_item_menu.item_selected.connect(apply_hand_item)
	var terrain_brush: TerrainBrush = (
		get_tree().get_first_node_in_group("terrain_brush") as TerrainBrush
	)
	if terrain_brush != null:
		_on_terrain_edit_mode_changed(terrain_brush.get_edit_mode())
	var skin: CharacterSkin = _get_skin()
	if skin != null:
		skin.torch_equipped_changed.connect(_on_torch_equipped_changed)


func apply_hand_item(item: PlayerItems.Item) -> void:
	if not _spawned:
		return
	var skin: CharacterSkin = _get_skin()
	if skin.is_torch_busy() or skin.is_pickaxe_busy():
		return
	var terrain_hud_layer: CanvasLayer = (
		get_tree().get_first_node_in_group("terrain_hud") as CanvasLayer
	)
	match item:
		PlayerItems.Item.NONE:
			if skin.is_torch_equipped():
				skin.stow_torch()
			if terrain_hud_layer != null and terrain_hud_layer.has_method("set_edit_mode"):
				terrain_hud_layer.set_edit_mode(TerrainBrush.EditMode.OFF)
		PlayerItems.Item.TORCH:
			if terrain_hud_layer != null and terrain_hud_layer.has_method("set_edit_mode"):
				terrain_hud_layer.set_edit_mode(TerrainBrush.EditMode.OFF)
			if not skin.is_torch_equipped():
				skin.equip_torch()
		PlayerItems.Item.PICKAXE_DESTROY, PlayerItems.Item.PICKAXE_ADD:
			if skin.is_torch_equipped():
				skin.stow_torch()
			if terrain_hud_layer != null and terrain_hud_layer.has_method("set_edit_mode"):
				terrain_hud_layer.set_edit_mode(PlayerItems.edit_mode_from_item(item))
		_:
			if PlayerItems.is_weapon(item):
				if skin.is_torch_equipped():
					skin.stow_torch()
				if terrain_hud_layer != null and terrain_hud_layer.has_method("set_edit_mode"):
					terrain_hud_layer.set_edit_mode(TerrainBrush.EditMode.OFF)
	PlayerItems.apply_weapon_visual(skin, item)
	_sync_item_menu(item)


func _toggle_item_menu() -> void:
	if get_tree().paused:
		return
	var terrain_hud_layer: CanvasLayer = (
		get_tree().get_first_node_in_group("terrain_hud") as CanvasLayer
	)
	if terrain_hud_layer == null or not terrain_hud_layer.has_method("get_item_menu"):
		return
	var player_item_menu: PlayerItemMenu = terrain_hud_layer.get_item_menu()
	if player_item_menu != null:
		player_item_menu.toggle_menu()


func _sync_item_menu(item: PlayerItems.Item) -> void:
	var terrain_hud_layer: CanvasLayer = (
		get_tree().get_first_node_in_group("terrain_hud") as CanvasLayer
	)
	if terrain_hud_layer == null or not terrain_hud_layer.has_method("get_item_menu"):
		return
	var player_item_menu: PlayerItemMenu = terrain_hud_layer.get_item_menu()
	if player_item_menu != null:
		player_item_menu.set_active_item(item)


func _on_torch_equipped_changed(equipped: bool) -> void:
	if equipped:
		_sync_item_menu(PlayerItems.Item.TORCH)
	elif not _is_terrain_edit_active():
		_sync_item_menu(PlayerItems.Item.NONE)


func _on_terrain_edit_mode_changed(mode: TerrainBrush.EditMode) -> void:
	_get_skin().set_terrain_edit_equipped(mode != TerrainBrush.EditMode.OFF)
	if mode != TerrainBrush.EditMode.OFF:
		_sync_item_menu(PlayerItems.item_from_edit_mode(mode))
	elif not _get_skin().is_torch_equipped():
		_sync_item_menu(PlayerItems.Item.NONE)
