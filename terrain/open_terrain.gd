@tool
class_name OpenTerrain
extends ChunkedTerrainWorld
## Boxed-in style 3D noise clipped by a heightmap surface (open top, side/bottom walls).

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
		_heightmap_image_cache = null
		_request_rebuild()
## Raises or lowers the ground surface in meters (relative to this node's Y).
@export var surface_height_offset: float = 0.0:
	set(value):
		surface_height_offset = value
		_request_rebuild()

@export_group("Edges")
## Clip terrain to world bounds on X, Z, and bottom Y. Top remains open.
@export var boxed_edges_enabled: bool = true:
	set(value):
		boxed_edges_enabled = value
		_request_rebuild()
## Clips the terrain to a sphere of this radius around the node (a fish bowl); 0 keeps box edges.
@export var bowl_radius: float = 0.0:
	set(value):
		bowl_radius = maxf(value, 0.0)
		_request_rebuild()
## Fills solid ground below the heightmap surface instead of 3D cave noise.
@export var solid_underside: bool = false:
	set(value):
		solid_underside = value
		_request_rebuild()

## Private copy of the heightmap's image, shared read-only by every settings snapshot and
## worker thread instead of being duplicated per snapshot.
var _heightmap_image_cache: Image


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
	settings.open_terrain_solid_fill = solid_underside
	settings.open_terrain_heightmap_image = _duplicate_heightmap_image()
	settings.open_terrain_surface_offset = surface_height_offset
	settings.open_terrain_bowl_radius = bowl_radius


func _build_world_density(
	settings: ChunkedTerrainWorld.SettingsSnapshot
) -> DensitySampler.WorldDensity:
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
		settings.open_terrain_heightmap_image,
		settings.open_terrain_surface_offset,
		settings.open_terrain_solid_fill,
		settings.open_terrain_bowl_radius
	)


func _duplicate_heightmap_image() -> Image:
	if heightmap == null:
		return null
	if _heightmap_image_cache != null:
		return _heightmap_image_cache
	var image: Image = heightmap.get_image()
	if image == null or image.is_empty():
		return null
	_heightmap_image_cache = image.duplicate()
	return _heightmap_image_cache
