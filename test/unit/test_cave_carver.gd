extends GutTest
## The seeded underworld on its own (no chunks, no scene): a seed always carves the same caves
## and every number lands in its range; under a solid open terrain the surface is still the
## surface, the top few metres stay ground for burrows, there is air in the tunnels and the
## caverns further down but the ground is mostly ground, ravines open the surface on some
## seeds and pinch out at their depth, and bedrock is solid.

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
	var cut: int = 0
	for value: int in range(1, 40):
		var carver: CaveCarver = CaveCarver.from_seed(value, BEDROCK_Y)
		assert_between(carver.tunnel_frequency, 0.028, 0.045, "tunnel frequency, seed %d" % value)
		assert_between(carver.tunnel_threshold, 0.14, 0.2, "tunnel band, seed %d" % value)
		assert_between(carver.cavern_cutoff, 0.42, 0.55, "cavern cutoff, seed %d" % value)
		assert_between(carver.tunnel_depth, 4.0, 8.0, "tunnel depth, seed %d" % value)
		assert_between(carver.cavern_depth, 16.0, 26.0, "cavern depth, seed %d" % value)
		assert_gt(carver.cavern_depth, carver.tunnel_depth, "caverns lie under the tunnels")
		assert_almost_eq(carver.floor_y, BEDROCK_Y, 0.001)
		if carver.ravine_width > 0.0:
			cut += 1
			assert_between(carver.ravine_width, 0.05, 0.08, "ravine band, seed %d" % value)
			assert_between(carver.ravine_frequency, 0.01, 0.02, "ravine frequency, seed %d" % value)
			assert_between(carver.ravine_depth, 8.0, 18.0, "ravine depth, seed %d" % value)
			assert_between(carver.ravine_lean, 0.25, 0.6, "ravine lean, seed %d" % value)
	assert_between(cut, 8, 32, "about half the seeds cut ravines")


func test_air_above_the_surface_and_ground_just_under_it() -> void:
	var ground: DensitySampler.WorldDensity = _ground()
	var checked: int = 0
	for step: int in 60:
		var x: float = float(step) * 6.0 - 180.0
		var z: float = float(step) * -5.0 + 150.0
		var height: float = ground.sample_open_terrain_height(x, z)
		assert_gt(ground.evaluate(Vector3(x, height + 3.0, z)), 0.0, "air 3 m up")
		var under := Vector3(x, height - 0.25, z)
		if ground.caves.air(under, 0.25) > 0.0:
			continue  # the mouth of a sinkhole or a ravine, open to the sky
		checked += 1
		assert_lt(ground.evaluate(under), 0.0, "ground just under")
	assert_gt(checked, 40, "most of the surface is ground")


## The mesher interpolates between samples to place a vertex, so the ground must be metres
## below the surface wherever no cave is near, not a constant: held at -1 it terraced every
## slope. Within a cave's reach the density is the cave's own distance instead.
func test_ground_away_from_caves_is_metres_below_the_surface() -> void:
	var ground: DensitySampler.WorldDensity = _ground()
	ground.caves.ravine_width = 0.0  # a ravine's distance reaches the whole top; tested on its own
	var checked: int = 0
	for step: int in 80:
		var x: float = float(step) * 4.5 - 180.0
		var z: float = float(step) * -3.5 + 140.0
		var height: float = ground.sample_open_terrain_height(x, z)
		for depth: float in [1.0, 2.5, 4.0, 7.0]:
			var spot := Vector3(x, height - depth, z)
			if ground.caves.air(spot, depth) > -depth:
				continue
			checked += 1
			assert_almost_eq(
				ground.evaluate(spot), -depth, 0.001, "%.1f m down at %v" % [depth, spot]
			)
	assert_gt(checked, 200, "most of the ground near the surface is clear of caves")


func test_a_caves_air_is_a_distance_on_both_sides_of_its_wall() -> void:
	var carver: CaveCarver = CaveCarver.from_seed(SEED, BEDROCK_Y)
	carver.ravine_width = 0.0  # the tunnels alone; the ravines have their own test
	var inside: int = 0
	var near: int = 0
	var unreachable: int = 0
	for step_x: int in 40:
		for step_z: int in 40:
			var spot := Vector3(float(step_x) * 7.0 - 140.0, -14.0, float(step_z) * 7.0 - 140.0)
			var air: float = carver.air(spot, 14.0)
			if air > 0.0:
				inside += 1
			elif air > -3.0:
				near += 1
			if carver.air(Vector3(spot.x, -1.0, spot.z), 1.0) == -INF:
				unreachable += 1
	assert_gt(inside, 0, "some tunnel at 14 m")
	assert_gt(near, inside, "and ground within 3 m of a tunnel wall all round it")
	assert_gt(unreachable, 1600 / 2, "a metre down, no cave reaches most of the ground")


func test_bedrock_is_solid_everywhere() -> void:
	var ground: DensitySampler.WorldDensity = _ground()
	for step: int in 60:
		var x: float = float(step) * 5.0 - 150.0
		var z: float = float(step) * 7.0 - 210.0
		assert_lt(ground.evaluate(Vector3(x, BEDROCK_Y - 0.5, z)), 0.0)


func test_tunnels_and_caverns_exist_but_the_ground_is_mostly_ground() -> void:
	var ground: DensitySampler.WorldDensity = _ground()
	ground.caves.ravine_width = 0.0  # the ravines have their own test
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


## Ravines alone (the other features turned off): they open the surface over a share of the
## ground, are gone below their depth, and are a distance like the rest of the caves' air.
func test_ravines_open_the_surface_and_pinch_out_at_their_depth() -> void:
	var carver: CaveCarver = CaveCarver.from_seed(SEED, BEDROCK_Y)
	carver.tunnel_threshold = 0.0
	carver.cavern_cutoff = 2.0
	carver.sinkhole_threshold = 2.0
	carver.ravine_width = 0.06
	carver.ravine_depth = 12.0
	var open_at_surface: int = 0
	var open_midway: int = 0
	var open_below: int = 0
	var near_a_wall: int = 0
	var total: int = 0
	for step_x: int in 40:
		for step_z: int in 40:
			var x: float = float(step_x) * 7.0 - 140.0
			var z: float = float(step_z) * 7.0 - 140.0
			total += 1
			if carver.air(Vector3(x, -0.1, z), 0.1) > 0.0:
				open_at_surface += 1
			var midway: float = carver.air(Vector3(x, -6.0, z), 6.0)
			if midway > 0.0:
				open_midway += 1
			elif midway > -3.0:
				near_a_wall += 1
			if carver.air(Vector3(x, -13.0, z), 13.0) > 0.0:
				open_below += 1
	assert_between(open_at_surface, total / 20, total / 3, "ravines take a share of the ground")
	assert_gt(open_at_surface, open_midway, "and narrow as they go down")
	assert_gt(open_midway, 0, "still open halfway down")
	assert_gt(near_a_wall, 0, "ground within metres of a wall reads as metres")
	assert_eq(open_below, 0, "nothing below their depth")
	assert_true("ravines 0.06 to 12 m down" in carver.summary(), carver.summary())
	carver.ravine_width = 0.0
	assert_eq(carver.air(Vector3(3.0, -0.1, 3.0), 0.1), -INF, "without ravines nothing reaches")
	assert_true("no ravines" in carver.summary(), carver.summary())


func test_a_carver_for_settings_puts_bedrock_above_the_grid_floor() -> void:
	var settings := ChunkedTerrainWorld.SettingsSnapshot.new()
	settings.noise_seed = SEED
	settings.chunks_y = 3
	settings.chunk_world_size = 32.0
	settings.world_origin = Vector3(0.0, 4.0, 0.0)
	var carver: CaveCarver = CaveCarver.for_settings(settings)
	assert_almost_eq(carver.floor_y, 4.0 - 48.0 + CaveCarver.FLOOR_MARGIN, 0.001)
