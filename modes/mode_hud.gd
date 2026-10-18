extends CanvasLayer
class_name ModeHud
## Game mode overlay: a status line at the top, timed messages in the middle, and an end-of-match
## panel with Play Again / Main Menu.

signal play_again_pressed
signal main_menu_pressed

var _status: Label
var _message: Label
var _message_time_left: float = 0.0
var _end_panel: PanelContainer
var _end_title: Label
var _end_subtitle: Label


func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS

	_status = _make_label(22)
	_status.anchor_left = 0.0
	_status.anchor_right = 1.0
	_status.offset_top = 10.0
	_status.offset_bottom = 44.0
	add_child(_status)

	_message = _make_label(34)
	_message.anchor_left = 0.0
	_message.anchor_right = 1.0
	_message.anchor_top = 0.32
	_message.anchor_bottom = 0.32
	_message.offset_bottom = 90.0
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_message)

	_build_end_panel()


func _process(delta: float) -> void:
	if _message_time_left > 0.0:
		_message_time_left -= delta
		_message.modulate.a = clampf(_message_time_left / 0.6, 0.0, 1.0)
		if _message_time_left <= 0.0:
			_message.text = ""


func set_status(text: String) -> void:
	_status.text = text


## Shows a centered message; seconds <= 0 keeps it until replaced.
func show_message(text: String, seconds: float = 3.0) -> void:
	_message.text = text
	_message.modulate.a = 1.0
	_message_time_left = seconds if seconds > 0.0 else INF


func show_end(title: String, subtitle: String) -> void:
	_end_title.text = title
	_end_subtitle.text = subtitle
	_end_panel.visible = true
	_message.text = ""
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _build_end_panel() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_end_panel = PanelContainer.new()
	_end_panel.custom_minimum_size = Vector2(420, 0)
	_end_panel.visible = false
	center.add_child(_end_panel)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_end_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	_end_title = _make_label(36)
	column.add_child(_end_title)
	_end_subtitle = _make_label(18)
	_end_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_end_subtitle)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	var play_again := Button.new()
	play_again.text = "Play Again"
	play_again.custom_minimum_size = Vector2(150, 40)
	play_again.pressed.connect(play_again_pressed.emit)
	buttons.add_child(play_again)
	var main_menu := Button.new()
	main_menu.text = "Main Menu"
	main_menu.custom_minimum_size = Vector2(150, 40)
	main_menu.pressed.connect(main_menu_pressed.emit)
	buttons.add_child(main_menu)
