extends SpringArm3D
class_name OrbitCamera
## Third-person shooter camera in the Fortnite mould: over the right shoulder whenever a weapon
## is out, pitch from straight down to well above the horizon, the arm collides with terrain and
## structure so the view never goes through a wall, scroll to zoom, hold middle mouse to orbit.
## Right mouse aims with any weapon: the camera tightens in over the shoulder and the field of
## view narrows. A scoped weapon (see PlayerItems.scope_fovs) has a zoom ladder on top: the
## scope key (V, or clicking the right stick) cycles shoulder view, each scope step, and back
## out, the way a console right-stick click does; the wheel steps the zoom while scoped.


const AIM_ACTION: StringName = &"aim"
const SCOPE_ACTION: StringName = &"scope"
const AIM_HOLD_THRESHOLD: float = 0.4

@export_range(-90.0, 90.0, 0.1, "radians") var min_limit_x: float = -1.4
@export_range(-90.0, 90.0, 0.1, "radians") var max_limit_x: float = 1.25
@export var mouse_sensitivity: float = 0.0025
@export var recenter_speed: float = 10.0
@export var min_spring_length: float = 2.5
@export var max_spring_length: float = 14.0
@export var scroll_zoom_step: float = 0.65
## Over-the-shoulder offset (right, up, forward in the character's frame) while a weapon is out,
## so the bug stands left of the crosshair instead of under it.
@export var shoulder_offset: Vector3 = Vector3(0.9, 0.3, 0.0)
## When terrain or a wall pushes the camera in closer than this, the bug's body is hidden
## rather than filling the screen.
@export var hide_body_distance: float = 1.1
@export var aim_spring_length: float = 3.0
@export var aim_position_offset: Vector3 = Vector3(0.6, -0.3, 1.1)
@export var aim_fov: float = 45.0
@export var aim_transition_speed: float = 4.0
@export_range(0.1, 1.0, 0.05) var aim_mouse_sensitivity_scale: float = 0.75
@export var aim_crosshair_screen_ratio: Vector2 = Vector2(0.5, 0.5)
## Where the eye sits for a scoped view (right, up, forward in the character's frame, from the
## arm's rest position).
@export var scope_eye_offset: Vector3 = Vector3(0.0, -0.15, 0.4)
@export var scope_transition_speed: float = 6.0

@onready var _camera: Camera3D = $Camera3D

var _orbiting: bool = false
var _aiming: bool = false
var _toggled_aim: bool = false
## Scoped weapons only: 0 = over the shoulder, 1.. = that step of the weapon's zoom ladder.
var _scope_level: int = 0
var _aiming_timer: float = 0.0
var _aim_blend: float = 0.0
var _shoulder_blend: float = 0.0
var _scope_blend: float = 0.0
var _scope_fov: float = 0.0
var _user_spring_length: float = 6.0
var _rest_position: Vector3 = Vector3.ZERO
var _default_fov: float = 60.0
var _body_hidden: bool = false


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
	# The arm pulls the camera in when the ground or a wall is in the way.
	collision_mask = MapInfo.TERRAIN_LAYER | MapInfo.STRUCTURE_LAYER
	margin = 0.3
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
		# A narrower view turns slower, so a scope feels steady.
		if _camera != null and _default_fov > 0.0:
			sensitivity_scale *= clampf(_camera.fov / _default_fov, 0.1, 1.0)
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


## 0..1: how far into the scoped (first-person) view the camera is.
func get_scope_blend() -> float:
	return _scope_blend


func is_scoped() -> bool:
	return _scope_blend > 0.5


## Current step of the weapon's zoom ladder: 0 over the shoulder, 1.. through the scope.
func get_scope_level() -> int:
	return _scope_level


## Steps on the equipped weapon's zoom ladder (0 without a scope).
func get_scope_level_count() -> int:
	return PlayerItems.scope_fovs(_get_equipped_weapon_item()).size()


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
		_scope_level = 0
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

	# The scope key, on a scoped weapon, cycles the zoom ladder: shoulder, each scope step, and
	# back to the shoulder. From the hip it goes straight to the first step (and stays, like a
	# tapped aim).
	var steps: int = get_scope_level_count()
	if steps > 0 and InputMap.has_action(SCOPE_ACTION) and Input.is_action_just_pressed(SCOPE_ACTION):
		if current_aim:
			_scope_level = (_scope_level + 1) % (steps + 1)
		else:
			current_aim = true
			_toggled_aim = true
			_scope_level = 1
	if not current_aim or steps == 0:
		_scope_level = 0
	_scope_level = mini(_scope_level, steps)

	if current_aim:
		_aiming_timer += delta
	else:
		_aiming_timer = 0.0
	_aiming = current_aim


func _update_aim_camera(delta: float) -> void:
	var weapon_out: bool = _has_weapon_equipped()
	var scope_fov: float = PlayerItems.scope_fov(_get_equipped_weapon_item(), _scope_level) if weapon_out else 0.0
	var scoped: bool = _aiming and scope_fov > 0.0 and _scope_level > 0
	if scoped:
		# Stepping the ladder eases between magnifications instead of snapping.
		_scope_fov = scope_fov if _scope_fov <= 0.0 or _scope_blend < 0.5 else lerpf(_scope_fov, scope_fov, minf(1.0, 12.0 * delta))
	_scope_blend = move_toward(_scope_blend, 1.0 if scoped else 0.0, scope_transition_speed * delta)
	var target_blend: float = 1.0 if _aiming and weapon_out and not scoped else 0.0
	_aim_blend = move_toward(_aim_blend, target_blend, aim_transition_speed * delta)
	_shoulder_blend = move_toward(_shoulder_blend, 1.0 if weapon_out else 0.0, aim_transition_speed * delta)

	var third_person_length: float = lerpf(_user_spring_length, aim_spring_length, _aim_blend)
	spring_length = lerpf(third_person_length, 0.0, _scope_blend)
	var offset: Vector3 = _offset_in_parent_space(shoulder_offset) * _shoulder_blend
	offset += _offset_in_parent_space(aim_position_offset) * _aim_blend
	var scope_eye: Vector3 = _offset_in_parent_space(scope_eye_offset)
	position = (_rest_position + offset).lerp(_rest_position + scope_eye, _scope_blend)
	if _camera != null:
		var third_person_fov: float = lerpf(_default_fov, aim_fov, _aim_blend)
		_camera.fov = lerpf(third_person_fov, _scope_fov if _scope_fov > 0.0 else aim_fov, _scope_blend)
	_set_body_hidden(_scope_blend > 0.85 or (spring_length > 0.0 and get_hit_length() < hide_body_distance))


## The bug's own body is hidden while looking through a scope, or when the camera is pushed in
## against it (it would fill the view either way).
func _set_body_hidden(hidden: bool) -> void:
	if hidden == _body_hidden:
		return
	_body_hidden = hidden
	var player_node: Node = get_parent()
	if player_node == null:
		return
	var visual_root: Node3D = player_node.get_node_or_null("VisualRoot") as Node3D
	if visual_root != null:
		visual_root.visible = not hidden


## A (right, up, forward) offset in the character's frame, as a vector in the player's space.
func _offset_in_parent_space(offset: Vector3) -> Vector3:
	var player_node: Node3D = get_parent() as Node3D
	if player_node == null:
		return offset

	var visual_root: Node3D = player_node.get_node_or_null("VisualRoot") as Node3D
	if visual_root == null:
		return offset

	var surface_up: Vector3 = _get_player_up()
	var character_right: Vector3 = visual_root.global_basis.x.slide(surface_up)
	if character_right.length_squared() < 0.0001:
		character_right = visual_root.global_basis.z.slide(surface_up)
	if character_right.length_squared() < 0.0001:
		character_right = global_basis.x.slide(surface_up)
	if character_right.length_squared() < 0.0001:
		return offset
	character_right = character_right.normalized()

	var character_forward: Vector3 = (-visual_root.global_basis.z).slide(surface_up)
	if character_forward.length_squared() < 0.0001:
		character_forward = (-global_basis.z).slide(surface_up)
	if character_forward.length_squared() < 0.0001:
		character_forward = character_right.cross(surface_up)
	character_forward = character_forward.normalized()

	var world_offset: Vector3 = (
		-character_right * offset.x
		+ surface_up * offset.y
		+ character_forward * offset.z
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
	# A headless server (automated runs) has no mouse to capture.
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED and DisplayServer.get_name() != "headless":
		return false
	if _is_item_menu_open():
		return false
	if _is_terrain_focus_active():
		return false
	if not InputMap.has_action(AIM_ACTION):
		return false
	return _has_weapon_equipped()


func _has_weapon_equipped() -> bool:
	return PlayerItems.is_weapon(_get_equipped_weapon_item())


func _get_equipped_weapon_item() -> PlayerItems.Item:
	var player_node: Node = get_parent()
	if player_node == null:
		return PlayerItems.Item.NONE
	var visual_root: Node = player_node.get_node_or_null("VisualRoot")
	if visual_root == null or visual_root.get_child_count() == 0:
		return PlayerItems.Item.NONE
	var skin_node: Node = visual_root.get_child(0)
	if skin_node == null or not skin_node.has_method("get_equipped_weapon_item"):
		return PlayerItems.Item.NONE
	return skin_node.call("get_equipped_weapon_item")


func _apply_scroll_zoom(button_index: MouseButton) -> void:
	var direction: float = 0.0
	match button_index:
		MOUSE_BUTTON_WHEEL_UP:
			direction = -1.0
		MOUSE_BUTTON_WHEEL_DOWN:
			direction = 1.0
		_:
			return
	# Through a scope the wheel steps the magnification: up to zoom in, down to zoom out (and
	# out of the scope at the bottom), instead of moving the third-person camera.
	if _scope_level > 0:
		_scope_level = clampi(_scope_level - int(direction), 0, get_scope_level_count())
		return
	_user_spring_length = clampf(
		_user_spring_length + direction * scroll_zoom_step,
		min_spring_length,
		max_spring_length
	)
	if _aim_blend <= 0.001 and _scope_blend <= 0.001:
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
