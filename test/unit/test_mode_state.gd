extends GutTest
## Every mode's state snapshot must survive a round trip onto a fresh mode: that snapshot is
## what a client will show the match from. Modes are instantiated outside the tree so none of
## them starts a match. The catalog's formats and maps are checked for agreement too.

const MODE_SCRIPTS: Dictionary = {
	"hold_out": "res://modes/hold_out.gd",
	"forage": "res://modes/forage.gd",
	"slayer": "res://modes/slayer.gd",
	"capture_the_egg": "res://modes/capture_the_egg.gd",
	"king_of_the_anthill": "res://modes/king_of_the_anthill.gd",
	"cordyceps_royale": "res://modes/cordyceps_royale.gd",
	"burrow": "res://modes/burrow.gd",
}

## The fields every competitive (ColonyMatch) mode snapshots, and the zone modes' extras.
const COLONY_STATE: Dictionary = {
	"scores": {0: 3, 1: 5}, "time_left": 100.0, "teams": 2, "score_limit": 40
}
const ZONE_STATE: Dictionary = {
	"zone_owners": [0, -1, 1],
	"zone_points": [Vector3(1, 0, 2), Vector3(5, 0, 5), Vector3(9, 1, 0)],
}
const ZONE_MODES: Array = ["king_of_the_anthill"]

## A state per mode that exercises every field the mode snapshots (colony and zone fields are
## merged in by _sample).
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
	"forage":
	{
		"phase": 1,
		"banked": 2,
		"carried": {1: 3, 2: 0, 3: 1},
		"noise": 37.5,
		"hordes": 2,
		"time_left": 200.0,
		"window_left": 0.0,
		"aboard": [2],
		"landing_zone": Vector3(1, 2, 3),
		"extraction": Vector3(10, 2, -4),
	},
	"slayer": {},
	"capture_the_egg": {"eggs_taken": [false, true]},
	"king_of_the_anthill": {"hill_timer": 12.5},
	"cordyceps_royale":
	{
		"stage": 1,
		"stage_time": 12.25,
		"infection": {1: 0.4, 2: 1.0, 5: 0.0},
		"turned_humans": {2: true},
		"turned_count": 3,
	},
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
		"queen_position": Vector3(4, -5, 6),
		"queen_state": 3,
		"queen_health": 120.0,
		"queen_carry": 0,
		"workers_alive": 3,
	},
}


func _new_mode(mode_id: String) -> GameMode:
	var mode: GameMode = (load(MODE_SCRIPTS[mode_id]) as Script).new() as GameMode
	autofree(mode)
	return mode


## The sample state of a mode, with the colony and zone fields filled in where they apply.
func _sample(mode_id: String) -> Dictionary:
	var state: Dictionary = (SAMPLE_STATES[mode_id] as Dictionary).duplicate()
	var mode: GameMode = _new_mode(mode_id)
	if mode is ColonyMatch and not state.has("scores"):
		state.merge(COLONY_STATE)
	if ZONE_MODES.has(mode_id):
		state.merge(ZONE_STATE)
	return state


func test_every_catalog_mode_has_a_test_state() -> void:
	for mode_id: String in ModeCatalog.MODES.keys():
		assert_true(SAMPLE_STATES.has(mode_id), "mode '%s' needs a sample state here" % mode_id)
		assert_true(MODE_SCRIPTS.has(mode_id), "mode '%s' needs its script listed here" % mode_id)


func test_state_round_trips_onto_a_fresh_mode() -> void:
	for mode_id: String in MODE_SCRIPTS.keys():
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
	for mode_id: String in MODE_SCRIPTS.keys():
		var mode: GameMode = _new_mode(mode_id)
		var sample: Dictionary = _sample(mode_id)
		mode.apply_state(sample)
		var snapshot: Dictionary = mode.snapshot_state()
		for key: String in sample.keys():
			assert_eq(snapshot[key], sample[key], "%s: '%s' is in the snapshot" % [mode_id, key])


func test_base_fields_are_always_present() -> void:
	for mode_id: String in MODE_SCRIPTS.keys():
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
	burrow.apply_state({"time": 100.0})
	assert_string_contains(burrow._status_text(), "Day 3")
	assert_string_contains(burrow._status_text(), "Dirt 12, Stone 3")
	assert_string_contains(burrow._status_text(), "Workers 3/4")
	burrow.apply_state({"founded": false, "queen_carry": 1, "queen_health": 80.0})
	assert_string_contains(burrow._status_text(), "The workers carry the queen")
	assert_string_contains(burrow._status_text(), "Queen 50%")
	burrow.apply_state({"queen_carry": 2})
	assert_string_contains(burrow._status_text(), "You carry the queen")

	var forage: GameMode = _new_mode("forage")
	forage.apply_state(SAMPLE_STATES["forage"])
	assert_string_contains(forage._status_text(), "Materials 6/10", "banked plus carried")
	assert_string_contains(forage._status_text(), "3:20")


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


func test_shelved_modes_still_load_by_id() -> void:
	for mode_id: String in ModeCatalog.MODES.keys():
		if bool(ModeCatalog.mode(mode_id).get("shelved", false)):
			assert_false(
				ModeCatalog.map_scene(ModeCatalog.maps_for(mode_id, "").front()).is_empty()
			)
			assert_not_null(_new_mode(mode_id), mode_id)
