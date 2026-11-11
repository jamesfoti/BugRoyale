extends GutTest
## The layers a seed adds over the height noise (DensitySampler.WorldDensity and OpenTerrain):
## the noise roll draws every number in its range and the same seed the same numbers; regions
## make the lowlands lower than the highlands and leave plain ground alone when off; the
## height curve's floor fills the valleys flat and its cliff band steepens the climb, both
## keeping the height rising with the noise; the relief shows only on steep faces within its
## band and never above the sky chunks' reach; and flat spots are level at their centre, land
## inside the bounds and apart from each other; and Surface Layer moves the surface from
## the box's centre to the chosen layer from the top.

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


func test_surface_layer_puts_the_surface_in_that_layer_from_the_top() -> void:
	var world: OpenTerrain = OpenTerrain.new()
	world.rebuild_on_ready = false
	world.chunk_size = 32.0
	world.chunks_y = 16
	add_child_autofree(world)
	var centred: ChunkedTerrainWorld.SettingsSnapshot = world._make_settings_snapshot()
	assert_almost_eq(centred.open_terrain_surface_offset, 0.0, 0.001, "layer 0 is the centre")
	world.surface_layer = 2
	var raised: ChunkedTerrainWorld.SettingsSnapshot = world._make_settings_snapshot()
	# 16 layers of 32 m: the top is 256 m up; the middle of the second layer is 48 m under it.
	assert_almost_eq(raised.open_terrain_surface_offset, 256.0 - 48.0, 0.001)
	world.surface_height_offset = -4.0
	var nudged: ChunkedTerrainWorld.SettingsSnapshot = world._make_settings_snapshot()
	assert_almost_eq(
		nudged.open_terrain_surface_offset, 256.0 - 52.0, 0.001, "the offset still applies"
	)


## The Cave Roll sliders travel in the snapshot by CaveCarver field name, with the roll.
func test_the_cave_roll_sliders_travel_in_the_snapshot() -> void:
	var world: OpenTerrain = OpenTerrain.new()
	world.rebuild_on_ready = false
	add_child_autofree(world)
	world.cave_tunnel_depth = 9.0
	world.cave_roll = OpenTerrain.CaveRoll.FIXED
	var settings: ChunkedTerrainWorld.SettingsSnapshot = world._make_settings_snapshot()
	assert_eq(settings.open_terrain_cave_roll, OpenTerrain.CaveRoll.FIXED)
	assert_eq(settings.open_terrain_cave_values.size(), OpenTerrain.CAVE_FIELDS.size())
	assert_almost_eq(settings.open_terrain_cave_values["tunnel_depth"], 9.0, 0.0001)
	for field: String in OpenTerrain.CAVE_FIELDS:
		assert_not_null(CaveCarver.new().get(field), "%s is a CaveCarver field" % field)


## The Cave Range pairs steer a seeded roll without moving its other numbers, and the shape
## (fade, shallow size) applies whatever the roll.
## The Biomes lists travel in the snapshot as data and their weights are the kinds'
## likelihoods: one kind alone is everywhere, a weight of 0 is never, 1 against 1 is near
## half the patches each; a cave kind holds only between its depths.
func test_the_biome_lists_and_their_weights_say_what_lies_where() -> void:
	var world: OpenTerrain = OpenTerrain.new()
	world.rebuild_on_ready = false
	world.caves_enabled = true
	world.solid_underside = true
	add_child_autofree(world)
	var marsh: Biome = load("res://biomes/land_marsh.tres")
	var crystal: Biome = load("res://biomes/cave_crystal.tres")
	world.land_biomes = [marsh]
	world.cave_biomes = [crystal]
	var settings: ChunkedTerrainWorld.SettingsSnapshot = world._make_settings_snapshot()
	assert_eq(settings.open_terrain_land_biomes.size(), 1, "the land list travels as data")
	assert_eq(settings.open_terrain_cave_biomes[0]["name"], "crystal")
	var forced: DensitySampler.WorldDensity = world._build_world_density(settings)
	for spot: Vector2 in [Vector2.ZERO, Vector2(200.0, -150.0), Vector2(-240.0, 240.0)]:
		assert_eq(forced.land_biome(spot.x, spot.y)["name"], "marsh", "marsh alone, everywhere")
		assert_eq(
			forced.caves.biome(Vector3(spot.x, -60.0, spot.y), 60.0)["name"],
			"crystal",
			"crystal deep down"
		)
		assert_eq(
			forced.caves.biome(Vector3(spot.x, -10.0, spot.y), 10.0),
			{},
			"a deep kind holds nowhere near the surface"
		)
	assert_true(forced.land_summary().contains("marsh 100%"), "the rebuild line says so")
	var meadow: Biome = load("res://biomes/land_meadow.tres")
	var even_marsh: Biome = marsh.duplicate()
	even_marsh.weight = meadow.weight
	var never: Biome = load("res://biomes/land_barrens.tres").duplicate()
	never.weight = 0.0
	world.land_biomes = [meadow, even_marsh, never]
	world.land_patch_size = 100.0
	var halves: DensitySampler.WorldDensity = world._build_world_density(
		world._make_settings_snapshot()
	)
	var counts: Dictionary = {}
	for step_x: int in 50:
		for step_z: int in 50:
			var name: String = (
				halves
				. land_biome(float(step_x) * 40.0 - 1000.0, float(step_z) * 40.0 - 1000.0)["name"]
			)
			counts[name] = int(counts.get(name, 0)) + 1
	assert_false(counts.has("barrens"), "0 is never")
	assert_between(float(counts.get("meadow", 0)) / 2500.0, 0.3, 0.7, "1 against 1 is near half")
	assert_eq(Biome.tint_of(meadow.to_data()), TerrainMaterials.NATURAL_VERTEX_COLOR)
	assert_almost_eq(Biome.tint_of(marsh.to_data()).a, 0.5, 0.001, "the others blend half-way")
	assert_eq(Biome.tint_of({}), TerrainMaterials.NATURAL_VERTEX_COLOR, "no kind, no tint")
	assert_eq(Biome.data_of(null).size(), 0, "no list is no kinds")
	assert_eq(Biome.data_of([null, meadow]).size(), 1, "an empty slot is skipped")


## The game's build on ready runs in the background: frames come while it builds, the
## world says so and reports how far it is, and every chunk stands once it is done.
func test_the_build_on_ready_runs_behind_the_frames_and_reports_its_progress() -> void:
	var world: OpenTerrain = OpenTerrain.new()
	world.chunk_size = 8.0
	world.voxel_size = 4.0
	var reports: Array[Vector2i] = []
	world.build_progress.connect(
		func(done: int, total: int) -> void: reports.append(Vector2i(done, total))
	)
	var stood: Array[bool] = []
	world.built.connect(func() -> void: stood.append(true))
	add_child_autofree(world)
	await get_tree().process_frame
	assert_true(world.is_building(), "building after the frame it entered on")
	var frames: int = 0
	while world.is_building() and frames < 600:
		await get_tree().process_frame
		frames += 1
	assert_false(world.is_building(), "done within ten seconds")
	var grid: Vector3i = world._get_grid_dimensions()
	assert_eq(world.get_chunk_count(), grid.x * grid.y * grid.z, "every chunk of the grid")
	assert_eq(stood.size(), 1, "built once")
	assert_gt(reports.size(), 1, "progress came in more than once")
	var last: Vector2i = reports[reports.size() - 1]
	assert_eq(last.x, last.y, "the last word is complete")
	assert_eq(last.y, grid.x * grid.y * grid.z, "every chunk counted")
	var previous: int = -1
	for report: Vector2i in reports:
		assert_true(report.x >= previous, "the count never falls")
		previous = report.x
	# A blocking rebuild reports once, complete.
	reports.clear()
	world.rebuild_all()
	assert_eq(reports.size(), 1)
	assert_eq(reports[0].x, reports[0].y)
	# The chunks the rebuild replaced are freed at the end of the frame.
	await get_tree().process_frame


## The build comes in nearest its focus first: the column a spawn asked for stands while
## the rest of the map is still building, the progress counts that ground until it does,
## and an edit made meanwhile at a chunk not yet placed shows once the chunk is.
func test_the_build_puts_the_focused_ground_first_and_keeps_an_early_edit() -> void:
	var world: OpenTerrain = OpenTerrain.new()
	world.chunk_size = 8.0
	world.voxel_size = 4.0
	var reports: Array[Vector2i] = []
	world.build_progress.connect(
		func(done: int, total: int) -> void: reports.append(Vector2i(done, total))
	)
	add_child_autofree(world)
	var extents: Vector3 = world.get_world_extents()
	var near: Vector3 = world.global_position - extents * 0.5 + Vector3(1.0, 0.0, 1.0)
	var far: Vector3 = world.global_position + extents * 0.5 - Vector3(1.0, 0.0, 1.0)
	await get_tree().process_frame
	assert_true(world.is_building())
	assert_false(world.play_ground_ready(), "nothing says where play is yet")
	assert_true(
		world.is_ground_ready_around(far + Vector3(100.0, 0.0, 100.0)),
		"off the grid: nothing to wait for"
	)
	world.focus_build_at(near, 0.0)
	# A hole dug at the far corner before its chunk is placed: wide, since the voxels are
	# four metres, and no deeper than the box.
	var top: float = world.global_position.y + extents.y * 0.5
	var dig := Vector3(far.x, minf(world.get_surface_height_at(far), top - 2.0), far.z)
	world.apply_brush(dig, 6.0, false)
	assert_gt(world.get_edited_voxel_count(), 0, "the hole took some voxels")
	var stood_early: bool = false
	var frames: int = 0
	while world.is_building() and frames < 600:
		if not stood_early and world.is_ground_ready_around(near, 0.0, true):
			stood_early = world._world_build_placed < world._world_build_total
			assert_true(world.play_ground_ready(), "the focus's ground is what play waits for")
		await get_tree().process_frame
		frames += 1
	assert_true(stood_early, "the focused column stood before the map was done")
	assert_false(world.is_building())
	var grid: Vector3i = world._get_grid_dimensions()
	var counted_the_focus: bool = false
	for report: Vector2i in reports:
		if report.y == grid.y:
			counted_the_focus = true
	assert_true(counted_the_focus, "progress counted the focus column's chunks while it waited")
	assert_eq(reports[reports.size() - 1].y, grid.x * grid.y * grid.z, "then the whole map")
	frames = 0
	while (
		(
			not world._async_jobs.is_empty()
			or not world._pending_rebuild_chunk_coordinates.is_empty()
		)
		and frames < 600
	):
		await get_tree().process_frame
		frames += 1
	# The far chunk carries the hole: not the surface the same chunk of the same map has undug.
	var plain: OpenTerrain = OpenTerrain.new()
	plain.rebuild_on_ready = false
	plain.chunk_size = 8.0
	plain.voxel_size = 4.0
	add_child_autofree(plain)
	plain.rebuild_all()
	var dug_faces: PackedVector3Array = _faces_at(world, dig)
	var plain_faces: PackedVector3Array = _faces_at(plain, dig)
	assert_gt(plain_faces.size(), 0, "the surface crosses the far chunk")
	assert_true(dug_faces != plain_faces, "the hole shows in the chunk placed after the edit")
	await get_tree().process_frame


## The triangles of the chunk holding a point, as the mesh has them.
func _faces_at(world: OpenTerrain, point: Vector3) -> PackedVector3Array:
	var settings: ChunkedTerrainWorld.SettingsSnapshot = world._make_settings_snapshot()
	for chunk_coordinate: Vector3i in world._chunks:
		if world._get_chunk_world_aabb(chunk_coordinate, settings).has_point(point):
			var chunk: TerrainChunk = world._chunks[chunk_coordinate]
			return chunk.mesh.get_faces() if chunk.mesh != null else PackedVector3Array()
	return PackedVector3Array()


func test_the_cave_ranges_and_shape_travel_and_steer_the_roll() -> void:
	var world: OpenTerrain = OpenTerrain.new()
	world.rebuild_on_ready = false
	add_child_autofree(world)
	world.cave_range_tunnel_ramp = Vector2(55.0, 55.0)
	world.cave_fade = 5.0
	var settings: ChunkedTerrainWorld.SettingsSnapshot = world._make_settings_snapshot()
	var plain: CaveCarver = CaveCarver.from_seed(settings.noise_seed, -100.0)
	var steered: CaveCarver = CaveCarver.for_settings(settings)
	assert_almost_eq(steered.tunnel_ramp, 55.0, 0.0001, "the ramp comes from its range")
	assert_almost_eq(steered.fade, 5.0, 0.0001, "the fade is the node's")
	assert_almost_eq(steered.tunnel_depth, plain.tunnel_depth, 0.0001, "the other numbers stay")
	assert_almost_eq(steered.cavern_cutoff, plain.cavern_cutoff, 0.0001)
	assert_almost_eq(plain.fade, CaveCarver.FADE, 0.0001, "the plain roll keeps the default")


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


## The chunks a box can touch come from its span of the grid, as a test of every chunk's
## box would have them: a box ending on a seam does not take the chunk past it, one well
## off the grid takes nothing, and the padding reaches the chunks whose edge samples the
## box shares.
func test_the_chunks_a_box_touches_come_from_its_span_of_the_grid() -> void:
	var world: OpenTerrain = OpenTerrain.new()
	world.rebuild_on_ready = false
	world.chunk_size = 8.0
	world.voxel_size = 4.0
	add_child_autofree(world)
	world.rebuild_all()
	var settings: ChunkedTerrainWorld.SettingsSnapshot = world._make_settings_snapshot()
	var origin: Vector3 = world.global_position + world._chunk_corner_local(Vector3i.ZERO, settings)
	var boxes: Array[AABB] = [
		AABB(origin + Vector3(1.0, 1.0, 1.0), Vector3(2.0, 2.0, 2.0)),
		AABB(origin + Vector3(6.0, 6.0, 6.0), Vector3(4.0, 4.0, 4.0)),
		AABB(origin, Vector3(8.0, 8.0, 8.0)),
		AABB(origin + Vector3(8.0, 8.0, 8.0), Vector3(8.0, 8.0, 8.0)),
		AABB(origin + Vector3(-10.0, 3.0, 3.0), Vector3(2.0, 2.0, 2.0)),
		AABB(origin + Vector3(-100.0, 0.0, 0.0), Vector3(2.0, 2.0, 2.0)),
		AABB(origin + Vector3(37.0, 21.0, 37.0), Vector3(30.0, 30.0, 30.0)),
	]
	for box: AABB in boxes:
		var expected: Array[Vector3i] = []
		var search: AABB = box.grow(world.get_voxel_size() * 2.0)
		for chunk_coordinate: Vector3i in world._chunks:
			if world._get_chunk_world_aabb(chunk_coordinate, settings).intersects(search):
				expected.append(chunk_coordinate)
		var found: Array[Vector3i] = world._get_chunk_coordinates_intersecting_aabb(box)
		expected.sort()
		found.sort()
		assert_eq(found, expected, "the box at %s" % str(box.position - origin))
	assert_gt(
		world._get_chunk_coordinates_intersecting_aabb(boxes[1]).size(), 1, "the seam box spans"
	)
	await get_tree().process_frame


## The map's build lays the whole map coarse first, so every chunk stands within a few
## frames, then replaces each with its fine chunk; the coarse one is freed, and the box
## of ground the fine chunk refined is reported (whatever stood on the coarse ground
## there follows it).
func test_the_build_lays_coarse_ground_over_the_whole_map_before_the_fine_pass() -> void:
	var world: OpenTerrain = OpenTerrain.new()
	world.chunk_size = 8.0
	world.voxel_size = 2.0
	var refined: Array[AABB] = []
	world.ground_refined.connect(func(box: AABB) -> void: refined.append(box))
	add_child_autofree(world)
	await get_tree().process_frame
	var grid: Vector3i = world._get_grid_dimensions()
	var total: int = grid.x * grid.y * grid.z
	assert_eq(world._coarse_total, total, "two-metre voxels: the coarse pass runs")
	var coarse_everywhere: bool = false
	var coarse_chunk: TerrainChunk = null
	var coarse_coordinate: Vector3i = Vector3i.ZERO
	var frames: int = 0
	while world.is_building() and frames < 900:
		if (
			not coarse_everywhere
			and world._chunks.size() == total
			and world._world_build_placed < total
		):
			coarse_everywhere = true
			for chunk_coordinate: Vector3i in world._chunks:
				if not world._placed_fine.has(chunk_coordinate):
					coarse_coordinate = chunk_coordinate
					coarse_chunk = world._chunks[chunk_coordinate]
					break
		await get_tree().process_frame
		frames += 1
	assert_true(coarse_everywhere, "every chunk stood, coarse, before the fine pass was done")
	assert_false(world.is_building())
	assert_eq(world._placed_fine.size(), total, "every chunk fine at the end")
	assert_eq(world.get_chunk_count(), total)
	assert_true(coarse_chunk != world._chunks[coarse_coordinate], "the coarse chunk replaced")
	assert_false(is_instance_valid(coarse_chunk), "and freed")
	assert_eq(refined.size(), total, "every fine chunk reported the ground it refined")
	assert_eq(refined[0].size, Vector3.ONE * 8.0, "as its own box")


## The fine pass lays the surface of the whole map before the caves under it: the chunks
## a margin under their column's lowest surface are deep; the local player's ring of
## columns comes first, their deep chunks next, the rest of the surface, the rest of the
## deep; play begins once the ring's surface band is fine, with the deep chunks and the
## far surface still to come; and the progress counts that band.
func test_the_fine_pass_lays_the_surface_of_the_whole_map_before_the_caves() -> void:
	var world: OpenTerrain = OpenTerrain.new()
	world.chunks_x = 4
	world.chunks_y = 7
	world.chunks_z = 4
	world.chunk_size = 8.0
	world.voxel_size = 4.0
	# Two chunks each way round the spawn.
	world.play_ring = 16.0
	var reports: Array[Vector2i] = []
	world.build_progress.connect(
		func(done: int, total: int) -> void: reports.append(Vector2i(done, total))
	)
	add_child_autofree(world)
	var extents: Vector3 = world.get_world_extents()
	var corner: Vector3 = world.global_position - extents * 0.5 + Vector3(1.0, 0.0, 1.0)
	await get_tree().process_frame
	assert_true(world.is_building())
	# The player spawns on the surface, so the chunk it stands in is one of the band's.
	corner.y = world.get_surface_height_at(corner) + 1.0
	# The surface lies about halfway up the 56 m box: the two layers topping out 8 m and
	# 16 m up it are deep, the one topping out 24 m up is not.
	assert_eq(world._deep.size(), 2 * 16, "two layers of deep chunks")
	for chunk_coordinate: Vector3i in world._deep:
		assert_lt(chunk_coordinate.y, 2, "the deep chunks are the bottom two layers")
	# The chunks under way before the focus came are wherever the earlier order put them.
	var early: Dictionary = {}
	for job: ChunkMeshBuilder.AsyncRebuildJob in world._world_build_tasks.values():
		for chunk_coordinate: Vector3i in job.chunk_coordinates:
			early[chunk_coordinate] = true
	for chunk_coordinate: Vector3i in world._placed_fine:
		early[chunk_coordinate] = true
	world.focus_build_at(corner, 0.0, true)
	assert_eq(world._play_columns.size(), 9, "two chunks each way round the corner")
	await get_tree().process_frame
	# Each chunk's group, taken now since the build forgets them when it is done.
	var groups: Dictionary = {}
	for chunk_z: int in 4:
		for chunk_y: int in 7:
			for chunk_x: int in 4:
				var chunk_coordinate := Vector3i(chunk_x, chunk_y, chunk_z)
				groups[chunk_coordinate] = world._build_group(chunk_coordinate)
	# Off the back of the queue, where the next is taken: the ring's surface band, the
	# ring's deep chunks, the rest of the surface, the rest of the deep.
	var queue: Array[Vector3i] = world._world_build_queue
	for index: int in range(1, queue.size()):
		assert_true(
			int(groups[queue[index - 1]]) >= int(groups[queue[index]]),
			"the queue runs from the last group to the first"
		)
	var fine_at_play: Array[Vector3i] = []
	var frames: int = 0
	while world.is_building() and frames < 600:
		if fine_at_play.is_empty() and world.play_ground_ready():
			fine_at_play.assign(world._placed_fine.keys())
		await get_tree().process_frame
		frames += 1
	assert_false(world.is_building())
	assert_false(fine_at_play.is_empty(), "play began before the map was done")
	for chunk_coordinate: Vector3i in fine_at_play:
		if not early.has(chunk_coordinate):
			assert_lte(int(groups[chunk_coordinate]), 1, "only the ring was fine when play began")
	# Chunks are started in queue order with WORLD_BUILD_IN_FLIGHT of them on the pool, so
	# the order they came in runs through the groups with at most that much overlap.
	var first_of: Dictionary = {}
	var last_of: Dictionary = {}
	var order: Array = world._placed_fine.keys()
	for index: int in order.size():
		if early.has(order[index]):
			continue
		var group: int = int(groups[order[index]])
		if not first_of.has(group):
			first_of[group] = index
		last_of[group] = index
	for group: int in range(1, 4):
		assert_true(
			(
				int(last_of[group - 1]) - int(first_of[group])
				< ChunkedTerrainWorld.WORLD_BUILD_IN_FLIGHT
			),
			"group %d came in after group %d, within the pool's overlap" % [group, group - 1]
		)
	var counted_the_band: bool = false
	for report: Vector2i in reports:
		if report.y == 9 * 5:
			counted_the_band = true
	assert_true(counted_the_band, "progress counted the ring's surface band, five a column")
	assert_eq(world._placed_fine.size(), 4 * 7 * 4, "every chunk fine at the end")
	await get_tree().process_frame


## Play waits for the chunks a body stands in, chunk by chunk, not only the surface band:
## a focus below the band (a saved spot underground) makes its cave chunks ground play
## waits for, first in the queue with the band; a body there is held until they and the
## band over them are fine, and until a rebuild queued for one of them (a saved world's
## edits) has landed; and the progress counts them with the band.
func test_play_waits_for_the_chunks_round_a_body_below_the_surface_band() -> void:
	var world: OpenTerrain = OpenTerrain.new()
	world.chunks_x = 4
	world.chunks_y = 7
	world.chunks_z = 4
	world.chunk_size = 8.0
	world.voxel_size = 4.0
	var reports: Array[Vector2i] = []
	world.build_progress.connect(
		func(done: int, total: int) -> void: reports.append(Vector2i(done, total))
	)
	add_child_autofree(world)
	await get_tree().process_frame
	assert_true(world.is_building())
	# A spot in the middle of column (1, 1), 9 m up the 56 m box: in the second layer from
	# the bottom, a deep one, with six metres' reach into the bottom layer under it.
	var cave: Vector3 = world.global_position + Vector3(-4.0, -19.0, -4.0)
	var reach: float = 6.0
	assert_true(world._deep.has(Vector3i(1, 1, 1)), "the spot's chunk is deep")
	world.focus_build_at(cave, reach)
	assert_eq(world._play_columns.size(), 9, "the columns within reach")
	assert_eq(world._play_chunks.size(), 18, "the two deep layers of those columns")
	for chunk_coordinate: Vector3i in world._play_chunks:
		assert_true(world._deep.has(chunk_coordinate), "the chunks round the spot are deep")
		assert_eq(world._build_group(chunk_coordinate), 0, "and come first, with the band")
	for chunk_coordinate: Vector3i in world._deep:
		if not world._play_chunks.has(chunk_coordinate):
			assert_gt(world._build_group(chunk_coordinate), 1, "the other deep chunks wait")
	var ground: Dictionary = world._ground_round(cave, reach)
	assert_eq(ground.size(), 9 * 5 + 18, "the band of nine columns and the chunks round it")
	var ready_at: Array[Vector3i] = []
	var play_at: Array[Vector3i] = []
	var held_for_rebuild: bool = false
	var released_again: bool = false
	var frames: int = 0
	while world.is_building() and frames < 600:
		if ready_at.is_empty() and world.is_ground_ready_around(cave, reach, true):
			ready_at.assign(world._placed_fine.keys())
			# A saved world's edits: a rebuild queued for a chunk the body stands in holds it.
			world._queue_chunk_rebuild(Vector3i(1, 1, 1), AABB())
			held_for_rebuild = not world.is_ground_ready_around(cave, reach, true)
			world._dispatch_pending_rebuilds()
		elif not ready_at.is_empty() and not released_again:
			released_again = world.is_ground_ready_around(cave, reach, true)
		if play_at.is_empty() and world.play_ground_ready():
			play_at.assign(world._placed_fine.keys())
		await get_tree().process_frame
		frames += 1
	assert_false(world.is_building())
	assert_false(ready_at.is_empty(), "the ground round the spot was fine before the map was done")
	assert_lt(ready_at.size(), 4 * 7 * 4, "well before")
	for chunk_coordinate: Vector3i in ground:
		assert_true(ready_at.has(chunk_coordinate), "every chunk round the spot was fine by then")
	assert_true(held_for_rebuild, "a rebuild queued for a chunk round the spot held the body")
	assert_true(released_again, "and let it go once the rebuild landed")
	assert_false(play_at.is_empty(), "play began before the map was done")
	for chunk_coordinate: Vector3i in ground:
		assert_true(play_at.has(chunk_coordinate), "play waited for the same ground")
	var counted: bool = false
	for report: Vector2i in reports:
		if report.y == 9 * 5 + 18:
			counted = true
	assert_true(counted, "progress counted the band and the chunks round the spot")
	await get_tree().process_frame


## A world that streams its underground builds only the band down to STREAM_MARGIN under
## the surface; the chunks below come in round a body there and go when it leaves, and
## one built after an edit was made there while nobody was near carries the edit.
func test_the_underground_streams_round_the_bodies() -> void:
	var world: OpenTerrain = _streaming_world()
	add_child_autofree(world)
	await get_tree().process_frame
	assert_true(world.is_building())
	var frames: int = 0
	while world.is_building() and frames < 900:
		await get_tree().process_frame
		frames += 1
	assert_false(world.is_building(), "the band built")
	var grid: Vector3i = world._get_grid_dimensions()
	var streamed: int = 0
	for chunk_z: int in grid.z:
		for chunk_y: int in grid.y:
			for chunk_x: int in grid.x:
				if world._is_streamed(Vector3i(chunk_x, chunk_y, chunk_z)):
					streamed += 1
	assert_gt(streamed, grid.x * grid.z, "more than a layer is streamed")
	assert_eq(world.get_chunk_count(), grid.x * grid.y * grid.z - streamed, "the band alone")
	var corner: Vector3 = world._grid_corner()
	var deep: Vector3 = corner + Vector3(12.0, 10.0, 12.0)
	var far: Vector3 = corner + Vector3(grid.x * 8.0 - 4.0, 6.0, grid.z * 8.0 - 4.0)
	assert_true(world._is_streamed(world._chunks_touching(deep, 0.0)[0]), "the spot is streamed")
	assert_false(world.is_ground_ready_around(deep, 2.0, true), "nothing there yet")
	# A hole dug far off while nobody is near: no chunk there to rebuild.
	world.apply_brush(far, 3.0, false)
	assert_true(world._pending_rebuild_chunk_coordinates.is_empty(), "no rebuild queued")
	var body := Node3D.new()
	body.add_to_group("fighter")
	add_child_autofree(body)
	body.global_position = deep
	assert_true(
		await _wait_for(func() -> bool: return world.is_ground_ready_around(deep, 2.0, true))
	)
	assert_false(world.streamed_ground_missing_under(body), "the ground under it stands")
	var round_body: Array[Vector3i] = []
	for chunk_coordinate: Vector3i in world._chunks_touching(deep, 2.0):
		if world._is_streamed(chunk_coordinate):
			round_body.append(chunk_coordinate)
	assert_false(round_body.is_empty())
	body.global_position = far
	assert_true(
		await _wait_for(func() -> bool: return world.is_ground_ready_around(far, 2.0, true))
	)
	var freed: Callable = func() -> bool:
		for chunk_coordinate: Vector3i in round_body:
			if world._chunks.has(chunk_coordinate):
				return false
		return true
	assert_true(await _wait_for(freed), "freed once the body left")
	var plain: OpenTerrain = _streaming_world()
	plain.rebuild_on_ready = false
	add_child_autofree(plain)
	plain.rebuild_all()
	var plain_body := Node3D.new()
	plain_body.add_to_group("fighter")
	add_child_autofree(plain_body)
	plain_body.global_position = far
	assert_true(
		await _wait_for(func() -> bool: return plain.is_ground_ready_around(far, 2.0, true))
	)
	assert_true(_faces_at(world, far) != _faces_at(plain, far), "the hole is in the chunk")
	await get_tree().process_frame


## Round the local player the streamed chunks stand at least coarse out to STREAM_ROUGH, so a
## long cavern shows its far end; within STREAM_VIEW they are fine, and a fine chunk replaces
## the coarse one there.
func test_the_underground_stands_coarse_farther_round_the_player() -> void:
	var world: OpenTerrain = _streaming_world()
	world.chunks_x = 16
	world.chunks_z = 16
	add_child_autofree(world)
	await get_tree().process_frame
	var frames: int = 0
	while world.is_building() and frames < 1800:
		await get_tree().process_frame
		frames += 1
	assert_false(world.is_building())
	var corner: Vector3 = world._grid_corner()
	var deep: Vector3 = corner + Vector3(12.0, 10.0, 12.0)
	var body := Node3D.new()
	body.add_to_group("fighter")
	body.add_to_group("player")
	add_child_autofree(body)
	body.global_position = deep
	var settled: Callable = func() -> bool:
		return (
			world._stream_queue.is_empty()
			and world._rough_queue.is_empty()
			and world._stream_inflight.is_empty()
			and not world._stream_rough.is_empty()
		)
	assert_true(await _wait_for(settled), "the coarse chunks came in")
	var near: int = 0
	var far: int = 0
	for chunk_coordinate: Vector3i in world._stream_rough:
		var low: Vector3 = corner + Vector3(chunk_coordinate) * world.chunk_size
		var nearest: Vector3 = deep.clamp(low, low + Vector3.ONE * world.chunk_size)
		var distance: float = deep.distance_to(nearest)
		assert_lte(distance, ChunkedTerrainWorld.STREAM_ROUGH + ChunkedTerrainWorld.STREAM_KEEP)
		if distance > ChunkedTerrainWorld.STREAM_VIEW:
			far += 1
		else:
			near += 1
	assert_gt(far, 0, "coarse chunks past the fine reach")
	assert_eq(near, 0, "within the fine reach every chunk is fine")
	for chunk_coordinate: Vector3i in world._chunks_touching(deep, 2.0):
		if world._is_streamed(chunk_coordinate):
			assert_true(world._stream_loaded.has(chunk_coordinate), "fine round the player")


func _streaming_world() -> OpenTerrain:
	var world: OpenTerrain = OpenTerrain.new()
	world.chunks_x = 8
	world.chunks_y = 14
	world.chunks_z = 8
	world.chunk_size = 8.0
	world.voxel_size = 4.0
	world.solid_underside = true
	world.surface_layer = 2
	world.stream_underground = true
	return world


## Waits up to five seconds of physics frames for a condition.
func _wait_for(condition: Callable) -> bool:
	for _frame: int in 300:
		if condition.call():
			return true
		await get_tree().physics_frame
	return bool(condition.call())
