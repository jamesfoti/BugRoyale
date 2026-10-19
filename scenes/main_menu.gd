extends Control
## Entry menu: pick a game mode, then a map (see ModeCatalog), and the player class; or settings.


const LOADING_SCREEN_SCENE_PATH: String = "res://scenes/loading_screen.tscn"
## Extra space around the character in the Choose Player preview.
const PREVIEW_FRAMING_PADDING: float = 1.15

## The title and button column. Hidden while a page (Choose Player, Settings, map pick) is open,
## the way the pause menu hides its own panel behind Settings, so nothing shows through.
@onready var _main_page: Control = $UI/Margin
@onready var _title: Label = $UI/Margin/VBox/Title
@onready var _hornets_button: Button = $UI/Margin/VBox/Buttons/HornetsButton
@onready var _ants_vs_ants_button: Button = $UI/Margin/VBox/Buttons/AntsVsAntsButton
@onready var _battle_royale_button: Button = $UI/Margin/VBox/Buttons/BattleRoyaleButton
@onready var _choose_player_button: Button = $UI/Margin/VBox/Buttons/ChoosePlayerButton
@onready var _settings_button: Button = $UI/Margin/VBox/Buttons/SettingsButton
@onready var _settings_menu: Control = $UI/SettingsMenu
@onready var _player_select_page: Control = $UI/PlayerSelectPage
@onready var _player_name_label: Label = $UI/PlayerSelectPage/CenterPanel/Margin/VBox/PlayerName
@onready var _player_description_label: Label = $UI/PlayerSelectPage/CenterPanel/Margin/VBox/PlayerDescription
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
var _preview_selected_character: LoadingScreen.PlayerCharacter = LoadingScreen.PlayerCharacter.ANT_WARRIOR


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_sky_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_set_preview_viewport_active(false)
	_title.text = str(ProjectSettings.get_setting("application/config/name", "BugRoyale"))
	_setup_preview_scenes()
	_preview_selected_character = LoadingScreen.selected_player_character
	_choose_player_button.pressed.connect(_on_choose_player_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_settings_menu.closed.connect(_on_settings_closed)
	_preview_use_button.pressed.connect(_on_preview_use_pressed)
	_preview_previous_button.pressed.connect(_cycle_preview_character.bind(-1))
	_preview_next_button.pressed.connect(_cycle_preview_character.bind(1))
	# Cycling needs at least two characters; the buttons stay for future bugs.
	var has_choices: bool = LoadingScreen.PlayerCharacter.size() > 1
	_preview_previous_button.disabled = not has_choices
	_preview_next_button.disabled = not has_choices
	_preview_back_button.pressed.connect(_on_preview_back_pressed)
	_hornets_button.pressed.connect(_on_mode_pressed.bind("hornets"))
	_ants_vs_ants_button.pressed.connect(_on_mode_pressed.bind("ants_vs_ants"))
	_battle_royale_button.pressed.connect(_on_mode_pressed.bind("battle_royale"))
	_hornets_button.tooltip_text = ModeCatalog.mode("hornets").get("description", "")
	_ants_vs_ants_button.tooltip_text = ModeCatalog.mode("ants_vs_ants").get("description", "")
	_battle_royale_button.tooltip_text = ModeCatalog.mode("battle_royale").get("description", "")
	_build_map_page()
	# The preview character is only spawned while the Choose Player page is open.


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


## Swaps the main button column for a page, or back. Returning refocuses the button that opened
## the page so keyboard and gamepad navigation picks up where it left off.
func _show_main_page(focus_button: Button = null) -> void:
	_main_page.visible = true
	if focus_button != null:
		focus_button.grab_focus()


func _hide_main_page() -> void:
	_main_page.visible = false


func _on_settings_pressed() -> void:
	_hide_main_page()
	_settings_menu.open()


func _on_settings_closed() -> void:
	_show_main_page(_settings_button)


func _on_choose_player_pressed() -> void:
	_preview_selected_character = LoadingScreen.selected_player_character
	_hide_main_page()
	_player_select_page.visible = true
	_set_preview_viewport_active(true)
	_update_preview_display()
	_preview_use_button.grab_focus()


func _on_preview_use_pressed() -> void:
	_set_selected_character(_preview_selected_character)
	_close_player_select_page()


func _on_preview_back_pressed() -> void:
	_close_player_select_page()
	_preview_selected_character = LoadingScreen.selected_player_character


func _close_player_select_page() -> void:
	_player_select_page.visible = false
	_set_preview_viewport_active(false)
	_clear_preview_character()
	_show_main_page(_choose_player_button)


func _clear_preview_character() -> void:
	if _preview_instance != null:
		_preview_instance.queue_free()
		_preview_instance = null


func _set_selected_character(selected_character: LoadingScreen.PlayerCharacter) -> void:
	LoadingScreen.selected_player_character = selected_character


func _update_preview_display() -> void:
	var selected_character: LoadingScreen.PlayerCharacter = _preview_selected_character
	_player_name_label.text = _display_name_for_character(selected_character)
	_player_description_label.text = "%s\n%s" % [
		CharacterSkin.role_for(selected_character), CharacterSkin.description_for(selected_character)
	]
	_spawn_preview_character(selected_character)


func _spawn_preview_character(selected_character: LoadingScreen.PlayerCharacter) -> void:
	_clear_preview_character()

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


func _display_name_for_character(selected_character: LoadingScreen.PlayerCharacter) -> String:
	return CharacterSkin.display_name_for(selected_character)


func _set_preview_viewport_active(active: bool) -> void:
	if _preview_viewport == null:
		return
	_preview_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	)


# --- Play flow: mode -> map -> start --------------------------------------------------------

var _map_page: Control
var _map_page_title: Label
var _map_page_description: Label
var _map_buttons: VBoxContainer
var _chosen_mode_id: String = ""


func _on_mode_pressed(mode_id: String) -> void:
	_chosen_mode_id = mode_id
	var mode_info: Dictionary = ModeCatalog.mode(mode_id)
	var maps: Array = mode_info.get("maps", [])
	if maps.size() == 1:
		_start_match(maps[0])
		return
	_map_page_title.text = mode_info.get("name", "") + ": Choose a Map"
	_map_page_description.text = mode_info.get("description", "")
	for child: Node in _map_buttons.get_children():
		child.queue_free()
	for map_id: String in maps:
		var map_button := Button.new()
		map_button.text = ModeCatalog.map_name(map_id)
		map_button.custom_minimum_size = Vector2(280, 44)
		map_button.pressed.connect(_start_match.bind(map_id))
		_map_buttons.add_child(map_button)
	_hide_main_page()
	_map_page.visible = true
	if _map_buttons.get_child_count() > 0:
		(_map_buttons.get_child(0) as Button).grab_focus()


func _close_map_page() -> void:
	_map_page.visible = false
	var mode_buttons: Dictionary = {
		"hornets": _hornets_button, "ants_vs_ants": _ants_vs_ants_button, "battle_royale": _battle_royale_button,
	}
	_show_main_page(mode_buttons.get(_chosen_mode_id) as Button)


func _start_match(map_id: String) -> void:
	var mode_info: Dictionary = ModeCatalog.mode(_chosen_mode_id)
	if mode_info.has("forced_character"):
		_set_selected_character(mode_info["forced_character"])
	LoadingScreen.pending_mode_id = _chosen_mode_id
	LoadingScreen.pending_scene_path = ModeCatalog.map_scene(map_id)
	get_tree().change_scene_to_file(LOADING_SCREEN_SCENE_PATH)


func _build_map_page() -> void:
	_map_page = Control.new()
	_map_page.name = "MapSelectPage"
	_map_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_page.visible = false
	$UI.add_child(_map_page)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	_map_page.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_page.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	_map_page_title = Label.new()
	_map_page_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_page_title.add_theme_font_size_override("font_size", 22)
	column.add_child(_map_page_title)
	_map_page_description = Label.new()
	_map_page_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_page_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_page_description.custom_minimum_size = Vector2(380, 0)
	_map_page_description.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
	column.add_child(_map_page_description)
	_map_buttons = VBoxContainer.new()
	_map_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_map_buttons.add_theme_constant_override("separation", 8)
	column.add_child(_map_buttons)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_close_map_page)
	column.add_child(back)
