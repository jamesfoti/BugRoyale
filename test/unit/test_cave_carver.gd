extends GutTest
## The seeded underworld on its own (no chunks, no scene): a seed always carves the same caves
## and every number lands in its range; under a solid open terrain the surface is still the
## surface, the top few metres stay ground for burrows, there is air in the tunnels and the
## caverns further down but the ground is mostly ground, and bedrock is solid.

const SEED: int = 7
const BEDROCK_Y: float = -45.5


func _ground() -> DensitySampler.WorldDensity:
	var density: DensitySampler.WorldDensity = DensitySampler.create_open_terrain_world_density(
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
		true
	)
	density.caves = CaveCarver.from_seed(SEED, BEDROCK_Y)
	return density


func test_the_same_seed_carves_the_same_caves() -> void:
	var first: CaveCarver = CaveCarver.from_seed(SEED, BEDROCK_Y)
	var second: CaveCarver = CaveCarver.from_seed(SEED, BEDROCK_Y)
	assert_eq(first.summary(), second.summary())
	var spot := Vector3(31.0, -12.0, -7.0)
	assert_almost_eq(first.air(spot, 12.0), second.air(spot, 12.0), 0.0001)
	assert_ne(
		CaveCarver.from_seed(SEED + 1, BEDROCK_Y).summary(), first.summary(), "another seed differs"
	)


func test_every_number_lands_in_its_range() -> void:
	for value: int in range(1, 40):
		var carver: CaveCarver = CaveCarver.from_seed(value, BEDROCK_Y)
		assert_between(carver.tunnel_frequency, 0.028, 0.045, "tunnel frequency, seed %d" % value)
		assert_between(carver.tunnel_threshold, 0.14, 0.2, "tunnel band, seed %d" % value)
		assert_between(carver.cavern_cutoff, 0.42, 0.55, "cavern cutoff, seed %d" % value)
		assert_between(carver.tunnel_depth, 4.0, 8.0, "tunnel depth, seed %d" % value)
		assert_between(carver.cavern_depth, 16.0, 26.0, "cavern depth, seed %d" % value)
		assert_gt(carver.cavern_depth, carver.tunnel_depth, "caverns lie under the tunnels")
		assert_almost_eq(carver.floor_y, BEDROCK_Y, 0.001)


func test_air_above_the_surface_and_ground_just_under_it() -> void:
	var ground: DensitySampler.WorldDensity = _ground()
	for step: int in 60:
		var x: float = float(step) * 6.0 - 180.0
		var z: float = float(step) * -5.0 + 150.0
		var height: float = ground.sample_open_terrain_height(x, z)
		assert_gt(ground.evaluate(Vector3(x, height + 3.0, z)), 0.0, "air 3 m up")
		assert_lt(ground.evaluate(Vector3(x, height - 0.25, z)), 0.0, "ground just under")


func test_bedrock_is_solid_everywhere() -> void:
	var ground: DensitySampler.WorldDensity = _ground()
	for step: int in 60:
		var x: float = float(step) * 5.0 - 150.0
		var z: float = float(step) * 7.0 - 210.0
		assert_lt(ground.evaluate(Vector3(x, BEDROCK_Y - 0.5, z)), 0.0)


func test_tunnels_and_caverns_exist_but_the_ground_is_mostly_ground() -> void:
	var ground: DensitySampler.WorldDensity = _ground()
	var shallow_air: int = 0
	var tunnel_air: int = 0
	var cavern_air: int = 0
	var total: int = 0
	for step_x: int in 40:
		for step_z: int in 40:
			var x: float = float(step_x) * 10.0 - 200.0
			var z: float = float(step_z) * 10.0 - 200.0
			var height: float = ground.sample_open_terrain_height(x, z)
			total += 1
			if ground.evaluate(Vector3(x, height - 2.0, z)) > 0.0:
				shallow_air += 1
			if ground.evaluate(Vector3(x, height - 12.0, z)) > 0.0:
				tunnel_air += 1
			if ground.evaluate(Vector3(x, height - 32.0, z)) > 0.0:
				cavern_air += 1
	assert_lt(shallow_air, total / 10, "the top metres are for burrows: few sinkholes")
	assert_gt(tunnel_air, 0, "some tunnel at 12 m")
	assert_gt(cavern_air, 0, "some cavern at 32 m")
	assert_lt(tunnel_air, total / 2, "but not a honeycomb")
	assert_lt(cavern_air, total / 2, "nor a hollow")
	assert_gt(cavern_air, tunnel_air, "the rooms below are bigger than the tunnels above")


func test_a_carver_for_settings_puts_bedrock_above_the_grid_floor() -> void:
	var settings := ChunkedTerrainWorld.SettingsSnapshot.new()
	settings.noise_seed = SEED
	settings.chunks_y = 3
	settings.chunk_world_size = 32.0
	settings.world_origin = Vector3(0.0, 4.0, 0.0)
	var carver: CaveCarver = CaveCarver.for_settings(settings)
	assert_almost_eq(carver.floor_y, 4.0 - 48.0 + CaveCarver.FLOOR_MARGIN, 0.001)
