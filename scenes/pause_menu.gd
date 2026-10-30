extends CanvasLayer
## Pause overlay: Resume, Settings, Restart, Main Menu, or Quit.

const MAIN_MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"

var _paused: bool = false

@onready var _panel: PanelContainer = $Panel
@onready var _resume_button: Button = $Panel/Margin/MainMenu/ResumeButton
@onready var _stuck_button: Button = $Panel/Margin/MainMenu/StuckButton
@onready var _settings_button: Button = $Panel/Margin/MainMenu/SettingsButton
@onready var _reset_button: Button = $Panel/Margin/MainMenu/ResetButton
@onready var _main_menu_button: Button = $Panel/Margin/MainMenu/MainMenuButton
@onready var _quit_button: Button = $Panel/Margin/MainMenu/QuitButton
@onready var _settings_menu: Control = $SettingsMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_resume_button.pressed.connect(_on_resume_pressed)
	_stuck_button.pressed.connect(_on_stuck_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_settings_menu.closed.connect(_on_settings_closed)


func _unhandled_input(event: InputEvent) -> void:
	# The settings page handles its own Esc / Pause (back) while it is open.
	if event.is_action_pressed("pause"):
		if _paused:
			_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()
		return

	if not _paused:
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	_resume()
	get_viewport().set_input_as_handled()


func _on_resume_pressed() -> void:
	_resume()


func _on_settings_pressed() -> void:
	_panel.visible = false
	_settings_menu.open()


func _on_settings_closed() -> void:
	_show_main_menu()


func _on_reset_pressed() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("respawn_random"):
		player.call("respawn_random")
	_resume()


## "Stuck?" (as in State of Decay): moves the player to the nearest clear patch of ground a few
## steps away, keeping everything else as it was. Works on any map through MapInfo. If nothing
## nearby is clear, it falls back to a random respawn. Searches rings of growing radius so the
## hop is as short as possible.
func _on_stuck_pressed() -> void:
	var player: CharacterBody3D = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player == null:
		return
	var spot: Vector3 = _clear_spot_near(player)
	if spot == Vector3.INF:
		if player.has_method("respawn_random"):
			player.call("respawn_random")
	elif player.has_method("unstick"):
		player.call("unstick", spot)
	else:
		player.global_position = spot
		player.velocity = Vector3.ZERO
	_resume()


func _clear_spot_near(player: CharacterBody3D) -> Vector3:
	var map: MapInfo = MapInfo.from_scene(get_tree().current_scene)
	var origin: Vector3 = player.global_position
	var up: Vector3 = map.up_at(origin)
	var side: Vector3 = (
		up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	)
	var collision_shape: CollisionShape3D = (
		player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	)
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	for ring_radius: float in [1.5, 3.0, 5.0, 8.0, 12.0]:
		for step: int in 8:
			var offset: Vector3 = (
				side.rotated(up, TAU * float(step) / 8.0 + ring_radius) * ring_radius
			)
			var ground: Dictionary = map.ground_hit(origin + offset + up * 2.0)
			if ground.is_empty():
				continue
			var spot_up: Vector3 = map.up_at(ground.position)
			var spot: Vector3 = ground.position + spot_up * 1.2
			if map.is_underwater(spot):
				continue
			if collision_shape != null and not _fits(space, collision_shape, spot, spot_up, player):
				continue
			return spot
	return Vector3.INF


## True when the player's capsule, hovering just above a spot, touches nothing solid.
func _fits(
	space: PhysicsDirectSpaceState3D,
	collision_shape: CollisionShape3D,
	spot: Vector3,
	up: Vector3,
	player: CharacterBody3D
) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision_shape.shape
	var basis := Basis(Quaternion(Vector3.UP, up))
	query.transform = Transform3D(basis, spot + basis * collision_shape.position + up * 0.1)
	query.collision_mask = MapInfo.TERRAIN_LAYER | MapInfo.STRUCTURE_LAYER
	query.exclude = [player.get_rid()]
	return space.intersect_shape(query, 1).is_empty()


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _show_main_menu() -> void:
	_settings_menu.visible = false
	_panel.visible = true
	_settings_button.grab_focus()


func _pause() -> void:
	_paused = true
	visible = true
	_show_main_menu()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _resume() -> void:
	_paused = false
	visible = false
	_settings_menu.visible = false
	_panel.visible = true
	get_tree().paused = false
	_sync_game_mouse_mode()


func _sync_game_mouse_mode() -> void:
	var hud: Node = get_tree().get_first_node_in_group("terrain_hud")
	if hud != null and hud.has_method("sync_mouse_mode"):
		hud.call("sync_mouse_mode")
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
