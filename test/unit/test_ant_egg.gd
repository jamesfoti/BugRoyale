extends GutTest
## An egg on the chamber floor: on the colony's team, in its group, hurt like anything else,
## and gone when its health is.


func test_an_egg_stands_on_its_team_and_can_be_broken() -> void:
	var floor_node := Node3D.new()
	add_child_autofree(floor_node)
	var egg: AntEgg = AntEgg.spawn(floor_node, Vector3(1.0, -7.0, 2.0), Vector3.UP, 0)
	assert_true(egg.is_in_group(AntEgg.GROUP))
	assert_eq(egg.health.team, 0, "the colony's own shots never hurt it")
	assert_almost_eq(egg.health.max_health, AntEgg.MAX_HEALTH, 0.001)
	assert_true(egg.is_alive())
	assert_eq(egg.global_position, Vector3(1.0, -7.0, 2.0))
	watch_signals(egg.health)
	egg.health.apply_damage(AntEgg.MAX_HEALTH * 0.5)
	assert_true(egg.is_alive(), "one hit is not the end")
	egg.health.apply_damage(AntEgg.MAX_HEALTH)
	assert_false(egg.is_alive())
	assert_signal_emitted(egg.health, "died")
