class_name InteriorTerrariumSpawner
extends RefCounted
## Spawns a glass box and capped terrarium terrain on the room floor.


const GLASS_BOX_SCENE_PATH: String = "res://props/glass_box/glass_box.tscn"
const DEFAULT_TERRAIN_MATERIAL_PATH: String = "res://materials/terrain_procedural.tres"


class SpawnResult:
	var root: Node3D
	var glass_box: Node3D
	var terrain: Node3D
	var water: TerrariumWater
	var floor_position: Vector3 = Vector3.ZERO
	var terrarium_world_size: Vector3 = Vector3(5.0, 5.0, 5.0)
	var glass_box_size: Vector3 = Vector3.ONE


static func build_if_clear(
	layout: InteriorRoomLayout.Layout,
	placements: Array[InteriorRoomFurniture.Placement],
	grid_config: TerrariumBudget.GridConfig,
	noise_seed: int,
	terrain_material: Material = null,
	spawn_terrain: bool = true,
	noise_amplitude: float = OpenTerrainPreset.NOISE_AMPLITUDE,
	noise_frequency: float = OpenTerrainPreset.NOISE_FREQUENCY,
	noise_octaves: int = OpenTerrainPreset.NOISE_OCTAVES,
	noise_lacunarity: float = OpenTerrainPreset.NOISE_LACUNARITY,
	noise_gain: float = OpenTerrainPreset.NOISE_GAIN,
	surface_height_offset: float = OpenTerrainPreset.SURFACE_HEIGHT_OFFSET,
	heightmap: Texture2D = null,
	boxed_edges_enabled: bool = OpenTerrainPreset.BOXED_EDGES_ENABLED,
	furniture_scale: float = 1.0,
	spawn_water: bool = true,
	water_level_ratio: float = TerrariumWater.DEFAULT_WATER_LEVEL_RATIO
) -> Variant:
	var glass_box_size: Vector3 = TerrariumBudget.derive_glass_box_size(grid_config.world_size)
	var spawn_position: Vector3 = find_spawn_position(
		layout,
		placements,
		glass_box_size,
		furniture_scale
	)
	if spawn_position == Vector3.INF:
		return null
	return _build_at(
		spawn_position,
		grid_config,
		noise_seed,
		terrain_material,
		spawn_terrain,
		noise_amplitude,
		noise_frequency,
		noise_octaves,
		noise_lacunarity,
		noise_gain,
		surface_height_offset,
		heightmap,
		boxed_edges_enabled,
		spawn_water,
		water_level_ratio
	)


static func find_spawn_position(
	layout: InteriorRoomLayout.Layout,
	placements: Array[InteriorRoomFurniture.Placement],
	box_size: Vector3,
	furniture_scale: float = 1.0
) -> Vector3:
	var table_position: Vector3 = _find_table_position(
		layout,
		placements,
		box_size,
		furniture_scale
	)
	if table_position != Vector3.INF:
		return table_position
	return InteriorGlassBoxSpawner.find_clear_floor_position(
		layout,
		placements,
		box_size,
		furniture_scale
	)


static func _find_table_position(
	layout: InteriorRoomLayout.Layout,
	placements: Array[InteriorRoomFurniture.Placement],
	_box_size: Vector3,
	furniture_scale: float
) -> Vector3:
	var preferred_types: Array[InteriorRoomFurniture.FurnitureType] = (
		InteriorRoomFurniture.get_preferred_terrarium_surfaces(layout.room_type)
	)
	for furniture_type: InteriorRoomFurniture.FurnitureType in preferred_types:
		for placement: InteriorRoomFurniture.Placement in placements:
			if placement.furniture_type != furniture_type:
				continue
			var surface_info: InteriorRoomFurniture.SurfaceInfo = (
				InteriorRoomFurniture.get_surface_info(furniture_type)
			)
			if surface_info.top_surface_y < 0.0:
				continue
			var scale: float = maxf(furniture_scale, 0.1)
			return Vector3(
				placement.position.x,
				placement.position.y + surface_info.top_surface_y * scale,
				placement.position.z
			)
	return Vector3.INF


static func _build_at(
	spawn_position: Vector3,
	grid_config: TerrariumBudget.GridConfig,
	noise_seed: int,
	terrain_material: Material,
	spawn_terrain: bool,
	noise_amplitude: float,
	noise_frequency: float,
	noise_octaves: int,
	noise_lacunarity: float,
	noise_gain: float,
	surface_height_offset: float,
	heightmap: Texture2D,
	boxed_edges_enabled: bool,
	spawn_water: bool = true,
	water_level_ratio: float = TerrariumWater.DEFAULT_WATER_LEVEL_RATIO
) -> SpawnResult:
	var result := SpawnResult.new()
	result.terrarium_world_size = grid_config.world_size
	result.glass_box_size = TerrariumBudget.derive_glass_box_size(grid_config.world_size)
	result.floor_position = spawn_position

	var root := Node3D.new()
	root.name = "GlassBoxProp"
	root.position = spawn_position

	var glass_box: Node3D = _create_glass_box(result.glass_box_size)
	if glass_box != null:
		root.add_child(glass_box)
		result.glass_box = glass_box

	var material: Material = terrain_material
	if material == null and ResourceLoader.exists(DEFAULT_TERRAIN_MATERIAL_PATH):
		material = load(DEFAULT_TERRAIN_MATERIAL_PATH) as Material

	if spawn_terrain:
		var terrain: TerrariumTerrain = TerrariumTerrain.create_configured(
			grid_config,
			noise_seed,
			material,
			noise_amplitude,
			noise_frequency,
			noise_octaves,
			noise_lacunarity,
			noise_gain,
			surface_height_offset,
			heightmap,
			boxed_edges_enabled
		)
		terrain.position = Vector3(0.0, TerrariumBudget.get_terrain_floor_offset(grid_config.world_size), 0.0)
		root.add_child(terrain)
		result.terrain = terrain

	if spawn_water:
		var water: TerrariumWater = TerrariumWater.create(grid_config.world_size, water_level_ratio)
		root.add_child(water)
		result.water = water
	result.root = root
	return result


static func _create_glass_box(glass_box_size: Vector3) -> Node3D:
	var scene: PackedScene = load(GLASS_BOX_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("[InteriorTerrariumSpawner] Failed to load glass box scene.")
		return null
	var glass_box: Node3D = scene.instantiate()
	if glass_box == null:
		push_error("[InteriorTerrariumSpawner] Failed to instantiate glass box.")
		return null
	glass_box.name = "GlassBox"
	glass_box.scale = glass_box_size
	return glass_box
