extends GutTest
## The loose rock pass (LooseRock) on a chunk's sampled field: a lone solid sample with air
## all round it is cleared and a lump over the limit is kept; a lump on the seam between two
## chunks is judged the same from both sides, cleared when it reaches no more than a sample
## past the shared face and kept when it reaches further; rock built with the brush, with a
## material or the map's own ground, is never cleared, while rock a dig thinned still goes;
## a row of real cave chunks loses only rock and every pair agrees on its shared face; and
## the limit travels in the settings snapshot.

const STEP: float = 1.0
const CELLS: int = 12
const SAMPLES: Vector3i = Vector3i(CELLS + 1, CELLS + 1, CELLS + 1)
const ORIGIN: Vector3 = Vector3.ZERO
const LIMIT: int = 8


## Air everywhere but inside the given solids (WorldDensity.solids).
func _air_with(solids: Array[Dictionary]) -> WorldDensity:
	var density: WorldDensity = WorldDensity.new()
	density.noise_enabled = false
	density.solids = solids
	return density


## A stadium solid whose samples, at 1 m, are the ones within reach_x of centre.x along x and
## reach_across of it along z, on the row at centre.y: a lump of (2 reach_x + 1) by
## (2 reach_across + 1) samples, one high.
func _lump(centre: Vector3, reach_x: int = 0, reach_across: int = 0) -> Dictionary:
	return {
		"center": Vector3(centre.x, centre.y - 0.4, centre.z),
		"half_length": float(reach_x) + 0.6,
		"radius": float(reach_across) + 0.6,
		"height": 0.8,
		"along_z": false,
	}


func _field(density: WorldDensity, chunk: Vector3i) -> SignedDensityField:
	return DensitySampler.build_chunk_field(density, SAMPLES, ORIGIN, chunk * CELLS, STEP)


func _clear(field: SignedDensityField, density: WorldDensity, chunk: Vector3i) -> int:
	return LooseRock.clear(field, density, ORIGIN, chunk * CELLS, STEP, CELLS, 0.0, LIMIT)


func _solid_at(field: SignedDensityField, x: int, y: int, z: int) -> bool:
	return field.get_sample(x, y, z) < 0.0


func test_a_lone_sample_is_cleared_and_a_lump_over_the_limit_kept() -> void:
	var density: WorldDensity = _air_with(
		[_lump(Vector3(3.0, 6.0, 3.0)), _lump(Vector3(8.0, 6.0, 8.0), 1, 1)]
	)
	var field: SignedDensityField = _field(density, Vector3i.ZERO)
	assert_true(_solid_at(field, 3, 6, 3), "the lone sample is rock before the pass")
	assert_true(_solid_at(field, 8, 6, 8), "and so is the nine-sample slab")
	var before: float = field.get_sample(3, 6, 3)
	assert_eq(_clear(field, density, Vector3i.ZERO), 1, "one sample cleared")
	assert_false(_solid_at(field, 3, 6, 3), "the lone sample is air")
	assert_almost_eq(field.get_sample(3, 6, 3), -before, 0.0001, "mirrored about the iso level")
	for x: int in range(7, 10):
		for z: int in range(7, 10):
			assert_true(_solid_at(field, x, 6, z), "the slab is kept at %d, %d" % [x, z])
	assert_gt(field.min_value, -1.0, "the range is refreshed")
	assert_eq(LooseRock.clear(field, density, ORIGIN, Vector3i.ZERO, STEP, CELLS, 0.0, 0), 0)


func test_a_lump_on_a_seam_is_judged_the_same_from_both_chunks() -> void:
	# Three lumps on the face between chunks 0 and 1 along x (world x 12): one sample on the
	# face, three samples from a sample before it to a sample past it, and three from the
	# face to two samples past it, which only chunk 1 could see whole.
	var density: WorldDensity = _air_with(
		[
			_lump(Vector3(12.0, 6.0, 2.0)),
			_lump(Vector3(12.0, 6.0, 6.0), 1),
			_lump(Vector3(13.0, 6.0, 10.0), 1),
		]
	)
	var left: SignedDensityField = _field(density, Vector3i.ZERO)
	var right: SignedDensityField = _field(density, Vector3i(1, 0, 0))
	assert_eq(_clear(left, density, Vector3i.ZERO), 1 + 2, "chunk 0 clears its side of two lumps")
	assert_eq(_clear(right, density, Vector3i(1, 0, 0)), 1 + 2, "chunk 1 clears its side of two")
	for y: int in SAMPLES.y:
		for z: int in SAMPLES.z:
			assert_almost_eq(
				left.get_sample(CELLS, y, z),
				right.get_sample(0, y, z),
				0.0001,
				"shared face agrees"
			)
	assert_false(_solid_at(left, CELLS, 6, 2), "the lone sample on the face is cleared")
	assert_false(_solid_at(left, CELLS - 1, 6, 6), "the lump a sample either side goes")
	assert_false(_solid_at(right, 1, 6, 6))
	assert_true(_solid_at(left, CELLS, 6, 10), "the lump two samples past the face stays")
	assert_true(_solid_at(right, 2, 6, 10))


func test_built_rock_stays_and_thinned_rock_goes() -> void:
	var density: WorldDensity = _air_with([_lump(Vector3(3.0, 6.0, 9.0))])
	density.prepare_for_region(AABB(Vector3.ONE * -100.0, Vector3.ONE * 200.0))
	var edits: TerrainEdits = TerrainEdits.new()
	edits.set_voxel_size(STEP)
	edits.set_grid_origin(ORIGIN)
	density.terrain_edits = edits
	var evaluate: Callable = Callable(density, "evaluate")
	# A stone block in the sky, a lump of the map's own ground built in the sky, and the
	# natural lump thinned by a dig that stops short of it.
	assert_true(
		edits.add_box(
			Vector3(3.0, 6.0, 3.0), Vector3.ONE * 0.5, true, evaluate, TerrainMaterials.Kind.STONE
		)
	)
	assert_true(edits.add_brush(Vector3(9.0, 6.0, 3.0), 0.6, true, evaluate))
	assert_true(edits.add_brush(Vector3(3.5, 6.0, 9.0), 0.3, false, evaluate))
	var field: SignedDensityField = _field(density, Vector3i.ZERO)
	assert_true(_solid_at(field, 3, 6, 3), "the block is rock")
	assert_true(_solid_at(field, 9, 6, 3), "the built ground is rock")
	assert_true(_solid_at(field, 3, 6, 9), "the thinned lump is still rock")
	assert_eq(_clear(field, density, Vector3i.ZERO), 1, "one sample cleared")
	assert_true(_solid_at(field, 3, 6, 3), "the block stays")
	assert_true(_solid_at(field, 9, 6, 3), "the built ground stays")
	assert_false(_solid_at(field, 3, 6, 9), "the thinned lump goes")


func test_a_cave_chunk_loses_only_rock_and_agrees_with_its_neighbour() -> void:
	var density: WorldDensity = DensitySampler.create_open_terrain_world_density(
		7,
		0.01,
		3.0,
		3,
		2.0,
		0.5,
		Vector3.ZERO,
		Vector3(256.0, 96.0, 256.0),
		0.5,
		false,
		null,
		0.0,
		true
	)
	density.caves = CaveCarver.from_seed(7, -93.5)
	var origin: Vector3 = Vector3(-256.0, -96.0, -256.0)
	var samples: Vector3i = Vector3i.ONE * 9
	var cleared_somewhere: bool = false
	# Rows of chunks through the cave band, each cleared on its own as the builder does.
	for chunk_z: int in 8:
		var previous: SignedDensityField = null
		for chunk_x: int in 8:
			var chunk: Vector3i = Vector3i(chunk_x, 1, chunk_z)
			var field: SignedDensityField = DensitySampler.build_chunk_field(
				density, samples, origin, chunk * 8, 4.0
			)
			var before: PackedFloat32Array = field.values.duplicate()
			var cleared: int = LooseRock.clear(
				field, density, origin, chunk * 8, 4.0, 8, 0.0, LIMIT
			)
			var changed: int = 0
			for index: int in before.size():
				if is_equal_approx(before[index], field.values[index]):
					continue
				changed += 1
				assert_lt(before[index], 0.0, "only rock changes")
				assert_gt(field.values[index], 0.0, "and it becomes air")
			assert_eq(changed, cleared, "the count is the samples changed")
			cleared_somewhere = cleared_somewhere or cleared > 0
			if previous != null:
				for y: int in samples.y:
					for z: int in samples.z:
						assert_almost_eq(
							previous.get_sample(8, y, z),
							field.get_sample(0, y, z),
							0.0001,
							(
								"chunk %d agrees with chunk %d on their shared face"
								% [chunk_x - 1, chunk_x]
							)
						)
			previous = field
	assert_true(cleared_somewhere, "some chunk in the rows had floating rock")


func test_the_limit_travels_in_the_snapshot() -> void:
	var world: ChunkedTerrainWorld = ChunkedTerrainWorld.new()
	world.rebuild_on_ready = false
	world.loose_rock_voxels = 3
	add_child_autofree(world)
	assert_eq(world._make_settings_snapshot().loose_rock_voxels, 3)
