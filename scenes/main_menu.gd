extends Control
## Entry menu: choose a world and whether to use the active ragdoll character.


const PLANET_SCENE_PATH: String = "res://scenes/planet_test.tscn"
const BOXED_IN_TERRAIN_SCENE_PATH: String = "res://scenes/boxed_in_terrain_test.tscn"
const OPEN_TERRAIN_SCENE_PATH: String = "res://scenes/open_terrain_test.tscn"
const BATTLEFIELD_TERRAIN_SCENE_PATH: String = "res://scenes/battlefield_terrain_test.tscn"
const TERRARIUM_SCENE_PATH: String = "res://scenes/terrarium_test.tscn"
const LOADING_SCREEN_SCENE_PATH: String = "res://scenes/loading_screen.tscn"

@onready var _title: Label = $UI/Margin/VBox/Title
@onready var _planet_button: Button = $UI/Margin/VBox/Buttons/PlanetButton
@onready var _boxed_in_terrain_button: Button = $UI/Margin/VBox/Buttons/BoxedInTerrainButton
@onready var _open_terrain_button: Button = $UI/Margin/VBox/Buttons/OpenTerrainButton
@onready var _battlefield_button: Button = $UI/Margin/VBox/Buttons/BattlefieldButton
@onready var _terrarium_button: Button = $UI/Margin/VBox/Buttons/TerrariumButton
@onready var _ragdoll_checkbox: CheckButton = $UI/Margin/VBox/Buttons/RagdollCheck


func _ready() -> void:
	_title.text = str(ProjectSettings.get_setting("application/config/name", "PhysicsRoyale"))
	_ragdoll_checkbox.button_pressed = LoadingScreen.use_ragdoll_character
	_ragdoll_checkbox.toggled.connect(_on_ragdoll_toggled)
	_planet_button.pressed.connect(_on_planet_pressed)
	_boxed_in_terrain_button.pressed.connect(_on_boxed_in_terrain_pressed)
	_open_terrain_button.pressed.connect(_on_open_terrain_pressed)
	_battlefield_button.pressed.connect(_on_battlefield_pressed)
	_terrarium_button.pressed.connect(_on_terrarium_pressed)


func _on_ragdoll_toggled(enabled: bool) -> void:
	LoadingScreen.use_ragdoll_character = enabled


func _on_planet_pressed() -> void:
	_open_scene(PLANET_SCENE_PATH)


func _on_boxed_in_terrain_pressed() -> void:
	_open_scene(BOXED_IN_TERRAIN_SCENE_PATH)


func _on_open_terrain_pressed() -> void:
	_open_scene(OPEN_TERRAIN_SCENE_PATH)


func _on_battlefield_pressed() -> void:
	_open_scene(BATTLEFIELD_TERRAIN_SCENE_PATH)


func _on_terrarium_pressed() -> void:
	_open_scene(TERRARIUM_SCENE_PATH)


func _open_scene(scene_path: String) -> void:
	LoadingScreen.pending_scene_path = scene_path
	get_tree().change_scene_to_file(LOADING_SCREEN_SCENE_PATH)
