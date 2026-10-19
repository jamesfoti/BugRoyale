@tool
class_name TerrariumTerrain
extends OpenTerrain
## Small open heightmap terrain sized to fit inside a glass terrarium.


func _ready() -> void:
	_apply_defaults_without_rebuild()
	# Rebuild is driven by TerrariumRoom, not export setters or rebuild_on_ready.


func _request_rebuild() -> void:
	# Export setters must not auto-rebuild; TerrariumRoom calls rebuild_all() explicitly.
	pass


func _apply_defaults_without_rebuild() -> void:
	is_playable_world = false
	bounds_falloff_enabled = false
	boxed_edges_enabled = true
	chunk_resolution = 1
	use_threaded_rebuild = false
	chunks_x = mini(maxi(chunks_x, 1), TerrariumBudget.MAX_CHUNKS_PER_AXIS)
	chunks_y = mini(maxi(chunks_y, 1), TerrariumBudget.MAX_CHUNKS_PER_AXIS)
	chunks_z = mini(maxi(chunks_z, 1), TerrariumBudget.MAX_CHUNKS_PER_AXIS)
	chunk_size = clampf(chunk_size, TerrariumBudget.MIN_CHUNK_SIZE, TerrariumBudget.MAX_CHUNK_SIZE)


func _ensure_world_defaults() -> void:
	_apply_defaults_without_rebuild()


func _register_playable_groups() -> void:
	pass


func rebuild_all() -> void:
	_apply_defaults_without_rebuild()
	super.rebuild_all()


func _get_world_log_name() -> String:
	return "TerrariumTerrain"


func get_surface_height_at(world_position: Vector3) -> float:
	var local_position: Vector3 = to_local(world_position)
	var half_extents: Vector3 = get_world_extents() * 0.5
	if (
		absf(local_position.x) > half_extents.x
		or absf(local_position.z) > half_extents.z
	):
		return global_position.y
	var density: DensitySampler.WorldDensity = _get_bake_density()
	if density.open_terrain_enabled:
		return density.sample_open_terrain_height(world_position.x, world_position.z)
	return global_position.y - half_extents.y


static func create_configured(
	grid_config: TerrariumBudget.GridConfig,
	noise_seed: int,
	terrain_material: Material,
	noise_amplitude: float = OpenTerrainPreset.NOISE_AMPLITUDE,
	noise_frequency: float = OpenTerrainPreset.NOISE_FREQUENCY,
	noise_octaves: int = OpenTerrainPreset.NOISE_OCTAVES,
	noise_lacunarity: float = OpenTerrainPreset.NOISE_LACUNARITY,
	noise_gain: float = OpenTerrainPreset.NOISE_GAIN,
	surface_height_offset: float = OpenTerrainPreset.SURFACE_HEIGHT_OFFSET,
	heightmap: Texture2D = null,
	boxed_edges_enabled: bool = OpenTerrainPreset.BOXED_EDGES_ENABLED,
	bowl_radius: float = 0.0
) -> TerrariumTerrain:
	var terrain := TerrariumTerrain.new()
	terrain.bowl_radius = bowl_radius
	terrain.name = "TerrariumTerrain"
	terrain.rebuild_on_ready = false
	terrain.auto_rebuild_in_editor = false
	terrain.is_playable_world = false
	terrain.chunks_x = grid_config.chunks.x
	terrain.chunks_y = grid_config.chunks.y
	terrain.chunks_z = grid_config.chunks.z
	terrain.chunk_size = grid_config.chunk_size
	terrain.chunk_resolution = 1
	terrain.bounds_falloff_enabled = false
	terrain.boxed_edges_enabled = boxed_edges_enabled
	terrain.heightmap = heightmap
	terrain.surface_height_offset = surface_height_offset
	terrain.noise_seed = noise_seed
	terrain.noise_amplitude = noise_amplitude
	terrain.noise_frequency = noise_frequency
	terrain.noise_octaves = noise_octaves
	terrain.noise_lacunarity = noise_lacunarity
	terrain.noise_gain = noise_gain
	terrain.use_threaded_rebuild = false
	if terrain_material != null:
		terrain.terrain_material = terrain_material
	return terrain
