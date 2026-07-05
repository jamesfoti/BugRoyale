@tool
class_name FlatTerrain
extends ChunkedTerrainWorld
## 3D noise terrain clipped to a boxed world volume.


@export_group("Flat Terrain Grid")
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

@export_group("Edges")
## Clip terrain to the world bounds on the X, Y, and Z axes.
@export var boxed_edges_enabled: bool = true:
	set(value):
		boxed_edges_enabled = value
		_request_rebuild()


func _register_playable_groups() -> void:
	add_to_group("flat_terrain")


func _get_grid_dimensions() -> Vector3i:
	return Vector3i(chunks_x, chunks_y, chunks_z)


func _get_world_log_name() -> String:
	return "FlatTerrain"


func get_surface_height_at(world_position: Vector3) -> float:
	return global_position.y


func _apply_world_specific_settings(settings: ChunkedTerrainWorld.SettingsSnapshot) -> void:
	settings.sphere_enabled = false
	settings.flat_terrain_enabled = true
	settings.flat_boxed_edges_enabled = boxed_edges_enabled


func _build_world_density(settings: ChunkedTerrainWorld.SettingsSnapshot) -> DensitySampler.WorldDensity:
	return DensitySampler.create_flat_terrain_world_density(
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
