extends CanvasLayer
## Autoload: the in-game bug reporter, opened from the pause menu (Report a bug; no hot key,
## since F9 is the editor's own suspend key and pressed over a running game froze it). It
## freezes the game over the frame the player was looking at, asks what happened, and saves
## a report folder under user://bug_reports/:
## that frame as a PNG, a JSON with everything a player would otherwise have to remember to
## write down (version, map, mode, seed, where they stood, the mode's status line, frame
## times, the last terrain edits) and the tail of the engine log. "Open folder" shows the
## folder so the report can be attached to an issue or a message. Esc closes it.

## The form went away (saved or not); the pause menu puts itself back.
signal closed

const REPORTS_DIR: String = "user://bug_reports"
const ENGINE_LOG: String = "user://logs/godot.log"
## Lines kept from the end of the engine log, and edits kept from the end of the edit log
## (the whole log in practice: with it and the seed the ground can be rebuilt as it was).
const LOG_TAIL_LINES: int = 200
const EDIT_TAIL: int = 20000

var _open: bool = false
var _screenshot: Image
var _data: Dictionary = {}
var _was_paused: bool = false
var _mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _last_report_dir: String = ""

@onready var _description: TextEdit = $Panel/Margin/Column/Description
@onready var _context: Label = $Panel/Margin/Column/Context
@onready var _saved: Label = $Panel/Margin/Column/Saved
@onready var _save_button: Button = $Panel/Margin/Column/Buttons/SaveButton
@onready var _open_folder_button: Button = $Panel/Margin/Column/Buttons/OpenFolderButton
@onready var _close_button: Button = $Panel/Margin/Column/Buttons/CloseButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_save_button.pressed.connect(_on_save_pressed)
	_open_folder_button.pressed.connect(_on_open_folder_pressed)
	_close_button.pressed.connect(close)


## Before the GUI sees the key, so Esc closes this and not the pause menu underneath.
## Everything else falls through to the text box.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if _open and (event as InputEventKey).keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


## Freezes the game and shows the form. The screenshot is the frame as the player saw it:
## taken after the next draw, before the overlay goes up.
func open() -> void:
	if _open:
		return
	_open = true
	_was_paused = get_tree().paused
	_mouse_mode = Input.mouse_mode
	await RenderingServer.frame_post_draw
	_screenshot = get_viewport().get_texture().get_image()
	_data = collect_context()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_description.text = ""
	_saved.text = ""
	_open_folder_button.disabled = true
	_save_button.disabled = false
	_context.text = _summary(_data)
	visible = true
	_description.grab_focus()


func close() -> void:
	if not _open:
		return
	visible = false
	get_tree().paused = _was_paused
	Input.mouse_mode = _mouse_mode
	_screenshot = null
	_data = {}
	_open = false
	closed.emit()


## Writes the report folder and returns its path (empty when nothing could be written).
func save_report(description: String) -> String:
	var stamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(
		" ", "_"
	)
	var folder: String = "%s/%s" % [REPORTS_DIR, stamp]
	var user_dir: DirAccess = DirAccess.open("user://")
	if user_dir == null or user_dir.make_dir_recursive(folder) != OK:
		push_warning("[BugReporter] Could not create %s" % folder)
		return ""
	if _screenshot != null:
		_screenshot.save_png(folder + "/screenshot.png")
	var data: Dictionary = _data if not _data.is_empty() else collect_context()
	data["description"] = description.strip_edges()
	var report: FileAccess = FileAccess.open(folder + "/report.json", FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify(_jsonable(data), "\t"))
		report.close()
	_write_log_tail(folder + "/log.txt")
	_last_report_dir = folder
	print("[BugReporter] Saved %s" % ProjectSettings.globalize_path(folder))
	return folder


## Everything about the moment worth attaching, as plain data.
func collect_context() -> Dictionary:
	var scene: Node = get_tree().current_scene
	var scene_path: String = scene.scene_file_path if scene != null else ""
	var version_info: Dictionary = Engine.get_version_info()
	return {
		"written_at": Time.get_datetime_string_from_system(false, true),
		"game":
		{
			"version": str(ProjectSettings.get_setting("application/config/version", "")),
			"godot": str(version_info.get("string", "")),
			"os": OS.get_name(),
			"gpu": RenderingServer.get_video_adapter_name(),
			"renderer": RenderingServer.get_current_rendering_method(),
			"window": str(DisplayServer.window_get_size()),
			"uptime_s": snappedf(Time.get_ticks_msec() / 1000.0, 0.1),
		},
		"match":
		{
			"scene": scene_path,
			"map": ModeCatalog.map_id_for_scene(scene_path),
			"mode": LoadingScreen.current_mode_id,
			"format": LoadingScreen.current_format_id,
			"seed": LoadingScreen.last_terrain_seed,
			"character":
			LoadingScreen.PlayerCharacter.keys()[LoadingScreen.selected_player_character],
			"clock_speed": DayCycle.speed,
		},
		"player": _player_state(),
		"mode_state": _mode_state(scene),
		"performance":
		{
			"fps": Engine.get_frames_per_second(),
			"process_ms":
			snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
			"physics_ms":
			snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
			"static_memory_mb":
			snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
			"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			"draw_calls":
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		},
		"terrain": _terrain_state(),
	}


func _player_state() -> Dictionary:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return {}
	var state: Dictionary = {
		"position": player.global_position,
		"facing_degrees": player.global_rotation_degrees,
	}
	if player is CharacterBody3D:
		state["velocity"] = (player as CharacterBody3D).velocity
		state["on_floor"] = (player as CharacterBody3D).is_on_floor()
	var arm: Node3D = player.get_node_or_null("OrbitCamera") as Node3D
	if arm != null:
		state["camera_degrees"] = arm.rotation_degrees
	return state


func _mode_state(scene: Node) -> Dictionary:
	if scene == null:
		return {}
	var mode: GameMode = scene.get_node_or_null("GameMode") as GameMode
	if mode == null:
		return {}
	var alive: int = 0
	for fighter: Fighter in mode.fighters:
		if fighter.is_alive():
			alive += 1
	return {
		"status": mode._status_text(),
		"started": mode._started,
		"fighters": mode.fighters.size(),
		"alive": alive,
	}


func _terrain_state() -> Dictionary:
	var terrain: ChunkedTerrainWorld = (
		get_tree().get_first_node_in_group("terrain_world") as ChunkedTerrainWorld
	)
	if terrain == null:
		return {}
	var edit_log: Array[Dictionary] = terrain.get_edit_log()
	var last_edits: Array = []
	for edit: Dictionary in edit_log.slice(maxi(edit_log.size() - EDIT_TAIL, 0)):
		var copy: Dictionary = edit.duplicate()
		copy.erase("removed")
		last_edits.append(copy)
	return {
		"chunks": terrain.get_chunk_count(),
		"edited_voxels": terrain.get_edited_voxel_count(),
		"edits": edit_log.size(),
		"last_edits": last_edits,
		# Every overridden voxel, so the ground can be put back exactly even when it came from
		# a saved world rather than this session's edits.
		"edit_state": terrain.export_edit_state(),
	}


## One line under the text box saying what goes with the report.
func _summary(data: Dictionary) -> String:
	var match_info: Dictionary = data.get("match", {})
	var game: Dictionary = data.get("game", {})
	var where: String = "%s / %s" % [match_info.get("map", ""), match_info.get("mode", "")]
	if str(match_info.get("map", "")).is_empty():
		where = "menu"
	var player: Dictionary = data.get("player", {})
	var spot: String = ", at %s" % str(player.get("position", "")) if player.has("position") else ""
	return (
		"Attached: screenshot, v%s, %s, seed %s%s, %d FPS, the last terrain edits and the log."
		% [
			game.get("version", "?"),
			where,
			str(match_info.get("seed", 0)),
			spot,
			int(data.get("performance", {}).get("fps", 0)),
		]
	)


func _write_log_tail(path: String) -> void:
	if not FileAccess.file_exists(ENGINE_LOG):
		return
	var engine_log: FileAccess = FileAccess.open(ENGINE_LOG, FileAccess.READ)
	if engine_log == null:
		return
	var lines: PackedStringArray = engine_log.get_as_text().split("\n")
	engine_log.close()
	var tail: PackedStringArray = lines.slice(maxi(lines.size() - LOG_TAIL_LINES, 0))
	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if out != null:
		out.store_string("\n".join(tail))
		out.close()


## Dictionaries and arrays as they are, numbers, strings and bools as they are, and anything
## else (vectors, enums' names) as its text, so JSON.stringify never guesses.
static func _jsonable(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			for key: Variant in value as Dictionary:
				out[str(key)] = _jsonable(value[key])
			return out
		TYPE_ARRAY:
			var items: Array = []
			for item: Variant in value as Array:
				items.append(_jsonable(item))
			return items
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return value
		_:
			return str(value)


func _on_save_pressed() -> void:
	var folder: String = save_report(_description.text)
	if folder.is_empty():
		_saved.text = "Could not write the report."
		return
	_saved.text = "Saved to %s" % ProjectSettings.globalize_path(folder)
	_open_folder_button.disabled = false
	_save_button.disabled = true


func _on_open_folder_pressed() -> void:
	if not _last_report_dir.is_empty():
		OS.shell_open(ProjectSettings.globalize_path(_last_report_dir))
