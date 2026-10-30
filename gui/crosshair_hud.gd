class_name CrosshairHud
extends Control
## Shooter reticle. With a weapon out it draws a four-line crosshair around a center dot whose
## spread opens with the shot's actual cone (movement, firing, being airborne) and tightens when
## aiming, so what you see is where the bullets can go. Through a scope it draws the scope
## instead: a black mask with a round window and the weapon's reticle.

@export var crosshair_size: float = 12.0
@export var crosshair_thickness: float = 2.5
@export var crosshair_gap: float = 7.0
@export var dot_radius: float = 2.0
@export var crosshair_color: Color = Color(0.95, 0.98, 1.0, 0.9)
@export var crosshair_outline_color: Color = Color(0.0, 0.0, 0.0, 0.45)
@export var crosshair_outline_thickness: float = 1.0
@export var scope_window_ratio: float = 0.42
@export var scope_mask_color: Color = Color(0.0, 0.0, 0.0, 1.0)
@export var scope_line_color: Color = Color(0.05, 0.05, 0.05, 0.95)
@export var holo_color: Color = Color(1.0, 0.25, 0.2, 0.9)


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
	var orbit_camera: OrbitCamera = _get_orbit_camera()
	var scope_blend: float = orbit_camera.get_scope_blend() if orbit_camera != null else 0.0
	if scope_blend > 0.5:
		_draw_scope(PlayerItems.scope_style(_get_equipped_weapon_item()), scope_blend)
		return
	_draw_crosshair(_get_crosshair_center(), _spread_pixels())


func _draw_crosshair(center: Vector2, spread: float) -> void:
	var half_thickness: float = crosshair_thickness * 0.5
	var gap: float = crosshair_gap + spread
	var lines: Array[Rect2] = [
		Rect2(
			center.x - gap - crosshair_size,
			center.y - half_thickness,
			crosshair_size,
			crosshair_thickness
		),
		Rect2(center.x + gap, center.y - half_thickness, crosshair_size, crosshair_thickness),
		Rect2(
			center.x - half_thickness,
			center.y - gap - crosshair_size,
			crosshair_thickness,
			crosshair_size
		),
		Rect2(center.x - half_thickness, center.y + gap, crosshair_thickness, crosshair_size),
	]
	for line: Rect2 in lines:
		draw_rect(line.grow(crosshair_outline_thickness), crosshair_outline_color)
		draw_rect(line, crosshair_color)
	draw_circle(center, dot_radius + crosshair_outline_thickness, crosshair_outline_color)
	draw_circle(center, dot_radius, crosshair_color)


## Black outside a round window, then the reticle. The window shrinks in from the edges as the
## scope blend rises, so the view closes down into the eyepiece.
func _draw_scope(style: String, blend: float) -> void:
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * scope_window_ratio
	radius = lerpf(size.length(), radius, clampf((blend - 0.5) * 2.0, 0.0, 1.0))
	var far: float = size.length() * 2.0
	var segments: int = 72
	for index: int in segments:
		var angle_a: float = TAU * index / segments
		var angle_b: float = TAU * (index + 1) / segments
		var direction_a := Vector2(cos(angle_a), sin(angle_a))
		var direction_b := Vector2(cos(angle_b), sin(angle_b))
		draw_colored_polygon(
			PackedVector2Array(
				[
					center + direction_a * radius,
					center + direction_b * radius,
					center + direction_b * far,
					center + direction_a * far,
				]
			),
			scope_mask_color
		)
	# Eyepiece rim.
	draw_arc(center, radius, 0.0, TAU, 96, Color(0.08, 0.08, 0.08, 1.0), 6.0, true)
	match style:
		"holo":
			draw_arc(center, radius * 0.22, 0.0, TAU, 48, holo_color, 2.5, true)
			draw_circle(center, 2.5, holo_color)
			for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				draw_line(
					center + direction * radius * 0.26,
					center + direction * radius * 0.36,
					holo_color,
					2.0,
					true
				)
		_:
			# Fine crosshair through the window with range marks below and beside the center.
			draw_line(
				center + Vector2(-radius, 0.0),
				center + Vector2(radius, 0.0),
				scope_line_color,
				1.5,
				true
			)
			draw_line(
				center + Vector2(0.0, -radius),
				center + Vector2(0.0, radius),
				scope_line_color,
				1.5,
				true
			)
			for step: int in range(1, 5):
				var tick: float = radius * 0.18 * step
				var length: float = 6.0 if step % 2 == 0 else 4.0
				draw_line(
					center + Vector2(tick, -length),
					center + Vector2(tick, length),
					scope_line_color,
					1.5,
					true
				)
				draw_line(
					center + Vector2(-tick, -length),
					center + Vector2(-tick, length),
					scope_line_color,
					1.5,
					true
				)
				draw_line(
					center + Vector2(-length, tick),
					center + Vector2(length, tick),
					scope_line_color,
					1.5,
					true
				)
			draw_circle(center, 2.0, Color(0.9, 0.1, 0.1, 0.9))


## The shot cone's radius on screen, in pixels.
func _spread_pixels() -> float:
	var shooter: Node = _get_shooter()
	var camera: Camera3D = get_viewport().get_camera_3d()
	if shooter == null or camera == null or not shooter.has_method("get_spread_degrees"):
		return 0.0
	var spread: float = float(shooter.call("get_spread_degrees"))
	var focal_pixels: float = (size.y * 0.5) / tan(deg_to_rad(camera.fov) * 0.5)
	return tan(deg_to_rad(spread)) * focal_pixels


func _should_show_crosshair() -> bool:
	if get_tree().paused:
		return false
	if _is_item_menu_open():
		return false
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return false
	return PlayerItems.is_weapon(_get_equipped_weapon_item())


func _is_item_menu_open() -> bool:
	var item_menu: Node = get_tree().get_first_node_in_group("player_item_menu")
	if item_menu == null or not item_menu.has_method("is_open"):
		return false
	return item_menu.call("is_open")


func _get_player() -> Node:
	return get_tree().get_first_node_in_group("player")


func _get_equipped_weapon_item() -> PlayerItems.Item:
	var player: Node = _get_player()
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
	var player: Node = _get_player()
	if player == null:
		return null
	return player.get_node_or_null("OrbitCamera") as OrbitCamera


func _get_shooter() -> Node:
	var player: Node = _get_player()
	if player == null:
		return null
	return player.get_node_or_null("ShooterTest")


func _get_crosshair_center() -> Vector2:
	var orbit_camera: OrbitCamera = _get_orbit_camera()
	if orbit_camera != null:
		return orbit_camera.get_crosshair_screen_position(size)
	return size * 0.5
