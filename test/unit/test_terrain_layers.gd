extends GutTest
## The layers a seed adds over the height noise (DensitySampler.WorldDensity and OpenTerrain):
## the noise roll draws every number in its range and the same seed the same numbers; regions
## make the lowlands lower than the highlands and leave plain ground alone when off; the
## height curve's floor fills the valleys flat and its cliff band steepens the climb, both
## keeping the height rising with the noise; the relief shows only on steep faces within its
## band and never above the sky chunks' reach; and flat spots are level at their centre, land
## inside the bounds and apart from each other.

const SEED: int = 7
const AMPLITUDE: float = 20.0
const HALF := Vector3(256.0, 48.0, 256.0)


func _surface(solid: bool = false) -> DensitySampler.WorldDensity:
	return DensitySampler.create_open_terrain_world_density(
		SEED, 0.008, AMPLITUDE, 3, 2.0, 0.5, Vector3.ZERO, HALF, 0.5, false, null, 0.0, solid
	)


## Heights over a 40 by 40 grid of the ground, 12 m apart.
func _heights(surface: DensitySampler.WorldDensity) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for step_x: int in 40:
		for step_z: int in 40:
			out.append(
				surface.sample_open_terrain_height(
					float(step_x) * 12.0 - 240.0, float(step_z) * 12.0 - 240.0
				)
			)
	return out


func _mean(values: PackedFloat32Array) -> float:
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / float(values.size())


func _settings(roll: bool) -> ChunkedTerrainWorld.SettingsSnapshot:
	var settings := ChunkedTerrainWorld.SettingsSnapshot.new()
	settings.noise_seed = SEED
	settings.noise_frequency = 0.008
	settings.noise_amplitude = 12.0
	settings.noise_octaves = 3
	settings.noise_lacunarity = 2.0
	settings.noise_gain = 0.5
	settings.open_terrain_noise_roll = OpenTerrain.NoiseRoll.SEEDED if roll else 0
	return settings


func test_the_noise_roll_draws_in_range_and_the_same_seed_the_same() -> void:
	var fixed: Dictionary = OpenTerrain.rolled_noise(_settings(false))
	assert_almost_eq(float(fixed["amplitude"]), 12.0, 0.0001, "fixed is the sliders")
	assert_almost_eq(float(fixed["frequency"]), 0.008, 0.0001)
	var first: Dictionary = OpenTerrain.rolled_noise(_settings(true))
	var second: Dictionary = OpenTerrain.rolled_noise(_settings(true))
	assert_eq(OpenTerrain.noise_summary(first), OpenTerrain.noise_summary(second))
	var summaries: Dictionary = {}
	for value: int in range(1, 40):
		var settings: ChunkedTerrainWorld.SettingsSnapshot = _settings(true)
		settings.noise_seed = value
		var noise: Dictionary = OpenTerrain.rolled_noise(settings)
		assert_between(float(noise["frequency"]), 0.004, 0.01, "frequency, seed %d" % value)
		assert_between(float(noise["amplitude"]), 8.0, 40.0, "amplitude, seed %d" % value)
		assert_between(int(noise["octaves"]), 2, 5, "octaves, seed %d" % value)
		assert_between(float(noise["lacunarity"]), 1.8, 2.6, "lacunarity, seed %d" % value)
		assert_between(float(noise["gain"]), 0.3, 0.65, "gain, seed %d" % value)
		summaries[OpenTerrain.noise_summary(noise)] = true
	assert_gt(summaries.size(), 30, "seeds differ in their noise")


func test_regions_lower_the_lowlands_and_leave_plain_ground_alone_when_off() -> void:
	var plain: PackedFloat32Array = _heights(_surface())
	var off: DensitySampler.WorldDensity = _surface()
	off.roll_regions(SEED, 0.0, Vector2(500.0, 900.0), Vector2(0.2, 0.2), Vector2.ONE, Vector2.ONE)
	assert_eq(off.region_summary(), "no regions")
	var heights: PackedFloat32Array = _heights(off)
	for index: int in plain.size():
		assert_almost_eq(heights[index], plain[index], 0.0001)
	var on: DensitySampler.WorldDensity = _surface()
	on.roll_regions(
		SEED, 1.0, Vector2(500.0, 900.0), Vector2(0.1, 0.1), Vector2(0.5, 0.5), Vector2.ZERO
	)
	assert_true("highland over" in on.region_summary(), on.region_summary())
	var lowland_spread: float = 0.0
	var highland_spread: float = 0.0
	var lowland: int = 0
	var highland: int = 0
	for step_x: int in 40:
		for step_z: int in 40:
			var world_x: float = float(step_x) * 12.0 - 240.0
			var world_z: float = float(step_z) * 12.0 - 240.0
			var mask: float = on._region_noise.get_noise_2d(world_x, world_z)
			var deviation: float = absf(on.sample_open_terrain_height(world_x, world_z))
			if mask < -0.45:
				lowland_spread += deviation
				lowland += 1
			elif mask > 0.45:
				highland_spread += deviation
				highland += 1
	assert_gt(lowland, 20, "the grid reaches a lowland")
	assert_gt(highland, 20, "and a highland")
	assert_lt(
		lowland_spread / float(lowland),
		highland_spread / float(highland) * 0.5,
		"the lowlands have well under half the highlands' relief"
	)


func test_the_floor_fills_the_valleys_and_the_cliff_band_steepens_the_climb() -> void:
	var curve: DensitySampler.WorldDensity = _surface()
	curve.curve_floor = 0.4
	var lowest: float = INF
	var previous: float = -INF
	for step: int in 101:
		var unit: float = float(step) / 100.0
		var shaped: float = curve.curve_height(unit)
		lowest = minf(lowest, shaped)
		assert_true(shaped >= previous - 0.0001, "the floor keeps the height rising")
		previous = shaped
	assert_almost_eq(lowest, 0.4, 0.001, "nothing lies below the floor")
	assert_almost_eq(curve.curve_height(0.9), 0.9, 0.001, "and the hills are untouched")
	curve.curve_floor = 0.0
	curve.curve_cliff = 1.0
	curve.curve_cliff_at = 0.5
	curve.curve_cliff_width = 0.1
	assert_almost_eq(curve.curve_height(0.3), 0.0, 0.001, "the plains are flat")
	assert_almost_eq(curve.curve_height(0.8), 1.0, 0.001, "the plateau is flat")
	assert_gt(curve.curve_height(0.6) - curve.curve_height(0.4), 0.99, "the climb is sheer")
	curve.curve_cliff = 0.5
	previous = -INF
	for step: int in 101:
		var shaped: float = curve.curve_height(float(step) / 100.0)
		assert_true(shaped >= previous - 0.0001, "the band keeps the height rising")
		previous = shaped
	assert_true("cliffs 0.5 at 0.50" in curve.curve_summary(), curve.curve_summary())
	var plain: PackedFloat32Array = _heights(_surface())
	var floored: DensitySampler.WorldDensity = _surface()
	floored.curve_floor = 0.4
	var heights: PackedFloat32Array = _heights(floored)
	assert_gt(_mean(heights), _mean(plain) + 1.0, "filled valleys raise the ground")
	for height: float in heights:
		assert_true(height >= -AMPLITUDE * 0.2 - 0.001, "no ground below the floor's level")


func test_the_curve_rolls_from_the_seed_at_its_chances() -> void:
	var floors: int = 0
	var cliffs: int = 0
	for value: int in range(1, 60):
		var surface: DensitySampler.WorldDensity = _surface()
		surface.roll_curve(
			value,
			0.6,
			Vector2(0.2, 0.45),
			0.5,
			Vector2(0.4, 0.8),
			Vector2(0.4, 0.6),
			Vector2(0.08, 0.2)
		)
		if surface.curve_floor > 0.0:
			floors += 1
			assert_between(surface.curve_floor, 0.2, 0.45, "floor, seed %d" % value)
		if surface.curve_cliff > 0.0:
			cliffs += 1
			assert_between(surface.curve_cliff, 0.4, 0.8, "cliff, seed %d" % value)
			assert_between(surface.curve_cliff_at, 0.4, 0.6, "cliff level, seed %d" % value)
			assert_between(surface.curve_cliff_width, 0.08, 0.2, "cliff width, seed %d" % value)
	assert_between(floors, 22, 48, "about six in ten seeds have a floor")
	assert_between(cliffs, 15, 45, "about half have a cliff band")


func test_relief_shows_on_steep_faces_within_its_band_only() -> void:
	var ground: DensitySampler.WorldDensity = _surface(true)
	ground.set_relief(3.0, SEED)
	assert_eq(ground.relief_summary(), "relief 3.0 m")
	assert_almost_eq(ground.relief_reach(), 6.0, 0.0001, "the band is twice the amplitude")
	var flat_moved: int = 0
	var steep_moved: int = 0
	var far_moved: int = 0
	var steep_columns: int = 0
	for step_x: int in 60:
		for step_z: int in 60:
			var world_x: float = float(step_x) * 8.0 - 240.0
			var world_z: float = float(step_z) * 8.0 - 240.0
			var height: float = ground.sample_open_terrain_height(world_x, world_z)
			var slope: float = ground.surface_slope(world_x, world_z, height)
			var near := Vector3(world_x, height - 1.0, world_z)
			var plain: float = near.y - height
			var with_relief: float = ground.evaluate_open_terrain_with_surface(near, height, false)
			if slope < 0.3 and absf(with_relief - plain) > 0.001:
				flat_moved += 1
			if slope > 1.0:
				steep_columns += 1
				if absf(with_relief - plain) > 0.001:
					steep_moved += 1
			var far := Vector3(world_x, height - 7.0, world_z)
			if (
				absf(
					ground.evaluate_open_terrain_with_surface(far, height, false) - (far.y - height)
				)
				> 0.001
			):
				far_moved += 1
	assert_eq(flat_moved, 0, "gentle ground is left alone")
	assert_eq(far_moved, 0, "and so is everything outside the band")
	assert_gt(steep_columns, 30, "the ground has steep faces to test")
	assert_gt(steep_moved, steep_columns / 2, "most steep faces carry relief")
	ground.set_relief(0.0, SEED)
	assert_eq(ground.relief_summary(), "no relief")
	assert_almost_eq(ground.relief_reach(), 0.0, 0.0001)


func test_flat_spots_are_level_inside_the_bounds_and_apart() -> void:
	var plain: DensitySampler.WorldDensity = _surface()
	var landed: DensitySampler.WorldDensity = _surface()
	landed.roll_flat_spots(SEED, Vector2i(3, 3), Vector2(10.0, 10.0))
	assert_eq(landed.flat_spot_summary(), "3 flat spots")
	var points: Array[Vector3] = landed.flat_spot_points()
	assert_eq(points.size(), 3)
	for index: int in points.size():
		var spot: Vector4 = landed.flat_spots[index]
		assert_between(spot.x, -HALF.x + 20.0, HALF.x - 20.0, "inside the bounds along x")
		assert_between(spot.y, -HALF.z + 20.0, HALF.z - 20.0, "inside the bounds along z")
		for other_index: int in points.size():
			if other_index != index:
				var other: Vector4 = landed.flat_spots[other_index]
				assert_gt(
					Vector2(spot.x - other.x, spot.y - other.y).length(), 39.9, "spots keep apart"
				)
		var centre: float = landed.sample_open_terrain_height(spot.x, spot.y)
		assert_almost_eq(
			centre,
			plain.sample_open_terrain_height(spot.x, spot.y),
			0.0001,
			"the centre is the ground"
		)
		assert_almost_eq(points[index].y, centre, 0.0001)
		var spread: float = 0.0
		var natural_spread: float = 0.0
		for angle: int in 8:
			var direction := Vector2.RIGHT.rotated(float(angle) * TAU / 8.0) * 8.0
			spread += absf(
				(
					landed.sample_open_terrain_height(spot.x + direction.x, spot.y + direction.y)
					- centre
				)
			)
			natural_spread += absf(
				(
					plain.sample_open_terrain_height(spot.x + direction.x, spot.y + direction.y)
					- centre
				)
			)
		assert_lt(spread, natural_spread * 0.2 + 0.01, "the landing is level, spot %d" % index)
		var far := Vector2(spot.x + 30.0, spot.y)
		assert_almost_eq(
			landed.sample_open_terrain_height(far.x, far.y),
			plain.sample_open_terrain_height(far.x, far.y),
			0.0001,
			"past the fade the ground is its own"
		)
	var none: DensitySampler.WorldDensity = _surface()
	none.roll_flat_spots(SEED, Vector2i.ZERO, Vector2(10.0, 10.0))
	assert_eq(none.flat_spot_summary(), "no flat spots")
