extends GutTest
## The colony's ledger: food becomes an egg at six, one egg a day, never past the room dug for
## the colony, eggs hatch at dawn, a lost egg is gone, and the whole thing survives a save.

var _brood: ColonyBrood


func before_each() -> void:
	_brood = ColonyBrood.new()
	watch_signals(_brood)


func test_starts_with_nothing_and_the_founding_four_as_the_cap() -> void:
	assert_eq(_brood.food, 0)
	assert_eq(_brood.eggs, 0)
	assert_eq(_brood.capacity(), ColonyBrood.STARTING_WORKERS)
	assert_eq(_brood.text(), "Food 0  ·  Eggs 0")


func test_an_egg_costs_six_food() -> void:
	_brood.deliver(5)
	assert_false(_brood.lay(2), "five is not enough")
	assert_eq(_brood.food, 5, "nothing spent on a refusal")
	_brood.deliver(1)
	assert_true(_brood.lay(2))
	assert_eq(_brood.food, 0)
	assert_eq(_brood.eggs, 1)
	assert_signal_emitted(_brood, "changed")


func test_one_egg_a_day() -> void:
	_brood.deliver(ColonyBrood.FOOD_PER_EGG * 3)
	assert_true(_brood.lay(1))
	assert_false(_brood.lay(1), "the second egg waits for tomorrow")
	assert_eq(_brood.food, ColonyBrood.FOOD_PER_EGG * 2)
	_brood.dawn()
	assert_true(_brood.lay(2), "a new day, a new egg")


func test_the_colony_never_outgrows_its_room() -> void:
	_brood.deliver(ColonyBrood.FOOD_PER_EGG * 4)
	assert_false(_brood.lay(ColonyBrood.STARTING_WORKERS), "four workers fill the founding room")
	_brood.add_room(ColonyBrood.ROOM_PER_WORKER_M3 - 1.0)
	assert_eq(_brood.capacity(), ColonyBrood.STARTING_WORKERS, "not quite a worker's worth yet")
	_brood.add_room(1.0)
	assert_eq(_brood.capacity(), ColonyBrood.STARTING_WORKERS + 1)
	assert_true(_brood.lay(ColonyBrood.STARTING_WORKERS))
	_brood.dawn()
	assert_false(_brood.lay(ColonyBrood.STARTING_WORKERS + 1), "the hatched worker took the room")
	assert_true(_brood.lay(ColonyBrood.STARTING_WORKERS), "a dead worker's room is free again")


func test_eggs_hatch_at_dawn_and_a_lost_egg_does_not() -> void:
	_brood.deliver(ColonyBrood.FOOD_PER_EGG * 2)
	_brood.add_room(ColonyBrood.ROOM_PER_WORKER_M3 * 2.0)
	assert_true(_brood.lay(1))
	_brood.dawn()
	assert_true(_brood.lay(2))
	_brood.lose_egg()
	assert_eq(_brood.eggs, 0)
	assert_eq(_brood.dawn(), 0, "nothing left to hatch")
	_brood.lose_egg()
	assert_eq(_brood.eggs, 0, "never below zero")


func test_the_ledger_round_trips() -> void:
	_brood.deliver(9)
	_brood.add_room(85.0)
	_brood.lay(1)
	var copy: ColonyBrood = ColonyBrood.new()
	copy.import_state(_brood.export_state())
	assert_eq(copy.food, 3)
	assert_eq(copy.eggs, 1)
	assert_eq(copy.laid_today, 1)
	assert_almost_eq(copy.room_m3, 85.0, 0.001)
	assert_eq(copy.capacity(), ColonyBrood.STARTING_WORKERS + 2)
	assert_false(copy.lay(1), "the day's egg is already laid")
