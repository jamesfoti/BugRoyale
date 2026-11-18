extends GutTest
## The terrain's liquids in play, on a small wet map with a lake: a LiquidSource pours its volume
## into it, LiquidHazards hurts in sewage and not in water, a body whose head is under the lake
## runs out of breath (Breath), and MapInfo counts a point under it as under water.

const SEED: int = 43


func _world() -> OpenTerrain:
	var world := OpenTerrain.new()
	world.rebuild_on_ready = false
	world.chunks_x = 4
	world.chunks_y = 3
	world.chunks_z = 4
	world.chunk_size = 32.0
	world.voxel_size = 2.0
	world.surface_layer = 2
	world.noise_seed = SEED
	world.caves_enabled = false
	world.solid_underside = true
	world.boxed_edges_enabled = false
	world.noise_amplitude = 14.0
	world.wetness_shift = 1.0
	add_child_autoqfree(world)
	world.rebuild_all()
	return world


## The deepest point of the map's lake: {bed, surface}.
func _deepest(world: OpenTerrain) -> Dictionary:
	var lakes: LakeMap = world._get_bake_density().lakes
	var best: Dictionary = {}
	var deepest: float = 0.0
	for x: int in range(-60, 61, 2):
		for z: int in range(-60, 61, 2):
			var level: float = lakes.level_at(x, z)
			if level == -INF:
				continue
			var bed: float = world.get_surface_height_at(Vector3(x, 0, z))
			if level - bed > deepest:
				deepest = level - bed
				best = {"bed": Vector3(x, bed, z), "surface": level}
	return best


func test_a_source_pours_its_volume_into_the_lake() -> void:
	var world: OpenTerrain = _world()
	var deepest: Dictionary = _deepest(world)
	assert_false(deepest.is_empty(), "the map has a lake")
	var before: float = world.get_liquids().get_total_volume()
	var spot: Vector3 = Vector3(deepest.bed.x, deepest.surface + 1.0, deepest.bed.z)
	var source: LiquidSource = LiquidSource.pour(
		self, world, spot, TerrainLiquids.KIND_WATER, 40.0, 0.5
	)
	await wait_physics_frames(60)
	assert_almost_eq(source.poured if is_instance_valid(source) else 40.0, 40.0, 0.5, "all of it")
	assert_almost_eq(world.get_liquids().get_total_volume() - before, 40.0, 1.0, "into the lake")


func test_sewage_hurts_and_water_does_not() -> void:
	var world: OpenTerrain = _world()
	var deepest: Dictionary = _deepest(world)
	var hazards: LiquidHazards = LiquidHazards.attach(self, world)
	assert_not_null(hazards, "the hazards come with the liquids")
	var bed: Vector3 = deepest.bed
	assert_eq(hazards.damage_at(bed), 0.0, "lake water does no harm")
	var surface := Vector3(bed.x, deepest.surface + 0.5, bed.z)
	world.add_liquid(surface, 8.0, TerrainLiquids.KIND_SEWAGE)
	assert_eq(hazards.damage_at(bed), 6.0, "sewage on the lake does")
	assert_eq(hazards.damage_at(bed + Vector3.UP * 30.0), 0.0, "and nothing high in the air")


func test_a_head_under_the_lake_runs_out_of_breath() -> void:
	var world: OpenTerrain = _world()
	var deepest: Dictionary = _deepest(world)
	var depth: float = deepest.surface - deepest.bed.y
	assert_gt(depth, 1.5, "a lake deep enough to go under")
	var body := Node3D.new()
	add_child_autoqfree(body)
	body.global_position = deepest.bed + Vector3.UP * 0.2
	var breath := Breath.new()
	breath.max_breath_seconds = 0.2
	body.add_child(breath)
	await wait_physics_frames(3)
	assert_true(breath.submerged, "the head is under")
	await wait_physics_frames(20)
	assert_eq(breath.breath, 0.0, "out of breath")
	var map := MapInfo.new()
	map.world = world
	assert_true(map.is_underwater(deepest.bed + Vector3.UP * 0.5), "MapInfo sees the lake")
	assert_false(map.is_underwater(deepest.bed + Vector3.UP * 40.0), "and not the sky over it")
