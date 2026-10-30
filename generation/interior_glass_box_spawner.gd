class_name InteriorGlassBoxSpawner
extends RefCounted
## Spawns a scaled glass box on the room floor when the spot is clear.

const GLASS_BOX_SCENE_PATH: String = "res://props/glass_box/glass_box.tscn"
const DEFAULT_BOX_SIZE: Vector3 = Vector3(1.5, 1.5, 1.5)


static func get_box_aabb(layout: InteriorRoomLayout.Layout, box_size: Vector3) -> AABB:
	var center: Vector3 = layout.world_aabb.get_center()
	var safe_size := Vector3(maxf(box_size.x, 0.25), maxf(box_size.y, 0.25), maxf(box_size.z, 0.25))
	return AABB(
		Vector3(center.x - safe_size.x * 0.5, layout.floor_y, center.z - safe_size.z * 0.5),
		safe_size
	)


static func can_place_at_center(
	layout: InteriorRoomLayout.Layout,
	placements: Array[InteriorRoomFurniture.Placement],
	box_size: Vector3
) -> bool:
	return find_clear_floor_position(layout, placements, box_size) != Vector3.INF


static func build_if_clear(
	layout: InteriorRoomLayout.Layout,
	placements: Array[InteriorRoomFurniture.Placement],
	box_size: Vector3 = DEFAULT_BOX_SIZE,
	furniture_scale: float = 1.0
) -> Node3D:
	var position: Vector3 = find_clear_floor_position(layout, placements, box_size, furniture_scale)
	if position == Vector3.INF:
		return null
	return _build_at(layout, box_size, position)


static func find_clear_floor_position(
	layout: InteriorRoomLayout.Layout,
	placements: Array[InteriorRoomFurniture.Placement],
	box_size: Vector3,
	furniture_scale: float = 1.0
) -> Vector3:
	var room_center: Vector3 = layout.world_aabb.get_center()
	var candidates: Array[Vector3] = _build_floor_candidates(layout, box_size)
	candidates.sort_custom(
		func(a: Vector3, b: Vector3) -> bool:
			var a_dist: float = Vector2(a.x - room_center.x, a.z - room_center.z).length_squared()
			var b_dist: float = Vector2(b.x - room_center.x, b.z - room_center.z).length_squared()
			return a_dist < b_dist
	)
	for candidate: Vector3 in candidates:
		if _is_position_clear(layout, placements, box_size, candidate, furniture_scale):
			return candidate
	return Vector3.INF


static func _build_floor_candidates(
	layout: InteriorRoomLayout.Layout, box_size: Vector3
) -> Array[Vector3]:
	var candidates: Array[Vector3] = []
	var safe_size := Vector3(maxf(box_size.x, 0.25), maxf(box_size.y, 0.25), maxf(box_size.z, 0.25))
	var half_footprint := Vector2(safe_size.x, safe_size.z) * 0.5
	var wall_margin: float = 0.35
	var bounds: AABB = layout.world_aabb
	var min_x: float = bounds.position.x + half_footprint.x + wall_margin
	var max_x: float = bounds.position.x + bounds.size.x - half_footprint.x - wall_margin
	var min_z: float = bounds.position.z + half_footprint.y + wall_margin
	var max_z: float = bounds.position.z + bounds.size.z - half_footprint.y - wall_margin
	if min_x > max_x or min_z > max_z:
		return candidates

	var span_x: float = max_x - min_x
	var span_z: float = max_z - min_z
	var step: float = clampf(minf(span_x, span_z) / 7.0, 0.45, 0.75)
	var floor_y: float = layout.floor_y

	var z: float = min_z
	while z <= max_z + 0.001:
		var x: float = min_x
		while x <= max_x + 0.001:
			candidates.append(Vector3(x, floor_y, z))
			x += step
		z += step
	return candidates


static func _is_position_clear(
	layout: InteriorRoomLayout.Layout,
	placements: Array[InteriorRoomFurniture.Placement],
	box_size: Vector3,
	center: Vector3,
	furniture_scale: float = 1.0
) -> bool:
	var box_aabb := _get_box_aabb_at(layout, box_size, center)
	for placement: InteriorRoomFurniture.Placement in placements:
		if _furniture_intersects_box(placement, box_aabb, furniture_scale):
			return false
	return true


static func _get_box_aabb_at(
	layout: InteriorRoomLayout.Layout, box_size: Vector3, center: Vector3
) -> AABB:
	var safe_size := Vector3(maxf(box_size.x, 0.25), maxf(box_size.y, 0.25), maxf(box_size.z, 0.25))
	return AABB(
		Vector3(center.x - safe_size.x * 0.5, layout.floor_y, center.z - safe_size.z * 0.5),
		safe_size
	)


static func _furniture_intersects_box(
	placement: InteriorRoomFurniture.Placement, box_aabb: AABB, furniture_scale: float = 1.0
) -> bool:
	if placement.furniture_type == InteriorRoomFurniture.FurnitureType.RUG:
		return false
	var footprint: Vector3 = InteriorRoomFurniture.get_scaled_footprint(placement, furniture_scale)
	var probe := AABB(placement.position - footprint * 0.5, footprint)
	probe.position.y = box_aabb.position.y
	probe.size.y = maxf(box_aabb.size.y, footprint.y)
	return box_aabb.intersects(probe)


static func _build_at(
	layout: InteriorRoomLayout.Layout, box_size: Vector3, center: Vector3
) -> Node3D:
	var root := Node3D.new()
	root.name = "GlassBoxProp"
	root.position = Vector3(center.x, layout.floor_y, center.z)

	var scene: PackedScene = load(GLASS_BOX_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("[InteriorGlassBoxSpawner] Failed to load glass box scene.")
		return root

	var glass_box: Node3D = scene.instantiate()
	if glass_box == null:
		push_error("[InteriorGlassBoxSpawner] Failed to instantiate glass box.")
		return root

	var safe_size := Vector3(maxf(box_size.x, 0.25), maxf(box_size.y, 0.25), maxf(box_size.z, 0.25))
	glass_box.scale = safe_size
	glass_box.name = "GlassBox"
	root.add_child(glass_box)
	return root
