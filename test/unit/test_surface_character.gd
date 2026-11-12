extends GutTest
## The seeded surface character (warp, ridges, redistribution): a seed always rolls the same
## one and every number lands in its range, neutral values are the plain noise exactly, a
## power above 1 lowers the ground and keeps it within the amplitude, a warp moves the hills
## within the amplitude, and a ridged mix lifts the crests.

const SEED: int = 7
const AMPLITUDE: float = 6.0
const POWER_RANGE := Vector2(0.7, 1.6)
const WARP_RANGE := Vector2(10.0, 40.0)
const RIDGE_RANGE := Vector2(0.2, 0.5)


func _surface() -> WorldDensity:
	return DensitySampler.create_open_terrain_world_density(
		SEED,
		0.008,
		AMPLITUDE,
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


## Heights over a 40 by 40 grid of the ground, 9 m apart.
func _heights(surface: WorldDensity) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for step_x: int in 40:
		for step_z: int in 40:
			out.append(
				surface.sample_open_terrain_height(
					float(step_x) * 9.0 - 180.0, float(step_z) * 9.0 - 180.0
				)
			)
	return out


func _mean(values: PackedFloat32Array) -> float:
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / float(values.size())


func _assert_within_amplitude(values: PackedFloat32Array, label: String) -> void:
	for value: float in values:
		assert_between(value, -AMPLITUDE - 0.001, AMPLITUDE + 0.001, label)


func test_the_same_seed_rolls_the_same_character() -> void:
	var first: WorldDensity = _surface()
	var second: WorldDensity = _surface()
	first.roll_surface(SEED, POWER_RANGE, 1.0, WARP_RANGE, 1.0, RIDGE_RANGE)
	second.roll_surface(SEED, POWER_RANGE, 1.0, WARP_RANGE, 1.0, RIDGE_RANGE)
	assert_eq(first.surface_summary(), second.surface_summary())
	assert_almost_eq(
		first.sample_open_terrain_height(31.0, -7.0),
		second.sample_open_terrain_height(31.0, -7.0),
		0.0001
	)
	second.roll_surface(SEED + 1, POWER_RANGE, 1.0, WARP_RANGE, 1.0, RIDGE_RANGE)
	assert_ne(first.surface_summary(), second.surface_summary(), "another seed differs")


func test_every_number_lands_in_its_range_and_the_chances_are_chances() -> void:
	var warped: int = 0
	var ridged: int = 0
	for value: int in range(1, 60):
		var surface: WorldDensity = _surface()
		surface.roll_surface(value, POWER_RANGE, 0.5, WARP_RANGE, 0.35, RIDGE_RANGE)
		assert_between(
			surface.surface_power, POWER_RANGE.x, POWER_RANGE.y, "power, seed %d" % value
		)
		if surface.surface_warp > 0.0:
			warped += 1
			assert_between(
				surface.surface_warp, WARP_RANGE.x, WARP_RANGE.y, "warp, seed %d" % value
			)
		if surface.surface_ridge > 0.0:
			ridged += 1
			assert_between(
				surface.surface_ridge, RIDGE_RANGE.x, RIDGE_RANGE.y, "ridge, seed %d" % value
			)
	assert_between(warped, 15, 45, "about half the seeds warp")
	assert_between(ridged, 8, 34, "about a third ridge")
	var never: WorldDensity = _surface()
	never.roll_surface(SEED, Vector2.ONE, 0.0, WARP_RANGE, 0.0, RIDGE_RANGE)
	assert_eq(never.surface_summary(), "plain surface")


func test_neutral_values_are_the_plain_noise_exactly() -> void:
	var plain: PackedFloat32Array = _heights(_surface())
	var neutral: WorldDensity = _surface()
	neutral.roll_surface(SEED, Vector2.ONE, 0.0, WARP_RANGE, 0.0, RIDGE_RANGE)
	var heights: PackedFloat32Array = _heights(neutral)
	for index: int in plain.size():
		assert_almost_eq(heights[index], plain[index], 0.0001)
	var varied: int = 0
	for height: float in plain:
		if absf(height) > 1.0:
			varied += 1
	assert_gt(varied, 200, "the plain ground has hills to shape")


func test_a_power_above_one_lowers_the_ground_within_the_amplitude() -> void:
	var plain: PackedFloat32Array = _heights(_surface())
	var shaped: WorldDensity = _surface()
	shaped.surface_power = 2.0
	var heights: PackedFloat32Array = _heights(shaped)
	assert_lt(_mean(heights), _mean(plain) - 0.5, "the valleys flatten into low plains")
	_assert_within_amplitude(heights, "power keeps the amplitude")
	var changed: int = 0
	for index: int in plain.size():
		if absf(heights[index] - plain[index]) > 0.1:
			changed += 1
	assert_gt(changed, 1000, "and most of the ground moved")
	assert_true("power 2.0" in shaped.surface_summary(), shaped.surface_summary())


func test_a_warp_moves_the_hills_within_the_amplitude() -> void:
	var plain: PackedFloat32Array = _heights(_surface())
	var warped: WorldDensity = _surface()
	warped.surface_warp = 30.0
	warped.init_warp_noise(SEED)
	var heights: PackedFloat32Array = _heights(warped)
	_assert_within_amplitude(heights, "warp keeps the amplitude")
	assert_almost_eq(_mean(heights), _mean(plain), 0.6, "the same ground, pushed about")
	var moved: int = 0
	for index: int in plain.size():
		if absf(heights[index] - plain[index]) > 0.25:
			moved += 1
	assert_gt(moved, 800, "most hills are somewhere else")
	assert_true("warp 30 m" in warped.surface_summary(), warped.surface_summary())


func test_a_ridged_mix_lifts_the_crests() -> void:
	var plain: PackedFloat32Array = _heights(_surface())
	var ridged: WorldDensity = _surface()
	ridged.surface_ridge = 1.0
	var heights: PackedFloat32Array = _heights(ridged)
	_assert_within_amplitude(heights, "ridges keep the amplitude")
	assert_gt(_mean(heights), _mean(plain) + 0.5, "crests along the zero lines lift the ground")
	assert_true("ridges 1.00" in ridged.surface_summary(), ridged.surface_summary())
