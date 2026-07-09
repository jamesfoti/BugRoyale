extends SpringArm3D
class_name OrbitCamera
## Camera pitch while playing; hold middle mouse to orbit; scroll to zoom; aim zoom with weapon.


const AIM_ACTION: StringName = &"aim"
const AIM_HOLD_THRESHOLD: float = 0.4

@export_range(-90.0, 90.0, 0.1, "radians") var min_limit_x: float = -1.4
@export_range(-90.0, 90.0, 0.1, "radians") var max_limit_x: float = 0.2
@export var mouse_sensitivity: float = 0.0025
@export var recenter_speed: float = 10.0
@export var min_spring_length: float = 2.5
@export var max_spring_length: float = 14.0
@export var scroll_zoom_step: float = 0.65
@export var aim_spring_length: float = 3.0
@export var aim_position_offset: Vector3 = Vector3(0.6, -0.3, 1.1)
@export var aim_fov: float = 45.0
@export var aim_transition_speed: float = 4.0
@export_range(0.1, 1.0, 0.05) var aim_mouse_sensitivity_scale: float = 0.75
@export var aim_crosshair_screen_ratio: Vector2 = Vector2(0.5, 0.5)

@onready var _camera: Camera3D = $Camera3D

var _orbiting: bool = false
var _aiming: bool = false
var _toggled_aim: bool = false
var _aiming_timer: float = 0.0
var _aim_blend: float = 0.0
var _user_spring_length: float = 6.0
var _rest_position: Vector3 = Vector3.ZERO
var _default_fov: float = 60.0


func _ready() -> void:
	if not InputMap.has_action(AIM_ACTION):
		push_error(
			"Missing InputMap action '%s'. Add it under Project > Project Settings > Input Map."
			% AIM_ACTION
		)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_rest_position = position
	_user_spring_length = clampf(spring_length, min_spring_length, max_spring_length)
	spring_length = _user_spring_length
	if _camera != null:
		_default_fov = _camera.fov


func _process(delta: float) -> void:
	_update_aim_state(delta)
	_update_aim_camera(delta)


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if _is_item_menu_open():
		return
	if _is_terrain_focus_active():
		return
	if event.is_action_pressed("ui_cancel"):
		if _is_terrain_edit_active():
			return
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		if get_viewport().gui_get_hovered_control() != null:
			return
		if _is_terrain_edit_active():
			return
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_apply_scroll_zoom(button.button_index)
			get_viewport().set_input_as_handled()
			return
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _input(event: InputEvent) -> void:
	if _is_item_menu_open():
		return
	if _is_terrain_focus_active():
		return
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			_orbiting = button.pressed
		elif button.pressed:
			_apply_scroll_zoom(button.button_index)

	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		var sensitivity_scale: float = aim_mouse_sensitivity_scale if _aiming else 1.0
		rotation.y -= motion.relative.x * mouse_sensitivity * sensitivity_scale
		rotation.x = clampf(
			rotation.x - motion.relative.y * mouse_sensitivity * sensitivity_scale,
			min_limit_x,
			max_limit_x
		)


func is_orbiting() -> bool:
	return _orbiting


func is_aiming() -> bool:
	return _aiming


func get_aim_blend() -> float:
	return _aim_blend


func get_crosshair_screen_position(viewport_size: Vector2) -> Vector2:
	var screen_center: Vector2 = viewport_size * 0.5
	if _aim_blend <= 0.001:
		return screen_center
	var aim_screen_position: Vector2 = Vector2(
		viewport_size.x * aim_crosshair_screen_ratio.x,
		viewport_size.y * aim_crosshair_screen_ratio.y
	)
	return screen_center.lerp(aim_screen_position, _aim_blend)


func _update_aim_state(delta: float) -> void:
	if not _can_use_aim():
		_aiming = false
		_toggled_aim = false
		_aiming_timer = 0.0
		return

	var current_aim: bool = false
	if Input.is_action_just_released(AIM_ACTION) and _aiming_timer <= AIM_HOLD_THRESHOLD:
		current_aim = true
		_toggled_aim = true
	else:
		current_aim = _toggled_aim or Input.is_action_pressed(AIM_ACTION)
		if Input.is_action_just_pressed(AIM_ACTION):
			_toggled_aim = false

	if current_aim:
		_aiming_timer += delta
	else:
		_aiming_timer = 0.0
	_aiming = current_aim


func _update_aim_camera(delta: float) -> void:
	var target_blend: float = 1.0 if _aiming and _has_weapon_equipped() else 0.0
	_aim_blend = move_toward(_aim_blend, target_blend, aim_transition_speed * delta)
	spring_length = lerpf(_user_spring_length, aim_spring_length, _aim_blend)
	var aim_offset: Vector3 = _get_aim_offset_in_parent_space()
	position = _rest_position.lerp(_rest_position + aim_offset, _aim_blend)
	if _camera != null:
		_camera.fov = lerpf(_default_fov, aim_fov, _aim_blend)


func _get_aim_offset_in_parent_space() -> Vector3:
	var player_node: Node3D = get_parent() as Node3D
	if player_node == null:
		return aim_position_offset

	var visual_root: Node3D = player_node.get_node_or_null("VisualRoot") as Node3D
	if visual_root == null:
		return aim_position_offset

	var surface_up: Vector3 = _get_player_up()
	var character_right: Vector3 = visual_root.global_basis.x.slide(surface_up)
	if character_right.length_squared() < 0.0001:
		character_right = visual_root.global_basis.z.slide(surface_up)
	if character_right.length_squared() < 0.0001:
		character_right = global_basis.x.slide(surface_up)
	if character_right.length_squared() < 0.0001:
		return aim_position_offset
	character_right = character_right.normalized()

	var character_forward: Vector3 = (-visual_root.global_basis.z).slide(surface_up)
	if character_forward.length_squared() < 0.0001:
		character_forward = (-global_basis.z).slide(surface_up)
	if character_forward.length_squared() < 0.0001:
		character_forward = character_right.cross(surface_up)
	character_forward = character_forward.normalized()

	var world_offset: Vector3 = (
		-character_right * aim_position_offset.x
		+ surface_up * aim_position_offset.y
		+ character_forward * aim_position_offset.z
	)
	return player_node.global_transform.basis.inverse() * world_offset


func _get_player_up() -> Vector3:
	var player_node: Node = get_parent()
	if player_node is CharacterBody3D:
		var up_direction: Vector3 = (player_node as CharacterBody3D).up_direction
		if up_direction.length_squared() > 0.0001:
			return up_direction.normalized()
	return Vector3.UP


func _can_use_aim() -> bool:
	if get_tree().paused:
		return false
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return false
	if _is_item_menu_open():
		return false
	if _is_terrain_focus_active():
		return false
	if not InputMap.has_action(AIM_ACTION):
		return false
	return _has_weapon_equipped()


func _has_weapon_equipped() -> bool:
	var player_node: Node = get_parent()
	if player_node == null:
		return false
	var visual_root: Node = player_node.get_node_or_null("VisualRoot")
	if visual_root == null or visual_root.get_child_count() == 0:
		return false
	var skin_node: Node = visual_root.get_child(0)
	if skin_node == null or not skin_node.has_method("get_equipped_weapon_item"):
		return false
	var equipped_weapon_item: PlayerItems.Item = skin_node.call("get_equipped_weapon_item")
	return PlayerItems.is_weapon(equipped_weapon_item)


func _apply_scroll_zoom(button_index: MouseButton) -> void:
	var direction: float = 0.0
	match button_index:
		MOUSE_BUTTON_WHEEL_UP:
			direction = -1.0
		MOUSE_BUTTON_WHEEL_DOWN:
			direction = 1.0
		_:
			return
	_user_spring_length = clampf(
		_user_spring_length + direction * scroll_zoom_step,
		min_spring_length,
		max_spring_length
	)
	if _aim_blend <= 0.001:
		spring_length = _user_spring_length


func recenter_yaw(delta: float) -> void:
	rotation.y = lerpf(rotation.y, 0.0, minf(1.0, recenter_speed * delta))


func _is_terrain_edit_active() -> bool:
	var brush: TerrainBrush = get_tree().get_first_node_in_group("terrain_brush") as TerrainBrush
	return brush != null and brush.get_edit_mode() != TerrainBrush.EditMode.OFF


func _is_terrain_focus_active() -> bool:
	var player_node: Node = get_parent()
	if player_node == null or not player_node.has_method("is_terrain_focus_active"):
		return false
	return player_node.call("is_terrain_focus_active")


func _is_item_menu_open() -> bool:
	var menu: PlayerItemMenu = get_tree().get_first_node_in_group("player_item_menu") as PlayerItemMenu
	return menu != null and menu.is_open()
