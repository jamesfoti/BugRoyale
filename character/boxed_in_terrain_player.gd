extends CharacterBody3D
class_name BoxedInTerrainPlayer
## Walks on boxed-in terrain with standard gravity and camera-relative movement.

const GODOT_PLUSH_SKIN_SCRIPT = preload("res://character/godot_plush/godot_plush_skin.gd")
const _MIN_DIR_LEN_SQ: float = 0.0001
const _INPUT_DEADZONE: float = 0.01
const _SPAWN_ATTEMPTS: int = 12
const _SPAWN_RAY_HEIGHT: float = 80.0
const _MAX_MOUSE_DELTA: float = 80.0

@export var terrain: Node3D
@export var speed: float = 5.0
@export var run_speed: float = 8.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.0025
@export var spawn_clearance: float = 1.2

@onready var _plush_skin: GODOT_PLUSH_SKIN_SCRIPT = $VisualRoot/GodotPlushSkin
@onready var _orbit_camera: OrbitCamera = $OrbitCamera
@onready var _camera: Camera3D = $OrbitCamera/Camera3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _walk_surface: Node3D
var _anim_state: String = ""
var _want_jump: bool = false
var _spawned: bool = false
var _terrain_focus: bool = false


func is_terrain_focus_active() -> bool:
	return _terrain_focus


func exit_terrain_focus() -> void:
	_set_terrain_focus(false)


func _ready() -> void:
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
	if terrain == null or not _spawned:
		return

	if _terrain_focus:
		_want_jump = false
		_apply_focus_physics(delta)
		_align_to_flat_forward(delta, _get_flat_forward())
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
		_align_to_flat_forward(delta, facing_direction)
	elif not _is_camera_orbiting():
		global_transform.basis = global_transform.basis.orthonormalized()
	move_and_slide()
	_update_animation(movement_direction)


func _apply_movement(delta: float, movement_direction: Vector3) -> void:
	var move_speed: float = run_speed if Input.is_action_pressed("run") else speed
	if movement_direction.length_squared() > _MIN_DIR_LEN_SQ:
		velocity.x = movement_direction.x * move_speed
		velocity.z = movement_direction.z * move_speed
	elif is_on_floor():
		velocity.x = 0.0
		velocity.z = 0.0
		if velocity.y < 0.0:
			velocity.y = 0.0

	if not is_on_floor():
		velocity.y -= _gravity * delta

	if _want_jump and is_on_floor() and not _get_skin().is_waving():
		velocity.y = jump_velocity
	_want_jump = false


func _apply_focus_physics(delta: float) -> void:
	if is_on_floor():
		velocity.x = 0.0
		velocity.z = 0.0
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta


func _apply_mouse_yaw(mouse_delta_x: float) -> void:
	if absf(mouse_delta_x) > _MAX_MOUSE_DELTA:
		return
	rotate_y(-mouse_delta_x * mouse_sensitivity)


func _is_camera_orbiting() -> bool:
	return _orbit_camera.is_orbiting()


func _get_flat_forward() -> Vector3:
	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		forward = global_transform.basis.x
		forward.y = 0.0
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		return Vector3.FORWARD
	return forward.normalized()


func _get_camera_flat_forward() -> Vector3:
	var forward: Vector3 = -_camera.global_basis.z
	forward.y = 0.0
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
	var forward_backward_input: float = Input.get_axis("move_backward", "move_forward")
	if forward_backward_input < -_INPUT_DEADZONE:
		var camera_forward: Vector3 = _get_camera_flat_forward()
		if camera_forward != Vector3.ZERO:
			return camera_forward
	return movement_direction.normalized()


func _align_to_flat_forward(delta: float, facing_direction: Vector3) -> void:
	if facing_direction.length_squared() < _MIN_DIR_LEN_SQ:
		return
	var target_basis: Basis = Basis.looking_at(facing_direction, Vector3.UP).orthonormalized()
	var alignment_blend: float = minf(1.0, 10.0 * delta)
	var current_rotation: Quaternion = global_transform.basis.get_rotation_quaternion()
	var target_rotation: Quaternion = target_basis.get_rotation_quaternion()
	if current_rotation.dot(target_rotation) < 0.0:
		target_rotation = -target_rotation
	global_transform.basis = Basis(current_rotation.slerp(target_rotation, alignment_blend))


func _cache_terrain_refs() -> void:
	if terrain == null:
		terrain = get_tree().get_first_node_in_group("boxed_in_terrain") as Node3D
	if terrain is TerrariumRoom:
		var terrarium_room: TerrariumRoom = terrain as TerrariumRoom
		var playable: TerrariumTerrain = terrarium_room.get_playable_terrain()
		_walk_surface = playable if playable != null else terrarium_room
	elif terrain is OpenTerrain:
		_walk_surface = terrain as OpenTerrain
	elif terrain is BoxedInTerrain:
		_walk_surface = terrain as BoxedInTerrain
	elif terrain != null and terrain.has_method("get_surface_height_at"):
		_walk_surface = terrain


func respawn_random() -> void:
	_cache_terrain_refs()
	_apply_spawn(_find_random_surface_spawn())


func _spawn_on_terrain() -> void:
	_cache_terrain_refs()
	if terrain == null:
		push_warning("[BoxedInTerrainPlayer] No terrain assigned.")
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
	_want_jump = false
	_terrain_focus = false
	_anim_state = ""
	_orbit_camera.rotation = Vector3(_orbit_camera.rotation.x, 0.0, _orbit_camera.rotation.z)
	_get_skin().set_state("idle")
	_spawned = true


func _find_random_surface_spawn() -> Dictionary:
	var spawn_data: Dictionary = {
		"position": Vector3.ZERO,
		"from_raycast_hit": false,
	}
	if terrain is TerrariumRoom:
		var terrarium_room: TerrariumRoom = terrain as TerrariumRoom
		var playable: TerrariumTerrain = terrarium_room.get_playable_terrain()
		if playable != null:
			_walk_surface = playable
		spawn_data.position = terrarium_room.get_spawn_position(spawn_clearance)
		spawn_data.from_raycast_hit = playable != null
		return spawn_data
	if _walk_surface == null:
		spawn_data.position = Vector3(0.0, spawn_clearance, 0.0)
		return spawn_data

	var world_extents: Vector3 = _walk_surface.get_world_extents()
	var half_extent_x: float = world_extents.x * 0.4
	var half_extent_z: float = world_extents.z * 0.4
	var random_offset: Vector3 = Vector3(
		randf_range(-half_extent_x, half_extent_x),
		0.0,
		randf_range(-half_extent_z, half_extent_z)
	)
	var world_center: Vector3 = _walk_surface.global_position
	var ray_origin: Vector3 = world_center + random_offset + Vector3.UP * _SPAWN_RAY_HEIGHT
	var ray_end: Vector3 = world_center + random_offset - Vector3.UP * _SPAWN_RAY_HEIGHT
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin, ray_end
	)
	ray_query.collide_with_areas = false
	var raycast_hit: Dictionary = space.intersect_ray(ray_query)
	if raycast_hit.is_empty() or not _is_terrain_collider(raycast_hit.get("collider")):
		var fallback_height: float = _walk_surface.get_surface_height_at(world_center + random_offset)
		spawn_data.position = Vector3(
			world_center.x + random_offset.x,
			fallback_height + spawn_clearance,
			world_center.z + random_offset.z
		)
		return spawn_data

	spawn_data.position = raycast_hit.position + Vector3.UP * spawn_clearance
	spawn_data.from_raycast_hit = true
	return spawn_data


func _is_terrain_collider(collider: Variant) -> bool:
	if terrain == null or not (collider is Node):
		return false
	var node: Node = collider as Node
	if terrain is TerrariumRoom:
		var playable: TerrariumTerrain = (terrain as TerrariumRoom).get_playable_terrain()
		if playable != null:
			return playable == node or playable.is_ancestor_of(node)
		return false
	if terrain.is_ancestor_of(node) or terrain == node:
		return true
	return false


func _get_skin() -> GODOT_PLUSH_SKIN_SCRIPT:
	return _plush_skin


func _set_anim_state(plush_skin: GODOT_PLUSH_SKIN_SCRIPT, state_name: String) -> void:
	if _anim_state == state_name:
		return
	_anim_state = state_name
	plush_skin.set_state(state_name)


func _update_animation(movement_direction: Vector3) -> void:
	var plush_skin: GODOT_PLUSH_SKIN_SCRIPT = _get_skin()
	if plush_skin.is_waving():
		return

	if not is_on_floor():
		_set_anim_state(plush_skin, "jump" if velocity.y > 0.05 else "fall")
	elif movement_direction.length_squared() > _MIN_DIR_LEN_SQ:
		_set_anim_state(plush_skin, "run" if Input.is_action_pressed("run") else "walk")
	else:
		_set_anim_state(plush_skin, "idle")


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
	var plush_skin: GODOT_PLUSH_SKIN_SCRIPT = _get_skin()
	if plush_skin != null:
		plush_skin.torch_equipped_changed.connect(_on_torch_equipped_changed)


func apply_hand_item(item: PlayerItems.Item) -> void:
	if not _spawned:
		return
	var plush_skin: GODOT_PLUSH_SKIN_SCRIPT = _get_skin()
	if plush_skin.is_torch_busy() or plush_skin.is_pickaxe_busy():
		return
	var terrain_hud_layer: CanvasLayer = (
		get_tree().get_first_node_in_group("terrain_hud") as CanvasLayer
	)
	match item:
		PlayerItems.Item.NONE:
			if plush_skin.is_torch_equipped():
				plush_skin.stow_torch()
			if terrain_hud_layer != null and terrain_hud_layer.has_method("set_edit_mode"):
				terrain_hud_layer.set_edit_mode(TerrainBrush.EditMode.OFF)
		PlayerItems.Item.TORCH:
			if terrain_hud_layer != null and terrain_hud_layer.has_method("set_edit_mode"):
				terrain_hud_layer.set_edit_mode(TerrainBrush.EditMode.OFF)
			if not plush_skin.is_torch_equipped():
				plush_skin.equip_torch()
		PlayerItems.Item.PICKAXE_DESTROY, PlayerItems.Item.PICKAXE_ADD:
			if plush_skin.is_torch_equipped():
				plush_skin.stow_torch()
			if terrain_hud_layer != null and terrain_hud_layer.has_method("set_edit_mode"):
				terrain_hud_layer.set_edit_mode(PlayerItems.edit_mode_from_item(item))
		_:
			if PlayerItems.is_weapon(item):
				if plush_skin.is_torch_equipped():
					plush_skin.stow_torch()
				if terrain_hud_layer != null and terrain_hud_layer.has_method("set_edit_mode"):
					terrain_hud_layer.set_edit_mode(TerrainBrush.EditMode.OFF)
	PlayerItems.apply_weapon_visual(plush_skin, item)
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
