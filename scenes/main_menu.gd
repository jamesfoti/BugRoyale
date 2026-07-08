extends Control
## Entry menu: choose world and player character.


const PLANET_SCENE_PATH: String = "res://scenes/planet_test.tscn"
const BATTLEFIELD_TERRAIN_SCENE_PATH: String = "res://scenes/battlefield_terrain_test.tscn"
const TERRARIUM_SCENE_PATH: String = "res://scenes/terrarium_test.tscn"
const LOADING_SCREEN_SCENE_PATH: String = "res://scenes/loading_screen.tscn"
const PLAYER_STANDARD_PREVIEW_SCENE_PATH: String = "res://character/godot_plush/godot_plush_skin.tscn"

@onready var _title: Label = $UI/Margin/VBox/Title
@onready var _planet_button: Button = $UI/Margin/VBox/Buttons/PlanetButton
@onready var _battlefield_button: Button = $UI/Margin/VBox/Buttons/BattlefieldButton
@onready var _terrarium_button: Button = $UI/Margin/VBox/Buttons/TerrariumButton
@onready var _selected_player_label: Label = $UI/Margin/VBox/Buttons/SelectedPlayerLabel
@onready var _choose_player_button: Button = $UI/Margin/VBox/Buttons/ChoosePlayerButton
@onready var _player_select_page: Control = $UI/PlayerSelectPage
@onready var _player_name_label: Label = $UI/PlayerSelectPage/CenterPanel/Margin/VBox/PlayerName
@onready var _preview_root: Node3D = $UI/PlayerSelectPage/CenterPanel/Margin/VBox/PreviewContainer/PreviewViewport/PreviewRoot
@onready var _preview_use_button: Button = $UI/PlayerSelectPage/CenterPanel/Margin/VBox/Buttons/UseButton
@onready var _preview_back_button: Button = $UI/PlayerSelectPage/CenterPanel/Margin/VBox/BackButton

var _preview_player_scenes: Dictionary[LoadingScreen.PlayerCharacter, PackedScene] = {}
var _preview_instance: Node3D
var _preview_rotation_degrees_per_second: float = 25.0
var _preview_selected_character: LoadingScreen.PlayerCharacter = LoadingScreen.PlayerCharacter.STANDARD


func _ready() -> void:
	_title.text = str(ProjectSettings.get_setting("application/config/name", "PhysicsRoyale"))
	_setup_preview_scenes()
	_preview_selected_character = LoadingScreen.selected_player_character
	_refresh_selected_player_label()
	_choose_player_button.pressed.connect(_on_choose_player_pressed)
	_preview_use_button.pressed.connect(_on_preview_use_pressed)
	_preview_back_button.pressed.connect(_on_preview_back_pressed)
	_planet_button.pressed.connect(_on_planet_pressed)
	_battlefield_button.pressed.connect(_on_battlefield_pressed)
	_terrarium_button.pressed.connect(_on_terrarium_pressed)
	_update_preview_display()


func _process(delta: float) -> void:
	if _preview_instance == null:
		return
	_preview_instance.rotate_y(deg_to_rad(_preview_rotation_degrees_per_second * delta))


func _setup_preview_scenes() -> void:
	var standard_scene: PackedScene = load(PLAYER_STANDARD_PREVIEW_SCENE_PATH) as PackedScene
	if standard_scene != null:
		_preview_player_scenes[LoadingScreen.PlayerCharacter.STANDARD] = standard_scene


func _on_choose_player_pressed() -> void:
	_preview_selected_character = LoadingScreen.selected_player_character
	_player_select_page.visible = true
	_update_preview_display()


func _on_preview_use_pressed() -> void:
	_set_selected_character(_preview_selected_character)
	_player_select_page.visible = false
	_refresh_selected_player_label()


func _on_preview_back_pressed() -> void:
	_player_select_page.visible = false
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


func _refresh_selected_player_label() -> void:
	_selected_player_label.text = "Player: %s" % _display_name_for_character(
		LoadingScreen.selected_player_character
	)


func _display_name_for_character(selected_character: LoadingScreen.PlayerCharacter) -> String:
	return "Godot Plush"


func _on_planet_pressed() -> void:
	_open_scene(PLANET_SCENE_PATH)


func _on_battlefield_pressed() -> void:
	_open_scene(BATTLEFIELD_TERRAIN_SCENE_PATH)


func _on_terrarium_pressed() -> void:
	_open_scene(TERRARIUM_SCENE_PATH)


func _open_scene(scene_path: String) -> void:
	LoadingScreen.pending_scene_path = scene_path
	get_tree().change_scene_to_file(LOADING_SCREEN_SCENE_PATH)
