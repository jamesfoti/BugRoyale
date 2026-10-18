extends Control
class_name LoadingScreen
## Shows the game sky while the main scene loads in the background.


const DEFAULT_GAME_SCENE_PATH: String = "res://scenes/planet_test.tscn"
enum PlayerCharacter {
	STANDARD,
	ANT,
}
static var pending_scene_path: String = ""
static var selected_player_character: PlayerCharacter = PlayerCharacter.STANDARD

@onready var _title: Label = $UI/Margin/VBox/Title
@onready var _status: Label = $UI/Margin/VBox/Status
@onready var _progress: ProgressBar = $UI/Margin/VBox/ProgressBar


func _ready() -> void:
	_title.text = str(ProjectSettings.get_setting("application/config/name", "PhysicsRoyale"))
	_set_progress(0, "Loading")
	call_deferred("_begin_load")


func _begin_load() -> void:
	await get_tree().process_frame
	var game_scene_path: String = _resolve_scene_path()

	var err: Error = ResourceLoader.load_threaded_request(game_scene_path)
	if err != OK:
		push_warning("[LoadingScreen] Threaded load unavailable, loading synchronously.")
		await _load_sync()
		return

	var stalled_frames: int = 0
	var last_progress: float = -1.0
	const STALL_FRAME_LIMIT: int = 180

	while true:
		var progress_status: Array = []
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(
			game_scene_path,
			progress_status
		)

		match status:
			ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, ResourceLoader.THREAD_LOAD_FAILED:
				await _load_sync()
				return
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				var progress: float = 0.0
				if progress_status.size() > 0:
					progress = progress_status[0] as float
				if is_equal_approx(progress, last_progress):
					stalled_frames += 1
				else:
					stalled_frames = 0
					last_progress = progress
				if stalled_frames >= STALL_FRAME_LIMIT:
					push_warning(
						"[LoadingScreen] Threaded load stalled at %d%%, loading synchronously."
						% int(round(progress * 100.0))
					)
					await _load_sync()
					return
				_set_progress(int(round(progress * 100.0)), _asset_load_message(progress))
				await get_tree().process_frame
			ResourceLoader.THREAD_LOAD_LOADED:
				var game_scene: PackedScene = (
					ResourceLoader.load_threaded_get(game_scene_path) as PackedScene
				)
				if game_scene == null:
					_load_sync()
					return
				_start_game(game_scene)
				return


func _load_sync() -> void:
	_set_progress(0, "Loading game scene")
	await get_tree().process_frame
	var game_scene_path: String = _resolve_scene_path()
	var game_scene: PackedScene = load(game_scene_path) as PackedScene
	if game_scene == null:
		_status.text = "Failed to load game"
		return
	_start_game(game_scene)


func _asset_load_message(asset_ratio: float) -> String:
	if asset_ratio < 0.25:
		return "Loading game scene"
	if asset_ratio < 0.55:
		return "Loading characters and props"
	if asset_ratio < 0.85:
		return "Loading shaders and materials"
	return "Loading game resources"


func _set_progress(percent: int, message: String) -> void:
	var clamped: int = clampi(percent, 0, 100)
	_progress.value = float(clamped)
	_status.text = "%s — %d%%" % [message, clamped]


func _start_game(game_scene: PackedScene) -> void:
	_set_progress(100, "Loading")
	var game_root: Node = game_scene.instantiate()
	get_tree().root.add_child(game_root)
	get_tree().current_scene = game_root
	queue_free()


func _resolve_scene_path() -> String:
	if pending_scene_path.is_empty():
		return DEFAULT_GAME_SCENE_PATH
	var scene_path: String = pending_scene_path
	pending_scene_path = ""
	return scene_path
