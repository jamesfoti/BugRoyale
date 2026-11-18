@tool
class_name BiomePlants
extends Node3D
## Grows the plants of a map's biomes (PlantFeature) over its built ground: for each plant the
## terrain lists under Biome Features, a field of meshes in each `TILE` square of the map, one
## MultiMeshInstance3D per plant and tile, so the far tiles drop out past the plant's draw
## distance. Each of the plant's cells (`spacing` metres) has one jittered spot that grows one
## when its hash falls under the density the biome there gives the plant, the ground there is
## built, not too steep and open (not up a termite mound's side or on a ledge over the
## surface). The same seed grows the same plants. A tile grows again when its ground is
## rebuilt (a dig), so nothing floats over a hole. It works in the editor as well as in play:
## the terrain lab shows its plants as it builds.

## The side of a tile in metres.
const TILE: float = 32.0
## How far over or under the surface's height a spot may lie and still count as open ground.
const OPEN_GROUND: float = 1.5

var terrain: OpenTerrain

## Tile (Vector2i) -> its MultiMeshInstance3Ds.
var _tiles: Dictionary = {}
## Plant feature -> {"mesh", "material"}, built once.
var _looks: Dictionary = {}
## Tiles to grow again next frame (their ground was rebuilt).
var _pending: Dictionary = {}
var _grown: bool = false


## Adds the grower beside a terrain (one per scene); null without a terrain.
static func attach(scene_root: Node, terrain_node: OpenTerrain) -> BiomePlants:
	if scene_root == null or terrain_node == null:
		return null
	var existing: BiomePlants = scene_root.get_node_or_null("BiomePlants") as BiomePlants
	if existing != null:
		return existing
	var plants := BiomePlants.new()
	plants.name = "BiomePlants"
	plants.terrain = terrain_node
	scene_root.add_child(plants)
	return plants


## The plant features a terrain lists.
static func plants_of(terrain_node: OpenTerrain) -> Array[PlantFeature]:
	var out: Array[PlantFeature] = []
	for feature: Variant in terrain_node.biome_features:
		if feature is PlantFeature:
			out.append(feature as PlantFeature)
	return out


func _ready() -> void:
	if terrain == null:
		return
	terrain.built.connect(grow)
	terrain.chunk_rebuilt.connect(_on_ground_changed)
	terrain.ground_placed.connect(_on_ground_changed)
	if not terrain.is_building() and terrain.get_child_count() > 0:
		grow.call_deferred()


func _process(_delta: float) -> void:
	if _pending.is_empty():
		return
	var tiles: Array = _pending.keys()
	_pending.clear()
	var density: WorldDensity = terrain._get_bake_density()
	if density == null:
		return
	var densities: Dictionary = _densities_by_biome(density)
	for tile: Vector2i in tiles:
		_grow_tile(tile, density, densities)


## How many plants stand now.
func count() -> int:
	var total: int = 0
	for tile: Vector2i in _tiles:
		for field: MultiMeshInstance3D in _tiles[tile]:
			total += field.multimesh.instance_count
	return total


## Clears the plants and grows them afresh over the terrain as built.
func grow() -> void:
	clear()
	_grown = true
	var plants: Array[PlantFeature] = plants_of(terrain)
	var density: WorldDensity = terrain._get_bake_density()
	if plants.is_empty() or density == null:
		return
	var started: int = Time.get_ticks_msec()
	var densities: Dictionary = _densities_by_biome(density)
	var area: AABB = _area()
	for tile_z: int in range(floori(area.position.z / TILE), ceili(area.end.z / TILE)):
		for tile_x: int in range(floori(area.position.x / TILE), ceili(area.end.x / TILE)):
			_grow_tile(Vector2i(tile_x, tile_z), density, densities)
	print(
		(
			"[BiomePlants] %d plants of %d kinds in %d ms"
			% [count(), plants.size(), Time.get_ticks_msec() - started]
		)
	)


## Frees every plant.
func clear() -> void:
	for tile: Vector2i in _tiles:
		for field: MultiMeshInstance3D in _tiles[tile]:
			field.queue_free()
	_tiles.clear()
	_pending.clear()


func _area() -> AABB:
	var extents: Vector3 = terrain.get_world_extents()
	return AABB(terrain.global_position - extents * 0.5, extents)


## Biome name -> {feature instance id: density}, from the land kinds as the terrain built them.
func _densities_by_biome(density: WorldDensity) -> Dictionary:
	var out: Dictionary = {}
	for kind: Dictionary in density.get_land_biomes():
		var by_feature: Dictionary = {}
		for entry: Dictionary in kind.get("features", []):
			by_feature[int(entry.get("id", 0))] = float(entry.get("density", 0.0))
		out[str(kind.get("name", ""))] = by_feature
	return out


func _grow_tile(tile: Vector2i, density: WorldDensity, densities: Dictionary) -> void:
	for old: MultiMeshInstance3D in _tiles.get(tile, []):
		old.queue_free()
	_tiles.erase(tile)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return
	var area: AABB = _area()
	var low := Vector2(maxf(tile.x * TILE, area.position.x), maxf(tile.y * TILE, area.position.z))
	var high := Vector2(
		minf((tile.x + 1) * TILE, area.end.x), minf((tile.y + 1) * TILE, area.end.z)
	)
	if high.x <= low.x or high.y <= low.y:
		return
	# The biome at a few spots of the tile, so each plant's spot need not ask the terrain.
	var names: Dictionary = {}
	var fields: Array[MultiMeshInstance3D] = []
	for plant: PlantFeature in plants_of(terrain):
		var transforms: Array[Transform3D] = []
		var colors: Array[Color] = []
		var spacing: float = maxf(plant.spacing, 0.5)
		var max_tilt: float = deg_to_rad(plant.max_slope_degrees)
		for cell_z: int in range(floori(low.y / spacing), ceili(high.y / spacing)):
			for cell_x: int in range(floori(low.x / spacing), ceili(high.x / spacing)):
				var roll := RandomNumberGenerator.new()
				roll.seed = hash([terrain.noise_seed, plant.feature_name, cell_x, cell_z])
				var x: float = (cell_x + roll.randf_range(0.1, 0.9)) * spacing
				var z: float = (cell_z + roll.randf_range(0.1, 0.9)) * spacing
				if x < low.x or x >= high.x or z < low.y or z >= high.y:
					continue
				var name: String = _biome_name(density, names, x, z)
				var share: float = float(densities.get(name, {}).get(plant.get_instance_id(), 0.0))
				if share <= 0.0 or roll.randf() >= share:
					continue
				var hit: Dictionary = _ground(space, area, x, z)
				if hit.is_empty():
					continue
				var normal: Vector3 = hit.normal
				if normal.angle_to(Vector3.UP) > max_tilt:
					continue
				var surface: float = terrain.get_surface_height_at(hit.position)
				if absf(hit.position.y - surface) > OPEN_GROUND:
					continue
				transforms.append(_placed(plant, roll, hit.position, normal))
				colors.append(_shade(plant, roll))
		if transforms.is_empty():
			continue
		fields.append(_field(plant, transforms, colors))
	if not fields.is_empty():
		_tiles[tile] = fields


## The biome's name at a spot, from the nearest of an 8 m grid's spots (asked once each).
func _biome_name(density: WorldDensity, names: Dictionary, x: float, z: float) -> String:
	var key := Vector2i(roundi(x / 8.0), roundi(z / 8.0))
	if not names.has(key):
		names[key] = str(density.land_biome(key.x * 8.0, key.y * 8.0).get("name", ""))
	return names[key]


## The built ground straight down at a column: {position, normal}, or empty (not built yet).
func _ground(space: PhysicsDirectSpaceState3D, area: AABB, x: float, z: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(x, area.end.y + 10.0, z),
		Vector3(x, area.position.y - 10.0, z),
		MapInfo.TERRAIN_LAYER
	)
	return space.intersect_ray(query)


func _placed(
	plant: PlantFeature, roll: RandomNumberGenerator, at: Vector3, normal: Vector3
) -> Transform3D:
	var up: Vector3 = Vector3.UP.lerp(normal, plant.follow_slope).normalized()
	var height: float = roll.randf_range(plant.height.x, plant.height.y)
	var width: float = height * plant.girth * roll.randf_range(0.85, 1.15)
	var yaw := Basis(Vector3.UP, roll.randf() * TAU)
	var tilt := Basis.IDENTITY
	var axis: Vector3 = Vector3.UP.cross(up)
	if axis.length() > 0.0001:
		tilt = Basis(axis.normalized(), Vector3.UP.angle_to(up))
	var basis: Basis = tilt * yaw * Basis.from_scale(Vector3(width, height, width))
	# A little sunk, so a foot on a slope does not hang over the low side.
	return Transform3D(basis, at - up * height * 0.03)


func _shade(plant: PlantFeature, roll: RandomNumberGenerator) -> Color:
	var amount: float = plant.color_variation
	var bright: float = 1.0 + roll.randf_range(-amount, amount)
	return Color(
		bright + roll.randf_range(-amount, amount) * 0.4,
		bright + roll.randf_range(-amount, amount) * 0.4,
		bright + roll.randf_range(-amount, amount) * 0.4
	)


func _field(
	plant: PlantFeature, transforms: Array[Transform3D], colors: Array[Color]
) -> MultiMeshInstance3D:
	var look: Dictionary = _look(plant)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = look.mesh
	multimesh.instance_count = transforms.size()
	for index: int in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
		multimesh.set_instance_color(index, colors[index])
	var field := MultiMeshInstance3D.new()
	field.multimesh = multimesh
	field.material_override = look.material
	field.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if plant.cast_shadows
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	field.visibility_range_end = plant.draw_distance
	field.visibility_range_end_margin = plant.draw_distance * 0.1
	field.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(field)
	return field


func _look(plant: PlantFeature) -> Dictionary:
	if not _looks.has(plant):
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.roughness = 0.9
		var mesh: Mesh = plant.mesh
		if mesh == null:
			mesh = PlantMeshes.build(plant.shape, plant.color, hash(plant.feature_name))
		_looks[plant] = {"mesh": mesh, "material": material}
	return _looks[plant]


func _on_ground_changed(box: AABB) -> void:
	# A whole rebuild grows everything again once it is built.
	if not _grown or terrain.is_building() or plants_of(terrain).is_empty():
		return
	for tile_z: int in range(floori(box.position.z / TILE), ceili(box.end.z / TILE)):
		for tile_x: int in range(floori(box.position.x / TILE), ceili(box.end.x / TILE)):
			_pending[Vector2i(tile_x, tile_z)] = true
