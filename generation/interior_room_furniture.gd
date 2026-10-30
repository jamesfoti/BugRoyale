class_name InteriorRoomFurniture
extends RefCounted
## Places simple box furniture for a single interior room.

enum FurnitureType {
	COUCH,
	ARMCHAIR,
	COFFEE_TABLE,
	DINING_TABLE,
	CHAIR,
	BED,
	DESK,
	DESK_CHAIR,
	DRESSER,
	COUNTER,
	ISLAND,
	TOILET,
	SINK,
	TUB,
	TV_STAND,
	FLOOR_LAMP,
	BOOKSHELF,
	RUG,
}


static func place_for_layout(layout: InteriorRoomLayout.Layout, seed: int) -> Array[Placement]:
	var placements: Array[Placement] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 9137
	match layout.room_type:
		InteriorRoomLayout.RoomType.LIVING_ROOM:
			_place_living_room(placements, layout, rng)
		InteriorRoomLayout.RoomType.BEDROOM:
			_place_bedroom(placements, layout, rng)
		InteriorRoomLayout.RoomType.KITCHEN:
			_place_kitchen(placements, layout)
		InteriorRoomLayout.RoomType.DINING_ROOM:
			_place_dining_room(placements, layout)
		InteriorRoomLayout.RoomType.BATHROOM:
			_place_bathroom(placements, layout)
		InteriorRoomLayout.RoomType.OFFICE:
			_place_office(placements, layout)
	return placements


static func get_footprint(furniture_type: FurnitureType) -> Vector3:
	match furniture_type:
		FurnitureType.COUCH:
			return Vector3(2.2, 1.0, 0.9)
		FurnitureType.ARMCHAIR:
			return Vector3(0.9, 1.0, 0.9)
		FurnitureType.BED:
			return Vector3(1.6, 1.0, 2.1)
		FurnitureType.DINING_TABLE:
			return Vector3(1.6, 1.0, 0.9)
		FurnitureType.COFFEE_TABLE:
			return Vector3(1.1, 0.6, 0.7)
		FurnitureType.DESK:
			return Vector3(1.3, 1.0, 0.65)
		FurnitureType.COUNTER, FurnitureType.ISLAND:
			return Vector3(1.6, 1.0, 0.8)
		FurnitureType.TUB:
			return Vector3(1.5, 0.8, 0.75)
		FurnitureType.RUG:
			return Vector3(2.0, 0.1, 1.4)
		FurnitureType.FLOOR_LAMP:
			return Vector3(0.4, 1.8, 0.4)
		_:
			return Vector3(0.8, 1.0, 0.8)


static func get_surface_info(furniture_type: FurnitureType) -> SurfaceInfo:
	var info := SurfaceInfo.new()
	match furniture_type:
		FurnitureType.COFFEE_TABLE:
			info.top_surface_y = 0.39
			info.footprint = Vector2(1.1, 0.7)
		FurnitureType.DINING_TABLE:
			info.top_surface_y = 0.79
			info.footprint = Vector2(1.6, 0.9)
		FurnitureType.DESK:
			info.top_surface_y = 0.79
			info.footprint = Vector2(1.3, 0.65)
		FurnitureType.ISLAND:
			info.top_surface_y = 0.9
			info.footprint = Vector2(1.2, 0.8)
		FurnitureType.COUNTER:
			info.top_surface_y = 0.9
			info.footprint = Vector2(2.0, 0.6)
		FurnitureType.TV_STAND:
			info.top_surface_y = 0.48
			info.footprint = Vector2(1.4, 0.4)
		_:
			info.top_surface_y = -1.0
	return info


static func is_terrarium_surface(furniture_type: FurnitureType) -> bool:
	return get_surface_info(furniture_type).top_surface_y >= 0.0


static func get_preferred_terrarium_surfaces(
	room_type: InteriorRoomLayout.RoomType
) -> Array[FurnitureType]:
	match room_type:
		InteriorRoomLayout.RoomType.LIVING_ROOM:
			return [FurnitureType.COFFEE_TABLE, FurnitureType.TV_STAND]
		InteriorRoomLayout.RoomType.DINING_ROOM:
			return [FurnitureType.DINING_TABLE]
		InteriorRoomLayout.RoomType.OFFICE:
			return [FurnitureType.DESK]
		InteriorRoomLayout.RoomType.KITCHEN:
			return [FurnitureType.ISLAND, FurnitureType.COUNTER]
		InteriorRoomLayout.RoomType.BEDROOM:
			return [FurnitureType.DESK]
		_:
			return []


static func get_scaled_footprint(placement: Placement, furniture_scale: float = 1.0) -> Vector3:
	var footprint: Vector3 = get_footprint(placement.furniture_type)
	if placement.furniture_type == InteriorRoomFurniture.FurnitureType.FLOOR_LAMP:
		footprint = Vector3(0.35, 0.1, 0.35)
	elif absf(cos(placement.rotation_y)) < absf(sin(placement.rotation_y)):
		footprint = Vector3(footprint.z, footprint.y, footprint.x)
	return footprint * maxf(furniture_scale, 0.1)


static func get_scaled_surface_footprint(
	placement: Placement, furniture_scale: float = 1.0
) -> Vector2:
	var info: SurfaceInfo = get_surface_info(placement.furniture_type)
	if info.top_surface_y < 0.0:
		return Vector2.ZERO
	var footprint: Vector2 = info.footprint
	if absf(cos(placement.rotation_y)) < absf(sin(placement.rotation_y)):
		footprint = Vector2(footprint.y, footprint.x)
	return footprint * maxf(furniture_scale, 0.1)


static func _room_center(layout: InteriorRoomLayout.Layout) -> Vector3:
	return layout.world_aabb.get_center()


static func _floor_y(layout: InteriorRoomLayout.Layout) -> float:
	return layout.world_aabb.position.y


static func _half(layout: InteriorRoomLayout.Layout) -> Vector3:
	return layout.world_aabb.size * 0.5


static func _add(
	placements: Array[Placement],
	layout: InteriorRoomLayout.Layout,
	furniture_type: FurnitureType,
	local_offset: Vector3,
	rotation_y: float
) -> void:
	var placement := Placement.new()
	placement.furniture_type = furniture_type
	placement.rotation_y = rotation_y
	placement.position = _room_center(layout) + local_offset
	placement.position.y = _floor_y(layout)
	placements.append(placement)


static func _place_living_room(
	placements: Array[Placement], layout: InteriorRoomLayout.Layout, rng: RandomNumberGenerator
) -> void:
	var half: Vector3 = _half(layout)
	var yaw: float = PI if rng.randf() > 0.5 else 0.0
	_add(placements, layout, FurnitureType.COUCH, Vector3(0.0, 0.0, half.z * 0.55), yaw)
	_add(
		placements,
		layout,
		FurnitureType.ARMCHAIR,
		Vector3(-half.x * 0.45, 0.0, half.z * 0.1),
		yaw + PI * 0.5
	)
	_add(
		placements,
		layout,
		FurnitureType.ARMCHAIR,
		Vector3(half.x * 0.45, 0.0, half.z * 0.1),
		yaw - PI * 0.5
	)
	_add(placements, layout, FurnitureType.COFFEE_TABLE, Vector3.ZERO, yaw)
	_add(placements, layout, FurnitureType.RUG, Vector3(0.0, 0.0, 0.15), yaw)
	_add(placements, layout, FurnitureType.TV_STAND, Vector3(0.0, 0.0, -half.z * 0.6), yaw + PI)
	_add(
		placements,
		layout,
		FurnitureType.FLOOR_LAMP,
		Vector3(half.x * 0.65, 0.0, -half.z * 0.35),
		0.0
	)


static func _place_bedroom(
	placements: Array[Placement], layout: InteriorRoomLayout.Layout, rng: RandomNumberGenerator
) -> void:
	var half: Vector3 = _half(layout)
	var yaw: float = PI if rng.randf() > 0.5 else 0.0
	_add(placements, layout, FurnitureType.BED, Vector3(-half.x * 0.2, 0.0, half.z * 0.35), yaw)
	_add(
		placements,
		layout,
		FurnitureType.DRESSER,
		Vector3(half.x * 0.55, 0.0, -half.z * 0.45),
		yaw + PI
	)
	_add(
		placements,
		layout,
		FurnitureType.DESK,
		Vector3(-half.x * 0.45, 0.0, -half.z * 0.35),
		yaw + PI * 0.5
	)
	_add(
		placements,
		layout,
		FurnitureType.DESK_CHAIR,
		Vector3(-half.x * 0.25, 0.0, -half.z * 0.35),
		yaw - PI * 0.5
	)


static func _place_kitchen(placements: Array[Placement], layout: InteriorRoomLayout.Layout) -> void:
	var half: Vector3 = _half(layout)
	_add(
		placements, layout, FurnitureType.COUNTER, Vector3(-half.x * 0.15, 0.0, -half.z * 0.45), 0.0
	)
	_add(
		placements,
		layout,
		FurnitureType.COUNTER,
		Vector3(half.x * 0.45, 0.0, -half.z * 0.15),
		PI * 0.5
	)
	_add(placements, layout, FurnitureType.ISLAND, Vector3(0.0, 0.0, 0.1), 0.0)
	_add(placements, layout, FurnitureType.CHAIR, Vector3(0.0, 0.0, half.z * 0.35), PI)


static func _place_dining_room(
	placements: Array[Placement], layout: InteriorRoomLayout.Layout
) -> void:
	var half: Vector3 = _half(layout)
	_add(placements, layout, FurnitureType.DINING_TABLE, Vector3.ZERO, 0.0)
	_add(placements, layout, FurnitureType.CHAIR, Vector3(0.0, 0.0, half.z * 0.35), 0.0)
	_add(placements, layout, FurnitureType.CHAIR, Vector3(0.0, 0.0, -half.z * 0.35), PI)
	_add(placements, layout, FurnitureType.CHAIR, Vector3(half.x * 0.35, 0.0, 0.0), -PI * 0.5)
	_add(placements, layout, FurnitureType.CHAIR, Vector3(-half.x * 0.35, 0.0, 0.0), PI * 0.5)


static func _place_bathroom(
	placements: Array[Placement], layout: InteriorRoomLayout.Layout
) -> void:
	var half: Vector3 = _half(layout)
	_add(placements, layout, FurnitureType.TOILET, Vector3(half.x * 0.35, 0.0, half.z * 0.35), PI)
	_add(placements, layout, FurnitureType.SINK, Vector3(-half.x * 0.35, 0.0, half.z * 0.35), 0.0)
	_add(placements, layout, FurnitureType.TUB, Vector3(-half.x * 0.2, 0.0, -half.z * 0.25), 0.0)


static func _place_office(placements: Array[Placement], layout: InteriorRoomLayout.Layout) -> void:
	var half: Vector3 = _half(layout)
	_add(placements, layout, FurnitureType.DESK, Vector3(0.0, 0.0, -half.z * 0.15), 0.0)
	_add(placements, layout, FurnitureType.DESK_CHAIR, Vector3(0.0, 0.0, half.z * 0.2), PI)
	_add(
		placements,
		layout,
		FurnitureType.BOOKSHELF,
		Vector3(half.x * 0.55, 0.0, -half.z * 0.35),
		-PI * 0.5
	)
	_add(
		placements,
		layout,
		FurnitureType.FLOOR_LAMP,
		Vector3(-half.x * 0.55, 0.0, half.z * 0.35),
		0.0
	)


class Placement:
	var furniture_type: FurnitureType = FurnitureType.CHAIR
	var position: Vector3 = Vector3.ZERO
	var rotation_y: float = 0.0


class SurfaceInfo:
	var top_surface_y: float = 0.0
	var footprint: Vector2 = Vector2.ONE
