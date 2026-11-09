extends GutTest
## The chunk builder's short cut for chunks wholly above the ground: filled from the column
## heights without a voxel pass, while a chunk the surface crosses, a placed solid in the sky
## or a built edit in the sky all bring the voxel pass back, and an edit elsewhere does not.

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
