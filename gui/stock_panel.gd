class_name StockPanel
extends PanelContainer
## What the pickaxe has to build with: one row per material with its swatch and voxel count,
## the material the brush is set to marked, empty kinds dimmed. Sits at the right edge of the
## mode HUD and redraws only when the numbers change.

var _rows: Dictionary = {}
var _title: Label
var _last_key: String = ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_right = -16.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.92

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	_title = Label.new()
	_title.text = "Dug"
	_title.add_theme_font_size_override("font_size", 15)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_title)
	for kind: TerrainMaterials.Kind in TerrainMaterials.PLACEABLE:
		if kind == TerrainMaterials.Kind.NATURAL:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var swatch := ColorRect.new()
		swatch.color = TerrainMaterials.color(kind)
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
		var label := Label.new()
		label.custom_minimum_size = Vector2(110, 0)
		label.add_theme_font_size_override("font_size", 15)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(label)
		column.add_child(row)
		_rows[kind] = row


## Shows the counts (TerrainMaterials.Kind -> voxels); `selected` is the brush's material.
func show_stock(counts: Dictionary, selected: int) -> void:
	var key: String = "%s|%d" % [str(counts), selected]
	if key == _last_key:
		return
	_last_key = key
	var marked: int = MaterialStock.cost_kind(selected)
	for kind: TerrainMaterials.Kind in _rows:
		var row: HBoxContainer = _rows[kind]
		var count: int = int(counts.get(kind, 0))
		var label: Label = row.get_child(1) as Label
		label.text = "%s  %d" % [TerrainMaterials.display_name(kind), count]
		var tint: Color = Color(0.55, 1.0, 0.65) if kind == marked else Color.WHITE
		if count == 0:
			tint.a = 0.45
		row.modulate = tint
