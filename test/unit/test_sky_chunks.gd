extends GutTest
## The chunk builder's short cut for chunks wholly above the ground: filled from the column
## heights without a voxel pass, while a chunk the surface crosses, a placed solid in the sky
## or a built edit in the sky all bring the voxel pass back, and an edit elsewhere does not.
## After a brush stroke a chunk's field is resampled from the one it had, only inside the
## stroke's box, and comes out the same as a field built whole, sky chunks included.

const SEED: int = 7
const STEP: float = 2.0
const SAMPLES: Vector3i = Vector3i(17, 17, 17)
## The grid's first sample: a 256 by 96 by 256 m world about the origin.
const ORIGIN: Vector3 = Vector3(-128.0, -48.0, -128.0)
## Sample offsets of two chunks in the third column of the grid (x and z from -64 to -32):
## the top chunk spans y 16 to 48, the middle one -16 to 16.
const SKY_CHUNK: Vector3i = Vector3i(32, 32, 32)
const SURFACE_CHUNK: Vector3i = Vector3i(32, 16, 32)


func _ground() -> DensitySampler.WorldDensity:
	var density: DensitySampler.WorldDensity = DensitySampler.create_open_terrain_world_density(
		SEED,
		0.01,
		3.0,
		3,
		2.0,
		0.5,
		Vector3.ZERO,
		Vector3(128.0, 48.0, 128.0),
		0.5,
		true,
		null,
		0.0,
		true
	)
	density.caves = CaveCarver.from_seed(SEED, -45.5)
	return density


func _field(density: DensitySampler.WorldDensity, chunk: Vector3i) -> SignedDensityField:
	return DensitySampler.build_chunk_field(density, SAMPLES, ORIGIN, chunk, STEP)


func _edits(density: DensitySampler.WorldDensity, at: Vector3) -> TerrainEdits:
	var edits := TerrainEdits.new()
	edits.set_voxel_size(STEP)
	edits.set_grid_origin(ORIGIN)
	edits.add_brush(at, 3.0, true, Callable(density, "evaluate"))
	return edits


func test_a_chunk_above_the_ground_is_sky_and_skips_the_voxel_pass() -> void:
	var field: SignedDensityField = _field(_ground(), SKY_CHUNK)
	assert_true(field.sky, "sky")
	assert_gt(field.min_value, 10.0, "metres of air above the highest hill")
	assert_almost_eq(field.min_value, field.max_value, 0.0001, "one clearance value throughout")
	for index: int in [0, 1000, field.values.size() - 1]:
		assert_almost_eq(field.values[index], field.min_value, 0.0001)


func test_a_chunk_the_surface_crosses_is_sampled() -> void:
	var field: SignedDensityField = _field(_ground(), SURFACE_CHUNK)
	assert_false(field.sky, "not sky")
	assert_lt(field.min_value, 0.0, "ground in it")
	assert_gt(field.max_value, 0.0, "and air")


func test_a_placed_solid_in_the_sky_brings_the_voxel_pass_back() -> void:
	var density: DensitySampler.WorldDensity = _ground()
	density.solids = [
		{
			"center": Vector3(-48.0, 22.0, -48.0),
			"half_length": 6.0,
			"radius": 3.0,
			"along_z": false,
			"height": 4.0,
		}
	]
	var field: SignedDensityField = _field(density, SKY_CHUNK)
	assert_false(field.sky, "a slab hangs in this chunk")
	assert_lt(field.min_value, 0.0, "and it is solid")


func test_a_built_edit_in_the_sky_brings_the_voxel_pass_back_but_one_elsewhere_does_not() -> void:
	var density: DensitySampler.WorldDensity = _ground()
	density.terrain_edits = _edits(density, Vector3(-48.0, 30.0, -48.0))
	var field: SignedDensityField = _field(density, SKY_CHUNK)
	assert_false(field.sky, "something was built up here")
	assert_lt(field.min_value, 0.0, "and it is solid")
	var elsewhere: DensitySampler.WorldDensity = _ground()
	elsewhere.terrain_edits = _edits(elsewhere, Vector3(100.0, 30.0, 100.0))
	assert_true(_field(elsewhere, SKY_CHUNK).sky, "a build in another chunk changes nothing here")


func test_a_resampled_field_matches_one_built_whole() -> void:
	var density: DensitySampler.WorldDensity = _ground()
	var before: SignedDensityField = _field(density, SURFACE_CHUNK)
	# A hole dug a few metres into the ground of that chunk, then the field with it, both ways.
	var at := Vector3(-48.0, density.sample_open_terrain_height(-48.0, -48.0) - 2.0, -48.0)
	var edits := TerrainEdits.new()
	edits.set_voxel_size(STEP)
	edits.set_grid_origin(ORIGIN)
	edits.add_brush(at, 3.0, false, Callable(density, "evaluate"))
	density.terrain_edits = edits
	var whole: SignedDensityField = _field(density, SURFACE_CHUNK)
	var resampled: SignedDensityField = DensitySampler.resample_chunk_field(
		before, density, ORIGIN, SURFACE_CHUNK, STEP, edits.get_last_changed_bounds()
	)
	assert_eq(resampled.size, whole.size)
	var differences: int = 0
	for index: int in whole.values.size():
		if not is_equal_approx(resampled.values[index], whole.values[index]):
			differences += 1
	assert_eq(differences, 0, "every sample as the whole build has it")
	assert_almost_eq(resampled.min_value, whole.min_value, 0.0001, "and the range")
	assert_almost_eq(resampled.max_value, whole.max_value, 0.0001)
	assert_false(resampled.sky)
	# A block built in the sky: the sky chunk's constant field gets the block's samples back.
	var sky_before: SignedDensityField = _field(_ground(), SKY_CHUNK)
	var sky_density: DensitySampler.WorldDensity = _ground()
	var block := Vector3(-48.0, 22.0, -48.0)
	var sky_edits := TerrainEdits.new()
	sky_edits.set_voxel_size(STEP)
	sky_edits.set_grid_origin(ORIGIN)
	sky_edits.add_brush(block, 3.0, true, Callable(sky_density, "evaluate"))
	sky_density.terrain_edits = sky_edits
	var sky_resampled: SignedDensityField = DensitySampler.resample_chunk_field(
		sky_before, sky_density, ORIGIN, SKY_CHUNK, STEP, sky_edits.get_last_changed_bounds()
	)
	assert_false(sky_resampled.sky, "no longer sky")
	assert_lt(sky_resampled.min_value, 0.0, "the block is solid in it")
	assert_lt(sky_resampled.sample_world(block, ORIGIN + Vector3(SKY_CHUNK) * STEP, STEP), 0.0)
