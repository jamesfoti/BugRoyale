extends GutTest
## The carved cave systems (CaveSystems): a seed always rolls the same ones and as many as
## the map's area says; every mouth sits on the surface inside the bounds, on steep ground
## more often than not, and opens the ground under a solid open terrain; the passages go
## down from their mouths and are air along their centre lines; a prepared region sees
## only the segments in reach; and far from every passage there is nothing.

const SEED: int = 7
const BOUNDS := AABB(Vector3(-256.0, -48.0, -256.0), Vector3(512.0, 96.0, 512.0))
const FLOOR_Y: float = -45.5


## Rolling hills 12 m tall, 80 m across.
func _height(x: float, z: float) -> float:
	return 12.0 * sin(x / 40.0) * cos(z / 50.0)


func _systems(seed_value: int = SEED) -> CaveSystems:
	return CaveSystems.roll(seed_value, BOUNDS, _height, FLOOR_Y)


func test_the_same_seed_rolls_the_same_systems_and_as_many_as_the_area_says() -> void:
	var first: CaveSystems = _systems()
	var again: CaveSystems = _systems()
	assert_eq(first.starts, again.starts, "the same passages")
	assert_eq(first.start_radii, again.start_radii, "the same radii")
	assert_ne(first.starts, _systems(8).starts, "another seed, other passages")
	var km2: float = BOUNDS.size.x * BOUNDS.size.z / 1000000.0
	assert_between(
		float(first.count), floor(CaveSystems.PER_KM2.x * km2), ceil(CaveSystems.PER_KM2.y * km2)
	)
	assert_eq(first.mouths.size(), first.count, "a mouth per system")
	assert_gt(first.starts.size(), first.count * CaveSystems.STEPS.x / 2, "passages of many steps")


func test_every_mouth_sits_on_the_surface_inside_the_bounds() -> void:
	var systems: CaveSystems = _systems()
	for mouth: Vector3 in systems.mouths:
		assert_true(BOUNDS.has_point(mouth), "inside the bounds: %v" % mouth)
		assert_almost_eq(mouth.y, _height(mouth.x, mouth.z), 0.001, "on the surface")
	var close_pairs: int = 0
	for first: int in systems.mouths.size():
		for second: int in range(first + 1, systems.mouths.size()):
			var a: Vector3 = systems.mouths[first]
			var b: Vector3 = systems.mouths[second]
			if Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) < CaveSystems.MOUTH_SPACING:
				close_pairs += 1
	assert_lt(close_pairs, 2, "the mouths keep apart")


func test_the_passages_go_down_and_are_air_along_their_centre_lines() -> void:
	var systems: CaveSystems = _systems()
	var deepest: float = INF
	for index: int in systems.starts.size():
		var middle: Vector3 = (systems.starts[index] + systems.ends[index]) * 0.5
		assert_gt(systems.air(middle), 0.0, "air at the centre of segment %d" % index)
		assert_gt(
			systems.ends[index].y, FLOOR_Y + CaveSystems.FLOOR_CLEARANCE - 0.01, "above bedrock"
		)
		deepest = minf(deepest, systems.ends[index].y)
	assert_lt(deepest, systems.mouths[0].y - 20.0, "some passage is well under its mouth")
	assert_eq(systems.air(Vector3(0.0, 400.0, 0.0)), -INF, "nothing far above the world")


func test_a_prepared_region_sees_only_the_segments_in_reach() -> void:
	var systems: CaveSystems = _systems()
	var middle: Vector3 = (systems.starts[0] + systems.ends[0]) * 0.5
	systems.prepare_region(AABB(middle + Vector3(300.0, 0.0, 300.0), Vector3.ONE * 10.0))
	assert_eq(systems.air(middle), -INF, "a region far away sees nothing here")
	systems.prepare_region(AABB(middle - Vector3.ONE * 5.0, Vector3.ONE * 10.0))
	assert_gt(systems.air(middle), 0.0, "the region about it sees the passage")


func test_the_mouths_open_the_ground_under_a_solid_open_terrain() -> void:
	var density: DensitySampler.WorldDensity = DensitySampler.create_open_terrain_world_density(
		SEED, 0.01, 3.0, 3, 2.0, 0.5, Vector3.ZERO, BOUNDS.size * 0.5, 0.5, false, null, 0.0, true
	)
	density.caves = CaveCarver.from_seed(SEED, FLOOR_Y)
	density.caves.systems = CaveSystems.roll(
		SEED, BOUNDS, Callable(density, "sample_open_terrain_height"), FLOOR_Y
	)
	var open: int = 0
	for mouth: Vector3 in density.caves.systems.mouths:
		var under: Vector3 = mouth - Vector3(0.0, 1.5, 0.0)
		density.prepare_for_region(AABB(under - Vector3.ONE * 4.0, Vector3.ONE * 8.0))
		if density.evaluate(under) > 0.0:
			open += 1
	assert_gt(open * 2, density.caves.systems.count, "most mouths are open a metre and a half down")
	assert_true(density.caves.summary().contains("cave systems"), "the rebuild line names them")
