extends Control
class_name CrosshairHud
## Center-screen aim reticle shown while a weapon is equipped.


@export var crosshair_size: float = 8.0
@export var crosshair_thickness: float = 2.0
@export var crosshair_gap: float = 4.0
@export var crosshair_color: Color = Color(0.95, 0.98, 1.0, 0.9)
@export var crosshair_outline_color: Color = Color(0.0, 0.0, 0.0, 0.45)
@export var crosshair_outline_thickness: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func _process(_delta: float) -> void:
	var should_show: bool = _should_show_crosshair()
	if visible != should_show:
		visible = should_show
	if visible:
		queue_redraw()


func _draw() -> void:
	var center: Vector2 = _get_crosshair_center()
	var half_thickness: float = crosshair_thickness * 0.5
	var outline_offset: float = crosshair_outline_thickness

	var horizontal_left: Rect2 = Rect2(
		center.x - crosshair_gap - crosshair_size,
		center.y - half_thickness,
		crosshair_size,
		crosshair_thickness
	)
	var horizontal_right: Rect2 = Rect2(
		center.x + crosshair_gap,
		center.y - half_thickness,
		crosshair_size,
		crosshair_thickness
	)
	var vertical_top: Rect2 = Rect2(
		center.x - half_thickness,
		center.y - crosshair_gap - crosshair_size,
		crosshair_thickness,
		crosshair_size
	)
	var vertical_bottom: Rect2 = Rect2(
		center.x - half_thickness,
		center.y + crosshair_gap,
		crosshair_thickness,
		crosshair_size
	)

	for crosshair_rect: Rect2 in [horizontal_left, horizontal_right, vertical_top, vertical_bottom]:
		var outline_rect: Rect2 = crosshair_rect.grow(outline_offset)
		draw_rect(outline_rect, crosshair_outline_color)
		draw_rect(crosshair_rect, crosshair_color)


func _should_show_crosshair() -> bool:
	if get_tree().paused:
		return false
	if _is_item_menu_open():
		return false
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return false
	if not PlayerItems.is_weapon(_get_equipped_weapon_item()):
		return false
	var orbit_camera: OrbitCamera = _get_orbit_camera()
	return orbit_camera != null and orbit_camera.is_aiming()


func _is_item_menu_open() -> bool:
	var item_menu: Node = get_tree().get_first_node_in_group("player_item_menu")
	if item_menu == null or not item_menu.has_method("is_open"):
		return false
	return item_menu.call("is_open")


func _get_equipped_weapon_item() -> PlayerItems.Item:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return PlayerItems.Item.NONE
	var visual_root: Node = player.get_node_or_null("VisualRoot")
	if visual_root == null or visual_root.get_child_count() == 0:
		return PlayerItems.Item.NONE
	var skin_node: Node = visual_root.get_child(0)
	if skin_node == null or not skin_node.has_method("get_equipped_weapon_item"):
		return PlayerItems.Item.NONE
	return skin_node.call("get_equipped_weapon_item")


func _get_orbit_camera() -> OrbitCamera:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return null
	return player.get_node_or_null("OrbitCamera") as OrbitCamera


func _get_crosshair_center() -> Vector2:
	var orbit_camera: OrbitCamera = _get_orbit_camera()
	if orbit_camera != null:
		return orbit_camera.get_crosshair_screen_position(size)
	return size * 0.5
