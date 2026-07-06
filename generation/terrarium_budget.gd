class_name TerrariumBudget
extends RefCounted
## Derives terrarium terrain and glass box dimensions from chunk grid settings.


const MIN_CHUNKS_PER_AXIS: int = 1
const MAX_CHUNKS_PER_AXIS: int = 16
const MIN_CHUNK_SIZE: float = 1.0
const MAX_CHUNK_SIZE: float = 64.0
const GLASS_WALL_INSET: float = 0.05
const GLASS_HEADROOM: float = 0.3
const DEFAULT_CHUNKS: Vector3i = Vector3i(1, 1, 1)
const DEFAULT_CHUNK_SIZE: float = 5.0


class GridConfig:
	var chunks: Vector3i = DEFAULT_CHUNKS
	var chunk_size: float = DEFAULT_CHUNK_SIZE
	var world_size: Vector3 = Vector3.ONE * DEFAULT_CHUNK_SIZE
	var total_chunks: int = 1
	var total_voxels: int = 0


static func derive_grid_from_chunks(chunks: Vector3i, chunk_size_requested: float) -> GridConfig:
	var config := GridConfig.new()
	var safe_chunks := Vector3i(
		clampi(chunks.x, MIN_CHUNKS_PER_AXIS, MAX_CHUNKS_PER_AXIS),
		clampi(chunks.y, MIN_CHUNKS_PER_AXIS, MAX_CHUNKS_PER_AXIS),
		clampi(chunks.z, MIN_CHUNKS_PER_AXIS, MAX_CHUNKS_PER_AXIS)
	)
	var safe_chunk_size: float = clampf(chunk_size_requested, MIN_CHUNK_SIZE, MAX_CHUNK_SIZE)
	config.chunks = safe_chunks
	config.chunk_size = safe_chunk_size
	config.world_size = Vector3(
		safe_chunk_size * float(safe_chunks.x),
		safe_chunk_size * float(safe_chunks.y),
		safe_chunk_size * float(safe_chunks.z)
	)
	config.total_chunks = safe_chunks.x * safe_chunks.y * safe_chunks.z
	var cells_per_axis: int = maxi(1, int(round(safe_chunk_size)))
	config.total_voxels = config.total_chunks * cells_per_axis * cells_per_axis * cells_per_axis
	return config


static func derive_glass_box_size(terrarium_world_size: Vector3) -> Vector3:
	return Vector3(
		terrarium_world_size.x + GLASS_WALL_INSET * 2.0,
		terrarium_world_size.y + GLASS_HEADROOM,
		terrarium_world_size.z + GLASS_WALL_INSET * 2.0
	)


static func get_terrain_floor_offset(world_size: Vector3) -> float:
	return world_size.y * 0.5
