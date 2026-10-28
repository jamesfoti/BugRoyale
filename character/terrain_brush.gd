extends Node
class_name TerrainBrush
## Raycasts terrain from screen center and applies edits. Two shapes: the SPHERE sculpts while
## left mouse is held; the BLOCK places or removes one grid-snapped cube per click, on the face
## under the crosshair, with a ghost showing where it will land. The block is block_size voxels
## on a side. Neither shape will add terrain that overlaps the player: terrain collision is a
## one-sided trimesh, so a player sealed inside new rock has nothing to stand on and falls out of
## the world. A blocked stamp is skipped and the preview turns grey.


enum EditMode {
	OFF,
	DESTROY,
	ADD,
}

enum Shape {
	SPHERE,
	BLOCK,
}

## A block is a whole number of voxels on a side with its faces on sample planes. Pushing the
## box out by this fraction of a voxel makes the face samples just solid, so the mesher draws a
## crisp cube with its vertices on those samples instead of an octahedron through the face
## centres.
const BLOCK_FACE_BIAS: float = 0.02
## Smallest and largest block the player can pick, in voxels per side. One voxel is the finest
## cube the mesher draws crisply; past six the stamp gets slow and the ghost unwieldy.
const MIN_BLOCK_SIZE: int = 1
const MAX_BLOCK_SIZE: int = 6
## A ray hitting a block lands a hair outside its face; this much slack (fraction of a voxel)
## snaps such hits to that face rather than the next plane out.
const BLOCK_SNAP_SLACK: float = 0.1
## Metres of air an ADD stamp must leave around the player's capsule to be allowed.
const PLAYER_CLEARANCE: float = 0.1
## Points tested along the capsule's axis when checking a stamp against it.
const PLAYER_CAPSULE_SAMPLES: int = 6

@export var edit_distance: float = 20.0
@export var brush_radius: float = 1.5
## Seconds between brush stamps while holding LMB.
@export var stroke_interval: float = 0.05
## What ADD builds with: the map's own ground, or a placed material such as stone or sand.
@export var add_material: TerrainMaterials.Kind = TerrainMaterials.Kind.NATURAL
@export var shape: Shape = Shape.SPHERE
## Voxels per side of the block the BLOCK shape places or removes.
@export_range(1, 6) var block_size: int = 2

@onready var _cursor: TerrainEditCursor = $TerrainEditCursor

var _terrain: ChunkedTerrainWorld
var _mode: EditMode = EditMode.OFF
var _hover_hit: Dictionary = {}
var _is_painting: bool = false
var _stroke_cooldown: float = 0.0
var _click_was_down: bool = false
var _clicked_this_frame: bool = false
## Centre of the block the next click would place or remove (valid while the ghost shows).
var _block_center: Vector3 = Vector3.ZERO
var _ghost: MeshInstance3D
var _ghost_outline: MeshInstance3D
var _ghost_material: StandardMaterial3D
var _ghost_outline_material: StandardMaterial3D

var _destroy_color: Color = Color(1.0, 0.45, 0.15)
var _add_color: Color = Color(0.25, 0.85, 1.0)
var _blocked_color: Color = Color(0.6, 0.6, 0.6)
## True while the previewed ADD stamp would overlap the player, so the click is refused.
var _blocked: bool = false
## The player's capsule collider, found once; null falls back to a sphere around the player.
var _player_collider: CollisionShape3D


func _ready() -> void:
	add_to_group("terrain_brush")
	_cursor.edit_radius = brush_radius
	_build_ghost()
	_player_collider = _find_player_capsule()
	call_deferred("_cache_terrain")


func set_edit_mode(mode: EditMode) -> void:
	if mode == EditMode.OFF and _is_painting and _terrain != null:
		_is_painting = false
		_terrain.end_continuous_edit()
	_mode = mode
	if _mode == EditMode.OFF:
		_hide_preview()


func get_edit_mode() -> EditMode:
	return _mode


func set_add_material(material: TerrainMaterials.Kind) -> void:
	add_material = material


func get_add_material() -> TerrainMaterials.Kind:
	return add_material


func set_shape(new_shape: Shape) -> void:
	if new_shape == shape:
		return
	if _is_painting and _terrain != null:
		_is_painting = false
		_terrain.end_continuous_edit()
	shape = new_shape
	_hide_preview()


func get_shape() -> Shape:
	return shape


func set_block_size(size: int) -> void:
	block_size = clampi(size, MIN_BLOCK_SIZE, MAX_BLOCK_SIZE)


func get_block_size() -> int:
	return block_size


func _process(delta: float) -> void:
	var left_down: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_clicked_this_frame = left_down and not _click_was_down
	_click_was_down = left_down

	if get_tree().paused or _mode == EditMode.OFF:
		_hide_preview()
		_hover_hit = {}
		_stroke_cooldown = 0.0
		return

	_ensure_terrain_cached()

	var player: Node = get_parent()
	if player == null:
		return
	if _is_terrain_focus_active(player):
		_hover_hit = _raycast_terrain_from_view(player)
		if _hover_hit.is_empty():
			_hide_preview()
			if _is_painting and _terrain != null:
				_is_painting = false
				_terrain.end_continuous_edit()
			return
		_show_preview()
		_process_paint_input(delta)
		return
	if _is_camera_orbiting(player):
		if _is_painting and _terrain != null:
			_is_painting = false
			_terrain.end_continuous_edit()
		_hide_preview()
		_hover_hit = {}
		return

	_hover_hit = _raycast_terrain_from_view(player)
	if _hover_hit.is_empty():
		_hide_preview()
		return

	_show_preview()
	_process_paint_input(delta)


func _process_paint_input(delta: float) -> void:
	if shape == Shape.BLOCK:
		if _clicked_this_frame and _can_apply_edit() and not _blocked:
			_apply_block()
		return

	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if _is_painting:
			_is_painting = false
			_stroke_cooldown = 0.0
			if _terrain != null:
				_terrain.end_continuous_edit()
		return

	var wants_paint: bool = _can_apply_edit()
	if wants_paint and not _is_painting:
		_is_painting = true
		_stroke_cooldown = 0.0
		if _terrain != null:
			_terrain.begin_continuous_edit()
		_apply_brush()
		_stroke_cooldown = stroke_interval
		return
	elif not wants_paint:
		if _is_painting:
			_is_painting = false
			_stroke_cooldown = 0.0
			if _terrain != null:
				_terrain.end_continuous_edit()
		return

	_stroke_cooldown -= delta
	if _stroke_cooldown > 0.0:
		return
	_apply_brush()
	_stroke_cooldown = stroke_interval


func _can_apply_edit() -> bool:
	# UI can only take the click when the cursor is visible; a captured mouse aims at screen center.
	if (
		Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED
		and get_viewport().gui_get_hovered_control() != null
	):
		return false
	if _hover_hit.is_empty():
		return false
	return _terrain != null


func _apply_brush() -> void:
	if _blocked:
		return
	var hit_position: Vector3 = _hover_hit.position
	_terrain.apply_brush(hit_position, brush_radius, _mode == EditMode.ADD, add_material)


func _apply_block() -> void:
	_terrain.apply_box(
		_block_center,
		Vector3.ONE * _block_half_extent(),
		_mode == EditMode.ADD,
		add_material
	)


# --- Preview --------------------------------------------------------------------------------

func _show_preview() -> void:
	if shape == Shape.BLOCK and _terrain != null:
		_cursor.hide_cursor()
		_block_center = _block_center_for_hit()
		_blocked = _mode == EditMode.ADD and _box_overlaps_player(
			_block_center, Vector3.ONE * _block_half_extent()
		)
		_show_ghost(_block_center, _terrain.get_voxel_size() * float(block_size))
		return
	_hide_ghost()
	_blocked = _mode == EditMode.ADD and _sphere_overlaps_player(_hover_hit.position, brush_radius)
	_cursor.show_at(
		_hover_hit.position,
		_hover_hit.normal,
		_mode == EditMode.ADD,
		add_material,
		_blocked
	)


func _hide_preview() -> void:
	_cursor.hide_cursor()
	_hide_ghost()


func _block_half_extent() -> float:
	return _terrain.get_voxel_size() * (float(block_size) * 0.5 + BLOCK_FACE_BIAS)


## Where a click would put (ADD) or take (DESTROY) a block, in world space. A block spans
## block_size voxels per side with its faces on sample planes, so its corner snaps to a sample
## (an even-sized block is centred on a sample, an odd one between two). Across the hit face the
## block is centred on the crosshair. Along the axis the face points, the block sits just outside
## (ADD) or just inside (DESTROY) the plane the ray hit, like placing against a face in a block
## game; a hit on natural ground buries the block up to a voxel rather than floating it.
func _block_center_for_hit() -> Vector3:
	var step: float = _terrain.get_voxel_size()
	var origin: Vector3 = _terrain.get_grid_world_origin()
	var normal: Vector3 = _hover_hit.normal as Vector3
	var axis: int = normal.abs().max_axis_index()
	var side: float = 1.0 if normal[axis] >= 0.0 else -1.0
	var local: Vector3 = ((_hover_hit.position as Vector3) - origin) / step
	var half: float = float(block_size) * 0.5
	var center: Vector3 = (local - Vector3.ONE * half).round() + Vector3.ONE * half
	var plane: float
	if side > 0.0:
		plane = floorf(local[axis] + BLOCK_SNAP_SLACK)
	else:
		plane = ceilf(local[axis] - BLOCK_SNAP_SLACK)
	center[axis] = plane + side * (half if _mode == EditMode.ADD else -half)
	return origin + center * step


func _build_ghost() -> void:
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost = MeshInstance3D.new()
	_ghost.name = "BlockGhost"
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3.ONE
	_ghost.mesh = box
	_ghost.material_override = _ghost_material
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.top_level = true
	_ghost.visible = false
	add_child(_ghost)

	_ghost_outline_material = StandardMaterial3D.new()
	_ghost_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_outline = MeshInstance3D.new()
	_ghost_outline.name = "BlockGhostOutline"
	_ghost_outline.mesh = _build_cube_outline_mesh()
	_ghost_outline.material_override = _ghost_outline_material
	_ghost_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost_outline.top_level = true
	_ghost_outline.visible = false
	add_child(_ghost_outline)


## The twelve edges of a unit cube as a line mesh.
func _build_cube_outline_mesh() -> ArrayMesh:
	var corners: PackedVector3Array = PackedVector3Array()
	for index: int in 8:
		corners.append(Vector3(
			-0.5 if (index & 1) == 0 else 0.5,
			-0.5 if (index & 2) == 0 else 0.5,
			-0.5 if (index & 4) == 0 else 0.5
		))
	var lines: PackedVector3Array = PackedVector3Array()
	for index: int in 8:
		for bit: int in [1, 2, 4]:
			if (index & bit) == 0:
				lines.append(corners[index])
				lines.append(corners[index | bit])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = lines
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


func _show_ghost(center: Vector3, size: float) -> void:
	var tint: Color = _destroy_color
	if _blocked:
		tint = _blocked_color
	elif _mode == EditMode.ADD:
		tint = _add_color
		if add_material != TerrainMaterials.Kind.NATURAL:
			tint = TerrainMaterials.color(add_material).lightened(0.15)
	var fill: Color = tint
	fill.a = 0.35
	var edge: Color = tint.lightened(0.4)
	edge.a = 0.9
	_ghost_material.albedo_color = fill
	_ghost_outline_material.albedo_color = edge
	# A hair larger than the block so the ghost's faces are not lost inside the drawn surface.
	var ghost_size: float = size * 1.01
	_ghost.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * ghost_size), center)
	_ghost_outline.global_transform = _ghost.global_transform
	_ghost.visible = true
	_ghost_outline.visible = true


func _hide_ghost() -> void:
	if _ghost != null:
		_ghost.visible = false
	if _ghost_outline != null:
		_ghost_outline.visible = false


# --- Player clearance -----------------------------------------------------------------------

func _find_player_capsule() -> CollisionShape3D:
	var player: Node = get_parent()
	if player == null:
		return null
	for child: Node in player.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is CapsuleShape3D:
			return child as CollisionShape3D
	return null


## Points along the player's capsule axis, from the bottom sphere centre to the top one, plus
## the capsule radius. Without a capsule the player is a 0.6 m sphere at their origin.
func _player_axis_points() -> Dictionary:
	var points: PackedVector3Array = PackedVector3Array()
	if _player_collider == null:
		var player: Node3D = get_parent() as Node3D
		if player == null:
			return {"points": points, "radius": 0.0}
		points.append(player.global_position + Vector3.UP * 0.6)
		return {"points": points, "radius": 0.6}
	var capsule: CapsuleShape3D = _player_collider.shape as CapsuleShape3D
	var axis: Vector3 = _player_collider.global_basis.y.normalized()
	var half_segment: float = maxf(capsule.height * 0.5 - capsule.radius, 0.0)
	var center: Vector3 = _player_collider.global_position
	for index: int in PLAYER_CAPSULE_SAMPLES:
		var t: float = float(index) / float(PLAYER_CAPSULE_SAMPLES - 1) * 2.0 - 1.0
		points.append(center + axis * (half_segment * t))
	return {"points": points, "radius": capsule.radius}


func _sphere_overlaps_player(center: Vector3, radius: float) -> bool:
	var capsule: Dictionary = _player_axis_points()
	var limit: float = radius + (capsule.radius as float) + PLAYER_CLEARANCE
	for point: Vector3 in capsule.points as PackedVector3Array:
		if point.distance_to(center) < limit:
			return true
	return false


func _box_overlaps_player(center: Vector3, half_extents: Vector3) -> bool:
	var capsule: Dictionary = _player_axis_points()
	var limit: float = (capsule.radius as float) + PLAYER_CLEARANCE
	for point: Vector3 in capsule.points as PackedVector3Array:
		var outside: Vector3 = ((point - center).abs() - half_extents).max(Vector3.ZERO)
		if outside.length() < limit:
			return true
	return false


# --- Terrain lookup -------------------------------------------------------------------------

func _cache_terrain() -> void:
	_terrain = null
	var parent: Node = get_parent()
	if parent is CelestialBodyPlayer:
		_terrain = _resolve_chunked_terrain((parent as CelestialBodyPlayer).celestial_body)
		if _terrain != null:
			return
	if parent is BoxedInTerrainPlayer:
		_terrain = _resolve_chunked_terrain((parent as BoxedInTerrainPlayer).terrain)
		if _terrain != null:
			return
	if parent is OpenTerrainPlayer:
		_terrain = _resolve_chunked_terrain((parent as OpenTerrainPlayer).terrain)
		if _terrain != null:
			return
	_terrain = get_tree().get_first_node_in_group("terrain_world") as ChunkedTerrainWorld
	if _terrain == null:
		_terrain = get_tree().get_first_node_in_group("open_terrain") as ChunkedTerrainWorld


func _ensure_terrain_cached() -> void:
	if _terrain != null and is_instance_valid(_terrain):
		return
	_cache_terrain()


func _resolve_chunked_terrain(world_node: Node3D) -> ChunkedTerrainWorld:
	if world_node == null:
		return null
	if world_node is ChunkedTerrainWorld:
		return world_node as ChunkedTerrainWorld
	if world_node is TerrariumRoom:
		var terrarium_room: TerrariumRoom = world_node as TerrariumRoom
		if not terrarium_room.content_rebuilt.is_connected(_on_terrain_world_rebuilt):
			terrarium_room.content_rebuilt.connect(_on_terrain_world_rebuilt)
		return terrarium_room.get_playable_terrain()
	return null


func _on_terrain_world_rebuilt() -> void:
	_cache_terrain()


func _raycast_terrain_from_view(player: Node) -> Dictionary:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return {}

	var screen_pos: Vector2 = get_viewport().get_visible_rect().size * 0.5
	if _is_terrain_focus_active(player):
		screen_pos = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_pos)
	var ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	ray_query.from = ray_origin
	ray_query.to = ray_origin + ray_direction * maxf(edit_distance * 2.0, 50.0)
	if player is CollisionObject3D:
		ray_query.exclude = [(player as CollisionObject3D).get_rid()]

	var space: PhysicsDirectSpaceState3D = (get_parent() as Node3D).get_world_3d().direct_space_state
	var raycast_hit: Dictionary = space.intersect_ray(ray_query)
	if raycast_hit.is_empty():
		return {}
	if player is Node3D and (player as Node3D).global_position.distance_to(raycast_hit.position) > edit_distance:
		return {}
	return raycast_hit


func _is_camera_orbiting(player: Node) -> bool:
	var orbit_camera: OrbitCamera = player.get_node_or_null("OrbitCamera") as OrbitCamera
	if orbit_camera != null:
		return orbit_camera.is_orbiting()
	return false


func _is_terrain_focus_active(player: Node) -> bool:
	if player is CelestialBodyPlayer:
		return (player as CelestialBodyPlayer).is_terrain_focus_active()
	if player is BoxedInTerrainPlayer:
		return (player as BoxedInTerrainPlayer).is_terrain_focus_active()
	if player is OpenTerrainPlayer:
		return (player as OpenTerrainPlayer).is_terrain_focus_active()
	return false
