@tool
extends EditorPlugin
## The Terrain Editor: Build, Destroy, New Seed and Randomize in a terrain's inspector, and a
## watch on the terrain library. When a build of the C++ replaces it, the editor saves the open
## scenes and restarts itself to load it, once the file has stopped changing and no game run
## from the editor is playing.

const _Inspector = preload("res://addons/terrain_editor/terrain_world_inspector.gd")
const _LibraryWatch = preload("res://addons/terrain_editor/library_watch.gd")
## Seconds between looks at the library.
const _WATCH_SECONDS: float = 1.0

var _inspector: EditorInspectorPlugin
var _watch: RefCounted
var _timer: Timer


func _enter_tree() -> void:
	_inspector = _Inspector.new()
	add_inspector_plugin(_inspector)
	# A headless editor is a tool run (tests, probes), not someone at work: no restarts.
	if DisplayServer.get_name() == "headless":
		return
	_watch = _LibraryWatch.new(_LibraryWatch.library_stamp())
	_timer = Timer.new()
	_timer.wait_time = _WATCH_SECONDS
	_timer.timeout.connect(_look_at_library)
	add_child(_timer)
	_timer.start()


func _exit_tree() -> void:
	if _inspector != null:
		remove_inspector_plugin(_inspector)
		_inspector = null
	if _timer != null:
		_timer.queue_free()
		_timer = null


func _look_at_library() -> void:
	if not _watch.look(_LibraryWatch.library_stamp()) or EditorInterface.is_playing_scene():
		return
	_timer.stop()
	print("[Terrain] The terrain library was rebuilt: saving the open scenes and restarting.")
	EditorInterface.restart_editor(true)
