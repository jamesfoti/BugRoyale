class_name FighterBody
extends CharacterBody3D
## A bug on the map: the player at this keyboard, a bot, or (later) a remote player. The body
## moves, climbs, shoots and animates; what it does each physics frame comes from its
## FighterController child as a FighterInput, so one body serves every kind of pilot. The
## subclasses (GroundPlayer, CelestialBodyPlayer) supply the movement for their world. Everything
## that belongs to the one human at this machine (HUD, inventory, terrain focus, mouse capture)
## only runs when is_local.

const _MIN_DIR_LEN_SQ: float = 0.0001

## Which bug this body is: skin, stats and weapon. Set before the body enters the tree.
var character: LoadingScreen.PlayerCharacter = LoadingScreen.selected_player_character
## Bots wear the lighter bot skin of their class (or an explicit scene, e.g. the black ant).
var use_bot_skin: bool = false
var skin_override_path: String = ""
## The local player finds its own spot on the ground when it enters the tree; bots and remote
## players are placed by whoever spawned them (respawn_at).
var auto_spawn: bool = true
## The pilot. Found among the children on ready; a body without one gets the local controller.
var controller: FighterController
var is_local: bool = false
## The match's number for this fighter (Fighter.id); 0 outside a match.
var fighter_id: int = 0

var _intent: FighterInput = FighterInput.new()
var _in_play: bool = true
var _spawned: bool = false
var _terrain_focus: bool = false
var _anim_state: String = ""
var _skin: CharacterSkin
var _visual_root: Node3D
var _shooter: Node


func _ready() -> void:
	add_to_group("fighter")
	_visual_root = get_node_or_null("VisualRoot") as Node3D
	_skin = CharacterSkin.install(_visual_root, character, use_bot_skin, skin_override_path)
	for child: Node in get_children():
		if child is FighterController:
			controller = child as FighterController
			break
	if controller == null:
		controller = LocalFighterController.new()
		controller.name = "LocalFighterController"
		add_child(controller)
	is_local = controller.is_local()
	_shooter = get_node_or_null("ShooterTest")
	if is_local:
		call_deferred("_connect_terrain_hud")


# --- Pilot ------------------------------------------------------------------------------------


## Asks the controller what to do this frame and hands the shot part to the weapon. Called once
## per physics step by the subclass, before it moves.
func sample_input(delta: float) -> void:
	_intent = controller.sample(self, delta) if controller != null else FighterInput.new()
	if not is_local and _shooter != null and _shooter.has_method("handle_input"):
		_shooter.call("handle_input", _intent)


func get_input() -> FighterInput:
	return _intent


## The input's forward, flattened onto the surface the body stands on; falls back to the input's
## up (a camera looking straight down the surface normal) and then to the body's own facing.
func get_view_flat_forward() -> Vector3:
	var surface_up: Vector3 = get_surface_up()
	var forward: Vector3 = _intent.view_forward.slide(surface_up)
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		forward = _intent.view_up.slide(surface_up)
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		return _get_flat_forward()
	return forward.normalized()


func get_view_flat_right() -> Vector3:
	var forward: Vector3 = get_view_flat_forward()
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		return Vector3.ZERO
	return forward.cross(get_surface_up()).normalized()


## Up of whatever the body stands on (world up, a climbed wall, the celestial body's radial).
func get_surface_up() -> Vector3:
	return Vector3.UP


## Where the model faces, flattened onto the surface. Subclasses implement.
func _get_flat_forward() -> Vector3:
	return Vector3.FORWARD


# --- In and out of play -----------------------------------------------------------------------


func is_in_play() -> bool:
	return _in_play


func is_spawned() -> bool:
	return _spawned


## Out of play (dead): frozen, hidden, not collidable, not thinking. Back in play: the reverse.
func set_in_play(active: bool) -> void:
	_in_play = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if _visual_root != null:
		_visual_root.visible = active
	collision_layer = MapInfo.FIGHTER_LAYER if active else 0
	if not active:
		velocity = Vector3.ZERO


## Puts the body back in play at a position, or at a random spot on the ground when INF.
func respawn_at(position_on_map: Vector3 = Vector3.INF) -> void:
	set_in_play(true)
	if position_on_map == Vector3.INF:
		respawn_random()
	else:
		_place_at(position_on_map)


## Subclasses: a fresh spawn at a random ground spot.
func respawn_random() -> void:
	pass


## Subclasses: a fresh spawn at a given spot.
func _place_at(_position_on_map: Vector3) -> void:
	pass


## Multiplies every movement speed the subclass exposes (a husk's shamble).
func scale_speed(factor: float) -> void:
	for property: String in [
		"speed", "run_speed", "climb_speed", "climb_run_speed", "fly_speed", "fly_run_speed"
	]:
		if property in self:
			set(property, float(get(property)) * factor)


# --- Skin and animation -----------------------------------------------------------------------


func get_skin() -> CharacterSkin:
	return _skin


func _get_skin() -> CharacterSkin:
	return _skin


func get_visual_root() -> Node3D:
	return _visual_root


func _set_anim_state(skin: CharacterSkin, state_name: String) -> void:
	if _anim_state == state_name:
		return
	_anim_state = state_name
	skin.set_state(state_name)


# --- Terrain editing, inventory and the HUD (the local player only) ---------------------------


func is_terrain_focus_active() -> bool:
	return _terrain_focus


func exit_terrain_focus() -> void:
	_set_terrain_focus(false)


## True while a menu or the terrain focus has the controls: the body idles.
func is_ui_blocking() -> bool:
	return is_local and (_terrain_focus or _is_item_menu_open())


func _set_terrain_focus(enabled: bool) -> void:
	if _terrain_focus == enabled:
		return
	_terrain_focus = enabled
	velocity = Vector3.ZERO
	if not is_local:
		return
	if _terrain_focus:
		Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _is_terrain_edit_active() -> bool:
	if not is_local:
		return false
	var terrain_brush: TerrainBrush = (
		get_tree().get_first_node_in_group("terrain_brush") as TerrainBrush
	)
	return terrain_brush != null and terrain_brush.get_edit_mode() != TerrainBrush.EditMode.OFF


func _is_item_menu_open() -> bool:
	if not is_local:
		return false
	var player_item_menu: PlayerItemMenu = (
		get_tree().get_first_node_in_group("player_item_menu") as PlayerItemMenu
	)
	return player_item_menu != null and player_item_menu.is_open()


func _terrain_hud() -> CanvasLayer:
	if not is_local:
		return null
	return get_tree().get_first_node_in_group("terrain_hud") as CanvasLayer


func _connect_terrain_hud() -> void:
	var terrain_hud_layer: CanvasLayer = _terrain_hud()
	if terrain_hud_layer == null:
		return
	if terrain_hud_layer.has_signal("terrain_edit_mode_changed"):
		terrain_hud_layer.terrain_edit_mode_changed.connect(_on_terrain_edit_mode_changed)
	if terrain_hud_layer.has_method("get_item_menu"):
		var player_item_menu: PlayerItemMenu = terrain_hud_layer.get_item_menu()
		if player_item_menu != null:
			player_item_menu.item_selected.connect(apply_hand_item)
	var terrain_brush: TerrainBrush = (
		get_tree().get_first_node_in_group("terrain_brush") as TerrainBrush
	)
	if terrain_brush != null:
		_on_terrain_edit_mode_changed(terrain_brush.get_edit_mode())
	if _skin != null:
		_skin.torch_equipped_changed.connect(_on_torch_equipped_changed)


## Puts an item in the bug's hands: the skin shows it, and for the local player the terrain HUD
## follows (pickaxe mode on or off) and the inventory highlights it.
func apply_hand_item(item: PlayerItems.Item) -> void:
	if not _spawned:
		return
	var skin: CharacterSkin = _skin
	if skin.is_torch_busy() or skin.is_pickaxe_busy():
		return
	var terrain_hud_layer: CanvasLayer = _terrain_hud()
	match item:
		PlayerItems.Item.NONE:
			if skin.is_torch_equipped():
				skin.stow_torch()
			if terrain_hud_layer != null and terrain_hud_layer.has_method("set_edit_mode"):
				terrain_hud_layer.set_edit_mode(TerrainBrush.EditMode.OFF)
		PlayerItems.Item.TORCH:
			if terrain_hud_layer != null and terrain_hud_layer.has_method("set_edit_mode"):
				terrain_hud_layer.set_edit_mode(TerrainBrush.EditMode.OFF)
			if not skin.is_torch_equipped():
				skin.equip_torch()
		PlayerItems.Item.PICKAXE_DESTROY, PlayerItems.Item.PICKAXE_ADD:
			if skin.is_torch_equipped():
				skin.stow_torch()
			if terrain_hud_layer != null and terrain_hud_layer.has_method("set_edit_mode"):
				terrain_hud_layer.set_edit_mode(PlayerItems.edit_mode_from_item(item))
		_:
			if PlayerItems.is_weapon(item):
				if skin.is_torch_equipped():
					skin.stow_torch()
				if terrain_hud_layer != null and terrain_hud_layer.has_method("set_edit_mode"):
					terrain_hud_layer.set_edit_mode(TerrainBrush.EditMode.OFF)
	PlayerItems.apply_weapon_visual(skin, item)
	_sync_item_menu(item)


func _toggle_item_menu() -> void:
	if get_tree().paused:
		return
	var terrain_hud_layer: CanvasLayer = _terrain_hud()
	if terrain_hud_layer == null or not terrain_hud_layer.has_method("get_item_menu"):
		return
	var player_item_menu: PlayerItemMenu = terrain_hud_layer.get_item_menu()
	if player_item_menu != null:
		player_item_menu.toggle_menu()


func _sync_item_menu(item: PlayerItems.Item) -> void:
	var terrain_hud_layer: CanvasLayer = _terrain_hud()
	if terrain_hud_layer == null or not terrain_hud_layer.has_method("get_item_menu"):
		return
	var player_item_menu: PlayerItemMenu = terrain_hud_layer.get_item_menu()
	if player_item_menu != null:
		player_item_menu.set_active_item(item)


func _on_torch_equipped_changed(equipped: bool) -> void:
	if equipped:
		_sync_item_menu(PlayerItems.Item.TORCH)
	elif not _is_terrain_edit_active():
		_sync_item_menu(PlayerItems.Item.NONE)


func _on_terrain_edit_mode_changed(mode: TerrainBrush.EditMode) -> void:
	_skin.set_terrain_edit_equipped(mode != TerrainBrush.EditMode.OFF)
	if mode != TerrainBrush.EditMode.OFF:
		_sync_item_menu(PlayerItems.item_from_edit_mode(mode))
	elif not _skin.is_torch_equipped():
		_sync_item_menu(PlayerItems.Item.NONE)


## The UI keys shared by every world: inventory, terrain focus. Movement edges (jump, climb) are
## the local controller's. Subclasses call this from their _unhandled_input.
func _handle_ui_input(event: InputEvent) -> void:
	if not is_local or get_tree().paused:
		return
	if _is_item_menu_open():
		if event.is_action_pressed("item_menu"):
			_toggle_item_menu()
			get_viewport().set_input_as_handled()
		return
	if _terrain_focus and event.is_action_pressed("ui_cancel"):
		_set_terrain_focus(false)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("terrain_focus"):
		if not _terrain_focus and not _is_terrain_edit_active():
			return
		_set_terrain_focus(not _terrain_focus)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("item_menu"):
		_toggle_item_menu()
		get_viewport().set_input_as_handled()
