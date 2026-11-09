extends GutTest
## The seeded terraces on an open terrain's surface, and the metres the sponge underside is
## scaled to: a seed always rolls the same terraces and every number lands in its range, never
## leaves the surface as the noise made it, always puts the heights on the treads where the
## coverage noise allows, and with the chance at 0 or 1 the roll does what it says.

const SEED: int = 7
const STEP_RANGE := Vector2(1.5, 5.0)
const STRENGTH_RANGE := Vector2(0.35, 1.0)


func _surface(solid: bool = false) -> DensitySampler.WorldDensity:
	return DensitySampler.create_open_terrain_world_density(
		SEED,
		0.008,
		12.0,
		3,
		2.0,
		0.5,
		Vector3.ZERO,
		Vector3(256.0, 48.0, 256.0),
		0.5,
		false,
		null,
		0.0,
		solid
	)


func test_the_same_seed_rolls_the_same_terraces() -> void:
	var first: DensitySampler.WorldDensity = _surface()
	var second: DensitySampler.WorldDensity = _surface()
	first.roll_terraces(SEED, 1.0, STEP_RANGE, STRENGTH_RANGE, 0.5)
	second.roll_terraces(SEED, 1.0, STEP_RANGE, STRENGTH_RANGE, 0.5)
	assert_eq(first.terrace_summary(), second.terrace_summary())
	assert_almost_eq(first.terrace_phase, second.terrace_phase, 0.0001)
	assert_almost_eq(
		first.sample_open_terrain_height(31.0, -7.0),
		second.sample_open_terrain_height(31.0, -7.0),
		0.0001
	)
	second.roll_terraces(SEED + 1, 1.0, STEP_RANGE, STRENGTH_RANGE, 0.5)
	assert_ne(first.terrace_summary(), second.terrace_summary(), "another seed differs")


func test_every_number_lands_in_its_range_and_the_chance_is_a_chance() -> void:
	var rolled: int = 0
	for value: int in range(1, 60):
		var surface: DensitySampler.WorldDensity = _surface()
		surface.roll_terraces(value, 0.4, STEP_RANGE, STRENGTH_RANGE, 0.5)
		assert_between(surface.terrace_step, STEP_RANGE.x, STEP_RANGE.y, "tread, seed %d" % value)
		assert_between(
			surface.terrace_strength,
			STRENGTH_RANGE.x,
			STRENGTH_RANGE.y,
			"strength, seed %d" % value
		)
		assert_between(surface.terrace_phase, 0.0, surface.terrace_step, "phase, seed %d" % value)
		if surface.terrace_enabled:
			rolled += 1
	assert_between(rolled, 10, 40, "about two seeds in five have terraces")
	var never: DensitySampler.WorldDensity = _surface()
	never.roll_terraces(SEED, 0.0, STEP_RANGE, STRENGTH_RANGE, 0.5)
	assert_false(never.terrace_enabled, "chance 0")
	var always: DensitySampler.WorldDensity = _surface()
	always.roll_terraces(SEED, 1.0, STEP_RANGE, STRENGTH_RANGE, 0.5)
	assert_true(always.terrace_enabled, "chance 1")
	var forced: DensitySampler.WorldDensity = _surface()
	forced.roll_terraces(SEED, 0.0, STEP_RANGE, STRENGTH_RANGE, 0.5, true)
	assert_true(forced.terrace_enabled, "forced on")
	assert_almost_eq(forced.terrace_step, never.terrace_step, 0.0001, "the same roll either way")


func test_without_terraces_the_surface_is_the_noise() -> void:
	var plain: DensitySampler.WorldDensity = _surface()
	var rolled_off: DensitySampler.WorldDensity = _surface()
	rolled_off.roll_terraces(SEED, 0.0, STEP_RANGE, STRENGTH_RANGE, 0.5)
	var varied: int = 0
	for step: int in 50:
		var x: float = float(step) * 9.0 - 220.0
		var z: float = float(step) * -6.0 + 150.0
		var height: float = plain.sample_open_terrain_height(x, z)
		assert_almost_eq(rolled_off.sample_open_terrain_height(x, z), height, 0.0001)
		if absf(height) > 1.0:
			varied += 1
	assert_gt(varied, 10, "the noise surface has hills to terrace")


func test_forced_terraces_put_the_heights_on_the_treads() -> void:
	var surface: DensitySampler.WorldDensity = _surface()
	surface.roll_terraces(SEED, 1.0, STEP_RANGE, STRENGTH_RANGE, 1.0, true)
	surface.terrace_strength = 1.0
	var on_tread: int = 0
	var total: int = 0
	for step_x: int in 30:
		for step_z: int in 30:
			var x: float = float(step_x) * 15.0 - 220.0
			var z: float = float(step_z) * 15.0 - 220.0
			var height: float = surface.sample_open_terrain_height(x, z)
			var along: float = fposmod(height - surface.terrace_phase, surface.terrace_step)
			var off: float = minf(along, surface.terrace_step - along)
			total += 1
			if off < surface.terrace_step * 0.05:
				on_tread += 1
	assert_gt(on_tread, total * 3 / 4, "with full coverage most heights sit on a tread")


func test_coverage_zero_leaves_the_noise_alone_even_when_forced() -> void:
	var plain: DensitySampler.WorldDensity = _surface()
	var covered_nowhere: DensitySampler.WorldDensity = _surface()
	covered_nowhere.roll_terraces(SEED, 1.0, STEP_RANGE, STRENGTH_RANGE, 0.0, true)
	for step: int in 40:
		var x: float = float(step) * 11.0 - 220.0
		var z: float = float(step) * 7.0 - 140.0
		assert_almost_eq(
			covered_nowhere.sample_open_terrain_height(x, z),
			plain.sample_open_terrain_height(x, z),
			0.0001
		)


func test_the_sponge_underside_is_scaled_to_metres() -> void:
	var sponge: DensitySampler.WorldDensity = _surface(false)
	var deepest: float = 0.0
	for step: int in 60:
		var x: float = float(step) * 7.0 - 210.0
		var z: float = float(step) * -5.0 + 150.0
		var height: float = sponge.sample_open_terrain_height(x, z)
		deepest = minf(deepest, sponge.evaluate(Vector3(x, height - 6.0, z)))
		assert_gt(sponge.evaluate(Vector3(x, height + 5.0, z)), 4.0, "metres of air above")
	assert_lt(deepest, -1.5, "the noise reaches past the unit it used to be capped at")
	assert_gt(deepest, -DensitySampler.SPONGE_NOISE_METRES - 0.001, "and no further than its scale")
