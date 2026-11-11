class_name LoadingScreen
extends Control
## Shows the game sky while the main scene loads in the background, then stays over the
## game while its map builds: the sky and the bar sit on canvas layers above every HUD, and
## the sky's viewport has a world of its own, so the map going in underneath never shows.

enum PlayerCharacter {
	ANT_WARRIOR,
	TERMITE_SOLDIER,
	WASP,
	TRAPDOOR_SPIDER,
}

const DEFAULT_GAME_SCENE_PATH: String = "res://scenes/garden.tscn"
## The bar is one scale: the scene's asset load fills this much of it, the map's build the
## rest, so it never runs backwards between the two.
const ASSET_SHARE: int = 20

static var pending_scene_path: String = ""
## Game mode to start on the next loaded map (see ModeCatalog); empty = free roam.
static var pending_mode_id: String = ""
## Format (ModeCatalog.FORMATS) for the next match; empty = the mode's default.
static var pending_format_id: String = ""
## Mode, format and map of the running match, for Play Again.
static var current_mode_id: String = ""
static var current_format_id: String = ""
static var current_scene_path: String = ""
static var selected_player_character: PlayerCharacter = PlayerCharacter.ANT_WARRIOR
## Noise seed rolled for the match being loaded (shown in the debug HUD); 0 before any match.
static var last_terrain_seed: int = 0
## Seed to use for the next match instead of rolling one (a host hands its seed to every peer so
## they all build the same map); 0 rolls. Consumed by the next load.
static var pending_terrain_seed: int = 0

## Resolved once per load: the synchronous fallback must get the same map the threaded load
## was given, not the default scene (pending_scene_path is consumed on first use).
var _resolved_scene_path: String = ""
## Frames since the game scene went in and its terrain stood: the screen stays over the
## game while the map builds in the background and leaves a few frames later.
var _frames_since_start: int = -1
## The map's terrain worlds, and how far each one's build is (done, total).
var _terrains: Array[ChunkedTerrainWorld] = []
var _terrain_progress: Dictionary = {}
## The mode put on the map, when there is one: the screen stays until its match starts.
var _game_mode: GameMode = null
## The bar never runs backwards: the ground play waits for grows as the bots are placed.
var _shown_percent: int = 0
var _leaving: bool = false

@onready var _title: Label = $UI/Margin/VBox/Title
@onready var _status: Label = $UI/Margin/VBox/Status
@onready var _progress: ProgressBar = $UI/Margin/VBox/ProgressBar


func _ready() -> void:
	_title.text = str(ProjectSettings.get_setting("application/config/name", "BugRoyale"))
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
			game_scene_path, progress_status
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
						(
							"[LoadingScreen] Threaded load stalled at %d%%, loading synchronously."
							% int(round(progress * 100.0))
						)
					)
					await _load_sync()
					return
				_set_progress(
					int(round(progress * float(ASSET_SHARE))), _asset_load_message(progress)
				)
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
	var game_root: Node = game_scene.instantiate()
	_randomize_terrain_seeds(game_root)
	for terrain: Node in game_root.find_children("*", "ChunkedTerrainWorld", true, false):
		var world: ChunkedTerrainWorld = terrain as ChunkedTerrainWorld
		_terrains.append(world)
		world.build_progress.connect(_on_terrain_progress.bind(world))
	# A terrarium room spawns its terrain a frame after the scene goes in (_adopt_terrains).
	var expects_terrain: bool = (
		not _terrains.is_empty()
		or not game_root.find_children("*", "TerrariumRoom", true, false).is_empty()
	)
	_set_progress(ASSET_SHARE if expects_terrain else 100, "Building terrain")
	get_tree().root.add_child(game_root)
	get_tree().current_scene = game_root
	_add_game_mode(game_root)
	_frames_since_start = 0


## The screen leaves once the ground play needs stands (the map keeps building behind the
## game) and the mode's match, when there is one, is under way.
func _process(_delta: float) -> void:
	if _frames_since_start < 0:
		return
	if not _leaving:
		_adopt_terrains()
		for room: Node in get_tree().get_nodes_in_group("terrarium_room"):
			if (room as TerrariumRoom).is_rebuilding():
				return
		for terrain: ChunkedTerrainWorld in _terrains:
			if is_instance_valid(terrain) and not terrain.play_ground_ready():
				return
		if _game_mode != null and is_instance_valid(_game_mode) and not _game_mode.has_started():
			return
		_leaving = true
		_set_progress(100, "Building terrain")
	_frames_since_start += 1
	if _frames_since_start > 5:
		queue_free()


## Takes in the terrain worlds the scene spawns after it goes in (a terrarium room's, a
## frame later): the screen waits on their ground too, and the bar counts their chunks.
func _adopt_terrains() -> void:
	for terrain: ChunkedTerrainWorld in MapInfo.terrain_worlds(get_tree()):
		if _terrains.has(terrain):
			continue
		_terrains.append(terrain)
		terrain.build_progress.connect(_on_terrain_progress.bind(terrain))


## A terrain world's build, as it goes: the bar shows every world's chunks together.
func _on_terrain_progress(done: int, total: int, world: ChunkedTerrainWorld) -> void:
	if _leaving:
		return
	_terrain_progress[world] = Vector2i(done, total)
	var all_done: int = 0
	var all_total: int = 0
	for progress: Vector2i in _terrain_progress.values():
		all_done += progress.x
		all_total += progress.y
	if all_total <= 0 or not is_inside_tree():
		return
	var built: float = float(all_done) / float(all_total)
	_shown_percent = maxi(
		_shown_percent, ASSET_SHARE + int(round(built * float(100 - ASSET_SHARE)))
	)
	_set_progress(_shown_percent, "Building terrain")


## Adds the chosen mode's scene to the loaded map (no mode = free roam).
func _add_game_mode(game_root: Node) -> void:
	current_mode_id = pending_mode_id
	pending_mode_id = ""
	current_format_id = (
		pending_format_id
		if not pending_format_id.is_empty()
		else ModeCatalog.default_format(current_mode_id)
	)
	pending_format_id = ""
	var mode_info: Dictionary = ModeCatalog.mode(current_mode_id)
	if mode_info.is_empty():
		return
	var mode_scene: PackedScene = load(mode_info["scene"]) as PackedScene
	var game_mode: Node = mode_scene.instantiate()
	game_mode.name = "GameMode"
	game_root.add_child(game_mode)
	_game_mode = game_mode as GameMode


## Reloads the current map with the current mode (Play Again).
static func restart_current(tree: SceneTree) -> void:
	pending_scene_path = current_scene_path
	pending_mode_id = current_mode_id
	pending_format_id = current_format_id
	tree.change_scene_to_file("res://scenes/loading_screen.tscn")


func _resolve_scene_path() -> String:
	if not _resolved_scene_path.is_empty():
		return _resolved_scene_path
	_resolved_scene_path = _resolve_pending_scene_path()
	return _resolved_scene_path


func _resolve_pending_scene_path() -> String:
	if pending_scene_path.is_empty():
		current_scene_path = DEFAULT_GAME_SCENE_PATH
		return DEFAULT_GAME_SCENE_PATH
	var scene_path: String = pending_scene_path
	pending_scene_path = ""
	current_scene_path = scene_path
	return scene_path


## Every match gets fresh ground: one new noise seed for the map's terrain (the terrarium's
## garden derives its own seed from it). Set before the scene enters the tree, so the terrain's
## single rebuild on ready already uses it. Rooms keep their seed so the furniture stays put.
## A persistent mode's saved world (WorldSave) comes back on the ground it was dug in.
func _randomize_terrain_seeds(game_root: Node) -> void:
	var persistent: bool = bool(ModeCatalog.mode(pending_mode_id).get("persistent", false))
	if pending_terrain_seed == 0 and persistent:
		pending_terrain_seed = WorldSave.saved_seed(
			pending_mode_id, ModeCatalog.map_id_for_scene(_resolved_scene_path)
		)
	if pending_terrain_seed != 0:
		last_terrain_seed = pending_terrain_seed
		pending_terrain_seed = 0
	else:
		last_terrain_seed = randi() % 1000000
	for terrain: Node in game_root.find_children("*", "ChunkedTerrainWorld", true, false):
		terrain.set("noise_seed", last_terrain_seed)
	for room: Node in game_root.find_children("*", "TerrariumRoom", true, false):
		room.set("terrarium_noise_seed", last_terrain_seed)
	print("[LoadingScreen] Terrain seed %d" % last_terrain_seed)
