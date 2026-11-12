extends GutTest
## The aquifers (CaveCarver.aquifer, water_level, barrier) and the pools' sheet
## (CaveWaterMesher): a column's level is steady and lies in range or the column is dry,
## about the rolled share of the map is wet, a wall of rock stands on the border between two
## cells of different levels and nowhere when the water is off, and a chunk's water sheet
## lies at its columns' levels, in cave air only, well under the surface.

const SEED: int = 7
const BEDROCK_Y: float = -93.5
const HALF := Vector3(256.0, 96.0, 256.0)
const ORIGIN := Vector3(-256.0, -96.0, -256.0)
const WATER_TOP: float = -15.0


func _carver(water_share: float = 0.6) -> CaveCarver:
	var carver: CaveCarver = CaveCarver.from_seed(SEED, BEDROCK_Y)
	carver.water_share = water_share
	carver.water_top = WATER_TOP
	return carver


func test_a_columns_level_is_steady_and_in_range_or_dry() -> void:
	var carver: CaveCarver = _carver()
	var wet: int = 0
	var total: int = 0
	for step_x: int in 40:
		for step_z: int in 40:
			var x: float = float(step_x) * 25.0 - 500.0
			var z: float = float(step_z) * 25.0 - 500.0
			var level: float = carver.water_level(x, z)
			assert_eq(level, carver.water_level(x, z), "the same level every time")
			total += 1
			if level == -INF:
				continue
			wet += 1
			assert_between(level, BEDROCK_Y + CaveCarver.WATER_FLOOR, WATER_TOP, "in range")
	assert_between(float(wet) / float(total), 0.35, 0.85, "about the share of the map is wet")
	carver.water_top = -INF
	assert_eq(carver.water_level(0.0, 0.0), -INF, "no water at all with the top unset")
	assert_eq(_carver(0.0).water_level(0.0, 0.0), -INF, "nor with no share")


func test_a_wall_stands_between_cells_of_different_levels_and_nowhere_with_the_water_off() -> void:
	var carver: CaveCarver = _carver(1.0)
	# Walk a line across the map, low down, and find a border where the level changes.
	var walls: int = 0
	var last_level: float = carver.water_level(-500.0, 37.0)
	var changes: int = 0
	for step: int in 1000:
		var x: float = float(step) - 500.0
		var level: float = carver.water_level(x, 37.0)
		if not is_equal_approx(level, last_level):
			changes += 1
			# Within the wall's reach of the border, some point is rock.
			var rock: bool = false
			for back: int in range(-3, 4):
				if carver.barrier(Vector3(x + float(back), BEDROCK_Y + 8.0, 37.0)) < 0.0:
					rock = true
			if rock:
				walls += 1
		last_level = level
	assert_gt(changes, 1, "the line crosses borders")
	assert_eq(walls, changes, "a wall on every border between levels")
	assert_eq(carver.barrier(Vector3(0.0, 50.0, 37.0)), INF, "none above every level")
	carver.water_top = -INF
	assert_eq(
		carver.barrier(Vector3(-100.0, BEDROCK_Y + 8.0, 37.0)), INF, "none with the water off"
	)


func test_a_chunks_water_sheet_lies_at_its_levels_in_cave_air_only() -> void:
	var density: WorldDensity = DensitySampler.create_open_terrain_world_density(
		SEED, 0.01, 3.0, 3, 2.0, 0.5, Vector3.ZERO, HALF, 0.5, false, null, 0.0, true
	)
	density.caves = _carver(1.0)
	var samples: Vector3i = Vector3i.ONE * 17
	var step: float = 2.0
	var sheets: int = 0
	for chunk_x: int in 16:
		for chunk_z: int in [4, 8, 12]:
			var chunk := Vector3i(chunk_x, 1, chunk_z)
			var field: SignedDensityField = DensitySampler.build_chunk_field(
				density, samples, ORIGIN, chunk * 16, step
			)
			var corner: Vector3 = ORIGIN + Vector3(chunk * 16) * step
			var centre: Vector3 = corner + Vector3.ONE * 16.0
			var sheet: TerrainMeshResult = CaveWaterMesher.build(
				field, density, ORIGIN, chunk * 16, step, 32.0, centre
			)
			if sheet.indices.is_empty():
				continue
			sheets += 1
			for vertex: Vector3 in sheet.vertices:
				var world: Vector3 = centre + vertex
				assert_almost_eq(
					world.y, density.caves.water_level(world.x, world.z), 0.01, "at the level"
				)
				assert_gt(field.sample_world(world, corner, step), -0.001, "in the cave's air")
				assert_gt(
					density.sample_open_terrain_height(world.x, world.z) - world.y,
					CaveWaterMesher.surface_margin() - 0.01,
					"well under the surface"
				)
	assert_gt(sheets, 0, "some chunk holds a pool")
	assert_true(density.caves.summary().contains("water in"), "the rebuild line names the water")
