extends GutTest
## Worlds on disk: a save comes back whole (voxel keys included), its seed and summary read
## back, deleting removes it, and nothing is written while saving is off.

const MODE: String = "test_world"
const MAP: String = "unit"


func before_each() -> void:
	WorldSave.enabled = true
	WorldSave.delete(MODE, MAP)


func after_each() -> void:
	WorldSave.enabled = true
	WorldSave.delete(MODE, MAP)


func _terrain_state() -> Dictionary:
	return {
		"next_sequence": 4,
		"edits":
		{
			"overrides": {Vector3i(1, 2, 3): -0.5, Vector3i(-4, 0, 9): 0.25},
			"materials": {Vector3i(1, 2, 3): 2},
		},
	}


func test_a_world_round_trips() -> void:
	var mode_state: Dictionary = {"home": Vector3(1, 2, 3), "nights": 3, "stock": {1: 12}}
	assert_true(WorldSave.save(MODE, MAP, 4242, _terrain_state(), mode_state, "Day 4"))
	assert_true(WorldSave.exists(MODE, MAP))
	var loaded: Dictionary = WorldSave.load_world(MODE, MAP)
	assert_eq(loaded["terrain"], _terrain_state(), "voxel keys and densities come back exact")
	assert_eq(loaded["mode"], mode_state)
	assert_eq(WorldSave.saved_seed(MODE, MAP), 4242)
	assert_eq(WorldSave.summary(MODE, MAP), "Day 4")


func test_no_save_means_no_world() -> void:
	assert_false(WorldSave.exists(MODE, MAP))
	assert_eq(WorldSave.load_world(MODE, MAP), {})
	assert_eq(WorldSave.saved_seed(MODE, MAP), 0)
	assert_eq(WorldSave.summary(MODE, MAP), "")


func test_a_newer_save_overwrites() -> void:
	WorldSave.save(MODE, MAP, 1, {}, {"nights": 1}, "Day 2")
	WorldSave.save(MODE, MAP, 1, {}, {"nights": 2}, "Day 3")
	assert_eq(WorldSave.load_world(MODE, MAP)["mode"]["nights"], 2)


func test_delete_removes_it() -> void:
	WorldSave.save(MODE, MAP, 1, {}, {}, "")
	WorldSave.delete(MODE, MAP)
	assert_false(WorldSave.exists(MODE, MAP))


func test_nothing_is_written_while_disabled() -> void:
	WorldSave.enabled = false
	assert_false(WorldSave.save(MODE, MAP, 1, {}, {}, ""))
	assert_false(WorldSave.exists(MODE, MAP))
	WorldSave.enabled = true
	assert_false(WorldSave.exists(MODE, MAP), "the disabled save left no file behind")
