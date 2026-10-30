class_name LocalFighterController
extends FighterController
## The keyboard, mouse and camera of the player at this machine, packed into a FighterInput.
## Jump and climb are edges taken from _unhandled_input so a press the UI consumed (an open
## inventory, a menu) never reaches the body, exactly as before the body read Input itself.
## Mouse motion is summed between physics frames into a yaw delta, and the camera's crosshair
## ray goes in as the aim, so the host can run this body from the snapshot alone.

const DESCEND_ACTION: StringName = &"descend"
const CLIMB_ACTION: StringName = &"climb"
const SHOOT_ACTION: StringName = &"shoot"
## A mouse event this large in one go is a glitch (the OS warping the cursor), not a turn.
const MAX_MOUSE_DELTA: float = 80.0

## Radians of body yaw per pixel of mouse travel (the celestial body uses it).
@export var mouse_sensitivity: float = 0.0025

var _jump_queued: bool = false
var _climb_queued: bool = false
var _yaw_accumulated: float = 0.0


func is_local() -> bool:
	return true


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	var body: Node = get_parent()
	if body != null and body.has_method("is_ui_blocking") and body.call("is_ui_blocking"):
		return
	if event.is_action_pressed("jump"):
		_jump_queued = true
	if event.is_action_pressed(CLIMB_ACTION):
		_climb_queued = true


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion):
		return
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED or get_tree().paused:
		return
	var body: Node = get_parent()
	if body != null and body.has_method("is_ui_blocking") and body.call("is_ui_blocking"):
		return
	var orbit_camera: OrbitCamera = (
		body.get_node_or_null("OrbitCamera") as OrbitCamera if body != null else null
	)
	if orbit_camera != null and orbit_camera.is_orbiting():
		return
	var delta_x: float = (event as InputEventMouseMotion).relative.x
	if absf(delta_x) > MAX_MOUSE_DELTA:
		return
	_yaw_accumulated += -delta_x * mouse_sensitivity


func sample(body: CharacterBody3D, _delta: float) -> FighterInput:
	var input: FighterInput = FighterInput.new()
	input.tick = Engine.get_physics_frames()
	input.jump_pressed = _jump_queued
	input.climb_pressed = _climb_queued
	input.yaw_delta = _yaw_accumulated
	_jump_queued = false
	_climb_queued = false
	_yaw_accumulated = 0.0
	if not enabled:
		return input
	input.move = Vector2(
		Input.get_axis("move_left", "move_right"), Input.get_axis("move_backward", "move_forward")
	)
	input.run = Input.is_action_pressed("run")
	input.jump_held = Input.is_action_pressed("jump")
	input.descend_held = (
		InputMap.has_action(DESCEND_ACTION) and Input.is_action_pressed(DESCEND_ACTION)
	)
	input.shoot_held = InputMap.has_action(SHOOT_ACTION) and Input.is_action_pressed(SHOOT_ACTION)

	var camera: Camera3D = body.get_node_or_null("OrbitCamera/Camera3D") as Camera3D
	var orbit_camera: OrbitCamera = body.get_node_or_null("OrbitCamera") as OrbitCamera
	if camera != null:
		input.view_forward = -camera.global_basis.z
		input.view_up = camera.global_basis.y
		# The shot follows the crosshair: screen centre, or where the aim camera puts it.
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		var screen_position: Vector2 = viewport_size * 0.5
		if orbit_camera != null:
			screen_position = orbit_camera.get_crosshair_screen_position(viewport_size)
		input.has_aim = true
		input.aim_origin = camera.project_ray_origin(screen_position)
		input.aim_direction = camera.project_ray_normal(screen_position)
	else:
		input.view_forward = -body.global_basis.z
		input.view_up = body.global_basis.y
	if orbit_camera != null:
		input.aiming = orbit_camera.is_aiming()
		input.orbiting = orbit_camera.is_orbiting()
	return input
