class_name ChunkMeshBuilder
extends RefCounted
## Thread-safe chunk mesh generation (no scene tree access).


static func run_async_job(job: AsyncRebuildJob) -> void:
	job.batch_result = build_batch(job.chunk_coordinates, job.settings)


static func run_parallel_job_element(element_index: int, job: ParallelBuildJob) -> void:
	build_chunk_into(job.results[element_index], job.chunk_coordinates[element_index], job.settings)
	job.lock.lock()
	job.done += 1
	job.lock.unlock()


static func build_batch(
	chunk_coordinates: Array[Vector3i], settings: ChunkedTerrainWorld.SettingsSnapshot
) -> BatchBuildResult:
	var build_batch_result: BatchBuildResult = BatchBuildResult.new()
	for chunk_coordinate: Vector3i in chunk_coordinates:
		build_batch_result.chunks[chunk_coordinate] = build_chunk(chunk_coordinate, settings)
	return build_batch_result


static func build_chunk(
	chunk_coordinate: Vector3i, settings: ChunkedTerrainWorld.SettingsSnapshot
) -> ChunkBuildResult:
	var chunk_build_result: ChunkBuildResult = ChunkBuildResult.new()
	build_chunk_into(chunk_build_result, chunk_coordinate, settings)
	return chunk_build_result


static func build_chunk_into(
	chunk_build_result: ChunkBuildResult,
	chunk_coordinate: Vector3i,
	settings: ChunkedTerrainWorld.SettingsSnapshot
) -> void:
	var cells_per_axis: int = settings.cells_per_axis
	var extent: float = settings.chunk_world_size
	var sample_size: Vector3i = Vector3i.ONE * (cells_per_axis + 1)
	var corner_local: Vector3 = _chunk_corner_local(chunk_coordinate, settings)
	var half_extent: Vector3 = Vector3.ONE * extent * 0.5
	var world_corner: Vector3 = settings.world_origin + corner_local
	var world_center: Vector3 = world_corner + half_extent
	var grid_world_origin: Vector3 = (
		settings.world_origin + _chunk_corner_local(Vector3i.ZERO, settings)
	)
	var world_step: float = extent / float(cells_per_axis)
	var grid_offset: Vector3i = Vector3i(
		chunk_coordinate.x * cells_per_axis,
		chunk_coordinate.y * cells_per_axis,
		chunk_coordinate.z * cells_per_axis
	)
	var density: DensitySampler.WorldDensity
	if settings.density_factory.is_valid():
		density = settings.density_factory.call(settings)
	elif settings.open_terrain_enabled:
		density = DensitySampler.create_open_terrain_world_density(
			settings.noise_seed,
			settings.noise_frequency,
			settings.noise_amplitude,
			settings.noise_octaves,
			settings.noise_lacunarity,
			settings.noise_gain,
			settings.bounds_center,
			settings.bounds_half,
			settings.bounds_clip_inset,
			settings.open_terrain_edges_enabled,
			settings.open_terrain_heightmap_image,
			settings.open_terrain_surface_offset,
			settings.open_terrain_solid_fill
		)
	elif settings.boxed_in_terrain_enabled:
		density = DensitySampler.create_boxed_in_terrain_world_density(
			settings.noise_seed,
			settings.noise_frequency,
			settings.noise_octaves,
			settings.noise_lacunarity,
			settings.noise_gain,
			settings.bounds_center,
			settings.bounds_half,
			settings.bounds_clip_inset,
			settings.boxed_in_edges_enabled
		)
	else:
		density = DensitySampler.WorldDensity.create(
			settings.noise_enabled,
			settings.noise_seed,
			settings.noise_frequency,
			settings.noise_amplitude,
			settings.noise_octaves,
			settings.noise_lacunarity,
			settings.noise_gain,
			settings.bounds_center,
			settings.bounds_half,
			settings.bounds_clip_inset
		)
	if settings.terrain_edits != null:
		density.terrain_edits = settings.terrain_edits
	if not settings.solids.is_empty():
		density.solids = settings.solids
	var field: SignedDensityField
	if settings.cached_field != null and settings.resample_bounds.has_volume():
		# After a brush stroke: the chunk's last field with the stroke's samples read again.
		field = DensitySampler.resample_chunk_field(
			settings.cached_field,
			density,
			grid_world_origin,
			grid_offset,
			world_step,
			settings.resample_bounds
		)
	else:
		field = DensitySampler.build_chunk_field(
			density, sample_size, grid_world_origin, grid_offset, world_step
		)
	if settings.keep_field:
		chunk_build_result.field = field
	# A chunk with rock and air in it may hold floating rock; a sky or solid chunk cannot.
	if (
		settings.loose_rock_voxels > 0
		and not field.sky
		and field.min_value < settings.iso_level
		and field.max_value >= settings.iso_level
	):
		LooseRock.clear(
			field,
			density,
			grid_world_origin,
			grid_offset,
			world_step,
			cells_per_axis,
			settings.iso_level,
			settings.loose_rock_voxels
		)
	if settings.keep_field:
		# A brush rebuild meshes in blocks and keeps them: after a stroke, only the blocks the
		# changed samples touch are meshed again.
		var previous_blocks: ChunkMeshBlocks = (
			settings.cached_blocks if settings.cached_field != null else null
		)
		var blocks: ChunkMeshBlocks = ChunkMeshBlocks.build(
			field,
			extent,
			settings.iso_level,
			grid_offset,
			grid_world_origin,
			world_center,
			density,
			previous_blocks
		)
		chunk_build_result.mesh_result = blocks.merge()
		chunk_build_result.blocks = blocks
	else:
		chunk_build_result.mesh_result = FlyingEdgesMesher.build_mesh(
			field, extent, settings.iso_level, grid_offset, grid_world_origin, world_center, density
		)
	if density.caves != null and density.caves.water_top > -INF and not field.sky:
		chunk_build_result.water_mesh_result = CaveWaterMesher.build(
			field, density, grid_world_origin, grid_offset, world_step, extent, world_center
		)
	chunk_build_result.local_position = corner_local + half_extent


static func _chunk_corner_local(
	chunk_coordinate: Vector3i, settings: ChunkedTerrainWorld.SettingsSnapshot
) -> Vector3:
	var extent: float = settings.chunk_world_size
	var grid_origin: Vector3 = (
		-Vector3(settings.chunks_x, settings.chunks_y, settings.chunks_z) * extent * 0.5
	)
	return grid_origin + Vector3(chunk_coordinate) * extent


class ChunkBuildResult:
	var mesh_result: FlyingEdgesMesher.MeshResult = FlyingEdgesMesher.MeshResult.new()
	## The chunk's field as meshed, kept when the settings ask (a brush rebuild, so the next
	## stroke there resamples it); null otherwise, since a whole map's fields are 100 MB.
	var field: SignedDensityField = null
	## The chunk's mesh in blocks, kept with the field for the next stroke's partial remesh.
	var blocks: ChunkMeshBlocks = null
	## The pools' water sheet in this chunk (CaveWaterMesher), empty when there is none.
	var water_mesh_result: FlyingEdgesMesher.MeshResult = FlyingEdgesMesher.MeshResult.new()
	var local_position: Vector3 = Vector3.ZERO


## What a brush-rebuilt chunk keeps for its next stroke: its field and its mesh blocks.
class ChunkCache:
	var field: SignedDensityField
	var blocks: ChunkMeshBlocks


class BatchBuildResult:
	var chunks: Dictionary = {}


class AsyncRebuildJob:
	var chunk_coordinates: Array[Vector3i] = []
	var rebuild_collision: bool = false
	## Build the field and mesh blocks for the chunk cache only; the chunk itself stays as
	## it is (ChunkedTerrainWorld.prepare_edit_around).
	var prepare_only: bool = false
	## A chunk of the map's coarse first pass (ChunkedTerrainWorld.COARSE_VOXEL).
	var coarse: bool = false
	var settings: ChunkedTerrainWorld.SettingsSnapshot
	var batch_result: BatchBuildResult = BatchBuildResult.new()
	var task_id: int = -1


## Shared state for WorkerThreadPool group tasks. Result slots are created up front on the
## calling thread; each task only fills its own slot, so no container is resized concurrently.
class ParallelBuildJob:
	var chunk_coordinates: Array[Vector3i] = []
	var results: Array[ChunkBuildResult] = []
	var settings: ChunkedTerrainWorld.SettingsSnapshot
	## How many chunks are built so far, counted under the lock by every worker.
	var done: int = 0
	var lock: Mutex = Mutex.new()

	func completed() -> int:
		lock.lock()
		var count: int = done
		lock.unlock()
		return count
