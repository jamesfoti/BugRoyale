extends Control
## Entry menu: choose world and player character, or open settings.


const PLANET_SCENE_PATH: String = "res://scenes/planet_test.tscn"
const BATTLEFIELD_TERRAIN_SCENE_PATH: String = "res://scenes/battlefield_terrain_test.tscn"
const TERRARIUM_SCENE_PATH: String = "res://scenes/terrarium_test.tscn"
const LOADING_SCREEN_SCENE_PATH: String = "res://scenes/loading_screen.tscn"
## Extra space around the character in the Choose Player preview.
const PREVIEW_FRAMING_PADDING: float = 1.15

@onready var _title: Label = $UI/Margin/VBox/Title
@onready var _planet_button: Button = $UI/Margin/VBox/Buttons/PlanetButton
@onready var _battlefield_button: Button = $UI/Margin/VBox/Buttons/BattlefieldButton
@onready var _terrarium_button: Button = $UI/Margin/VBox/Buttons/TerrariumButton
@onready var _selected_player_label: Label = $UI/Margin/VBox/Buttons/SelectedPlayerLabel
@onready var _choose_player_button: Button = $UI/Margin/VBox/Buttons/ChoosePlayerButton
@onready var _settings_button: Button = $UI/Margin/VBox/Buttons/SettingsButton
@onready var _settings_menu: Control = $UI/SettingsMenu
@onready var _player_select_page: Control = $UI/PlayerSelectPage
@onready var _player_name_label: Label = $UI/PlayerSelectPage/CenterPanel/Margin/VBox/PlayerName
@onready var _preview_root: Node3D = $UI/PlayerSelectPage/CenterPanel/Margin/VBox/PreviewContainer/PreviewViewport/PreviewRoot
@onready var _preview_use_button: Button = $UI/PlayerSelectPage/CenterPanel/Margin/VBox/Buttons/UseButton
@onready var _preview_previous_button: Button = $UI/PlayerSelectPage/CenterPanel/Margin/VBox/Buttons/PreviousButton
@onready var _preview_next_button: Button = $UI/PlayerSelectPage/CenterPanel/Margin/VBox/Buttons/NextButton
@onready var _preview_back_button: Button = $UI/PlayerSelectPage/CenterPanel/Margin/VBox/BackButton
@onready var _sky_viewport: SubViewport = $SkyViewportContainer/SkyViewport
@onready var _preview_viewport: SubViewport = $UI/PlayerSelectPage/CenterPanel/Margin/VBox/PreviewContainer/PreviewViewport
@onready var _preview_camera: Camera3D = $UI/PlayerSelectPage/CenterPanel/Margin/VBox/PreviewContainer/PreviewViewport/PreviewCamera

var _preview_player_scenes: Dictionary[LoadingScreen.PlayerCharacter, PackedScene] = {}
var _preview_instance: Node3D
var _preview_rotation_degrees_per_second: float = 25.0
var _preview_selected_character: LoadingScreen.PlayerCharacter = LoadingScreen.PlayerCharacter.ANT


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_sky_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_set_preview_viewport_active(false)
	_title.text = str(ProjectSettings.get_setting("application/config/name", "PhysicsRoyale"))
	_setup_preview_scenes()
	_preview_selected_character = LoadingScreen.selected_player_character
	_refresh_selected_player_label()
	_choose_player_button.pressed.connect(_on_choose_player_pressed)
	_settings_button.pressed.connect(_settings_menu.open)
	_settings_menu.closed.connect(_settings_button.grab_focus)
	_preview_use_button.pressed.connect(_on_preview_use_pressed)
	_preview_previous_button.pressed.connect(_cycle_preview_character.bind(-1))
	_preview_next_button.pressed.connect(_cycle_preview_character.bind(1))
	# Cycling needs at least two characters; the buttons stay for future bugs.
	var has_choices: bool = LoadingScreen.PlayerCharacter.size() > 1
	_preview_previous_button.disabled = not has_choices
	_preview_next_button.disabled = not has_choices
	_preview_back_button.pressed.connect(_on_preview_back_pressed)
	_planet_button.pressed.connect(_on_planet_pressed)
	_battlefield_button.pressed.connect(_on_battlefield_pressed)
	_terrarium_button.pressed.connect(_on_terrarium_pressed)
	_update_preview_display()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _preview_instance == null:
		return
	_preview_instance.rotate_y(deg_to_rad(_preview_rotation_degrees_per_second * delta))


func _setup_preview_scenes() -> void:
	for character: LoadingScreen.PlayerCharacter in LoadingScreen.PlayerCharacter.values():
		var scene: PackedScene = load(CharacterSkin.scene_path_for(character)) as PackedScene
		if scene != null:
			_preview_player_scenes[character] = scene


func _cycle_preview_character(direction: int) -> void:
	var characters: Array = LoadingScreen.PlayerCharacter.values()
	var index: int = characters.find(_preview_selected_character)
	_preview_selected_character = characters[posmod(index + direction, characters.size())]
	_update_preview_display()


func _on_choose_player_pressed() -> void:
	_preview_selected_character = LoadingScreen.selected_player_character
	_player_select_page.visible = true
	_set_preview_viewport_active(true)
	_update_preview_display()


func _on_preview_use_pressed() -> void:
	_set_selected_character(_preview_selected_character)
	_player_select_page.visible = false
	_set_preview_viewport_active(false)
	_refresh_selected_player_label()


func _on_preview_back_pressed() -> void:
	_player_select_page.visible = false
	_set_preview_viewport_active(false)
	_preview_selected_character = LoadingScreen.selected_player_character


func _set_selected_character(selected_character: LoadingScreen.PlayerCharacter) -> void:
	LoadingScreen.selected_player_character = selected_character
	_refresh_selected_player_label()


func _update_preview_display() -> void:
	var selected_character: LoadingScreen.PlayerCharacter = _preview_selected_character
	_player_name_label.text = _display_name_for_character(selected_character)
	_spawn_preview_character(selected_character)


func _spawn_preview_character(selected_character: LoadingScreen.PlayerCharacter) -> void:
	if _preview_instance != null:
		_preview_instance.queue_free()
		_preview_instance = null

	var preview_scene: PackedScene = _preview_player_scenes.get(selected_character, null) as PackedScene
	if preview_scene == null:
		return

	var preview_node: Node = preview_scene.instantiate()
	if not preview_node is Node3D:
		preview_node.queue_free()
		return
	_preview_instance = preview_node as Node3D
	_preview_root.add_child(_preview_instance)
	_preview_instance.position = Vector3.ZERO
	_preview_instance.rotation = Vector3.ZERO
	_set_idle_state_if_supported(_preview_instance)
	_frame_preview_camera()


## Fits the preview camera to the character's bounds, so differently sized characters fill the view.
func _frame_preview_camera() -> void:
	var bounds := AABB()
	var has_bounds: bool = false
	for mesh_instance: MeshInstance3D in _preview_instance.find_children("*", "MeshInstance3D", true, false):
		if mesh_instance.mesh == null or not mesh_instance.is_visible_in_tree():
			continue
		var mesh_bounds: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
		bounds = mesh_bounds if not has_bounds else bounds.merge(mesh_bounds)
		has_bounds = true
	if not has_bounds:
		return
	var half_fov: float = deg_to_rad(_preview_camera.fov * 0.5)
	var aspect: float = float(_preview_viewport.size.x) / maxf(float(_preview_viewport.size.y), 1.0)
	# The character spins, so fit its widest horizontal extent as well as its height.
	var spin_width: float = Vector2(bounds.size.x, bounds.size.z).length()
	var distance: float = maxf(
		bounds.size.y * 0.5 / tan(half_fov),
		spin_width * 0.5 / (tan(half_fov) * aspect)
	) * PREVIEW_FRAMING_PADDING
	var center: Vector3 = bounds.get_center()
	var view_direction: Vector3 = Vector3(sin(deg_to_rad(-12.0)), 0.12, cos(deg_to_rad(-12.0))).normalized()
	_preview_camera.global_position = center + view_direction * distance
	_preview_camera.look_at(center)


func _set_idle_state_if_supported(preview_node: Node3D) -> void:
	if preview_node.has_method("set_state"):
		preview_node.call("set_state", "idle")
	var animation_player: AnimationPlayer = preview_node.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player == null:
		return
	if animation_player.has_animation("Idle"):
		animation_player.play("Idle")
	elif animation_player.has_animation("idle"):
		animation_player.play("idle")
	elif animation_player.has_animation("Idle_1"):
		animation_player.play("Idle_1")
	elif animation_player.has_animation("walk"):
		animation_player.play("walk")


func _refresh_selected_player_label() -> void:
	_selected_player_label.text = "Player: %s" % _display_name_for_character(
		LoadingScreen.selected_player_character
	)


func _display_name_for_character(selected_character: LoadingScreen.PlayerCharacter) -> String:
	return CharacterSkin.display_name_for(selected_character)


func _set_preview_viewport_active(active: bool) -> void:
	if _preview_viewport == null:
		return
	_preview_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	)


func _on_planet_pressed() -> void:
	_open_scene(PLANET_SCENE_PATH)


func _on_battlefield_pressed() -> void:
	_open_scene(BATTLEFIELD_TERRAIN_SCENE_PATH)


func _on_terrarium_pressed() -> void:
	_open_scene(TERRARIUM_SCENE_PATH)


func _open_scene(scene_path: String) -> void:
	LoadingScreen.pending_scene_path = scene_path
	get_tree().change_scene_to_file(LOADING_SCREEN_SCENE_PATH)
