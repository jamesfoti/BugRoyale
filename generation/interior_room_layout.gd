class_name InteriorRoomLayout
extends RefCounted
## Single-room layout data for procedural interiors.


enum RoomType {
	RANDOM,
	LIVING_ROOM,
	BEDROOM,
	KITCHEN,
	DINING_ROOM,
	BATHROOM,
	OFFICE,
}


class Layout:
	var room_type: RoomType = RoomType.LIVING_ROOM
	var world_aabb: AABB = AABB()
	var floor_y: float = 0.0
	var spawn_position: Vector3 = Vector3.ZERO


static func generate(
	seed: int,
	room_type: RoomType,
	room_size: Vector3,
	wall_thickness: float,
	story_height: float
) -> Layout:
	var layout := Layout.new()
	var safe_size := Vector3(
		maxf(room_size.x, 3.0),
		maxf(story_height, 2.5),
		maxf(room_size.z, 3.0)
	)
	var thickness: float = maxf(wall_thickness, 0.2)
	var inner_size := Vector3(
		safe_size.x - thickness * 2.0,
		safe_size.y,
		safe_size.z - thickness * 2.0
	)
	layout.floor_y = 0.0
	layout.world_aabb = AABB(
		Vector3(-inner_size.x * 0.5, layout.floor_y, -inner_size.z * 0.5),
		inner_size
	)
	layout.room_type = _resolve_room_type(seed, room_type)
	layout.spawn_position = Vector3(
		layout.world_aabb.get_center().x,
		layout.floor_y + 1.4,
		layout.world_aabb.get_center().z
	)
	return layout


static func _resolve_room_type(seed: int, room_type: RoomType) -> RoomType:
	if room_type != RoomType.RANDOM:
		return room_type
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 4201
	var playable_types: Array[RoomType] = [
		RoomType.LIVING_ROOM,
		RoomType.BEDROOM,
		RoomType.KITCHEN,
		RoomType.DINING_ROOM,
		RoomType.BATHROOM,
		RoomType.OFFICE,
	]
	return playable_types[rng.randi_range(0, playable_types.size() - 1)]
