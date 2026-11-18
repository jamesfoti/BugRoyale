extends GutTest
## A biome's plants (BiomePlants, PlantFeature): a kind that lists a plant grows it over the
## built ground of a map whose terrain lists it too, and nowhere else; each stands on open
## ground at the surface, within the plant's heights, the same for the same seed; none stands
## under a lake unless it takes water that deep; and the built-in shapes all build a mesh a
## metre tall.

const SEED: int = 42


func _world(plant: PlantFeature, plant_on_map: bool) -> OpenTerrain:
	var entry := BiomeFeatureEntry.new()
	entry.feature = plant
	entry.density = 1.0
	var kind := Biome.new()
	kind.features = [entry]
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
	world.land_biomes = [kind]
	world.biome_features = [plant] if plant_on_map else []
	add_child_autoqfree(world)
	return world


func _plant() -> PlantFeature:
	var plant := PlantFeature.new()
	plant.feature_name = "test grass"
	plant.shape = PlantFeature.Shape.GRASS
	plant.height = Vector2(1.0, 2.0)
	plant.spacing = 6.0
	return plant


func _grown(world: OpenTerrain) -> BiomePlants:
	world.rebuild_all()
	await wait_physics_frames(3)
	var plants := BiomePlants.new()
	plants.terrain = world
	add_child_autoqfree(plants)
	plants.grow()
	return plants


func test_plants_grow_on_open_ground_only_where_listed() -> void:
	var plant: PlantFeature = _plant()
	var unlisted: BiomePlants = await _grown(_world(plant, false))
	assert_eq(unlisted.count(), 0, "a map that does not list the plant grows none")
	var world: OpenTerrain = _world(plant, true)
	var plants: BiomePlants = await _grown(world)
	assert_gt(plants.count(), 50, "a kind at density 1 grows it over the map")
	for field: Node in plants.get_children():
		var multimesh: MultiMesh = (field as MultiMeshInstance3D).multimesh
		for index: int in multimesh.instance_count:
			var placed: Transform3D = multimesh.get_instance_transform(index)
			var surface: float = world.get_surface_height_at(placed.origin)
			assert_lt(absf(placed.origin.y - surface), 2.0, "on the ground at the surface")
			assert_between(placed.basis.y.length(), 0.99, 2.01, "within its heights")
	var count: int = plants.count()
	plants.grow()
	assert_eq(plants.count(), count, "the same seed grows the same plants")


func test_no_plant_stands_under_a_lake_unless_it_takes_the_water() -> void:
	var plant: PlantFeature = _plant()
	var world: OpenTerrain = _world(plant, true)
	# A seed with a hollow, in a climate that brims it.
	world.noise_seed = 43
	world.wetness_shift = 1.0
	var plants: BiomePlants = await _grown(world)
	var lakes: LakeMap = world._get_bake_density().lakes
	assert_gt(lakes.get_lake_count(), 0, "the wet map has lakes")
	var dry: int = plants.count()
	var under: int = 0
	for field: Node in plants.get_children():
		var multimesh: MultiMesh = (field as MultiMeshInstance3D).multimesh
		for index: int in multimesh.instance_count:
			var placed: Vector3 = multimesh.get_instance_transform(index).origin
			if lakes.level_at(placed.x, placed.z) > placed.y + 1.0:
				under += 1
	assert_eq(under, 0, "none a metre under a lake")
	plant.max_water_depth = 10.0
	plants.grow()
	assert_gt(plants.count(), dry, "more grow once the plant takes deep water")


func test_every_shape_builds_a_mesh_a_metre_tall() -> void:
	for shape: int in PlantFeature.Shape.values():
		var mesh: ArrayMesh = PlantMeshes.build(shape, Color(0.4, 0.6, 0.3))
		var box: AABB = mesh.get_aabb()
		var label: String = PlantFeature.Shape.keys()[shape]
		assert_gt(mesh.get_surface_count(), 0, label)
		assert_almost_eq(box.end.y, 1.0, 0.001, "%s: a metre tall" % label)
		assert_lt(box.position.y, 0.15, "%s: its foot at the ground" % label)
