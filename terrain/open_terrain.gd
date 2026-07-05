@tool
class_name OpenTerrain
extends ChunkedTerrainWorld
## Heightmap terrain clipped to side and bottom walls with an open top.


@export_group("Open Terrain Grid")
@export_range(1, 64, 1) var chunks_x: int = 5:
	set(value):
		chunks_x = maxi(value, 1)
		_request_rebuild()
@export_range(1, 32, 1) var chunks_y: int = 3:
	set(value):
		chunks_y = maxi(value, 1)
		_request_rebuild()
@export_range(1, 64, 1) var chunks_z: int = 5:
	set(value):
		chunks_z = maxi(value, 1)
		_request_rebuild()

@export_group("Heightmap")
## Optional grayscale heightmap texture. When unset, procedural 2D noise is used.
@export var heightmap: Texture2D:
	set(value):
		heightmap = value
		_request_rebuild()

@export_group("Edges")
## Clip terrain to world bounds on X, Z, and bottom Y. Top remains open.
@export var boxed_edges_enabled: bool = true:
	set(value):
		boxed_edges_enabled = value
		_request_rebuild()


func _register_playable_groups() -> void:
	add_to_group("open_terrain")


func _get_grid_dimensions() -> Vector3i:
	return Vector3i(chunks_x, chunks_y, chunks_z)


func _get_world_log_name() -> String:
	return "OpenTerrain"


func get_surface_height_at(world_position: Vector3) -> float:
	var density: DensitySampler.WorldDensity = _get_bake_density()
	if density.open_terrain_enabled:
		return density.sample_open_terrain_height(world_position.x, world_position.z)
	return global_position.y


func _apply_world_specific_settings(settings: ChunkedTerrainWorld.SettingsSnapshot) -> void:
	settings.sphere_enabled = false
	settings.boxed_in_terrain_enabled = false
	settings.open_terrain_enabled = true
	settings.open_terrain_edges_enabled = boxed_edges_enabled
	settings.open_terrain_heightmap_image = _duplicate_heightmap_image()


func _build_world_density(settings: ChunkedTerrainWorld.SettingsSnapshot) -> DensitySampler.WorldDensity:
	return DensitySampler.create_open_terrain_world_density(
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
		settings.open_terrain_heightmap_image
	)


func _duplicate_heightmap_image() -> Image:
	if heightmap == null:
		return null
	var image: Image = heightmap.get_image()
	if image == null or image.is_empty():
		return null
	return image.duplicate()
