extends GutTest
## A biome's creatures (BiomeCreatures, CreatureBrain): termites come out in groups round the feet
## of the termite mounds of the biomes that list them, on a map whose terrain lists them, and
## nowhere else; they are on the creatures' team and no bot hunts them; a hit turns the one hurt
## and its kin near it on the attacker, and the rest stay calm.

const SEED: int = 42


func _world(termites_on_map: bool) -> OpenTerrain:
	var mounds: TermiteMoundFeature = load("res://features/termite_mounds.tres")
	var termites: CreatureFeature = load("res://features/termites.tres")
	var mound_entry := BiomeFeatureEntry.new()
	mound_entry.feature = mounds
	mound_entry.density = 0.7
	var termite_entry := BiomeFeatureEntry.new()
	termite_entry.feature = termites
	termite_entry.density = 1.0
	var kind := Biome.new()
	kind.features = [mound_entry, termite_entry]
	var world := OpenTerrain.new()
	world.name = "TerrainWorld"
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
	world.land_biomes = [kind]
	world.biome_features = [mounds, termites] if termites_on_map else [mounds]
	add_child_autoqfree(world)
	return world


func _creatures(world: OpenTerrain) -> BiomeCreatures:
	var creatures := BiomeCreatures.new()
	creatures.terrain = world
	# Queued, not freed at once: the bodies' lights have deferred calls in flight.
	add_child_autoqfree(creatures)
	creatures.spawn()
	return creatures


func _mound_feet(world: OpenTerrain) -> Array[Vector3]:
	var extents: Vector3 = world.get_world_extents()
	var area := AABB(world.global_position - extents * 0.5, extents)
	var out: Array[Vector3] = []
	for mound: Dictionary in world._get_bake_density().termite_mounds_in(area):
		out.append(mound.base)
	return out


func _flat_distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x - second.x, first.z - second.z).length()


func test_termites_come_out_round_the_mounds_only_where_listed() -> void:
	var calm_world: OpenTerrain = _world(false)
	var none: BiomeCreatures = _creatures(calm_world)
	assert_eq(none.bodies().size(), 0, "a map that does not list termites has none")
	none.free()
	calm_world.free()

	var world: OpenTerrain = _world(true)
	var feet: Array[Vector3] = _mound_feet(world)
	assert_gt(feet.size(), 0)
	var creatures: BiomeCreatures = _creatures(world)
	var bodies: Array[FighterBody] = creatures.bodies()
	assert_between(bodies.size(), 2, 30, "a group at each mound, up to the cap")
	for body: FighterBody in bodies:
		var nearest: float = INF
		for foot: Vector3 in feet:
			nearest = minf(nearest, _flat_distance(body.global_position, foot))
		assert_lt(nearest, 21.0, "out round a mound's foot")
		assert_true(body.is_in_group(CreatureFeature.GROUP))
		assert_eq(Damageable.team_of(body), CreatureFeature.TEAM)
		assert_true(body.controller is CreatureBrain)


func test_no_bot_hunts_them() -> void:
	var creatures: BiomeCreatures = _creatures(_world(true))
	var bodies: Array[FighterBody] = creatures.bodies()
	assert_gt(bodies.size(), 0)
	var found: Node3D = FighterRegistry.nearest_enemy(
		get_tree(), bodies[0].global_position, 0, [&"fighter"], 500.0, null
	)
	assert_null(found, "the registry leaves the creatures out")


func test_a_hit_turns_the_one_hurt_and_its_kin_on_the_attacker() -> void:
	var creatures: BiomeCreatures = _creatures(_world(true))
	var bodies: Array[FighterBody] = creatures.bodies()
	assert_gt(bodies.size(), 1)
	var hurt: FighterBody = bodies[0]
	var attacker := Node3D.new()
	var attacker_health := Damageable.new()
	attacker_health.name = "Damageable"
	attacker_health.team = 3
	attacker.add_child(attacker_health)
	add_child_autofree(attacker)
	attacker.global_position = hurt.global_position + Vector3(4.0, 0.0, 0.0)
	var hurt_health: Damageable = hurt.get_node("Damageable")
	assert_true(hurt_health.apply_damage(5.0, attacker))
	var hurt_brain: CreatureBrain = hurt.controller
	assert_eq(hurt_brain.attacker(), attacker, "the one hurt turns on the attacker")
	assert_eq(hurt_brain._find_target(), attacker, "and hunts it")
	var called: int = 0
	for body: FighterBody in bodies:
		if body == hurt:
			continue
		var brain: CreatureBrain = body.controller
		var near: bool = (
			body.global_position.distance_to(hurt.global_position) <= hurt_brain.call_radius
		)
		if near:
			called += 1
			assert_eq(brain.attacker(), attacker, "kin near it join in")
		else:
			assert_null(brain.attacker(), "kin far off stay calm")
	assert_gt(called, 0, "its group is near it")


func test_kin_never_hurt_each_other() -> void:
	var creatures: BiomeCreatures = _creatures(_world(true))
	var bodies: Array[FighterBody] = creatures.bodies()
	assert_gt(bodies.size(), 1)
	var health: Damageable = bodies[0].get_node("Damageable")
	assert_false(health.apply_damage(5.0, bodies[1]), "a bite from kin does nothing")
	assert_null((bodies[0].controller as CreatureBrain).attacker())
