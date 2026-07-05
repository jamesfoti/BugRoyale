extends Control
## Entry menu: choose planet, boxed-in terrain, or open terrain play mode.


const PLANET_SCENE_PATH: String = "res://scenes/planet_test.tscn"
const BOXED_IN_TERRAIN_SCENE_PATH: String = "res://scenes/boxed_in_terrain_test.tscn"
const OPEN_TERRAIN_SCENE_PATH: String = "res://scenes/open_terrain_test.tscn"
const LOADING_SCREEN_SCENE_PATH: String = "res://scenes/loading_screen.tscn"

@onready var _title: Label = $UI/Margin/VBox/Title
@onready var _planet_button: Button = $UI/Margin/VBox/Buttons/PlanetButton
@onready var _boxed_in_terrain_button: Button = $UI/Margin/VBox/Buttons/BoxedInTerrainButton
@onready var _open_terrain_button: Button = $UI/Margin/VBox/Buttons/OpenTerrainButton


func _ready() -> void:
	_title.text = str(ProjectSettings.get_setting("application/config/name", "PhysicsRoyale"))
	_planet_button.pressed.connect(_on_planet_pressed)
	_boxed_in_terrain_button.pressed.connect(_on_boxed_in_terrain_pressed)
	_open_terrain_button.pressed.connect(_on_open_terrain_pressed)


func _on_planet_pressed() -> void:
	_open_scene(PLANET_SCENE_PATH)


func _on_boxed_in_terrain_pressed() -> void:
	_open_scene(BOXED_IN_TERRAIN_SCENE_PATH)


func _on_open_terrain_pressed() -> void:
	_open_scene(OPEN_TERRAIN_SCENE_PATH)


func _open_scene(scene_path: String) -> void:
	LoadingScreen.pending_scene_path = scene_path
	get_tree().change_scene_to_file(LOADING_SCREEN_SCENE_PATH)
