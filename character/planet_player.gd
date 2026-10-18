extends CharacterBody3D
class_name PlanetPlayer
## Walks on spherical terrain: mouse yaw, W/S move relative to camera view.

const _MIN_DIR_LEN_SQ: float = 0.0001
const _INPUT_DEADZONE: float = 0.01
const _SPAWN_ATTEMPTS: int = 12
const _SPAWN_RAY_MARGIN: float = 40.0
const _FALLBACK_PLANET_RADIUS: float = 18.0
const _MAX_MOUSE_DELTA: float = 80.0

class SpawnData:
	var position: Vector3 = Vector3.ZERO
	var surface_up: Vector3 = Vector3.UP
	var forward: Vector3 = Vector3.FORWARD
	var from_raycast_hit: bool = false


@export var planet: Node3D
@export var speed: float = 5.0
@export var run_speed: float = 8.0
@export var jump_velocity: float = 4.5
@export var gravity_strength: float = 9.8
@export var surface_align_speed: float = 10.0
@export var mouse_sensitivity: float = 0.0025
@export var spawn_clearance: float = 1.2

## The selected character (plush by default) is installed under VisualRoot on ready.
@onready var _skin: CharacterSkin = CharacterSkin.install_selected($VisualRoot)
@onready var _orbit_camera: OrbitCamera = $OrbitCamera
@onready var _camera: Camera3D = $OrbitCamera/Camera3D

var _gravity_direction: Vector3 = Vector3.DOWN
var _planet: Planet
var _anim_state: String = ""
var _want_jump: bool = false
var _spawned: bool = false
var _terrain_focus: bool = false


func is_terrain_focus_active() -> bool:
	return _terrain_focus


func exit_terrain_focus() -> void:
	_set_terrain_focus(false)


func _ready() -> void:
	_cache_planet_refs()
	call_deferred("_spawn_on_planet")
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
	if event.is_action_pressed("item_menu"):
		_toggle_item_menu()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _spawned or _terrain_focus or _is_item_menu_open():
		return
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if _is_camera_orbiting():
		return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_apply_mouse_yaw(motion.relative.x)


func _physics_process(delta: float) -> void:
	if planet == null or not _spawned:
		return

	_update_gravity_direction()
	up_direction = _get_up()

	if _terrain_focus:
		_want_jump = false
		_apply_focus_physics(delta)
		var focus_facing: Vector3 = _get_flat_forward()
		_align_up_to_planet(delta, focus_facing)
		move_and_slide()
		_update_animation(Vector3.ZERO)
		return

	if _is_item_menu_open():
		_want_jump = false
		_apply_focus_physics(delta)
		move_and_slide()
		_update_animation(Vector3.ZERO)
		return

	var movement_direction: Vector3 = _get_movement_direction()
	_apply_movement(delta, movement_direction)

	var facing_direction: Vector3 = _get_facing_direction(movement_direction)
	if movement_direction.length_squared() > _MIN_DIR_LEN_SQ:
		var forward_backward_input: float = Input.get_axis("move_backward", "move_forward")
		if forward_backward_input > _INPUT_DEADZONE:
			_orbit_camera.recenter_yaw(delta)
		_align_up_to_planet(delta, facing_direction)
	elif not _is_camera_orbiting():
		_orthonormalize_basis()
	move_and_slide()
	_update_animation(movement_direction)


func _apply_movement(delta: float, movement_direction: Vector3) -> void:
	var move_speed: float = run_speed if Input.is_action_pressed("run") else speed
	var radial_speed: float = velocity.dot(_gravity_direction)

	if movement_direction.length_squared() > _MIN_DIR_LEN_SQ:
		velocity = movement_direction * move_speed + _gravity_direction * radial_speed
	elif is_on_floor():
		velocity = Vector3.ZERO

	if not is_on_floor():
		velocity += _gravity_direction * gravity_strength * delta

	if _want_jump and is_on_floor() and not _get_skin().is_waving():
		velocity += _get_up() * jump_velocity
	_want_jump = false


func _apply_focus_physics(delta: float) -> void:
	var radial_speed: float = velocity.dot(_gravity_direction)
	if is_on_floor():
		velocity = Vector3.ZERO
	else:
		velocity = _gravity_direction * radial_speed
		velocity += _gravity_direction * gravity_strength * delta


func _apply_mouse_yaw(mouse_delta_x: float) -> void:
	if absf(mouse_delta_x) > _MAX_MOUSE_DELTA:
		return
	var surface_up: Vector3 = _get_up()
	if surface_up.length_squared() > _MIN_DIR_LEN_SQ:
		global_basis = Basis(surface_up, -mouse_delta_x * mouse_sensitivity) * global_basis


func _is_camera_orbiting() -> bool:
	return _orbit_camera.is_orbiting()


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


func _get_camera_flat_forward() -> Vector3:
	var surface_up: Vector3 = _get_up()
	var forward: Vector3 = (-_camera.global_basis.z).slide(surface_up)
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		return _get_flat_forward()
	return forward.normalized()


func _get_movement_direction() -> Vector3:
	var forward_backward_input: float = Input.get_axis("move_backward", "move_forward")
	if absf(forward_backward_input) < _INPUT_DEADZONE:
		return Vector3.ZERO
	var forward: Vector3 = _get_camera_flat_forward()
	if forward == Vector3.ZERO:
		return Vector3.ZERO
	return forward * forward_backward_input


func _get_facing_direction(movement_direction: Vector3) -> Vector3:
	if movement_direction.length_squared() < _MIN_DIR_LEN_SQ:
		return _get_flat_forward()
	# Backpedal: keep facing camera forward so body rotation does not spin the camera.
	var forward_backward_input: float = Input.get_axis("move_backward", "move_forward")
	if forward_backward_input < -_INPUT_DEADZONE:
		var camera_forward: Vector3 = _get_camera_flat_forward()
		if camera_forward != Vector3.ZERO:
			return camera_forward
	return movement_direction.normalized()


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


func _orthonormalize_basis() -> void:
	global_transform.basis = global_transform.basis.orthonormalized()


func _cache_planet_refs() -> void:
	if planet == null:
		planet = get_tree().get_first_node_in_group("planet") as Node3D
	if planet is Planet:
		_planet = planet as Planet


func respawn_random() -> void:
	_cache_planet_refs()
	_apply_spawn(_find_random_surface_spawn())


func _spawn_on_planet() -> void:
	_cache_planet_refs()
	if planet == null:
		push_warning("[PlanetPlayer] No planet assigned.")
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
		Basis.looking_at(spawn_data.forward, spawn_data.surface_up),
		spawn_data.position
	)
	velocity = Vector3.ZERO
	_want_jump = false
	_terrain_focus = false
	_anim_state = ""
	_update_gravity_direction()
	_orbit_camera.rotation = Vector3(_orbit_camera.rotation.x, 0.0, _orbit_camera.rotation.z)
	_get_skin().set_state("idle")
	_spawned = true


func _find_random_surface_spawn() -> SpawnData:
	var spawn_data: SpawnData = SpawnData.new()
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
		spawn_data.from_raycast_hit = false
		return spawn_data

	var surface_up: Vector3 = raycast_hit.normal
	spawn_data.position = raycast_hit.position + surface_up * spawn_clearance
	spawn_data.surface_up = surface_up
	spawn_data.forward = _tangent_forward_on_plane(surface_up)
	spawn_data.from_raycast_hit = true
	return spawn_data


func _is_planet_collider(collider: Variant) -> bool:
	if planet == null or not (collider is Node):
		return false
	var node: Node = collider as Node
	return planet == node or planet.is_ancestor_of(node)


func _tangent_forward_on_plane(surface_up: Vector3) -> Vector3:
	var forward: Vector3 = surface_up.cross(Vector3.FORWARD)
	if forward.length_squared() < 0.01:
		forward = surface_up.cross(Vector3.RIGHT)
	return forward.normalized()


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

	var vertical_speed: float = velocity.dot(_get_up())
	if not is_on_floor():
		_set_anim_state(skin, "jump" if vertical_speed > 0.05 else "fall")
	elif movement_direction.length_squared() > _MIN_DIR_LEN_SQ:
		_set_anim_state(skin, "run" if Input.is_action_pressed("run") else "walk")
	else:
		_set_anim_state(skin, "idle")


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
