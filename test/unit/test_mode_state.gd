extends GutTest
## Every mode's state snapshot must survive a round trip onto a fresh mode: that snapshot is
## what a client will show the match from. Modes are instantiated outside the tree so none of
## them starts a match.

const MODE_SCRIPTS: Dictionary = {
	"ants_vs_ants": "res://modes/ants_vs_ants.gd",
	"hornets": "res://modes/attack_of_the_hornets.gd",
	"battle_royale": "res://modes/battle_royale.gd",
	"cordyceps_royale": "res://modes/cordyceps_royale.gd",
	"explore": "res://modes/explore.gd",
}

## A state per mode that exercises every field the mode snapshots.
const SAMPLE_STATES: Dictionary = {
	"ants_vs_ants": {"scores": [3, 5]},
	"hornets":
	{"wave": 4, "hornets_killed": 27, "hornets_left": 9, "in_break": false, "break_time_left": 2.5},
	"battle_royale": {"stage": 2, "stage_time": 7.5},
	"cordyceps_royale":
	{
		"stage": 1,
		"stage_time": 12.25,
		"infection": {1: 0.4, 2: 1.0, 5: 0.0},
		"turned_humans": {2: true},
		"turned_count": 3,
	},
	"explore": {"map_name": "Fish Bowl"},
}


func _new_mode(mode_id: String) -> GameMode:
	var mode: GameMode = (load(MODE_SCRIPTS[mode_id]) as Script).new() as GameMode
	autofree(mode)
	return mode


func test_every_catalog_mode_has_a_test_state() -> void:
	for mode_id: String in ModeCatalog.MODES.keys():
		assert_true(SAMPLE_STATES.has(mode_id), "mode '%s' needs a sample state here" % mode_id)
		assert_true(MODE_SCRIPTS.has(mode_id), "mode '%s' needs its script listed here" % mode_id)


func test_state_round_trips_onto_a_fresh_mode() -> void:
	for mode_id: String in MODE_SCRIPTS.keys():
		var source: GameMode = _new_mode(mode_id)
		source.apply_state(SAMPLE_STATES[mode_id])
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
		mode.apply_state(SAMPLE_STATES[mode_id])
		var snapshot: Dictionary = mode.snapshot_state()
		for key: String in SAMPLE_STATES[mode_id].keys():
			assert_eq(
				snapshot[key],
				SAMPLE_STATES[mode_id][key],
				"%s: '%s' is in the snapshot" % [mode_id, key]
			)


func test_base_fields_are_always_present() -> void:
	for mode_id: String in MODE_SCRIPTS.keys():
		var snapshot: Dictionary = _new_mode(mode_id).snapshot_state()
		assert_has(snapshot, "over", "%s snapshots whether the match is over" % mode_id)
		assert_has(snapshot, "end_title", mode_id)
		assert_has(snapshot, "end_subtitle", mode_id)
		assert_false(snapshot["over"], "%s: a fresh mode is not over" % mode_id)


func test_applying_a_partial_state_keeps_the_rest() -> void:
	var mode: GameMode = _new_mode("hornets")
	mode.apply_state(SAMPLE_STATES["hornets"])
	mode.apply_state({"wave": 9})
	var snapshot: Dictionary = mode.snapshot_state()
	assert_eq(snapshot["wave"], 9)
	assert_eq(snapshot["hornets_killed"], 27, "fields the partial state did not mention are kept")


func test_status_text_reads_from_state_alone() -> void:
	# Modes whose status needs no map: the line must reflect the applied state.
	var ants: GameMode = _new_mode("ants_vs_ants")
	ants.apply_state(SAMPLE_STATES["ants_vs_ants"])
	assert_string_contains(ants._status_text(), "Red 3")
	assert_string_contains(ants._status_text(), "5 Black")

	var explore: GameMode = _new_mode("explore")
	explore.apply_state(SAMPLE_STATES["explore"])
	assert_string_contains(explore._status_text(), "Fish Bowl")
