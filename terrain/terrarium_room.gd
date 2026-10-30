@tool
class_name TerrariumRoom
extends Node3D
## Procedurally generates a furnished room with an optional glass terrarium and voxel terrain.

signal content_rebuilt

enum TerrariumShape { BOX, BOWL }

const DEFAULT_TERRAIN_MATERIAL_PATH: String = "res://materials/terrarium_ground.tres"

@export_group("Room")
@export var room_seed: int = 77:
	set(value):
		room_seed = value
		_request_rebuild()
@export var room_type: InteriorRoomLayout.RoomType = InteriorRoomLayout.RoomType.RANDOM:
	set(value):
		room_type = value
		_request_rebuild()
@export var room_size: Vector3 = Vector3(8.0, 3.5, 8.0):
	set(value):
		room_size = Vector3(maxf(value.x, 3.0), maxf(value.y, 2.5), maxf(value.z, 3.0))
		_request_rebuild()
@export_range(0.2, 1.0, 0.05) var wall_thickness: float = 0.4:
	set(value):
		wall_thickness = maxf(value, 0.2)
		_request_rebuild()
@export_range(0.5, 8.0, 0.1, "or_greater") var room_scale: float = 4.0:
	set(value):
		room_scale = maxf(value, 0.5)
		_request_rebuild()
@export_range(0.5, 6.0, 0.1, "or_greater") var furniture_scale: float = 3.0:
	set(value):
		furniture_scale = maxf(value, 0.5)
		_request_rebuild()

@export_group("Content")
@export var spawn_shell: bool = true:
	set(value):
		spawn_shell = value
		_request_rebuild()
@export var spawn_furniture: bool = true:
	set(value):
		spawn_furniture = value
		_request_rebuild()
@export var spawn_light: bool = true:
	set(value):
		spawn_light = value
		_request_rebuild()
@export var spawn_glass_box: bool = true:
	set(value):
		spawn_glass_box = value
		_request_rebuild()
@export var glass_box_size: Vector3 = Vector3(1.5, 1.5, 1.5):
	set(value):
		glass_box_size = Vector3(maxf(value.x, 0.25), maxf(value.y, 0.25), maxf(value.z, 0.25))
		_request_rebuild()
@export_range(0.1, 8.0, 0.1, "or_greater") var ceiling_light_energy: float = 1.2:
	set(value):
		ceiling_light_energy = maxf(value, 0.1)
		_request_rebuild()

@export_group("Terrarium")
## Spawns a glass terrarium prop (and optional voxel terrain) on a table or the floor.
@export var spawn_terrarium: bool = true:
	set(value):
		spawn_terrarium = value
		_request_rebuild()
## Builds open heightmap voxel terrain inside the glass box.
@export var spawn_terrarium_terrain: bool = true:
	set(value):
		spawn_terrarium_terrain = value
		_request_rebuild()
## A glass box, or a round fish bowl (terrain and water are clipped to the sphere).
@export var terrarium_shape: TerrariumShape = TerrariumShape.BOX:
	set(value):
		terrarium_shape = value
		_request_rebuild()

@export_subgroup("Grid")
@export_range(1, 16, 1) var terrarium_chunks_x: int = 1:
	set(value):
		terrarium_chunks_x = maxi(value, 1)
		_request_rebuild()
@export_range(1, 16, 1) var terrarium_chunks_y: int = 1:
	set(value):
		terrarium_chunks_y = maxi(value, 1)
		_request_rebuild()
@export_range(1, 16, 1) var terrarium_chunks_z: int = 1:
	set(value):
		terrarium_chunks_z = maxi(value, 1)
		_request_rebuild()
@export_range(1.0, 64.0, 0.5, "suffix:m") var terrarium_chunk_size: float = 5.0:
	set(value):
		terrarium_chunk_size = clampf(
			value, TerrariumBudget.MIN_CHUNK_SIZE, TerrariumBudget.MAX_CHUNK_SIZE
		)
		_request_rebuild()

@export_subgroup("Terrain")
@export var terrarium_material: Material
@export var terrarium_noise_seed: int = OpenTerrainPreset.NOISE_SEED:
	set(value):
		terrarium_noise_seed = value
		_request_rebuild()
@export var terrarium_heightmap: Texture2D:
	set(value):
		terrarium_heightmap = value
		_request_rebuild()
## Raises or lowers the terrarium ground surface in meters.
@export var terrarium_surface_height_offset: float = OpenTerrainPreset.SURFACE_HEIGHT_OFFSET:
	set(value):
		terrarium_surface_height_offset = value
		_request_rebuild()
@export var terrarium_boxed_edges_enabled: bool = OpenTerrainPreset.BOXED_EDGES_ENABLED:
	set(value):
		terrarium_boxed_edges_enabled = value
		_request_rebuild()
@export var terrarium_noise_amplitude: float = OpenTerrainPreset.NOISE_AMPLITUDE:
	set(value):
		terrarium_noise_amplitude = value
		_request_rebuild()
@export var terrarium_noise_frequency: float = OpenTerrainPreset.NOISE_FREQUENCY:
	set(value):
		terrarium_noise_frequency = maxf(value, 0.001)
		_request_rebuild()
@export_range(1, 8, 1) var terrarium_noise_octaves: int = OpenTerrainPreset.NOISE_OCTAVES:
	set(value):
		terrarium_noise_octaves = maxi(value, 1)
		_request_rebuild()
@export var terrarium_noise_lacunarity: float = OpenTerrainPreset.NOISE_LACUNARITY:
	set(value):
		terrarium_noise_lacunarity = maxf(value, 1.0)
		_request_rebuild()
@export var terrarium_noise_gain: float = OpenTerrainPreset.NOISE_GAIN:
	set(value):
		terrarium_noise_gain = clampf(value, 0.01, 1.0)
		_request_rebuild()

@export_subgroup("Water")
## Fills the bottom of the terrarium with shader water.
@export var spawn_terrarium_water: bool = true:
	set(value):
		spawn_terrarium_water = value
		_request_rebuild()
## Water depth as a fraction of terrarium height (from the bottom).
@export_range(0.05, 0.6, 0.01)
var terrarium_water_level: float = TerrariumWater.DEFAULT_WATER_LEVEL_RATIO:
	set(value):
		terrarium_water_level = clampf(
			value, TerrariumWater.MIN_WATER_LEVEL_RATIO, TerrariumWater.MAX_WATER_LEVEL_RATIO
		)
		_request_rebuild()

@export_subgroup("Vegetation")
## Grows moss, ferns, rocks, driftwood and small trees over the terrarium terrain.
@export var spawn_terrarium_vegetation: bool = true:
	set(value):
		spawn_terrarium_vegetation = value
		_request_rebuild()
## Multiplies how many plants and props grow (1 = the default garden).
@export_range(0.0, 3.0, 0.1) var terrarium_vegetation_density: float = 1.0:
	set(value):
		terrarium_vegetation_density = maxf(value, 0.0)
		_request_rebuild()

@export_group("Runtime")
@export var rebuild_on_ready: bool = true
@export var auto_rebuild_in_editor: bool = false

var _layout: InteriorRoomLayout.Layout
var _shell_root: Node3D
var _furniture_root: Node3D
var _light_root: Node3D
var _glass_box_root: Node3D
var _terrarium_terrain: TerrariumTerrain
var _terrarium_water: TerrariumWater
var _bowl_radius: float = 0.0
var _dirty: bool = true
var _is_rebuilding: bool = false
var _force_sync_rebuild: bool = false


func _ready() -> void:
	_ensure_export_defaults()
	add_to_group("terrarium_room")
	add_to_group("boxed_in_terrain")
	if rebuild_on_ready and (not Engine.is_editor_hint() or auto_rebuild_in_editor):
		call_deferred("rebuild_all")


func is_rebuilding() -> bool:
	return _is_rebuilding


func get_playable_terrain() -> TerrariumTerrain:
	if _terrarium_terrain != null and is_instance_valid(_terrarium_terrain):
		return _terrarium_terrain
	return null


## Sphere radius of a fish-bowl terrarium, 0 for a glass box.
func get_bowl_radius() -> float:
	return _bowl_radius


## World center of the fish bowl's sphere (the terrain grid's center).
func get_bowl_center() -> Vector3:
	var playable: TerrariumTerrain = get_playable_terrain()
	if playable != null:
		return playable.global_position
	if _glass_box_root != null:
		return (
			_glass_box_root.global_position
			+ Vector3.UP * TerrariumBudget.get_terrain_floor_offset(get_terrarium_world_size())
		)
	return global_position


func get_surface_height_at(_world_position: Vector3) -> float:
	var playable: TerrariumTerrain = get_playable_terrain()
	if playable != null:
		return playable.get_surface_height_at(_world_position)
	if _layout != null:
		return global_position.y + _layout.floor_y
	return global_position.y


func get_world_extents() -> Vector3:
	var playable: TerrariumTerrain = get_playable_terrain()
	if playable != null:
		return playable.get_world_extents()
	if _layout != null:
		return _layout.world_aabb.size
	return room_size * room_scale


func get_spawn_position(spawn_clearance: float = 1.2) -> Vector3:
	var playable: TerrariumTerrain = get_playable_terrain()
	if playable == null:
		if _layout != null:
			return global_position + _layout.spawn_position
		return global_position + Vector3(0.0, spawn_clearance, 0.0)
	return _probe_terrarium_spawn(playable, spawn_clearance)


func _probe_terrarium_spawn(playable: TerrariumTerrain, spawn_clearance: float) -> Vector3:
	var half_extents: Vector3 = playable.get_world_extents() * 0.5
	var random_offset: Vector3 = Vector3(
		randf_range(-half_extents.x * 0.35, half_extents.x * 0.35),
		0.0,
		randf_range(-half_extents.z * 0.35, half_extents.z * 0.35)
	)
	var probe_xz: Vector3 = playable.global_position + random_offset
	var ray_top: Vector3 = probe_xz + Vector3.UP * half_extents.y * 0.95
	var ray_bottom: Vector3 = probe_xz - Vector3.UP * half_extents.y * 1.05
	if is_inside_tree():
		var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			ray_top, ray_bottom
		)
		ray_query.collide_with_areas = false
		var hit: Dictionary = space.intersect_ray(ray_query)
		if not hit.is_empty() and _is_terrarium_collider(playable, hit.get("collider")):
			return hit.position + Vector3.UP * spawn_clearance
	var surface_y: float = playable.get_surface_height_at(probe_xz)
	return Vector3(probe_xz.x, surface_y + spawn_clearance, probe_xz.z)


func _is_terrarium_collider(playable: TerrariumTerrain, collider: Variant) -> bool:
	if collider is Node:
		var node: Node = collider as Node
		return playable == node or playable.is_ancestor_of(node)
	return false


func get_room_type_name() -> String:
	if _layout == null:
		return InteriorRoomLayout.RoomType.keys()[room_type]
	return InteriorRoomLayout.RoomType.keys()[_layout.room_type]


func get_terrarium_chunks() -> Vector3i:
	return Vector3i(terrarium_chunks_x, terrarium_chunks_y, terrarium_chunks_z)


func get_terrarium_grid_config() -> TerrariumBudget.GridConfig:
	return TerrariumBudget.derive_grid_from_chunks(get_terrarium_chunks(), terrarium_chunk_size)


func get_terrarium_world_size() -> Vector3:
	return get_terrarium_grid_config().world_size


func get_effective_glass_box_size() -> Vector3:
	if spawn_terrarium:
		return TerrariumBudget.derive_glass_box_size(get_terrarium_world_size())
	return glass_box_size


func rebuild_all() -> void:
	_ensure_export_defaults()
	_dirty = true
	_is_rebuilding = true
	if Engine.is_editor_hint() and _force_sync_rebuild:
		_rebuild_content()
		_force_sync_rebuild = false
	else:
		call_deferred("_rebuild_content")


func rebuild_all_editor() -> void:
	_force_sync_rebuild = true
	rebuild_all()


func destroy_all() -> void:
	_clear_content()
	_layout = null
	_dirty = true
	if Engine.is_editor_hint():
		print("[TerrariumRoom] Destroyed room (editor)")


func _request_rebuild() -> void:
	_dirty = true
	if not is_node_ready():
		return
	if Engine.is_editor_hint() and not auto_rebuild_in_editor:
		return
	call_deferred("rebuild_all")


func _rebuild_content() -> void:
	if not _dirty:
		_finish_rebuild()
		return
	_dirty = false
	_clear_content()
	_layout = InteriorRoomLayout.generate(
		room_seed, room_type, room_size, wall_thickness, room_size.y, room_scale
	)
	if spawn_shell:
		_shell_root = InteriorRoomShellBuilder.build(_layout, wall_thickness * room_scale)
		add_child(_shell_root)
		_register_generated_node(_shell_root)
	if spawn_light:
		_light_root = InteriorRoomLighting.build(_layout, ceiling_light_energy)
		add_child(_light_root)
		_register_generated_node(_light_root)

	var placements: Array[InteriorRoomFurniture.Placement] = []
	if spawn_furniture:
		placements = InteriorRoomFurniture.place_for_layout(_layout, room_seed)
		_furniture_root = Node3D.new()
		_furniture_root.name = "Furniture"
		add_child(_furniture_root)
		_register_generated_node(_furniture_root)
		for placement: InteriorRoomFurniture.Placement in placements:
			var furniture_body: StaticBody3D = InteriorFurnitureBuilder.build(
				placement, furniture_scale
			)
			_furniture_root.add_child(furniture_body)
			_register_generated_node(furniture_body)

	if spawn_glass_box:
		_spawn_glass_or_terrarium(placements)

	if _terrarium_terrain == null:
		_finish_rebuild()
	elif Engine.is_editor_hint():
		_log_editor_build()


func _finish_rebuild() -> void:
	_is_rebuilding = false
	content_rebuilt.emit()


func _log_editor_build() -> void:
	var terrarium_note: String = ""
	if _terrarium_terrain != null:
		var grid: TerrariumBudget.GridConfig = get_terrarium_grid_config()
		terrarium_note = (
			" terrarium=%dx%dx%d chunks @ %.1f m (%.1fx%.1fx%.1f m)"
			% [
				grid.chunks.x,
				grid.chunks.y,
				grid.chunks.z,
				grid.chunk_size,
				grid.world_size.x,
				grid.world_size.y,
				grid.world_size.z,
			]
		)
	print(
		(
			"[TerrariumRoom] Built %s (editor, seed %d)%s"
			% [get_room_type_name(), room_seed, terrarium_note]
		)
	)


func _spawn_glass_or_terrarium(placements: Array[InteriorRoomFurniture.Placement]) -> void:
	if spawn_terrarium:
		var terrain_material: Material = terrarium_material
		if terrain_material == null and ResourceLoader.exists(DEFAULT_TERRAIN_MATERIAL_PATH):
			terrain_material = load(DEFAULT_TERRAIN_MATERIAL_PATH) as Material
		var spawn_result: Variant = InteriorTerrariumSpawner.build_if_clear(
			_layout,
			placements,
			get_terrarium_grid_config(),
			terrarium_noise_seed,
			terrain_material,
			spawn_terrarium_terrain,
			terrarium_noise_amplitude,
			terrarium_noise_frequency,
			terrarium_noise_octaves,
			terrarium_noise_lacunarity,
			terrarium_noise_gain,
			terrarium_surface_height_offset,
			terrarium_heightmap,
			terrarium_boxed_edges_enabled,
			furniture_scale,
			spawn_terrarium_water,
			terrarium_water_level,
			terrarium_shape == TerrariumShape.BOWL
		)
		if spawn_result == null:
			return
		var result: InteriorTerrariumSpawner.SpawnResult = (
			spawn_result as InteriorTerrariumSpawner.SpawnResult
		)
		_glass_box_root = result.root
		_terrarium_terrain = result.terrain as TerrariumTerrain
		_terrarium_water = result.water
		_bowl_radius = result.bowl_radius
		add_child(_glass_box_root)
		if _terrarium_terrain != null:
			_apply_terrarium_terrain_settings(_terrarium_terrain)
		_refresh_glass_box_visuals(_glass_box_root)
		_register_generated_node(_glass_box_root)
		if _terrarium_terrain != null:
			call_deferred("_rebuild_terrarium_terrain")
		else:
			_finish_rebuild()
		return

	_glass_box_root = InteriorGlassBoxSpawner.build_if_clear(_layout, placements, glass_box_size)
	if _glass_box_root != null:
		add_child(_glass_box_root)
		_refresh_glass_box_visuals(_glass_box_root)
		_register_generated_node(_glass_box_root)


func _clear_content() -> void:
	_terrarium_terrain = null
	_terrarium_water = null
	_bowl_radius = 0.0
	_free_generated_root(_shell_root)
	_shell_root = null
	_free_generated_root(_furniture_root)
	_furniture_root = null
	_free_generated_root(_light_root)
	_light_root = null
	_free_generated_root(_glass_box_root)
	_glass_box_root = null
	_remove_children_named(&"RoomShell")
	_remove_children_named(&"Furniture")
	_remove_children_named(&"RoomLight")
	_remove_children_named(&"GlassBoxProp")
	_remove_children_named(&"TerrariumTerrain")


func _free_generated_root(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	remove_child(node)
	if Engine.is_editor_hint():
		node.free()
	else:
		node.queue_free()


func _remove_children_named(child_name: StringName) -> void:
	for child in get_children():
		if child.name != child_name:
			continue
		remove_child(child)
		if Engine.is_editor_hint():
			child.free()
		else:
			child.queue_free()


func _register_generated_node(node: Node) -> void:
	if not Engine.is_editor_hint():
		return
	var scene_root: Node = get_tree().edited_scene_root
	if scene_root == null or node == scene_root:
		return
	node.owner = scene_root
	for child in node.get_children():
		_register_generated_node(child)


func _refresh_glass_box_visuals(glass_box_root: Node3D) -> void:
	var glass_box: Node = glass_box_root.get_node_or_null("GlassBox")
	if glass_box != null and glass_box.has_method("rebuild"):
		glass_box.call("rebuild")


func _rebuild_terrarium_terrain() -> void:
	if _terrarium_terrain == null or not is_instance_valid(_terrarium_terrain):
		_finish_rebuild()
		return
	_apply_terrarium_terrain_settings(_terrarium_terrain)
	_terrarium_terrain.rebuild_all()
	_grow_terrarium_vegetation()
	_log_editor_build()
	_finish_rebuild()


## Grows the garden over the freshly built terrain (the vegetation lives under the terrarium
## prop, so it is cleared with it). Seeded from the terrain so the same terrarium regrows alike.
func _grow_terrarium_vegetation() -> void:
	if not spawn_terrarium_vegetation or _glass_box_root == null:
		return
	var vegetation: TerrariumVegetation = TerrariumVegetation.build(
		_terrarium_terrain,
		_terrarium_water,
		terrarium_noise_seed * 31 + room_seed,
		terrarium_vegetation_density
	)
	if _bowl_radius > 0.0:
		vegetation.set_bowl(get_bowl_center(), _bowl_radius)
	_glass_box_root.add_child(vegetation)
	vegetation.grow_when_ready()


func _apply_terrarium_terrain_settings(terrain: TerrariumTerrain) -> void:
	var grid_config: TerrariumBudget.GridConfig = get_terrarium_grid_config()
	terrain.chunks_x = grid_config.chunks.x
	terrain.chunks_y = grid_config.chunks.y
	terrain.chunks_z = grid_config.chunks.z
	terrain.chunk_size = grid_config.chunk_size
	terrain.chunk_resolution = 1
	terrain.bounds_falloff_enabled = false
	terrain.use_threaded_rebuild = false
	terrain.is_playable_world = false
	terrain.noise_enabled = true
	terrain.noise_seed = terrarium_noise_seed
	terrain.noise_frequency = terrarium_noise_frequency
	terrain.noise_amplitude = terrarium_noise_amplitude
	terrain.noise_octaves = terrarium_noise_octaves
	terrain.noise_lacunarity = terrarium_noise_lacunarity
	terrain.noise_gain = terrarium_noise_gain
	terrain.surface_height_offset = terrarium_surface_height_offset
	terrain.heightmap = terrarium_heightmap
	terrain.boxed_edges_enabled = terrarium_boxed_edges_enabled
	var material: Material = terrarium_material
	if material == null and ResourceLoader.exists(DEFAULT_TERRAIN_MATERIAL_PATH):
		material = load(DEFAULT_TERRAIN_MATERIAL_PATH) as Material
	if material != null:
		terrain.terrain_material = material


func _ensure_export_defaults() -> void:
	if get("spawn_glass_box") == null:
		spawn_glass_box = true
	if get("spawn_terrarium") == null:
		spawn_terrarium = true
	if get("spawn_terrarium_terrain") == null:
		spawn_terrarium_terrain = true
	if get("spawn_terrarium_water") == null:
		spawn_terrarium_water = true
	if get("terrarium_water_level") == null:
		terrarium_water_level = TerrariumWater.DEFAULT_WATER_LEVEL_RATIO
	if get("terrarium_boxed_edges_enabled") == null:
		terrarium_boxed_edges_enabled = true
	if get("terrarium_surface_height_offset") == null:
		terrarium_surface_height_offset = OpenTerrainPreset.SURFACE_HEIGHT_OFFSET
	if get("terrarium_noise_lacunarity") == null:
		terrarium_noise_lacunarity = OpenTerrainPreset.NOISE_LACUNARITY
	if get("terrarium_noise_gain") == null:
		terrarium_noise_gain = OpenTerrainPreset.NOISE_GAIN
	if get("terrarium_noise_seed") == null:
		terrarium_noise_seed = OpenTerrainPreset.NOISE_SEED
	if get("glass_box_size") == null:
		glass_box_size = Vector3(1.5, 1.5, 1.5)
	if get("room_scale") == null:
		room_scale = 4.0
	if get("furniture_scale") == null:
		furniture_scale = 3.0
	_migrate_legacy_terrarium_settings()


func _migrate_legacy_terrarium_settings() -> void:
	var legacy_size: Variant = get("terrarium_world_size")
	if legacy_size is Vector3:
		_apply_legacy_world_size(legacy_size as Vector3)
		return
	var legacy_width: Variant = get("terrarium_width")
	if legacy_width is float:
		var legacy_height: float = (
			float(get("terrarium_height")) if get("terrarium_height") is float else 3.5
		)
		var legacy_depth: float = (
			float(get("terrarium_depth")) if get("terrarium_depth") is float else 5.0
		)
		_apply_legacy_world_size(Vector3(legacy_width, legacy_height, legacy_depth))


func _apply_legacy_world_size(world_size: Vector3) -> void:
	var chunk_size: float = maxf(terrarium_chunk_size, TerrariumBudget.MIN_CHUNK_SIZE)
	terrarium_chunks_x = maxi(1, int(round(world_size.x / chunk_size)))
	terrarium_chunks_y = maxi(1, int(round(world_size.y / chunk_size)))
	terrarium_chunks_z = maxi(1, int(round(world_size.z / chunk_size)))
