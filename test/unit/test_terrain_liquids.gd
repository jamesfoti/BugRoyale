extends GutTest
## The terrain's liquids (TerrainLiquids) on chunks seeded by hand (LiquidSeed): liquid falls to
## the floor and spreads level without losing volume, a wall holds a pool until a dig opens a
## door in it and the two sides even out, a cell filled in pushes its liquid up, `liquid_at`
## gives the depth under the surface and the liquid, liquid waits at the face of a chunk not
## built yet and runs in once it is, and the mesh is coloured by liquid.

const CELLS: int = 8


## A grid of 1 m cells with sample 0 at the origin, so cell (x, y, z) sits at (x, y, z).
func _liquids(grid := Vector3i(1, 1, 1)) -> TerrainLiquids:
	var liquids := TerrainLiquids.new()
	autofree(liquids)
	liquids.configure(CELLS, 1.0, Vector3.ZERO, Vector3.ZERO, grid)
	return liquids


## A box: solid floor (y 0) and walls round the outside, open over the floor. `open_sides`
## leaves those x faces (-1, 1) without a wall.
func _box(chunk := Vector3i.ZERO, open_sides: Array = []) -> LiquidSeed:
	var seed := LiquidSeed.make(chunk, CELLS)
	for z: int in CELLS:
		for y: int in CELLS:
			for x: int in CELLS:
				var wall: bool = z == 0 or z == CELLS - 1
				if x == 0 and not open_sides.has(-1):
					wall = true
				if x == CELLS - 1 and not open_sides.has(1):
					wall = true
				seed.set_solid_at(Vector3i(x, y, z), y == 0 or wall)
	return seed


func _layer_masses(liquids: TerrainLiquids, y: int, offset := Vector3i.ZERO) -> Array[float]:
	var out: Array[float] = []
	for z: int in range(1, CELLS - 1):
		for x: int in range(1, CELLS - 1):
			out.append(liquids.mass_at_cell(offset + Vector3i(x, y, z)))
	return out


func test_liquid_falls_to_the_floor_and_spreads_level_keeping_its_volume() -> void:
	var liquids: TerrainLiquids = _liquids()
	liquids.take_seed(_box())
	assert_eq(liquids.get_chunk_count(), 0, "a dry chunk nothing asked for is not kept")
	liquids.request_chunk(Vector3i.ZERO)
	liquids.take_seed(_box())
	var added: float = liquids.add_liquid(Vector3(3, 3, 3), 3.0, TerrainLiquids.KIND_WATER)
	assert_almost_eq(added, 3.0, 0.001, "it all fitted")
	liquids.settle(4000)
	assert_eq(liquids.get_awake_count(), 0, "settled")
	assert_almost_eq(liquids.get_total_volume(), 3.0, 0.05, "no liquid lost")
	var floor_cells: Array[float] = _layer_masses(liquids, 1)
	var on_floor: float = 0.0
	for mass: float in floor_cells:
		on_floor += mass
	assert_almost_eq(on_floor, liquids.get_total_volume(), 0.001, "all of it on the floor")
	assert_lt(floor_cells.max() - floor_cells.min(), 0.05, "spread level")


func test_a_wall_holds_a_pool_until_a_door_is_dug_and_the_sides_even_out() -> void:
	var liquids: TerrainLiquids = _liquids()
	var walled: LiquidSeed = _box()
	for z: int in CELLS:
		for y: int in CELLS:
			walled.set_solid_at(Vector3i(4, y, z), true)
	for z: int in range(1, CELLS - 1):
		for y: int in range(1, 5):
			for x: int in range(1, 4):
				walled.set_liquid_at(Vector3i(x, y, z), 1.0, TerrainLiquids.KIND_WATER)
	liquids.take_seed(walled)
	var volume: float = liquids.get_total_volume()
	assert_almost_eq(volume, 72.0, 0.001, "three columns by six by four full cells")
	liquids.settle(2000)
	assert_almost_eq(liquids.get_total_volume(), volume, 0.001, "a still pool stays")
	assert_eq(liquids.mass_at_cell(Vector3i(5, 1, 3)), 0.0, "the far side dry")

	var dug: LiquidSeed = _box()
	for z: int in CELLS:
		for y: int in CELLS:
			dug.set_solid_at(Vector3i(4, y, z), not (z == 3 and y >= 1 and y <= 5))
	liquids.take_seed(dug)
	assert_gt(liquids.get_awake_count(), 0, "the dig woke the pool")
	liquids.settle(20000)
	assert_almost_eq(liquids.get_total_volume(), volume, volume * 0.01, "the volume kept")
	var near: Dictionary = liquids.liquid_at(Vector3(2, 1, 3))
	var far: Dictionary = liquids.liquid_at(Vector3(6, 1, 3))
	assert_eq(int(far.kind), TerrainLiquids.KIND_WATER, "water ran through the door")
	assert_lt(float(near.surface), 4.5 - 0.5, "the pool's level dropped")
	assert_almost_eq(float(near.surface), float(far.surface), 0.3, "the sides evened out")


func test_a_cell_filled_in_pushes_its_liquid_up() -> void:
	var liquids: TerrainLiquids = _liquids()
	var seed: LiquidSeed = _box()
	seed.set_liquid_at(Vector3i(3, 1, 3), 1.0, TerrainLiquids.KIND_SEWAGE)
	liquids.take_seed(seed)
	var filled: LiquidSeed = _box()
	filled.set_solid_at(Vector3i(3, 1, 3), true)
	liquids.take_seed(filled)
	assert_eq(liquids.mass_at_cell(Vector3i(3, 1, 3)), 0.0, "none left in the ground")
	assert_almost_eq(liquids.mass_at_cell(Vector3i(3, 2, 3)), 1.0, 0.001, "pushed up a cell")
	assert_eq(liquids.kind_at_cell(Vector3i(3, 2, 3)), TerrainLiquids.KIND_SEWAGE, "still sewage")


func test_liquid_at_gives_the_depth_under_the_surface_and_the_liquid() -> void:
	var liquids: TerrainLiquids = _liquids()
	var seed: LiquidSeed = _box()
	for z: int in range(1, CELLS - 1):
		for x: int in range(1, CELLS - 1):
			for y: int in range(1, 4):
				seed.set_liquid_at(Vector3i(x, y, z), 1.0, TerrainLiquids.KIND_HOT_WATER)
	liquids.take_seed(seed)
	var deep: Dictionary = liquids.liquid_at(Vector3(3, 1, 3))
	assert_eq(int(deep.kind), TerrainLiquids.KIND_HOT_WATER, "hot water")
	assert_almost_eq(float(deep.surface), 3.5, 0.001, "the top of the third full cell")
	assert_almost_eq(float(deep.depth), 2.5, 0.001, "two and a half metres under")
	var over: Dictionary = liquids.liquid_at(Vector3(3, 3.8, 3))
	assert_almost_eq(float(over.depth), -0.3, 0.001, "just over the surface")
	assert_eq(
		int(liquids.liquid_at(Vector3(3, 6, 3)).kind), TerrainLiquids.KIND_NONE, "dry up high"
	)


func test_liquid_waits_at_a_chunk_not_built_yet_and_runs_in_once_it_is() -> void:
	var liquids: TerrainLiquids = _liquids(Vector3i(2, 1, 1))
	var seed: LiquidSeed = _box(Vector3i.ZERO, [1])
	for z: int in range(1, CELLS - 1):
		for y: int in range(1, 4):
			seed.set_liquid_at(Vector3i(6, y, z), 1.0, TerrainLiquids.KIND_WATER)
	liquids.take_seed(seed)
	liquids.add_liquid(Vector3(7, 1, 3), 0.5, TerrainLiquids.KIND_WATER)
	liquids.settle(500)
	assert_true(liquids.is_waiting_for(Vector3i(1, 0, 0)), "it asked for the next chunk")
	assert_false(liquids.has_chunk(Vector3i(1, 0, 0)), "which is not here yet")
	var volume: float = liquids.get_total_volume()
	liquids.take_seed(_box(Vector3i(1, 0, 0), [-1]))
	assert_true(liquids.has_chunk(Vector3i(1, 0, 0)), "taken once it came")
	liquids.settle(20000)
	assert_gt(liquids.mass_at_cell(Vector3i(12, 1, 3)), 0.1, "the water ran into it")
	assert_almost_eq(liquids.get_total_volume(), volume, volume * 0.01, "the volume kept")


func test_a_dry_chunk_far_from_liquid_is_not_kept() -> void:
	var liquids: TerrainLiquids = _liquids(Vector3i(3, 1, 1))
	liquids.take_seed(_box(Vector3i(2, 0, 0)))
	assert_eq(liquids.get_chunk_count(), 0, "nothing to hold")
	var wet: LiquidSeed = _box()
	wet.set_liquid_at(Vector3i(3, 1, 3), 1.0, TerrainLiquids.KIND_WATER)
	liquids.take_seed(wet)
	liquids.take_seed(_box(Vector3i(1, 0, 0)))
	assert_eq(liquids.get_chunk_count(), 2, "the wet chunk and the dry one beside it")


func test_the_mesh_is_coloured_by_liquid() -> void:
	var liquids: TerrainLiquids = _liquids()
	liquids.request_chunk(Vector3i.ZERO)
	liquids.take_seed(_box())
	liquids.add_liquid(Vector3(3, 2, 3), 6.0, TerrainLiquids.KIND_SEWAGE)
	liquids.settle(4000)
	var mesh: TerrainMeshResult = liquids.build_mesh(Vector3i.ZERO)
	assert_gt(mesh.indices.size(), 0, "a surface over the floor")
	assert_eq(mesh.colors.size(), mesh.vertices.size(), "a colour for every vertex")
	var sewage: Color = TerrainLiquids.kind_color(TerrainLiquids.KIND_SEWAGE)
	for color: Color in mesh.colors:
		assert_eq(color, sewage, "sewage coloured")
		break
	var highest: float = -INF
	for vertex: Vector3 in mesh.vertices:
		highest = maxf(highest, vertex.y + 4.0)
	assert_between(highest, 0.5, 2.0, "the surface lies low over the floor")
