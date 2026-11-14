extends GutTest
## Termite mounds: a land kind with a mounds share raises them in its patches and no other kind
## does; they stand inside the map, the same for the same seed; each is earth round a hollow
## middle (a spire's chimney, a dome's heart) over an open nest under the ground; and the
## build lays them down above the ground (the chunks up there are not skipped as sky).

const SEED: int = 42


func _world(kind_path: String) -> OpenTerrain:
	var world := OpenTerrain.new()
	world.rebuild_on_ready = false
	world.chunks_x = 6
	world.chunks_y = 3
	world.chunks_z = 6
	world.chunk_size = 32.0
	world.voxel_size = 2.0
	world.surface_layer = 2
	world.noise_seed = SEED
	world.caves_enabled = false
	world.solid_underside = true
	world.boxed_edges_enabled = false
	world.land_biomes = [load(kind_path)]
	add_child_autofree(world)
	return world


func _mounds(world: OpenTerrain) -> Array:
	var extents: Vector3 = world.get_world_extents()
	var density: WorldDensity = world._get_bake_density()
	return density.termite_mounds_in(AABB(world.global_position - extents * 0.5, extents))


func test_mounds_stand_only_where_a_kind_raises_them_inside_the_map() -> void:
	assert_eq(_mounds(_world("res://biomes/land_meadow.tres")).size(), 0, "meadow raises none")
	var world: OpenTerrain = _world("res://biomes/land_termite.tres")
	var mounds: Array = _mounds(world)
	assert_gt(mounds.size(), 0, "termite ground raises mounds")
	var half: Vector3 = world.get_world_extents() * 0.5
	for mound: Dictionary in mounds:
		var base: Vector3 = mound.base
		assert_lt(absf(base.x), half.x - mound.radius, "inside the map across")
		assert_lt(absf(base.z), half.z - mound.radius, "and along")
	assert_eq(_mounds(_world("res://biomes/land_termite.tres")), mounds, "the same seed, the same")


func test_a_mound_is_earth_round_a_hollow_middle_over_an_open_nest() -> void:
	var world: OpenTerrain = _world("res://biomes/land_termite.tres")
	var mounds: Array = _mounds(world)
	assert_gt(mounds.size(), 0)
	for mound: Dictionary in mounds:
		var base: Vector3 = mound.base
		var height: float = mound.height
		var lean: Vector2 = mound.lean
		var middle := base + Vector3(lean.x * 0.25, height * 0.5, lean.y * 0.25)
		var reach: float = mound.radius * (0.45 if mound.spire else 0.8)
		var label: String = "spire" if mound.spire else "dome"
		assert_false(world.is_solid_at(middle), "%s: hollow halfway up" % label)
		assert_true(
			world.is_solid_at(middle + Vector3(reach, 0.0, 0.0)), "%s: earth round it" % label
		)
		var over_top := base + Vector3(lean.x, height + 4.0, lean.y)
		assert_false(world.is_solid_at(over_top), "%s: open air over its top" % label)
		var nest: Vector3 = mound.nest
		assert_lt(nest.y, base.y - 6.0, "%s: the nest lies under the ground" % label)
		assert_false(world.is_solid_at(nest), "%s: the shaft opens into the nest" % label)
		var under: Vector3 = nest - Vector3(0.0, mound.nest_radius * 0.55 + 4.0, 0.0)
		assert_true(world.is_solid_at(under), "%s: solid ground under the nest" % label)


func test_the_build_lays_a_mound_down_above_the_ground() -> void:
	var world: OpenTerrain = _world("res://biomes/land_termite.tres")
	world.rebuild_all()
	await wait_physics_frames(3)
	var tallest: Dictionary = {}
	for mound: Dictionary in _mounds(world):
		if tallest.is_empty() or mound.height > tallest.height:
			tallest = mound
	var base: Vector3 = tallest.base
	var lean: Vector2 = tallest.lean
	# Straight down onto the shoulder of the mound, off its hollow middle.
	var shoulder := base + Vector3(lean.x * 0.1 + tallest.radius * 0.5, 0.0, lean.y * 0.1)
	var query := PhysicsRayQueryParameters3D.create(
		shoulder + Vector3.UP * 80.0, shoulder - Vector3.UP * 20.0, MapInfo.TERRAIN_LAYER
	)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
	assert_false(hit.is_empty(), "the built ground is there")
	var ground: float = world.get_surface_height_at(shoulder)
	assert_gt(hit.position.y, ground + 3.0, "the mound stands above the ground, built")
