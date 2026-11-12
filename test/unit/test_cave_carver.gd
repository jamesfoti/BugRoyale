extends GutTest
## The seeded underworld on its own (no chunks, no scene): a seed always carves the same caves
## and every number lands in its range; under a solid open terrain the surface is still the
## surface, the top few metres stay ground for burrows, there is air in the tunnels and the
## caverns further down but the ground is mostly ground, ravines open the surface on some
## seeds and pinch out at their depth, the warp bends every cave read, and bedrock is solid.
## Over the noise, the seed's structure: lean regions stay solid, seams of rock part the
## bands, bedding floors cut the caverns but not the tunnels, the thickness noise swells
## and pinches the tunnels, shafts run vertical through the seams, and halls open only in
## the deep band.

const SEED: int = 7
const BEDROCK_Y: float = -45.5


func _ground() -> WorldDensity:
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
	var sparse: int = 0
	var floored: int = 0
	for value: int in range(1, 40):
		var carver: CaveCarver = CaveCarver.from_seed(value, BEDROCK_Y)
		assert_between(carver.tunnel_frequency, 0.014, 0.024, "tunnel frequency, seed %d" % value)
		assert_between(carver.tunnel_threshold, 0.25, 0.35, "tunnel band, seed %d" % value)
		assert_between(carver.cavern_cutoff, 0.38, 0.6, "cavern cutoff, seed %d" % value)
		assert_between(carver.cavern_squash, 1.2, 2.2, "cavern squash, seed %d" % value)
		assert_between(carver.tunnel_depth, 6.0, 12.0, "tunnel depth, seed %d" % value)
		assert_between(carver.tunnel_ramp, 20.0, 40.0, "tunnel ramp, seed %d" % value)
		assert_between(carver.shallow_cutoff, 0.25, 0.45, "shallow cutoff, seed %d" % value)
		assert_between(carver.ceiling_jag, 0.8, 2.0, "ceiling jag, seed %d" % value)
		assert_between(carver.rubble, 0.3, 0.8, "rubble, seed %d" % value)
		assert_between(carver.cavern_depth, 16.0, 26.0, "cavern depth, seed %d" % value)
		assert_gt(carver.cavern_depth, carver.tunnel_depth, "caverns lie under the tunnels")
		assert_almost_eq(carver.floor_y, BEDROCK_Y, 0.001)
		assert_between(carver.warp_metres, 4.0, 10.0, "warp, seed %d" % value)
		assert_between(carver.warp_frequency, 0.005, 0.01, "warp frequency, seed %d" % value)
		assert_between(carver.region_size, 150.0, 400.0, "region size, seed %d" % value)
		if carver.region_lean > 0.0:
			sparse += 1
			assert_between(carver.region_lean, 0.5, 0.8, "lean rock, seed %d" % value)
		assert_between(carver.region_rich, 1.0, 1.25, "rich rock, seed %d" % value)
		assert_between(carver.region_bias, -0.2, 0.2, "region bias, seed %d" % value)
		assert_between(carver.thickness_size, 40.0, 80.0, "thickness size, seed %d" % value)
		assert_between(carver.thickness_thin, 0.5, 0.7, "thin tunnels, seed %d" % value)
		assert_between(carver.thickness_thick, 1.2, 1.5, "thick tunnels, seed %d" % value)
		assert_between(carver.deep_depth, 120.0, 260.0, "deep band, seed %d" % value)
		assert_between(carver.deep_tunnels, 0.3, 0.7, "deep tunnels, seed %d" % value)
		assert_between(carver.deep_rooms, 1.2, 1.6, "deep rooms, seed %d" % value)
		assert_between(carver.seam_width, 3.0, 8.0, "seam width, seed %d" % value)
		assert_between(carver.seam_strength, 0.5, 1.0, "seam strength, seed %d" % value)
		assert_between(carver.band_wave, 5.0, 20.0, "band wave, seed %d" % value)
		if carver.floor_thickness > 0.0:
			floored += 1
			assert_between(carver.floor_spacing, 24.0, 48.0, "floor spacing, seed %d" % value)
			assert_between(carver.floor_thickness, 2.0, 4.0, "floor thickness, seed %d" % value)
		assert_between(carver.hall_size, 120.0, 200.0, "hall size, seed %d" % value)
		assert_between(carver.hall_cutoff, 0.55, 0.7, "hall cutoff, seed %d" % value)
		assert_between(carver.shaft_frequency, 0.009, 0.015, "shaft frequency, seed %d" % value)
		assert_between(carver.shaft_width, 0.12, 0.2, "shaft width, seed %d" % value)
		assert_between(carver.shaft_lean, 0.08, 0.2, "shaft lean, seed %d" % value)
		assert_between(carver.shaft_share, 0.35, 0.55, "shaft share, seed %d" % value)
		if carver.ravine_width > 0.0:
			cut += 1
			assert_between(carver.ravine_width, 0.05, 0.08, "ravine band, seed %d" % value)
			assert_between(carver.ravine_frequency, 0.01, 0.02, "ravine frequency, seed %d" % value)
			assert_between(carver.ravine_depth, 8.0, 18.0, "ravine depth, seed %d" % value)
			assert_between(carver.ravine_lean, 0.25, 0.6, "ravine lean, seed %d" % value)
	assert_between(cut, 8, 32, "about half the seeds cut ravines")
	assert_between(sparse, 8, 32, "about half the seeds keep sparse tunnels in lean rock")
	assert_between(floored, 12, 36, "six seeds in ten floor their caverns")


func test_the_warp_bends_the_caves_and_reads_them_in_place_at_zero() -> void:
	var bent: CaveCarver = CaveCarver.from_seed(SEED, BEDROCK_Y)
	var straight: CaveCarver = CaveCarver.from_seed(SEED, BEDROCK_Y)
	straight.warp_metres = 0.0
	assert_true("warp %d m" % roundi(bent.warp_metres) in bent.summary(), bent.summary())
	assert_true("warp 0 m" in straight.summary(), straight.summary())
	var moved: int = 0
	var total: int = 0
	for step_x: int in 20:
		for step_z: int in 20:
			var spot := Vector3(float(step_x) * 11.0 - 110.0, -20.0, float(step_z) * 11.0 - 110.0)
			total += 1
			if absf(bent.air(spot, 20.0) - straight.air(spot, 20.0)) > 0.01:
				moved += 1
	assert_gt(moved, total * 3 / 4, "the warp moves the caves nearly everywhere")
	var sinkhole_spot := Vector3(3.0, -1.0, 3.0)
	assert_eq(
		bent.air(sinkhole_spot, 1.0) == -INF,
		straight.air(sinkhole_spot, 1.0) == -INF,
		"the sinkhole map is not warped: the same columns open"
	)


func test_air_above_the_surface_and_ground_just_under_it() -> void:
	var ground: WorldDensity = _ground()
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
	var ground: WorldDensity = _ground()
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
	assert_gt(checked, 160, "most of the ground near the surface is clear of caves")


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
	assert_gt(near, 0, "and ground within 3 m of a tunnel wall round it")
	assert_lt(near, inside, "less of it than the air: the passages are metres wide")
	assert_gt(unreachable, 1600 / 2, "a metre down, no cave reaches most of the ground")


## The widening stops at WIDEN_MAX, so 300 m down the ground is as dense as the maps' bottom.
func test_deep_ground_is_still_mostly_ground() -> void:
	var carver: CaveCarver = CaveCarver.from_seed(SEED, -500.0)
	carver.ravine_width = 0.0
	var air: int = 0
	var total: int = 0
	for step_x: int in 40:
		for step_z: int in 40:
			var spot := Vector3(float(step_x) * 7.0 - 140.0, -300.0, float(step_z) * 7.0 - 140.0)
			total += 1
			if carver.air(spot, 300.0) > 0.0:
				air += 1
	assert_gt(air, total / 20, "there are caves 300 m down")
	assert_lt(
		air, total * 45 / 100, "but the ground is mostly ground, as dense as the maps' bottom"
	)


func test_bedrock_is_solid_everywhere() -> void:
	var ground: WorldDensity = _ground()
	for step: int in 60:
		var x: float = float(step) * 5.0 - 150.0
		var z: float = float(step) * 7.0 - 210.0
		assert_lt(ground.evaluate(Vector3(x, BEDROCK_Y - 0.5, z)), 0.0)


func test_tunnels_and_caverns_exist_but_the_ground_is_mostly_ground() -> void:
	var ground: WorldDensity = _ground()
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
	carver.shaft_width = 0.0
	carver.hall_cutoff = 2.0
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


## A carver with the structure stripped down to what a test looks at: deep bedrock, the
## ravines, shafts and halls off, no band wave, and the regions and seams at full richness.
func _plain_carver() -> CaveCarver:
	var carver: CaveCarver = CaveCarver.from_seed(SEED, -500.0)
	carver.ravine_width = 0.0
	carver.shaft_width = 0.0
	carver.hall_cutoff = 2.0
	carver.band_wave = 0.0
	carver.seam_strength = 0.0
	carver.region_lean = 1.0
	carver.region_rich = 1.0
	return carver


## How many of a 40 by 40 grid of columns, 7 m apart, are air at this depth.
func _air_columns(carver: CaveCarver, depth: float) -> int:
	var air: int = 0
	for step_x: int in 40:
		for step_z: int in 40:
			var spot := Vector3(float(step_x) * 7.0 - 140.0, -depth, float(step_z) * 7.0 - 140.0)
			if carver.air(spot, depth) > 0.0:
				air += 1
	return air


## Biomes, from the resources in biomes/: near the surface the rock is mossy or plain, every
## kind lies somewhere, each kind but plain tints the wall half-way, and a kind that does
## not hold at a depth gives way to the first that does.
func test_biomes_lie_by_depth_and_tint_the_walls() -> void:
	var carver: CaveCarver = _plain_carver()
	carver.biomes = _cave_biomes()
	var kinds: Dictionary = {}
	for step_x: int in 30:
		for step_z: int in 30:
			var spot := Vector3(float(step_x) * 40.0 - 600.0, -100.0, float(step_z) * 40.0 - 600.0)
			var shallow: String = carver.biome(spot, 20.0).get("name", "")
			assert_true(
				shallow == "plain" or shallow == "mossy", "near the surface, plain or mossy"
			)
			kinds[carver.biome(spot, 100.0).get("name", "")] = true
			kinds[shallow] = true
	for name: String in ["plain", "mossy", "dripstone", "fungal", "crystal"]:
		assert_true(kinds.has(name), "%s lies somewhere" % name)
	for kind: Dictionary in carver.biomes:
		var tint: Color = Biome.tint_of(kind)
		if kind["name"] == "plain":
			assert_eq(tint, TerrainMaterials.NATURAL_VERTEX_COLOR, "plain is the ground's own")
		else:
			assert_almost_eq(tint.a, 0.5, 0.001, "a kind's tint blends half-way")
	assert_eq(carver.biome(Vector3.ZERO, 100.0), carver.biome(Vector3.ZERO, 100.0), "steady")
	carver.biomes = [carver.biomes[1]]
	assert_eq(carver.biome(Vector3.ZERO, 100.0), {}, "mossy alone: nothing holds deep down")
	assert_eq(carver.biome(Vector3.ZERO, 10.0)["name"], "mossy", "and mossy near the top")


func _cave_biomes() -> Array[Dictionary]:
	var out: Array[Biome] = []
	for name: String in ["plain", "mossy", "dripstone", "fungal", "crystal"]:
		out.append(load("res://biomes/cave_%s.tres" % name) as Biome)
	return Biome.data_of(out)


## Dripstone rooms stand on pillars: inside a room, some columns are rock with the biome
## fixed to dripstone and none with it fixed to plain. And the ceilings hang lower than the
## floors rise: with the jag and the rubble on, air is lost at the top of a room more than
## at the bottom.
func test_dripstone_rooms_have_pillars_and_ceilings_hang_in_points() -> void:
	var carver: CaveCarver = _plain_carver()
	carver.tunnel_threshold = 0.0
	carver.sinkhole_threshold = 2.0
	carver.floor_thickness = 0.0
	carver.ceiling_jag = 0.0
	carver.rubble = 0.0
	var cave_biomes: Array[Dictionary] = _cave_biomes()
	carver.biome_fixed = cave_biomes[0]
	# A room: a spot 100 m down with 3 m of air round it.
	var room := Vector3.ZERO
	var found: bool = false
	for step_x: int in 60:
		for step_z: int in 60:
			var spot := Vector3(float(step_x) * 5.0 - 150.0, -100.0, float(step_z) * 5.0 - 150.0)
			if carver.air(spot, 100.0) > 3.0:
				room = spot
				found = true
				break
		if found:
			break
	assert_true(found, "a room 100 m down")
	var plain_rock: int = _rock_in_square(carver, room)
	carver.biome_fixed = cave_biomes[2]
	var pillar_rock: int = _rock_in_square(carver, room)
	assert_eq(plain_rock, 0, "a plain room is all air about its middle")
	assert_gt(pillar_rock, 0, "a dripstone room has pillars in it")
	carver.biome_fixed = cave_biomes[0]
	var smooth: CaveCarver = _plain_carver()
	smooth.tunnel_threshold = 0.0
	smooth.sinkhole_threshold = 2.0
	smooth.floor_thickness = 0.0
	smooth.ceiling_jag = 0.0
	smooth.rubble = 0.0
	smooth.biome_fixed = cave_biomes[0]
	carver.ceiling_jag = 2.0
	carver.rubble = 0.8
	# Near a wall, which side is read from the smooth room: air growing upward is a floor.
	# Scree only takes air from a floor; the ceiling's points and folds go both ways.
	var floor_gained: int = 0
	var floor_lost: int = 0
	var ceiling_gained: int = 0
	var ceiling_lost: int = 0
	for step_x: int in 60:
		for step_z: int in 60:
			var at := Vector3(float(step_x) * 4.0 - 120.0, -100.0, float(step_z) * 4.0 - 120.0)
			var was: float = smooth.air(at, 100.0)
			if absf(was) > 2.0 or was == -INF:
				continue
			var up: float = smooth.air(at + Vector3(0.0, 0.5, 0.0), 99.5)
			var change: float = carver.air(at, 100.0) - was
			if up > was:
				floor_gained += 1 if change > 0.01 else 0
				floor_lost += 1 if change < -0.05 else 0
			else:
				ceiling_gained += 1 if change > 0.05 else 0
				ceiling_lost += 1 if change < -0.05 else 0
	assert_lt(floor_gained * 20, floor_lost, "scree all but never adds air to a floor")
	assert_gt(floor_lost, 0, "and lies on some")
	assert_gt(ceiling_gained, 0, "the ceiling folds up in places")
	assert_gt(ceiling_lost, 0, "and hangs down in others")


## Columns of a 3 m square about a spot (half-metre apart) that are rock there.
func _rock_in_square(carver: CaveCarver, room: Vector3) -> int:
	var rock: int = 0
	for step_x: int in 7:
		for step_z: int in 7:
			var spot: Vector3 = (
				room + Vector3(float(step_x) * 0.5 - 1.5, 0.0, float(step_z) * 0.5 - 1.5)
			)
			if carver.air(spot, 100.0) <= 0.0:
				rock += 1
	return rock


## On a steep face the tunnels run up to the surface: a metre and a half under it, no
## tunnel opens on flat ground and some do on a cliff.
func test_tunnels_open_on_steep_faces_only() -> void:
	var carver: CaveCarver = _plain_carver()
	carver.sinkhole_threshold = 2.0
	var flat: int = 0
	var cliff: int = 0
	for step_x: int in 40:
		for step_z: int in 40:
			var spot := Vector3(float(step_x) * 7.0 - 140.0, -1.5, float(step_z) * 7.0 - 140.0)
			if carver.air(spot, 1.5, 0.0) > 0.0:
				flat += 1
			if carver.air(spot, 1.5, 1.2) > 0.0:
				cliff += 1
	assert_eq(flat, 0, "no tunnel opens on flat ground this near the surface")
	assert_gt(cliff, 0, "some open on a cliff face")


## Near the top the tunnels run only in the shallow map's patches, and spread with depth
## until the bottom of the ramp, where they run everywhere; without a ramp they run
## everywhere from the start.
func test_the_tunnels_spread_from_patches_to_everywhere_down_the_ramp() -> void:
	var carver: CaveCarver = _plain_carver()
	carver.cavern_cutoff = 2.0
	carver.sinkhole_threshold = 2.0
	var top: float = carver.tunnel_depth + 6.0
	var bottom: float = carver.tunnel_depth + carver.tunnel_ramp + 6.0
	var top_air: int = _air_columns(carver, top)
	var bottom_air: int = _air_columns(carver, bottom)
	assert_gt(top_air, 0, "some tunnel near the top")
	assert_lt(top_air * 2, bottom_air, "fewer than half as many as at the ramp's bottom")
	carver.tunnel_ramp = 0.0
	var flat_top: int = _air_columns(carver, top)
	assert_gt(flat_top * 2, bottom_air, "no ramp: as many near the top as below")


## Regions: on a seed whose lean rock is solid, no tunnel or cavern opens where the region
## noise runs low, and they are back where it runs high; lean 1 is the old even sponge.
func test_lean_regions_stay_solid_and_rich_ones_are_riddled() -> void:
	var carver: CaveCarver = _plain_carver()
	carver.region_lean = 0.0
	var lean: int = 0
	var lean_air: int = 0
	var rich: int = 0
	var rich_air: int = 0
	for step_x: int in 40:
		for step_z: int in 40:
			var spot := Vector3(float(step_x) * 7.0 - 140.0, -60.0, float(step_z) * 7.0 - 140.0)
			var richness: float = carver.region_richness(spot)
			if richness <= 0.0:
				lean += 1
				if carver.air(spot, 60.0) > 0.0:
					lean_air += 1
			elif richness >= 1.0:
				rich += 1
				if carver.air(spot, 60.0) > 0.0:
					rich_air += 1
	assert_gt(lean, 100, "the grid crosses lean rock")
	assert_gt(rich, 100, "and rich rock")
	assert_eq(lean_air, 0, "lean rock is solid")
	assert_gt(rich_air, rich / 20, "rich rock has caves")
	carver.region_lean = 1.0
	assert_almost_eq(carver.region_richness(Vector3(50.0, -60.0, -30.0)), 1.0, 0.0001)


## Seams: at full strength the ground at the cavern depth is rock right across, with the
## tunnels above it and the caverns below it open; at no strength the seam is gone.
func test_seams_are_rock_between_the_bands() -> void:
	var carver: CaveCarver = _plain_carver()
	carver.seam_strength = 1.0
	var above: float = carver.cavern_depth - carver.seam_width - 6.0
	var below: float = carver.cavern_depth + carver.seam_width + 6.0
	assert_eq(_air_columns(carver, carver.cavern_depth), 0, "rock across the seam")
	assert_gt(_air_columns(carver, above), 0, "tunnels above it")
	assert_gt(_air_columns(carver, below), 0, "caverns below it")
	assert_almost_eq(carver.seam(carver.deep_depth), 0.0, 0.0001, "the deep seam too")
	carver.seam_strength = 0.0
	assert_gt(_air_columns(carver, carver.cavern_depth), 0, "no seam, caves through it")


## Bedding floors: inside a slab no cavern is air, between slabs they are, and the tunnels
## run through the slabs.
func test_bedding_floors_cut_the_caverns_but_not_the_tunnels() -> void:
	var carver: CaveCarver = _plain_carver()
	carver.floor_spacing = 30.0
	carver.floor_thickness = 3.0
	assert_lt(carver.floor_slab(61.0), 0.0, "a metre into a slab")
	assert_almost_eq(carver.floor_slab(75.0), 12.0, 0.0001, "12 m to the next slab")
	carver.tunnel_threshold = 0.0
	assert_eq(_air_columns(carver, 61.0), 0, "no cavern inside a slab")
	assert_gt(_air_columns(carver, 75.0), 0, "caverns between the slabs")
	carver.tunnel_threshold = 0.2
	carver.cavern_cutoff = 2.0
	assert_gt(_air_columns(carver, 61.0), 0, "tunnels run through a slab")
	carver.floor_thickness = 0.0
	assert_eq(carver.floor_slab(61.0), INF, "no floors")


func test_the_thickness_noise_swells_and_pinches_the_tunnels() -> void:
	var carver: CaveCarver = _plain_carver()
	carver.thickness_thin = 0.5
	carver.thickness_thick = 1.5
	var thinnest: float = INF
	var thickest: float = -INF
	for step_x: int in 30:
		for step_z: int in 30:
			var spot := Vector3(float(step_x) * 9.0 - 135.0, -40.0, float(step_z) * 9.0 - 135.0)
			var factor: float = carver.thickness(spot)
			assert_between(factor, 0.5, 1.5)
			thinnest = minf(thinnest, factor)
			thickest = maxf(thickest, factor)
	assert_lt(thinnest, 0.8, "crawls")
	assert_gt(thickest, 1.2, "and chambers")
	carver.thickness_thin = 1.0
	carver.thickness_thick = 1.0
	assert_almost_eq(carver.thickness(Vector3(5.0, -40.0, 5.0)), 1.0, 0.0001, "no thickness")


## Shafts alone: a column open 100 m down is open 10 m above and below too, and they cross
## a solid seam.
func test_shafts_are_vertical_and_cross_the_seams() -> void:
	var carver: CaveCarver = _plain_carver()
	carver.tunnel_threshold = 0.0
	carver.cavern_cutoff = 2.0
	carver.sinkhole_threshold = 2.0
	carver.seam_strength = 1.0
	carver.shaft_width = 0.16
	carver.shaft_share = 0.3
	var open_columns: int = 0
	var continuous: int = 0
	for step_x: int in 60:
		for step_z: int in 60:
			var x: float = float(step_x) * 5.0 - 150.0
			var z: float = float(step_z) * 5.0 - 150.0
			if carver.air(Vector3(x, -100.0, z), 100.0) <= 0.0:
				continue
			open_columns += 1
			if (
				carver.air(Vector3(x, -90.0, z), 90.0) > 0.0
				and carver.air(Vector3(x, -110.0, z), 110.0) > 0.0
			):
				continuous += 1
	assert_gt(open_columns, 0, "some shaft 100 m down")
	assert_gt(continuous, open_columns * 3 / 4, "and it runs on above and below")
	assert_gt(_air_columns(carver, carver.cavern_depth), 0, "shafts cross the cavern seam")
	carver.shaft_width = 0.0
	assert_eq(_air_columns(carver, 100.0), 0, "no shafts")


## Where two features meet their air blends: a wall a metre thick between them is filled, a
## wall thicker than the blend stays, and a feature out of reach (-INF) changes nothing.
func test_features_blend_where_they_meet() -> void:
	assert_almost_eq(CaveCarver._blend(-0.5, -0.5), 0.0, 0.0001, "a 1 m wall between two is filled")
	assert_almost_eq(CaveCarver._blend(-3.0, -3.0), -2.5, 0.0001, "a 6 m wall only rounds")
	assert_almost_eq(CaveCarver._blend(4.0, -4.0), 4.0, 0.0001, "apart, the deeper air")
	assert_almost_eq(CaveCarver._blend(-INF, -1.5), -1.5, 0.0001, "out of reach, the other")
	assert_gt(CaveCarver._blend(2.0, 1.5), 2.0, "inside both, a little more")


## Halls alone: nothing above the deep band, chambers in it, none with the cutoff off.
func test_halls_open_only_in_the_deep_band() -> void:
	var carver: CaveCarver = _plain_carver()
	carver.tunnel_threshold = 0.0
	carver.cavern_cutoff = 2.0
	carver.sinkhole_threshold = 2.0
	carver.deep_depth = 200.0
	carver.hall_cutoff = 0.45
	assert_eq(_air_columns(carver, 150.0), 0, "no hall above the deep band")
	var deep_air: int = 0
	for depth: float in [230.0, 260.0, 290.0]:
		deep_air += _air_columns(carver, depth)
	assert_gt(deep_air, 0, "a hall in the deep band")
	carver.hall_cutoff = 2.0
	assert_eq(_air_columns(carver, 260.0), 0, "no halls")


func test_a_carver_for_settings_puts_bedrock_above_the_grid_floor() -> void:
	var settings := TerrainSettings.new()
	settings.noise_seed = SEED
	settings.chunks_y = 3
	settings.chunk_world_size = 32.0
	settings.world_origin = Vector3(0.0, 4.0, 0.0)
	var carver: CaveCarver = CaveCarver.for_settings(settings)
	assert_almost_eq(carver.floor_y, 4.0 - 48.0 + CaveCarver.floor_margin(), 0.001)


## Cave Roll: Seeded ignores the sliders' values, Fixed sets them over the roll and remakes
## the noises so a new frequency takes, and the same seed with the same values carves the
## same caves.
func test_fixed_cave_values_override_the_roll() -> void:
	var settings := TerrainSettings.new()
	settings.noise_seed = SEED
	settings.chunks_y = 3
	settings.chunk_world_size = 32.0
	settings.open_terrain_cave_values = {"tunnel_frequency": 0.05, "tunnel_depth": 9.0}
	var rolled: CaveCarver = CaveCarver.for_settings(settings)
	assert_ne(rolled.tunnel_frequency, 0.05, "seeded: the roll's own frequency")
	settings.open_terrain_cave_roll = OpenTerrain.CAVE_ROLL_FIXED
	var fixed: CaveCarver = CaveCarver.for_settings(settings)
	assert_almost_eq(fixed.tunnel_frequency, 0.05, 0.0001)
	assert_almost_eq(fixed.tunnel_depth, 9.0, 0.0001)
	assert_almost_eq(fixed.tunnel_noise_frequency(), 0.05, 0.0001, "the noise was remade")
	assert_almost_eq(fixed.cavern_cutoff, rolled.cavern_cutoff, 0.0001, "the rest still rolls")
	var spot := Vector3(31.0, -30.0, -7.0)
	assert_almost_eq(
		fixed.air(spot, 30.0), CaveCarver.for_settings(settings).air(spot, 30.0), 0.0001
	)
	assert_ne(fixed.air(spot, 30.0), rolled.air(spot, 30.0), "and carves differently")
