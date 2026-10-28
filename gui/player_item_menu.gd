extends VBoxContainer
class_name PlayerItemMenu
## Popup list of hand items; selection activates torch or pickaxe / terrain edit.


signal item_selected(item: PlayerItems.Item)
## The player picked what the pickaxe builds with; emitted just before item_selected(PICKAXE_ADD).
signal add_material_selected(material: TerrainMaterials.Kind)
## The player toggled between the sculpting ball and the grid-snapped block.
signal brush_shape_selected(shape: TerrainBrush.Shape)

@onready var _toggle_button: Button = $ToggleButton
@onready var _popup: PanelContainer = $Popup
@onready var _none_button: Button = $Popup/Margin/Scroll/Buttons/NoneButton
@onready var _torch_button: Button = $Popup/Margin/Scroll/Buttons/TorchButton
@onready var _pickaxe_destroy_button: Button = $Popup/Margin/Scroll/Buttons/PickaxeDestroyButton
@onready var _pickaxe_add_button: Button = $Popup/Margin/Scroll/Buttons/PickaxeAddButton
@onready var _weapon_buttons_container: VBoxContainer = $Popup/Margin/Scroll/Buttons/WeaponButtons

var _open: bool = false
var _active_item: PlayerItems.Item = PlayerItems.Item.NONE
var _add_material: TerrainMaterials.Kind = TerrainMaterials.Kind.NATURAL
var _brush_shape: TerrainBrush.Shape = TerrainBrush.Shape.SPHERE
var _block_size: int = 2
var _shape_button: Button
var _weapon_buttons: Dictionary = {}
## TerrainMaterials.Kind -> its "Pickaxe — add" button (NATURAL is the scene's PickaxeAddButton).
var _material_buttons: Dictionary = {}


func _ready() -> void:
	add_to_group("player_item_menu")
	_toggle_button.focus_mode = Control.FOCUS_NONE
	for button: Button in [
		_none_button,
		_torch_button,
		_pickaxe_destroy_button,
		_pickaxe_add_button,
	]:
		button.focus_mode = Control.FOCUS_NONE
	_toggle_button.pressed.connect(_on_toggle_pressed)
	_none_button.pressed.connect(_select.bind(PlayerItems.Item.NONE))
	_torch_button.pressed.connect(_select.bind(PlayerItems.Item.TORCH))
	_pickaxe_destroy_button.pressed.connect(_select.bind(PlayerItems.Item.PICKAXE_DESTROY))
	_pickaxe_add_button.pressed.connect(_select_add_material.bind(TerrainMaterials.Kind.NATURAL))
	_material_buttons[TerrainMaterials.Kind.NATURAL] = _pickaxe_add_button
	_build_material_buttons()
	_build_weapon_buttons()
	_set_open(false)
	_refresh_buttons()


func is_open() -> bool:
	return _open


func toggle_menu() -> void:
	_set_open(not _open)


func close_menu() -> void:
	_set_open(false)


func set_active_item(item: PlayerItems.Item) -> void:
	_active_item = item
	_refresh_buttons()


func set_add_material(material: TerrainMaterials.Kind) -> void:
	_add_material = material
	_refresh_buttons()


func get_add_material() -> TerrainMaterials.Kind:
	return _add_material


func set_brush_shape(shape: TerrainBrush.Shape) -> void:
	_brush_shape = shape
	_refresh_shape_button()


func set_block_size(size: int) -> void:
	_block_size = size
	_refresh_shape_button()


func _on_shape_pressed() -> void:
	if _brush_shape == TerrainBrush.Shape.SPHERE:
		_brush_shape = TerrainBrush.Shape.BLOCK
	else:
		_brush_shape = TerrainBrush.Shape.SPHERE
	_refresh_shape_button()
	brush_shape_selected.emit(_brush_shape)


func _refresh_shape_button() -> void:
	if _shape_button == null:
		return
	if _brush_shape == TerrainBrush.Shape.BLOCK:
		_shape_button.text = "Brush shape — %d-voxel block (build by clicking; B; [ ] size)" % _block_size
	else:
		_shape_button.text = "Brush shape — ball (sculpt by holding; B)"


func _select_add_material(material: TerrainMaterials.Kind) -> void:
	_add_material = material
	add_material_selected.emit(material)
	_select(PlayerItems.Item.PICKAXE_ADD)


func _select(item: PlayerItems.Item) -> void:
	item_selected.emit(item)
	close_menu()


func _on_toggle_pressed() -> void:
	toggle_menu()


func _set_open(open: bool) -> void:
	_open = open
	_popup.visible = open
	_toggle_button.text = "Inventory (E) ▲" if open else "Inventory (E) ▼"
	if open:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		var hud: Node = get_tree().get_first_node_in_group("terrain_hud")
		if hud != null and hud.has_method("sync_mouse_mode"):
			hud.sync_mouse_mode()


func _refresh_buttons() -> void:
	_reset_button_style(_none_button, _active_item == PlayerItems.Item.NONE)
	_reset_button_style(_torch_button, _active_item == PlayerItems.Item.TORCH)
	_reset_button_style(
		_pickaxe_destroy_button,
		_active_item == PlayerItems.Item.PICKAXE_DESTROY
	)
	for material: TerrainMaterials.Kind in _material_buttons.keys():
		var material_button: Button = _material_buttons[material] as Button
		_reset_button_style(
			material_button,
			_active_item == PlayerItems.Item.PICKAXE_ADD and _add_material == material
		)
	for weapon_item: PlayerItems.Item in _weapon_buttons.keys():
		var weapon_button: Button = _weapon_buttons[weapon_item] as Button
		_reset_button_style(weapon_button, _active_item == weapon_item)


## One "Pickaxe — add <material>" row per placed material, after the plain add-terrain button,
## each with a swatch of the colour it builds in.
func _build_material_buttons() -> void:
	var buttons: Node = _pickaxe_add_button.get_parent()
	var insert_index: int = _pickaxe_add_button.get_index() + 1
	for material: TerrainMaterials.Kind in TerrainMaterials.PLACEABLE:
		if material == TerrainMaterials.Kind.NATURAL:
			continue
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var swatch: ColorRect = ColorRect.new()
		swatch.color = TerrainMaterials.color(material)
		swatch.custom_minimum_size = Vector2(18, 18)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
		var material_button: Button = Button.new()
		material_button.text = "Pickaxe — add %s" % TerrainMaterials.display_name(material).to_lower()
		material_button.focus_mode = Control.FOCUS_NONE
		material_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		material_button.pressed.connect(_select_add_material.bind(material))
		row.add_child(material_button)
		buttons.add_child(row)
		buttons.move_child(row, insert_index)
		insert_index += 1
		_material_buttons[material] = material_button
	# The shape toggle stays open so the player can flip it and pick a material in one visit.
	_shape_button = Button.new()
	_shape_button.focus_mode = Control.FOCUS_NONE
	_shape_button.pressed.connect(_on_shape_pressed)
	buttons.add_child(_shape_button)
	buttons.move_child(_shape_button, insert_index)
	_refresh_shape_button()


func _build_weapon_buttons() -> void:
	for weapon_item: PlayerItems.Item in PlayerItems.WEAPON_ITEMS:
		var weapon_button: Button = Button.new()
		weapon_button.text = PlayerItems.weapon_display_name(weapon_item)
		weapon_button.focus_mode = Control.FOCUS_NONE
		weapon_button.pressed.connect(_select.bind(weapon_item))
		_weapon_buttons_container.add_child(weapon_button)
		_weapon_buttons[weapon_item] = weapon_button


func _reset_button_style(button: Button, active: bool) -> void:
	button.modulate = Color(0.55, 1.0, 0.65) if active else Color.WHITE
