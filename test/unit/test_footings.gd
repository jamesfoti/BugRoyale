extends GutTest
## The footings a map builder puts under a structure (ChunkedTerrainWorld.footing): solid
## ground from bedrock up to the dirt. Under a 3D-noise underside the column is solid where
## the sponge around it is not; under a solid underside the caves keep out of it; it digs as
## the map's own ground (stone and veins) where a bed's soil digs as dirt; and the terrain
## sizes one from its own bedrock to cover a footprint's corners.

const SEED: int = 7
const BEDROCK_Y: float = -45.5
const AT := Vector3(20.0, 0.0, -10.0)
const REACH: float = 12.0


func _ground(solid_fill: bool) -> WorldDensity:
	var density: WorldDensity = DensitySampler.create_open_terrain_world_density(
		SEED,
		0.01,
		3.0,
		3,
		2.0,
		0.5,
		Vector3.ZERO,
		Vector3(256.0, 48.0, 256.0),
		0.5,
		false,
		null,
		0.0,
		solid_fill
	)
	if solid_fill:
		density.caves = CaveCarver.from_seed(SEED, BEDROCK_Y)
	return density


## A round footing of REACH about AT from bedrock up to a metre under the surface there.
func _footing(density: WorldDensity, ground: bool = true) -> Dictionary:
	var top: float = density.sample_open_terrain_height(AT.x, AT.z) - 1.0
	return {
		"center": Vector3(AT.x, BEDROCK_Y, AT.z),
		"half_length": REACH,
		"radius": REACH,
		"height": top - BEDROCK_Y,
		"along_z": false,
		"ground": ground,
	}


## Points through the footing's column, from just above bedrock to just under its top, at
## its centre and most of the way out toward its edge.
func _column(footing: Dictionary) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var top: float = BEDROCK_Y + float(footing["height"])
	var y: float = BEDROCK_Y + 1.0
	while y < top - 0.5:
		points.append(Vector3(AT.x, y, AT.z))
		for corner: Vector2 in [Vector2(-8, -8), Vector2(8, -8), Vector2(-8, 8), Vector2(8, 8)]:
			points.append(Vector3(AT.x + corner.x, y, AT.z + corner.y))
		y += 1.0
	return points


## Samples of the ground away from the footing, from 6 m under the surface down to bedrock.
func _elsewhere(density: WorldDensity) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for step: int in 50:
		var x: float = float(step) * 8.0 - 200.0
		var z: float = 100.0
		var surface: float = density.sample_open_terrain_height(x, z)
		var depth: float = 6.0
		while surface - depth > BEDROCK_Y + 2.0:
			points.append(Vector3(x, surface - depth, z))
			depth += 4.0
	return points


func _air_count(density: WorldDensity, points: Array[Vector3]) -> int:
	var air: int = 0
	for point: Vector3 in points:
		if density.evaluate(point) > 0.0:
			air += 1
	return air


func test_a_footing_is_solid_where_a_noise_underside_is_a_sponge() -> void:
	var density: WorldDensity = _ground(false)
	var footing: Dictionary = _footing(density)
	var column: Array[Vector3] = _column(footing)
	assert_gt(_air_count(density, column), 0, "without the footing the column has air in it")
	density.solids = [footing]
	assert_eq(_air_count(density, column), 0, "with it the column is solid top to bottom")
	assert_gt(_air_count(density, _elsewhere(density)), 0, "the ground elsewhere is still a sponge")
	var surface: float = density.sample_open_terrain_height(AT.x, AT.z)
	assert_gt(density.evaluate(Vector3(AT.x, surface + 2.0, AT.z)), 0.0, "air above the footing")


func test_a_footing_keeps_the_caves_out() -> void:
	var density: WorldDensity = _ground(true)
	var footing: Dictionary = _footing(density)
	density.solids = [footing]
	assert_eq(_air_count(density, _column(footing)), 0, "no cave inside the footing")
	assert_gt(_air_count(density, _elsewhere(density)), 0, "the caves are still carved elsewhere")


func test_a_footing_digs_as_the_ground_around_it_and_soil_as_dirt() -> void:
	var density: WorldDensity = _ground(true)
	var points: Array[Vector3] = []
	for depth: int in range(8, 40, 2):
		for across: float in [-6.0, 0.0, 6.0]:
			points.append(Vector3(AT.x + across, -float(depth), AT.z))
	density.solids = [_footing(density, true)]
	var kinds: Dictionary = {}
	for point: Vector3 in points:
		kinds[density.natural_material(point, point.y)] = true
	assert_true(
		kinds.size() > 1 or not kinds.has(TerrainMaterials.Kind.NATURAL),
		"a footing holds stone, veins or ore like the ground around it: %s" % [kinds.keys()]
	)
	density.solids = [_footing(density, false)]
	for point: Vector3 in points:
		assert_eq(
			density.natural_material(point, point.y),
			TerrainMaterials.Kind.NATURAL,
			"a bed's soil is dirt all the way down at %s" % point
		)


func test_the_terrain_sizes_a_footing_from_bedrock_to_cover_the_corners() -> void:
	var terrain := OpenTerrain.new()
	terrain.rebuild_on_ready = false
	terrain.chunks_x = 2
	terrain.chunks_y = 3
	terrain.chunks_z = 2
	terrain.chunk_size = 32.0
	terrain.voxel_size = 2.0
	terrain.position = Vector3(0.0, 4.0, 0.0)
	add_child_autofree(terrain)
	var bedrock: float = 4.0 - 48.0 + CaveCarver.floor_margin()
	assert_almost_eq(terrain.get_bedrock_y(), bedrock, 0.001, "bedrock is the caves' floor")

	var square: Dictionary = terrain.footing(Vector3(10.0, 0.0, -5.0), 20.0, 20.0, 7.0)
	assert_eq(square["center"], Vector3(10.0, bedrock, -5.0), "stands on bedrock")
	assert_almost_eq(
		float(square["radius"]), 22.0 * sqrt(2.0), 0.001, "a voxel wider, out to the corners"
	)
	assert_almost_eq(
		float(square["half_length"]), float(square["radius"]), 0.001, "a square is round"
	)
	assert_almost_eq(float(square["height"]), 7.0 - bedrock, 0.001, "up to the dirt")
	assert_true(bool(square["ground"]), "digs as the map's own ground")

	var long: Dictionary = terrain.footing(Vector3.ZERO, 30.0, 20.0, 7.0)
	assert_false(bool(long["along_z"]), "runs along x")
	for corner: Vector3 in [
		Vector3(32, 6, 22), Vector3(-32, 6, -22), Vector3(32, bedrock + 0.5, -22)
	]:
		assert_lte(WorldDensity.stadium_sdf(corner, long), 0.0, "covers the corner %s" % corner)
	assert_gt(WorldDensity.stadium_sdf(Vector3(0, 6, 40), long), 0.0, "not far out")
	assert_gt(WorldDensity.stadium_sdf(Vector3(0, 8, 0), long), 0.0, "not above the dirt")
	assert_gt(
		WorldDensity.stadium_sdf(Vector3(0, bedrock - 1.0, 0), long), 0.0, "not below bedrock"
	)
	assert_true(bool(terrain.footing(Vector3.ZERO, 20.0, 30.0, 7.0)["along_z"]), "or along z")
