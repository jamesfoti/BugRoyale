extends GutTest
## Every mode's state snapshot must survive a round trip onto a fresh mode: that snapshot is
## what a client will show the match from. Modes are instantiated outside the tree so none of
## them starts a match. The catalog's formats and maps are checked for agreement too.

const MODE_SCENES: Dictionary = {
	"hold_out": "res://modes/hold_out.tscn",
	"slayer": "res://modes/slayer.tscn",
	"burrow": "res://modes/burrow.tscn",
}

## The fields every competitive (ColonyMatch) mode snapshots.
const COLONY_STATE: Dictionary = {
	"scores": {0: 3, 1: 5}, "time_left": 100.0, "teams": 2, "score_limit": 40
}

## A state per mode that exercises every field the mode snapshots (colony fields are merged in
## by _sample).
const SAMPLE_STATES: Dictionary = {
	"hold_out":
	{
		"wave": 3,
		"swatted": 40,
		"in_build": true,
		"build_time_left": 12.0,
		"enemies_left": 0,
		"stock": {1: 12, 2: 3},
		"fort": Vector3(1, 2, 3),
		"approaches": [Vector3(30, 2, 0), Vector3(-20, 1, 25)],
	},
	"slayer": {},
	"burrow":
	{
		"home": Vector3(1, 2, 3),
		"founded": true,
		"stock": {1: 12, 2: 3},
		"nights": 2,
		"deaths": 1,
		"swatted": 7,
		"husks_down": 3,
		"time": 320.0,
		"play_seconds": 900.0,
		"husks_left": 2,
		"hornets_left": 5,
		"raiders_left": 4,
		"spiders_left": 0,
		"queen_position": Vector3(4, -5, 6),
		"queen_state": 3,
		"queen_health": 120.0,
		"queen_carry": 0,
		"workers_alive": 3,
		"brood": {"food": 4, "eggs": 1, "laid_today": 1, "room_m3": 50.0},
		"carried": {1: 2},
	},
}


func _new_mode(mode_id: String) -> GameMode:
	var mode: GameMode = (load(MODE_SCENES[mode_id]) as PackedScene).instantiate() as GameMode
	autofree(mode)
	return mode


## The sample state of a mode, with the colony fields filled in where they apply.
func _sample(mode_id: String) -> Dictionary:
	var state: Dictionary = (SAMPLE_STATES[mode_id] as Dictionary).duplicate()
	var mode: GameMode = _new_mode(mode_id)
	if mode is ColonyMatch and not state.has("scores"):
		state.merge(COLONY_STATE)
	return state


func test_every_catalog_mode_has_a_test_state() -> void:
	for mode_id: String in ModeCatalog.MODES.keys():
		assert_true(SAMPLE_STATES.has(mode_id), "mode '%s' needs a sample state here" % mode_id)
		assert_true(MODE_SCENES.has(mode_id), "mode '%s' needs its scene listed here" % mode_id)


func test_state_round_trips_onto_a_fresh_mode() -> void:
	for mode_id: String in MODE_SCENES.keys():
		var source: GameMode = _new_mode(mode_id)
		source.apply_state(_sample(mode_id))
		var snapshot: Dictionary = source.snapshot_state()

		var target: GameMode = _new_mode(mode_id)
		target.apply_state(snapshot)
		assert_eq(
			target.snapshot_state(),
			snapshot,
			"%s: the snapshot is stable across a round trip" % mode_id
		)


func test_sample_fields_come_back_out_of_the_snapshot() -> void:
	for mode_id: String in MODE_SCENES.keys():
		var mode: GameMode = _new_mode(mode_id)
		var sample: Dictionary = _sample(mode_id)
		mode.apply_state(sample)
		var snapshot: Dictionary = mode.snapshot_state()
		for key: String in sample.keys():
			assert_eq(snapshot[key], sample[key], "%s: '%s' is in the snapshot" % [mode_id, key])


func test_base_fields_are_always_present() -> void:
	for mode_id: String in MODE_SCENES.keys():
		var snapshot: Dictionary = _new_mode(mode_id).snapshot_state()
		assert_has(snapshot, "over", "%s snapshots whether the match is over" % mode_id)
		assert_has(snapshot, "end_title", mode_id)
		assert_has(snapshot, "end_subtitle", mode_id)
		assert_false(snapshot["over"], "%s: a fresh mode is not over" % mode_id)


func test_applying_a_partial_state_keeps_the_rest() -> void:
	var mode: GameMode = _new_mode("hold_out")
	mode.apply_state(SAMPLE_STATES["hold_out"])
	mode.apply_state({"wave": 9})
	var snapshot: Dictionary = mode.snapshot_state()
	assert_eq(snapshot["wave"], 9)
	assert_eq(snapshot["swatted"], 40, "fields the partial state did not mention are kept")


func test_status_text_reads_from_state_alone() -> void:
	# Modes whose status needs no map: the line must reflect the applied state.
	var slayer: GameMode = _new_mode("slayer")
	slayer.apply_state(COLONY_STATE)
	assert_string_contains(slayer._status_text(), "Red 3")
	assert_string_contains(slayer._status_text(), "5 Black")
	assert_string_contains(slayer._status_text(), "First to 40")
	assert_string_contains(slayer._status_text(), "1:40")

	var burrow: GameMode = _new_mode("burrow")
	burrow.apply_state(SAMPLE_STATES["burrow"])
	assert_string_contains(burrow._status_text(), "Night 3", "two nights survived, in the third")
	assert_string_contains(burrow._status_text(), "2:40 to dawn", "320 s into a 480 s cycle")
	assert_string_contains(burrow._status_text(), "Husks 2")
	assert_string_contains(burrow._status_text(), "Raiders 4")
	burrow.apply_state({"time": 100.0, "spiders_left": 2})
	assert_string_contains(burrow._status_text(), "Spiders 2")
	assert_string_contains(burrow._status_text(), "Hornets 5", "hornets hunt by day too")
	assert_string_contains(burrow._status_text(), "Day 3")
	assert_string_contains(burrow._status_text(), "Dirt 12, Stone 3")
	assert_string_contains(burrow._status_text(), "Food 4  ·  Eggs 1")
	assert_string_contains(burrow._status_text(), "Workers 3/5", "room for one more than four")
	burrow.apply_state({"queen_state": 2, "brood": {"food": 4}})
	assert_string_contains(burrow._status_text(), "Queen's egg fed 4/6", "set down, being fed")
	burrow.apply_state({"brood": {"food": 7}})
	assert_string_contains(burrow._status_text(), "Queen's egg fed 6/6: hatches at dawn")
	burrow.apply_state({"founded": false, "queen_carry": 1, "queen_health": 80.0})
	assert_string_contains(burrow._status_text(), "You carry the queen's egg")
	assert_string_contains(burrow._status_text(), "Egg 50%")
	burrow.apply_state({"queen_carry": 0})
	assert_string_contains(burrow._status_text(), "The queen's egg is down")


func test_burrow_hatches_the_queens_egg_at_dawn_only_once_it_is_fed() -> void:
	var burrow: GameMode = _new_mode("burrow")
	burrow.hud = ModeHud.new()
	add_child_autofree(burrow.hud)
	var queen: QueenAnt = QueenAnt.spawn(self, Vector3.ZERO, Vector3.UP, 0)
	autofree(queen)
	queen.place(Vector3.ZERO)
	burrow.queen = queen
	burrow.brood.deliver(ColonyBrood.QUEEN_FOOD - 2)
	burrow._dawn_on_the_egg()
	assert_true(queen.is_egg(), "short of its food, the egg waits another day")
	assert_eq(burrow.brood.food, ColonyBrood.QUEEN_FOOD - 2, "and keeps what it was brought")
	burrow.brood.deliver(3)
	burrow._dawn_on_the_egg()
	assert_false(queen.is_egg(), "fed, it hatches at dawn")
	assert_eq(burrow.brood.food, 1, "spending six; the rest is for her first egg")
	assert_eq(burrow.brood.eggs, 0, "no free eggs: she lays from food, one a day")


func test_catalog_formats_and_maps_agree() -> void:
	for mode_id: String in ModeCatalog.MODES.keys():
		var formats: Array = ModeCatalog.formats_for(mode_id)
		for format_id: String in formats:
			assert_true(
				ModeCatalog.FORMATS.has(format_id), "%s: unknown format %s" % [mode_id, format_id]
			)
			assert_false(
				ModeCatalog.maps_for(mode_id, format_id).is_empty(),
				"%s in %s has no map big enough" % [mode_id, format_id]
			)
		if not formats.is_empty():
			assert_true(formats.has(ModeCatalog.default_format(mode_id)), mode_id)


func test_the_front_door_is_burrow_hold_out_and_slayer_in_that_order() -> void:
	assert_eq(ModeCatalog.front_door(), ["burrow", "hold_out", "slayer"])
