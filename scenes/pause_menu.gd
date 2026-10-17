extends CanvasLayer
## Pause overlay: Resume, Settings, Restart, Main Menu, or Quit.

@onready var _panel: PanelContainer = $Panel
@onready var _resume_button: Button = $Panel/Margin/MainMenu/ResumeButton
@onready var _settings_button: Button = $Panel/Margin/MainMenu/SettingsButton
@onready var _reset_button: Button = $Panel/Margin/MainMenu/ResetButton
@onready var _main_menu_button: Button = $Panel/Margin/MainMenu/MainMenuButton
@onready var _quit_button: Button = $Panel/Margin/MainMenu/QuitButton
@onready var _settings_menu: Control = $SettingsMenu

const MAIN_MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"

var _paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_resume_button.pressed.connect(_on_resume_pressed)
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
