@tool
class_name OpenTerrain
extends ChunkedTerrainWorld
## Boxed-in style 3D noise clipped by a heightmap surface (open top, side/bottom walls), or
## solid ground under the surface with a seeded underworld carved out of it (caves_enabled).
## The surface may be terraced into shelves, seed by seed (Terraces).

## Whether the surface is stepped into terraces: rolled from the seed at terrace_chance, or
## forced on (to see a seed's terraces in the lab) or off.
enum Terraces { SEEDED, ALWAYS, NEVER }

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
@export_range(-8.0, 8.0, 0.5) var surface_height_offset: float = 0.0:
	set(value):
		surface_height_offset = value
		_request_rebuild()

@export_group("Terraces")
## Terraces: the surface stepped into shelves on some seeds, in some places (see
## DensitySampler.WorldDensity.terrace_height). Seeded rolls them from the seed at
## terrace_chance; Always and Never override the roll. The tread height and the strength (0 a
## soft benching, 1 flat treads and steep risers) are drawn from their ranges, and
## terrace_coverage is the share of the ground they appear on, a slow noise picking where.
@export var terraces: Terraces = Terraces.SEEDED:
	set(value):
		terraces = value
		_request_rebuild()
@export_range(0.0, 1.0, 0.05) var terrace_chance: float = 0.4:
	set(value):
		terrace_chance = value
		_request_rebuild()
## Tread height in metres, least and most.
@export var terrace_step: Vector2 = Vector2(1.5, 5.0):
	set(value):
		terrace_step = value
		_request_rebuild()
## Strength, least and most, 0 to 1.
@export var terrace_strength: Vector2 = Vector2(0.35, 1.0):
	set(value):
		terrace_strength = value
		_request_rebuild()
@export_range(0.0, 1.0, 0.05) var terrace_coverage: float = 0.5:
	set(value):
		terrace_coverage = value
		_request_rebuild()

@export_group("Edges")
## Clip terrain to world bounds on X, Z, and bottom Y. Top remains open.
@export var boxed_edges_enabled: bool = true:
	set(value):
		boxed_edges_enabled = value
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
	settings.boxed_in_terrain_enabled = false
	settings.open_terrain_enabled = true
	settings.open_terrain_edges_enabled = boxed_edges_enabled
	settings.open_terrain_solid_fill = solid_underside
	settings.open_terrain_heightmap_image = _duplicate_heightmap_image()
	settings.open_terrain_surface_offset = surface_height_offset
	settings.open_terrain_terraces = terraces
	settings.open_terrain_terrace_chance = terrace_chance
	settings.open_terrain_terrace_step = terrace_step
	settings.open_terrain_terrace_strength = terrace_strength
	settings.open_terrain_terrace_coverage = terrace_coverage


func _build_world_density(
	settings: ChunkedTerrainWorld.SettingsSnapshot
) -> DensitySampler.WorldDensity:
	var density: DensitySampler.WorldDensity = DensitySampler.create_open_terrain_world_density(
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
	if settings.caves_enabled and settings.open_terrain_solid_fill:
		density.caves = CaveCarver.for_settings(settings)
	if settings.open_terrain_terraces != Terraces.NEVER:
		density.roll_terraces(
			settings.noise_seed,
			settings.open_terrain_terrace_chance,
			settings.open_terrain_terrace_step,
			settings.open_terrain_terrace_strength,
			settings.open_terrain_terrace_coverage,
			settings.open_terrain_terraces == Terraces.ALWAYS
		)
	return density


func _world_summary(settings: ChunkedTerrainWorld.SettingsSnapshot) -> String:
	var density: DensitySampler.WorldDensity = _build_world_density(settings)
	var summary: String = ", seed %d: %s" % [settings.noise_seed, density.terrace_summary()]
	if density.caves != null:
		summary += ", " + density.caves.summary()
	return summary


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
