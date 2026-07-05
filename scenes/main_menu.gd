extends Control
## Entry menu: choose planet or flat terrain play mode.


const PLANET_SCENE_PATH: String = "res://scenes/planet_test.tscn"
const FLAT_TERRAIN_SCENE_PATH: String = "res://scenes/flat_terrain_test.tscn"
const LOADING_SCREEN_SCENE_PATH: String = "res://scenes/loading_screen.tscn"

@onready var _title: Label = $UI/Margin/VBox/Title
@onready var _planet_button: Button = $UI/Margin/VBox/Buttons/PlanetButton
@onready var _flat_terrain_button: Button = $UI/Margin/VBox/Buttons/FlatTerrainButton


func _ready() -> void:
	_title.text = str(ProjectSettings.get_setting("application/config/name", "PhysicsRoyale"))
	_planet_button.pressed.connect(_on_planet_pressed)
	_flat_terrain_button.pressed.connect(_on_flat_terrain_pressed)


func _on_planet_pressed() -> void:
	_open_scene(PLANET_SCENE_PATH)


func _on_flat_terrain_pressed() -> void:
	_open_scene(FLAT_TERRAIN_SCENE_PATH)


func _open_scene(scene_path: String) -> void:
	LoadingScreen.pending_scene_path = scene_path
	get_tree().change_scene_to_file(LOADING_SCREEN_SCENE_PATH)
