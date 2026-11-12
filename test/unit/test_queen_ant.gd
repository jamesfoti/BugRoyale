extends GutTest
## The queen in her egg: it starts as a crowned egg with the queen's body hidden, set down for
## good it waits until the mode hatches it and she comes out (hatched, once), a dropped egg
## lies where it was put and cannot hatch, and only a hatched queen under earth mends.


func _queen() -> QueenAnt:
	var queen: QueenAnt = QueenAnt.spawn(self, Vector3(3.0, 1.0, -2.0), Vector3.UP, 0)
	autofree(queen)
	return queen


func test_she_starts_as_an_egg_wearing_a_crown() -> void:
	var queen: QueenAnt = _queen()
	assert_true(queen.is_egg())
	var egg: Node3D = queen.get_node("Egg")
	assert_true(egg.visible, "the egg shows")
	assert_not_null(egg.get_node_or_null("Crown"), "and it wears a crown")
	assert_false((queen.get_node("Body") as Node3D).visible, "the queen's body waits inside")


func test_a_set_down_egg_waits_until_it_is_hatched_and_hatches_once() -> void:
	var queen: QueenAnt = _queen()
	var hatched: Array[int] = [0]
	queen.hatched.connect(func() -> void: hatched[0] += 1)
	queen.place(Vector3(5.0, 0.0, 5.0))
	assert_eq(queen.state, QueenAnt.State.HATCHING)
	queen.fed = true
	queen._process(30.0)
	assert_eq(hatched[0], 0, "fed, it still waits for the dawn (the mode's word)")
	assert_true(queen.is_egg())
	queen.hatch()
	assert_eq(hatched[0], 1, "out of her egg")
	assert_eq(queen.state, QueenAnt.State.SETTLED)
	assert_false((queen.get_node("Egg") as Node3D).visible, "the shell is gone")
	assert_true((queen.get_node("Body") as Node3D).visible, "and the queen shows")
	assert_eq(queen.global_position, Vector3(5.0, 0.0, 5.0), "on the spot the egg was put")
	queen.hatch()
	assert_eq(hatched[0], 1, "she hatches once")


func test_a_dropped_egg_lies_where_it_was_put_and_does_not_hatch() -> void:
	var queen: QueenAnt = _queen()
	queen.set_down(Vector3(-4.0, 0.5, 2.0))
	queen.hatch()
	queen._process(1.0)
	assert_eq(queen.state, QueenAnt.State.DOWN, "only an egg set down for good hatches")
	assert_eq(queen.global_position, Vector3(-4.0, 0.5, 2.0))


func test_the_hatched_queen_mends_only_under_earth() -> void:
	var queen: QueenAnt = _queen()
	queen.rest_at(Vector3.ZERO)
	queen.health.health = 50.0
	queen._process(1.0)
	assert_eq(queen.health.health, 50.0, "in the open she does not mend")
	queen.sheltered = true
	queen._process(1.0)
	assert_almost_eq(queen.health.health, 50.0 + QueenAnt.MEND_PER_SECOND, 0.001)
