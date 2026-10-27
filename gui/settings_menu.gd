extends Control
## Shared settings page (graphics quality, controls list). Used by the main menu and pause menu.
## Esc / Pause steps back: Controls -> Settings -> closed.

signal closed

enum GraphicsItem { HIGH, LOW }

const _GRAPHICS_DESCRIPTIONS: Dictionary[GraphicsItem, String] = {
	GraphicsItem.HIGH: "Full resolution, glow, ambient occlusion, and all shadows.",
	GraphicsItem.LOW: "Half 3D resolution (upscaled), no glow or ambient occlusion, fewer shadows, simpler water and sky.",
}

const _CONTROLS_LINES: Array[String] = [
	"W / S — Move forward / backward",
	"Mouse — Turn player",
	"Mouse — Camera pitch",
	"Middle mouse + drag — Orbit camera",
	"Scroll wheel — Zoom in / out",
	"Space — Jump",
	"Hold W against a steep wall — Climb it (Space to let go; F grabs or lets go instantly)",
	"Space in mid-air — Take off (Wasp); hold Space to rise while flying",
	"C — Descend while flying",
	"Shift — Run",
	"E — Inventory (torch, pickaxe, empty hands)",
	"P — Pause menu",
	"Esc — Free / capture mouse (or stow item / exit terrain edit)",
	"F3 — Debug overlay",
	"Ctrl — Toggle terrain focus while editing (stay put, aim with mouse)",
	"Left click — Shoot (weapon equipped)",
	"Right click — Aim over the shoulder (any weapon; tap to toggle, hold to aim)",
	"V / right stick click — Cycle zoom: shoulder, scope, closer scope, back out (scoped weapons)",
	"Mouse wheel while scoped — Step the zoom in or out",
	"Hold left click — Paint terrain (pickaxe equipped)",
]

## Dims whatever is behind the page. Off when the parent already has its own dimmer.
@export var show_backdrop: bool = true

@onready var _backdrop: ColorRect = $Backdrop
@onready var _panel: PanelContainer = $Center/Panel
@onready var _settings_page: VBoxContainer = $Center/Panel/Margin/SettingsPage
@onready var _controls_page: VBoxContainer = $Center/Panel/Margin/ControlsPage
@onready var _graphics_option: OptionButton = $Center/Panel/Margin/SettingsPage/GraphicsRow/GraphicsOption
@onready var _graphics_description: Label = $Center/Panel/Margin/SettingsPage/GraphicsDescription
@onready var _controls_button: Button = $Center/Panel/Margin/SettingsPage/ControlsButton
@onready var _back_button: Button = $Center/Panel/Margin/SettingsPage/BackButton
@onready var _controls_scroll: ScrollContainer = $Center/Panel/Margin/ControlsPage/ControlsScroll
@onready var _controls_text: RichTextLabel = $Center/Panel/Margin/ControlsPage/ControlsScroll/ControlsText
@onready var _controls_back_button: Button = $Center/Panel/Margin/ControlsPage/BackButton


func _ready() -> void:
	visible = false
	_backdrop.visible = show_backdrop
	# A bulleted list: a line that wraps indents under its own text, not under the bullet.
	_controls_text.text = "[ul]%s[/ul]" % "\n".join(_CONTROLS_LINES)
	_controls_text.minimum_size_changed.connect(_fit_controls)
	_graphics_option.clear()
	_graphics_option.add_item("High", GraphicsItem.HIGH)
	_graphics_option.add_item("Low", GraphicsItem.LOW)
	_graphics_option.item_selected.connect(_on_graphics_selected)
	_controls_button.pressed.connect(_show_controls_page)
	_back_button.pressed.connect(close)
	_controls_back_button.pressed.connect(_show_settings_page)
	get_viewport().size_changed.connect(_fit_controls)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		return
	if _controls_page.visible:
		_show_settings_page()
	else:
		close()
	get_viewport().set_input_as_handled()


func open() -> void:
	_sync_graphics_option()
	_show_settings_page()
	visible = true
	_graphics_option.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _sync_graphics_option() -> void:
	var item: GraphicsItem = GraphicsItem.LOW if GraphicsSettings.low_quality else GraphicsItem.HIGH
	_graphics_option.select(_graphics_option.get_item_index(item))
	_graphics_description.text = _GRAPHICS_DESCRIPTIONS[item]


func _on_graphics_selected(index: int) -> void:
	var item: GraphicsItem = _graphics_option.get_item_id(index) as GraphicsItem
	GraphicsSettings.set_low_quality(item == GraphicsItem.LOW)
	_graphics_description.text = _GRAPHICS_DESCRIPTIONS[item]


func _show_settings_page() -> void:
	_settings_page.visible = true
	_controls_page.visible = false
	_panel.custom_minimum_size = Vector2(360, 0)


## The controls list scrolls instead of pushing the panel off a short window: the scroll box
## takes the list's full height when it fits, and the window's height minus room for the title,
## the Back button and the margins when it does not.
func _fit_controls() -> void:
	if not _controls_page.visible:
		return
	var available: float = get_viewport_rect().size.y - 180.0
	_controls_scroll.custom_minimum_size.y = clampf(_controls_text.get_combined_minimum_size().y, 0.0, maxf(available, 120.0))


func _show_controls_page() -> void:
	_settings_page.visible = false
	_controls_page.visible = true
	_panel.custom_minimum_size = Vector2(420, 0)
	# The label wraps to the scroll box's width on the next layout pass, so measure it then.
	_fit_controls.call_deferred()
	_controls_back_button.grab_focus()
