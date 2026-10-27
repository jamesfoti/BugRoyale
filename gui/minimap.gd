extends Control
class_name Minimap
## Bottom-left minimap. A small orthographic camera looks straight down at the real map around
## the player and renders it into a round viewport, so any map, present or future, shows up with
## no per-map data: terrain, water, piers, ducts, mushrooms, whatever is there. Markers go on
## top: you at the centre, other bugs coloured by side, hornets, and the Cordyceps Royale spore
## circle. The map turns with your camera, so up on the map is always straight ahead.

const SIZE_PX: float = 200.0
const MARGIN_PX: float = 16.0
const RENDER_PX: int = 256
## Metres from the centre of the map to its rim (smaller on a tiny celestial body).
const VIEW_RADIUS: float = 45.0
const CAMERA_HEIGHT: float = 30.0
## The map re-renders every this many frames (markers update every frame).
const RENDER_EVERY_FRAMES: int = 2
const MARKER_RADIUS: float = 4.0
## How strongly the spores wash over the map outside the safe circle (0 = map only, 1 = solid).
const STORM_FILL: float = 0.55

const COLOR_SELF := Color(0.15, 0.95, 1.0)
const COLOR_FRIEND := Color(0.35, 0.9, 0.4)
const COLOR_ENEMY := Color(1.0, 0.3, 0.25)
const COLOR_HUSK := Color(0.75, 0.45, 0.95)
const COLOR_HORNET := Color(1.0, 0.85, 0.2)
const COLOR_OUTLINE := Color(0.0, 0.0, 0.0, 0.8)

const MASK_SHADER_CODE: String = """
shader_type canvas_item;

uniform vec4 rim_color : source_color = vec4(0.92, 0.92, 0.86, 0.95);
uniform float rim_width = 0.03;
// Cordyceps Royale: everything outside the safe circle (in map UV space) is washed with spores.
uniform vec2 storm_center_uv = vec2(0.5);
uniform float storm_radius_uv = 10.0;
uniform float storm_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 spore_color : source_color = vec3(0.62, 0.7, 0.34);

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	vec4 map = texture(TEXTURE, UV);
	float in_storm = smoothstep(storm_radius_uv - 0.01, storm_radius_uv + 0.01, length(UV - storm_center_uv));
	map.rgb = mix(map.rgb, spore_color, in_storm * storm_strength);
	float rim = smoothstep(1.0 - rim_width * 2.0, 1.0 - rim_width, r);
	float inside = 1.0 - smoothstep(0.985, 1.0, r);
	COLOR = vec4(mix(map.rgb, rim_color.rgb, rim * rim_color.a), inside);
}
"""

var player: Node3D
var map: MapInfo

var _viewport: SubViewport
var _camera: Camera3D
var _markers: Control
var _frame_material: ShaderMaterial
var _frame_count: int = 0
var _view_radius: float = VIEW_RADIUS
var _camera_height: float = CAMERA_HEIGHT
var _right: Vector3 = Vector3.RIGHT
var _forward: Vector3 = Vector3.FORWARD
var _player_team: int = Damageable.NO_TEAM
var _player_health: Damageable


## Puts a minimap on screen for a player; scene_root is the loaded map (for MapInfo).
static func attach(target_player: Node3D, scene_root: Node) -> Minimap:
	var layer := CanvasLayer.new()
	layer.name = "MinimapLayer"
	layer.layer = 4
	var minimap := Minimap.new()
	minimap.name = "Minimap"
	minimap.player = target_player
	minimap.map = MapInfo.from_scene(scene_root)
	layer.add_child(minimap)
	scene_root.add_child(layer)
	return minimap


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = MARGIN_PX
	offset_right = MARGIN_PX + SIZE_PX
	offset_top = -(MARGIN_PX + SIZE_PX)
	offset_bottom = -MARGIN_PX
	if map != null and map.kind == MapInfo.Kind.CELESTIAL_BODY:
		_view_radius = minf(VIEW_RADIUS, map.body_radius * 0.9)
		_camera_height = minf(CAMERA_HEIGHT, map.body_radius * 0.6)
	_player_health = player.get_node_or_null("Damageable") as Damageable
	_build_viewport()
	_build_frame()


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return
	_aim_camera()
	_frame_count += 1
	if _frame_count % RENDER_EVERY_FRAMES == 0:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_markers.queue_redraw()


# --- The rendered map -------------------------------------------------------------------------

func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "MapView"
	_viewport.size = Vector2i(RENDER_PX, RENDER_PX)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.positional_shadow_atlas_size = 0
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.use_debanding = false
	_viewport.gui_disable_input = true
	_viewport.handle_input_locally = false
	_viewport.audio_listener_enable_3d = false
	add_child(_viewport)

	_camera = Camera3D.new()
	_camera.name = "MapCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = _view_radius * 2.0
	_camera.near = 0.5
	_camera.far = _camera_height + 80.0
	# The toon outline quad pins itself to whatever camera draws it; it is not for the map.
	_camera.cull_mask = 0xFFFFF & ~ToonStyle.OUTLINE_RENDER_LAYER
	_camera.environment = _map_environment()
	_camera.current = true
	_viewport.add_child(_camera)


## Flat, even light and no fog, so the map reads the same in a dark crawlspace as on a sunny
## battlefield.
func _map_environment() -> Environment:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.05, 0.055, 0.065)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(1.0, 1.0, 1.0)
	environment.ambient_light_energy = 1.3
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = false
	environment.volumetric_fog_enabled = false
	environment.glow_enabled = false
	environment.ssao_enabled = false
	environment.ssil_enabled = false
	environment.sdfgi_enabled = false
	return environment


func _build_frame() -> void:
	var frame := TextureRect.new()
	frame.name = "Frame"
	frame.texture = _viewport.get_texture()
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = MASK_SHADER_CODE
	_frame_material = ShaderMaterial.new()
	_frame_material.shader = shader
	_frame_material.set_shader_parameter("spore_color", SporeStorm.SPORE_COLOR)
	frame.material = _frame_material
	add_child(frame)
	# Markers get a control of their own, added after the frame so they draw on top of the map.
	_markers = Control.new()
	_markers.name = "Markers"
	_markers.set_anchors_preset(Control.PRESET_FULL_RECT)
	_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_markers.draw.connect(_draw_markers)
	add_child(_markers)


## Points the map camera straight down at the player, turned so the main camera's heading is up.
func _aim_camera() -> void:
	var position_now: Vector3 = player.global_position
	var up: Vector3 = map.up_at(position_now) if map != null else Vector3.UP
	var main_camera: Camera3D = get_viewport().get_camera_3d()
	var heading: Vector3 = -main_camera.global_basis.z if main_camera != null else -player.global_basis.z
	heading = heading.slide(up)
	if heading.length_squared() < 0.0001:
		heading = (-player.global_basis.z).slide(up)
	if heading.length_squared() < 0.0001:
		heading = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD)
	_forward = heading.normalized()
	_right = _forward.cross(up).normalized()
	var height: float = _camera_height
	if map != null and map.ceiling_y < INF:
		# Under a crawlspace's joists: stay below them, or the map would show the subfloor.
		height = clampf(map.ceiling_y - position_now.y - 2.0, 6.0, _camera_height)
	_camera.global_transform = Transform3D(Basis(_right, _forward, up), position_now + up * height)


# --- Markers ----------------------------------------------------------------------------------

func _draw_markers() -> void:
	var center: Vector2 = size * 0.5
	var rim: float = size.x * 0.5
	var scale_px: float = rim / _view_radius
	_draw_spore_circle(center, rim, scale_px)
	if _player_health != null:
		_player_team = _player_health.team
	for node: Node in get_tree().get_nodes_in_group("bird"):
		_draw_marker(node, center, rim, scale_px, COLOR_HORNET, MARKER_RADIUS * 0.6)
	for node: Node in get_tree().get_nodes_in_group("fighter"):
		if node == player:
			continue
		_draw_marker(node, center, rim, scale_px, _fighter_color(node), MARKER_RADIUS)
	_draw_self(center)


func _fighter_color(node: Node) -> Color:
	if node.is_in_group("husk"):
		return COLOR_HUSK
	var team: int = Damageable.team_of(node)
	if team != Damageable.NO_TEAM and team == _player_team:
		return COLOR_FRIEND
	return COLOR_ENEMY


## A dot for a bug or hornet; anything past the rim sits on it, faded, to show the direction.
func _draw_marker(node: Node, center: Vector2, rim: float, scale_px: float, color: Color, radius: float) -> void:
	var body: Node3D = node as Node3D
	if body == null or not body.visible or not body.is_inside_tree():
		return
	var health: Damageable = body.get_node_or_null("Damageable") as Damageable
	if health != null and not health.is_alive():
		return
	var point: Vector2 = _to_map(body.global_position, center, scale_px)
	var offset: Vector2 = point - center
	var limit: float = rim - radius - 2.0
	var faded: Color = color
	if offset.length() > limit:
		point = center + offset.normalized() * limit
		faded.a = 0.45
	_markers.draw_circle(point, radius + 1.2, Color(COLOR_OUTLINE, COLOR_OUTLINE.a * faded.a))
	_markers.draw_circle(point, radius, faded)


## You: an arrowhead at the centre, pointing up the map (your camera's heading). Cyan, since no
## map paints anything that colour, with a heavy dark outline so it reads on light ground too.
func _draw_self(center: Vector2) -> void:
	var points := PackedVector2Array([
		center + Vector2(0.0, -10.0),
		center + Vector2(7.5, 7.5),
		center + Vector2(0.0, 3.5),
		center + Vector2(-7.5, 7.5),
	])
	var outline: PackedVector2Array = points.duplicate()
	outline.append(points[0])
	_markers.draw_polyline(outline, COLOR_OUTLINE, 5.0, true)
	_markers.draw_colored_polygon(points, COLOR_SELF)


## The edge of a Cordyceps Royale safe circle, where it crosses the map.
func _draw_spore_circle(center: Vector2, rim: float, scale_px: float) -> void:
	var storm: Node = get_tree().get_first_node_in_group("spore_storm")
	if storm == null or not ("center" in storm) or not ("radius" in storm):
		_frame_material.set_shader_parameter("storm_strength", 0.0)
		return
	var storm_center: Vector3 = storm.get("center")
	var storm_radius: float = storm.get("radius")
	if storm_radius == INF:
		_frame_material.set_shader_parameter("storm_strength", 0.0)
		return
	# Wash the map outside the circle with spores (the frame shader works in map UV space, where
	# the whole map spans 0..1 and the centre is the player).
	var center_uv: Vector2 = Vector2(0.5, 0.5) + (_to_map(storm_center, center, scale_px) - center) / size
	_frame_material.set_shader_parameter("storm_center_uv", center_uv)
	_frame_material.set_shader_parameter("storm_radius_uv", storm_radius / (_view_radius * 2.0))
	_frame_material.set_shader_parameter("storm_strength", STORM_FILL)
	if storm_radius <= 0.0:
		return
	var color: Color = Color(SporeStorm.SPORE_COLOR, 0.9)
	var previous: Vector2 = Vector2.INF
	var steps: int = 128
	for step: int in steps + 1:
		var angle: float = TAU * float(step) / float(steps)
		var world: Vector3 = storm_center + _right * cos(angle) * storm_radius + _forward * sin(angle) * storm_radius
		var point: Vector2 = _to_map(world, center, scale_px)
		var inside: bool = (point - center).length() < rim - 1.0
		if previous != Vector2.INF and inside and (previous - center).length() < rim - 1.0:
			_markers.draw_line(previous, point, color, 2.0, true)
		previous = point


## Where a world point lands on the map (planar, in the map camera's frame).
func _to_map(world: Vector3, center: Vector2, scale_px: float) -> Vector2:
	var relative: Vector3 = world - player.global_position
	return center + Vector2(relative.dot(_right), -relative.dot(_forward)) * scale_px
