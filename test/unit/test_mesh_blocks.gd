extends GutTest
## A chunk meshed in blocks (ChunkMeshBlocks) is the same surface as the chunk meshed in
## one go, and after a brush stroke only the blocks the stroke's samples touch are meshed
## again, the rest kept from the chunk's last build, with the same surface as a fresh build.

const SEED: int = 7
const STEP: float = 2.0
const SAMPLES: Vector3i = Vector3i(17, 17, 17)
const ORIGIN: Vector3 = Vector3(-128.0, -48.0, -128.0)
## Sample offset of a chunk the surface crosses (x and z from -64 to -32, y -16 to 16).
const CHUNK: Vector3i = Vector3i(32, 16, 32)
const EXTENT: float = 32.0


func _ground() -> WorldDensity:
	var density: WorldDensity = DensitySampler.create_open_terrain_world_density(
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


func _centre() -> Vector3:
	return ORIGIN + Vector3(CHUNK) * STEP + Vector3.ONE * EXTENT * 0.5


func _blocks(
	field: SignedDensityField, density: WorldDensity, previous: ChunkMeshBlocks = null
) -> ChunkMeshBlocks:
	return ChunkMeshBlocks.build(field, EXTENT, 0.0, CHUNK, ORIGIN, _centre(), density, previous)


func _sorted_vertices(mesh: TerrainMeshResult) -> Array:
	var out: Array = Array(mesh.vertices)
	out.sort()
	return out


func _assert_same_surface(a: TerrainMeshResult, b: TerrainMeshResult, what: String) -> void:
	assert_eq(a.indices.size(), b.indices.size(), what + ": the same triangle count")
	assert_eq(a.vertices.size(), b.vertices.size(), what + ": the same vertex count")
	var sorted_a: Array = _sorted_vertices(a)
	var sorted_b: Array = _sorted_vertices(b)
	var apart: int = 0
	for index: int in mini(sorted_a.size(), sorted_b.size()):
		if not (sorted_a[index] as Vector3).is_equal_approx(sorted_b[index] as Vector3):
			apart += 1
	assert_eq(apart, 0, what + ": the same vertices")


func test_blocks_merge_into_the_surface_the_whole_mesher_makes() -> void:
	var density: WorldDensity = _ground()
	var field: SignedDensityField = DensitySampler.build_chunk_field(
		density, SAMPLES, ORIGIN, CHUNK, STEP
	)
	var whole: TerrainMeshResult = FlyingEdgesMesher.build_mesh(
		field, EXTENT, 0.0, CHUNK, ORIGIN, _centre(), density
	)
	var blocks: ChunkMeshBlocks = _blocks(field, density)
	assert_eq(blocks.blocks.size(), 8, "sixteen cells a side: two blocks of eight a side")
	var merged: TerrainMeshResult = blocks.merge()
	assert_gt(whole.indices.size(), 0, "the surface crosses this chunk")
	assert_eq(merged.indices.size(), whole.indices.size(), "every triangle of the whole mesh")
	# A vertex on a block face is made by both blocks, so the merge holds a few more.
	assert_true(merged.vertices.size() >= whole.vertices.size())
	assert_eq(merged.colors.size(), merged.vertices.size(), "a colour per vertex, still")
	var top: int = 0
	for index: int in merged.indices:
		top = maxi(top, index)
	assert_lt(top, merged.vertices.size(), "every index points into the merged vertices")


func test_a_stroke_meshes_only_the_blocks_it_touched_and_the_surface_is_the_same() -> void:
	var density: WorldDensity = _ground()
	var before: SignedDensityField = DensitySampler.build_chunk_field(
		density, SAMPLES, ORIGIN, CHUNK, STEP
	)
	var previous: ChunkMeshBlocks = _blocks(before, density)
	# A hole in the chunk's low x, low z corner, down at the ground.
	var at := Vector3(-60.0, density.sample_open_terrain_height(-60.0, -60.0) - 2.0, -60.0)
	var edits := TerrainEdits.new()
	edits.set_voxel_size(STEP)
	edits.set_grid_origin(ORIGIN)
	edits.add_brush(at, 3.0, false, Callable(density, "evaluate"))
	density.terrain_edits = edits
	var field: SignedDensityField = DensitySampler.resample_chunk_field(
		before, density, ORIGIN, CHUNK, STEP, edits.get_last_changed_bounds()
	)
	assert_true(field.changed_last.x < 16 and field.changed_last.z < 16, "a corner changed")
	var partial: ChunkMeshBlocks = _blocks(field, density, previous)
	var kept: int = 0
	for index: int in partial.blocks.size():
		if partial.blocks[index] == previous.blocks[index]:
			kept += 1
	assert_gt(kept, 0, "blocks the stroke never touched are kept as they were")
	assert_lt(kept, partial.blocks.size(), "and the ones it touched are meshed again")
	var fresh: ChunkMeshBlocks = _blocks(field, density)
	_assert_same_surface(partial.merge(), fresh.merge(), "after the stroke")
	assert_ne(partial.merge().indices.size(), previous.merge().indices.size(), "the hole shows")
