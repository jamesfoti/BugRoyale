extends FighterController
class_name LocalFighterController
## The keyboard, mouse and camera of the player at this machine, packed into a FighterInput.
## Jump and climb are edges taken from _unhandled_input so a press the UI consumed (an open
## inventory, a menu) never reaches the body, exactly as before the body read Input itself.

const DESCEND_ACTION: StringName = &"descend"
const CLIMB_ACTION: StringName = &"climb"
const SHOOT_ACTION: StringName = &"shoot"

var _jump_queued: bool = false
var _climb_queued: bool = false


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


func sample(body: CharacterBody3D, _delta: float) -> FighterInput:
	var input: FighterInput = FighterInput.new()
	input.jump_pressed = _jump_queued
	input.climb_pressed = _climb_queued
	_jump_queued = false
	_climb_queued = false
	if not enabled:
		return input
	input.move = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_backward", "move_forward")
	)
	input.run = Input.is_action_pressed("run")
	input.jump_held = Input.is_action_pressed("jump")
	input.descend_held = InputMap.has_action(DESCEND_ACTION) and Input.is_action_pressed(DESCEND_ACTION)
	input.shoot_held = InputMap.has_action(SHOOT_ACTION) and Input.is_action_pressed(SHOOT_ACTION)

	var camera: Camera3D = body.get_node_or_null("OrbitCamera/Camera3D") as Camera3D
	if camera != null:
		input.view_forward = -camera.global_basis.z
		input.view_up = camera.global_basis.y
	else:
		input.view_forward = -body.global_basis.z
		input.view_up = body.global_basis.y
	var orbit_camera: OrbitCamera = body.get_node_or_null("OrbitCamera") as OrbitCamera
	if orbit_camera != null:
		input.aiming = orbit_camera.is_aiming()
		input.orbiting = orbit_camera.is_orbiting()
	return input
