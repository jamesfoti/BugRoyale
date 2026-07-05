class_name ChunkMeshBuilder
extends RefCounted
## Thread-safe chunk mesh generation (no scene tree access).


class ChunkBuildResult:
	var mesh_result: FlyingEdgesMesher.MeshResult = FlyingEdgesMesher.MeshResult.new()
	var local_position: Vector3 = Vector3.ZERO


class BatchBuildResult:
	var chunks: Dictionary = {}


class AsyncRebuildJob:
	var chunk_coordinates: Array[Vector3i] = []
	var rebuild_collision: bool = false
	var settings: ChunkedTerrainWorld.SettingsSnapshot
	var batch_result: BatchBuildResult = BatchBuildResult.new()
	var task_id: int = -1


static func run_async_job(job: AsyncRebuildJob) -> void:
	job.batch_result = build_batch(job.chunk_coordinates, job.settings)


static func build_batch(
	chunk_coordinates: Array[Vector3i],
	settings: ChunkedTerrainWorld.SettingsSnapshot
) -> BatchBuildResult:
	var build_batch_result: BatchBuildResult = BatchBuildResult.new()
	var edge_world_cache: Dictionary = {}
	for chunk_coordinate: Vector3i in chunk_coordinates:
		build_batch_result.chunks[chunk_coordinate] = build_chunk(
			chunk_coordinate, settings, edge_world_cache
		)
	return build_batch_result


static func build_chunk(
	chunk_coordinate: Vector3i,
	settings: ChunkedTerrainWorld.SettingsSnapshot,
	edge_world_cache: Dictionary
) -> ChunkBuildResult:
	var chunk_build_result: ChunkBuildResult = ChunkBuildResult.new()
	var cells_per_axis: int = settings.cells_per_axis
	var extent: float = settings.chunk_world_size
	var sample_size: Vector3i = Vector3i.ONE * (cells_per_axis + 1)
	var corner_local: Vector3 = _chunk_corner_local(chunk_coordinate, settings)
	var half_extent: Vector3 = Vector3.ONE * extent * 0.5
	var world_corner: Vector3 = settings.world_origin + corner_local
	var world_center: Vector3 = world_corner + half_extent
	var grid_offset: Vector3i = Vector3i(
		chunk_coordinate.x * cells_per_axis,
		chunk_coordinate.y * cells_per_axis,
		chunk_coordinate.z * cells_per_axis
	)
	var sphere_world: Vector3 = settings.bounds_center + settings.sphere_center
	var density: DensitySampler.WorldDensity
	if settings.flat_terrain_enabled:
		density = DensitySampler.create_flat_terrain_world_density(
			settings.noise_seed,
			settings.noise_frequency,
			settings.noise_octaves,
			settings.noise_lacunarity,
			settings.noise_gain,
			settings.bounds_center,
			settings.bounds_half,
			settings.bounds_clip_inset,
			settings.flat_boxed_edges_enabled
		)
	elif settings.planet_features_enabled and settings.sphere_enabled:
		density = DensitySampler.create_planet_world_density(
			sphere_world,
			settings.sphere_radius,
			settings.noise_seed,
			-1.0,
			-1.0,
			settings.planet_ravines_enabled,
			settings.planet_caves_enabled,
			settings.bounds_center,
			settings.bounds_half,
			settings.bounds_falloff_enabled,
			settings.bounds_falloff_distance,
			settings.bounds_falloff_strength,
			settings.bounds_clip_inset,
			settings.planet_ravine_depth,
			settings.planet_ravine_width
		)
	else:
		density = DensitySampler.WorldDensity.create(
			settings.sphere_enabled,
			sphere_world,
			settings.sphere_radius,
			settings.noise_enabled,
			settings.noise_seed,
			settings.noise_frequency,
			settings.noise_amplitude,
			settings.noise_octaves,
			settings.noise_lacunarity,
			settings.noise_gain,
			settings.bounds_center,
			settings.bounds_half,
			settings.bounds_falloff_enabled,
			settings.bounds_falloff_distance,
			settings.bounds_falloff_strength,
			settings.bounds_clip_inset
		)
	if settings.planet_edits != null:
		density.planet_edits = settings.planet_edits
	var field: SignedDensityField = DensitySampler.build_chunk_field(
		density,
		sample_size,
		world_corner,
		extent
	)
	chunk_build_result.mesh_result = FlyingEdgesMesher.build_mesh(
		field,
		extent,
		settings.iso_level,
		grid_offset,
		edge_world_cache,
		world_corner,
		world_center,
		density
	)
	chunk_build_result.local_position = corner_local + half_extent
	return chunk_build_result


static func _chunk_corner_local(
	chunk_coordinate: Vector3i,
	settings: ChunkedTerrainWorld.SettingsSnapshot
) -> Vector3:
	var extent: float = settings.chunk_world_size
	var grid_origin: Vector3 = (
		-Vector3(settings.chunks_x, settings.chunks_y, settings.chunks_z)
		* extent
		* 0.5
	)
	return grid_origin + Vector3(chunk_coordinate) * extent
