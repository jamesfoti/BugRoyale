class_name WorldSave
extends RefCounted
## A persistent world on disk: the terrain's edited voxels and a mode's own state for one map,
## under user://worlds/<mode>_<map>.save, so a burrow dug today is there tomorrow. The terrain
## seed goes with it: the loading screen rolls fresh ground for every match, and a saved world
## has to come back on the ground it was dug in. The whole file is one serialised dictionary
## (FileAccess.store_var, objects refused), small enough to read for its summary line.

const DIRECTORY: String = "user://worlds"
const VERSION: int = 1

## Off, nothing is written or read: headless smoke runs must not touch the player's worlds.
static var enabled: bool = true


static func path_for(mode_id: String, map_id: String) -> String:
	return "%s/%s_%s.save" % [DIRECTORY, mode_id, map_id]


static func exists(mode_id: String, map_id: String) -> bool:
	return enabled and FileAccess.file_exists(path_for(mode_id, map_id))


## Writes a world: the terrain's edit state (ChunkedTerrainWorld.export_edit_state), the mode's
## state, the seed the ground was built from and a line for the menu. False when it could not.
static func save(
	mode_id: String,
	map_id: String,
	terrain_seed: int,
	terrain_state: Dictionary,
	mode_state: Dictionary,
	summary: String
) -> bool:
	if not enabled:
		return false
	var user_dir: DirAccess = DirAccess.open("user://")
	if user_dir == null:
		return false
	user_dir.make_dir_recursive(DIRECTORY.trim_prefix("user://"))
	var file: FileAccess = FileAccess.open(path_for(mode_id, map_id), FileAccess.WRITE)
	if file == null:
		push_warning("[WorldSave] Could not write %s" % path_for(mode_id, map_id))
		return false
	(
		file
		. store_var(
			{
				"version": VERSION,
				"seed": terrain_seed,
				"saved_at": int(Time.get_unix_time_from_system()),
				"summary": summary,
				"terrain": terrain_state,
				"mode": mode_state,
			},
			false
		)
	)
	return true


## The saved world, or {} when there is none (or it is from another version of the format).
static func load_world(mode_id: String, map_id: String) -> Dictionary:
	if not exists(mode_id, map_id):
		return {}
	var file: FileAccess = FileAccess.open(path_for(mode_id, map_id), FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = file.get_var(false)
	if not data is Dictionary or int((data as Dictionary).get("version", 0)) != VERSION:
		return {}
	return data


## The seed a saved world's ground was built from (0 when there is no save).
static func saved_seed(mode_id: String, map_id: String) -> int:
	return int(load_world(mode_id, map_id).get("seed", 0))


## The saved world's line for the menu ("" when there is no save).
static func summary(mode_id: String, map_id: String) -> String:
	return str(load_world(mode_id, map_id).get("summary", ""))


static func delete(mode_id: String, map_id: String) -> void:
	if exists(mode_id, map_id):
		DirAccess.remove_absolute(path_for(mode_id, map_id))
