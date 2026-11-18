extends GutTest
## The lakes on the ground (LakeMap): a bowl in a wet climate holds one lake just under its rim,
## half full at half the amount, and none in a dry climate or with the amount at nothing; a
## chunk's seed (LiquidSeed.from_field) fills the open cells under the lake's level over the bowl's
## floor and leaves the cells over it dry.

const HALF := Vector3(64.0, 32.0, 64.0)
const AMPLITUDE: float = 10.0
const GRID_ORIGIN := Vector3(-64.0, -32.0, -64.0)
const STEP: float = 2.0
const CELLS: int = 8
## LakeMap.RIM_MARGIN.
const RIM_MARGIN: float = 0.3


## A round bowl: its floor 10 m under the middle, rising to 10 m over it at the map's sides.
func _bowl(wetness_shift: float) -> WorldDensity:
	var image := Image.create(65, 65, false, Image.FORMAT_RGB8)
	for z: int in 65:
		for x: int in 65:
			var distance: float = Vector2(x - 32, z - 32).length() / 32.0
			var value: float = clampf(distance * 0.5 + 0.0, 0.0, 1.0)
			image.set_pixel(x, z, Color(value, value, value))
	var density: WorldDensity = DensitySampler.create_open_terrain_world_density(
		1, 0.01, AMPLITUDE, 1, 2.0, 0.5, Vector3.ZERO, HALF, 0.5, false, image, 0.0, true
	)
	density.set_climate_shift(0.0, wetness_shift)
	return density


func test_a_bowl_in_a_wet_climate_holds_a_lake_just_under_its_rim() -> void:
	var lakes: LakeMap = LakeMap.build(_bowl(1.0), 1.0)
	assert_eq(lakes.get_lake_count(), 1, "one lake")
	var level: float = lakes.level_at(0.0, 0.0)
	assert_between(level, -1.0, -RIM_MARGIN + 0.01, "just under the rim (the sides near 0 m)")
	assert_eq(lakes.level_at(63.0, 63.0), -INF, "none up in the corner")
	assert_gt(lakes.get_area(), 2000.0, "a wide lake")


func test_half_the_amount_fills_half_way_and_none_or_a_dry_climate_none() -> void:
	var half: LakeMap = LakeMap.build(_bowl(1.0), 0.5)
	assert_almost_eq(half.level_at(0.0, 0.0), -5.0, 1.0, "half way up from the floor")
	assert_eq(LakeMap.build(_bowl(1.0), 0.0).get_lake_count(), 0, "no lakes at nothing")
	assert_eq(LakeMap.build(_bowl(-1.0), 1.0).get_lake_count(), 0, "none in a dry climate")


func test_a_seed_fills_the_open_cells_under_the_lake() -> void:
	var density: WorldDensity = _bowl(1.0)
	density.lakes = LakeMap.build(density, 1.0)
	var level: float = density.lakes.level_at(0.0, 0.0)
	# The chunk over the bowl's middle, from 10 m under the middle up to 4 m over it.
	var chunk := Vector3i(4, 1, 4)
	var offset: Vector3i = chunk * CELLS
	var field: SignedDensityField = DensitySampler.build_chunk_field(
		density, Vector3i.ONE * (CELLS + 1), GRID_ORIGIN, offset, STEP
	)
	var seed: LiquidSeed = LiquidSeed.from_field(
		field, density, chunk, CELLS, GRID_ORIGIN, STEP, 0.0
	)
	assert_false(seed.is_dry(), "the chunk holds lake water")
	for y: int in CELLS:
		var cell_bottom: float = GRID_ORIGIN.y + (offset.y + y) * STEP - STEP * 0.5
		var mass: float = seed.get_mass_at(Vector3i(0, y, 0))
		if seed.is_solid_at(Vector3i(0, y, 0)):
			assert_eq(mass, 0.0, "no water in the ground at %d" % y)
		elif cell_bottom + STEP <= level:
			assert_almost_eq(mass, 1.0, 0.001, "full under the level at %d" % y)
		elif cell_bottom >= level:
			assert_eq(mass, 0.0, "dry over the level at %d" % y)
		else:
			assert_almost_eq(mass, (level - cell_bottom) / STEP, 0.01, "the surface cell part full")
