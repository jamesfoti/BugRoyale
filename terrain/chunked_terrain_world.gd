@tool
class_name ChunkedTerrainWorld
extends Node3D
## Shared chunked voxel terrain orchestration for the open and boxed-in worlds.

## A brush changed the terrain at a world position (only emitted when voxels actually changed).
signal brush_applied(world_position: Vector3, radius: float)
## An edit went through: the dictionary apply_edit took, with its "sequence" filled in and
## "removed" (TerrainMaterials.Kind -> voxels dug out) and "added" (voxels turned solid). A
## host broadcasts these; a client applies them in sequence order.
signal edit_applied(edit: Dictionary)
## How far the map's build is, as it goes, in chunks placed: while a build focus is set
## (focus_build_at) and the ground round it is not yet complete, the count is of the
## chunks that ground needs; after that, of the whole map. A blocking rebuild reports
## once, complete.
signal build_progress(done: int, total: int)
## Every chunk of a rebuild of the whole map stands.
signal built
## A chunk stood for the first time in this world-space box (the map's build, or the
## underground streamed round a body): whatever was put there from the ground's heights
## before it stood (a plant, a dropped crumb) may want to look at the ground again. Its
## collision is in the physics server a step later.
signal ground_placed(box: AABB)
## A chunk was rebuilt after an edit (a dig, a blast, a saved world's edits) and its new mesh
## and collision are in, in this world-space box; whatever rested on it may want to look
## again (the collision is in the physics server a step later).
signal chunk_rebuilt(box: AABB)

const _CHUNK_SCRIPT = preload("res://terrain/terrain_chunk.gd")
## Worker threads a full rebuild is split over. GDScript on many threads contends in the
## engine (object lookups, reference counts) rather than scaling: measured 2026-11-09 on a
## 20-core machine, 48 garden-sized chunks took 784 ms on one thread, 315 ms on four and
## 1641 ms on all twenty. Four is the sweet spot by a wide margin either side.
const REBUILD_THREADS: int = 4
## How many edited chunks keep their last field for the next stroke (about 20 KB each at
## 16 cells, 150 KB at 32).
const FIELD_CACHE_CHUNKS: int = 512

## Metres of air an ADD edit must leave around a fighter's capsule to be allowed. Terrain
## collision is one-sided, so a fighter sealed inside new rock falls out of the world.
const FIGHTER_CLEARANCE: float = 0.1
## Points tested along a capsule's axis when checking an edit against it.
const CAPSULE_SAMPLES: int = 6
## Main-thread time a frame gives to placing built chunks in the scene (mesh upload and
## collision) during the map's background build.
const PLACE_BUDGET_USEC: int = 8000
## Tasks of the map's background build on the pool at once: the four threads the build
## scales to, plus one queued so no thread waits for the next frame's poll.
const WORLD_BUILD_IN_FLIGHT: int = 5
## Samples a build task takes at once, in chunks (_build_task_chunks): the pool is refilled
## once a frame, so a task shorter than a frame (a 16 m chunk is 20 ms or so) leaves its
## thread idle until the next; this many samples is tens of milliseconds.
const BUILD_TASK_SAMPLES: int = 16000
## A chunk whose top lies this far under the lowest surface of its column is deep: caves
## and bedrock, which nobody sees until they dig, so the build lays the surface of the
## whole map before them.
const DEEP_MARGIN: float = 8.0
## A map that streams its underground (stream_underground) builds with the map only the
## ground down to this far under the lowest surface of each column, everything a body on
## the surface sees into; the chunks below it are streamed.
const STREAM_MARGIN: float = 32.0
## Metres round the local player within which the streamed chunks stand (what it sees in a
## cave), round any other body (what it can walk into before the next look), and how much
## farther a chunk stays before it is freed, so a body on a seam does not make it flicker.
const STREAM_VIEW: float = 48.0
const STREAM_BODY: float = 16.0
const STREAM_KEEP: float = 16.0
## Physics frames between looks at where the bodies are.
const STREAM_EVERY: int = 10
## Until play can begin, the streamed chunks get pool places only when one lies within
## this many metres of a body (it stands or is held there), and only this many places: the
## ground round the spawn comes first. After it, they go before the map's own chunks.
const STREAM_URGENT: float = 8.0
const STREAM_TASKS_BEFORE_PLAY: int = 2
## How far round a body's feet the ground must stand before it may go on, plus a quarter of
## a second of its fall: a body walking or falling toward ground not built yet is held.
const GROUND_HOLD_REACH: float = 2.0
## Physics frames between moves of the build's order to where the local player is now, once
## play has begun: the ground nearest it comes next wherever it went.
const ORDER_EVERY: int = 120

@export_group("Terrain Grid")
@export_range(1.0, 128.0, 0.5, "or_greater") var chunk_size: float = 12.0:
	set(value):
		chunk_size = maxf(value, 1.0)
		_request_rebuild()
@export_range(1, 16, 1) var chunk_resolution: int = 1:
	set(value):
		chunk_resolution = maxi(value, 1)
		_request_rebuild()
## World metres per voxel. The maps dig at 1 m (a 512 m map in about 24 s headless, 34 s in
## the editor, on four threads). Each doubling cuts the build about eightfold: 2 m is 2.6 s,
## 4 m 0.7 s, so the lab can judge a seed's hills at 4 m and its terraces and ravines at 2 m.
@export_range(0.25, 8.0, 0.25) var voxel_size: float = 1.0:
	set(value):
		voxel_size = maxf(value, 0.05)
		_request_rebuild()

## The noise ranges are the ones a map may be randomised over: frequency 0.004 to 0.01
## (hills 250 m to 100 m across; higher was tried and worked down from), one to five
## octaves, gain 0.3 to 0.65 (smooth to craggy), lacunarity 1.8 to 2.6, amplitude 0 to 40 m.
## Slope grows with amplitude times frequency: 12 m on 200 m hills is a 20 degree roll, 36 m
## a 45 degree mountainside, and past that at 2 m voxels the shape goes blocky, so raise one
## and lower the other. Chunks above the top are not built, so amplitude plus offset must
## stay under the sky over the surface (half the box with the surface at its centre; 48 m
## on the maps), or the peaks come out flat-topped.
@export_group("Noise")
@export var noise_enabled: bool = true:
	set(value):
		noise_enabled = value
		_request_rebuild()
@export var noise_seed: int = 42:
	set(value):
		noise_seed = value
		_request_rebuild()
@export_range(0.004, 0.01, 0.0005) var noise_frequency: float = 0.008:
	set(value):
		noise_frequency = maxf(value, 0.001)
		_request_rebuild()
@export_range(0.0, 40.0, 0.1) var noise_amplitude: float = 3.0:
	set(value):
		noise_amplitude = value
		_request_rebuild()
@export_range(1, 5, 1) var noise_octaves: int = 3:
	set(value):
		noise_octaves = value
		_request_rebuild()
@export_range(1.8, 2.6, 0.05) var noise_lacunarity: float = 2.0:
	set(value):
		noise_lacunarity = maxf(value, 1.0)
		_request_rebuild()
@export_range(0.3, 0.65, 0.01) var noise_gain: float = 0.5:
	set(value):
		noise_gain = clampf(value, 0.01, 1.0)
		_request_rebuild()

@export_group("Caves")
## Carves a seeded underworld (CaveCarver) under a solid-filled open terrain: tunnels,
## caverns, sinkholes and bedrock. The grid wants a few chunks of depth for it to show.
@export var caves_enabled: bool = false:
	set(value):
		caves_enabled = value
		_request_rebuild()

@export_group("Meshing")
@export var iso_level: float = 0.0:
	set(value):
		iso_level = value
		_request_rebuild()
@export var generate_collision: bool = true:
	set(value):
		generate_collision = value
		_request_rebuild()
## Floating rock: a lump of solid voxels with air all round it, up to this many voxels, is
## cleared from a chunk before it is meshed (LooseRock), unless it was built with the brush.
## 0 keeps every lump. A lump that straddles a chunk seam by more than a voxel stays too.
@export_range(0, 64, 1) var loose_rock_voxels: int = 8:
	set(value):
		loose_rock_voxels = value
		_request_rebuild()
@export var terrain_material: Material

@export_group("Runtime")
@export var is_playable_world: bool = true
@export var rebuild_on_ready: bool = true
@export var auto_rebuild_in_editor: bool = false
@export var use_threaded_rebuild: bool = true
@export_range(1, 8, 1) var max_concurrent_rebuild_tasks: int = 4
## Metres of ground each way round the local player's spawn that play waits for (its
## surface band, at full detail), so a sprint from the spawn stays on built ground; the rest
## of the map follows nearest the player first, the haze (Atmosphere) hiding where it ends.
## A bot waits for its own ground only.
@export_range(0.0, 256.0, 1.0, "suffix:m") var play_ring: float = 96.0
## Builds only the ground down to STREAM_MARGIN under the surface with the map, and the
## chunks below that round the bodies that need them, freeing them when none is near: for a
## map far deeper than anyone sees at once (the maps are a kilometre deep). Off, every chunk
## is built with the map.
@export var stream_underground: bool = false

## Brush edits are refused outside this box (world space). Zero size: editable anywhere.
var edit_bounds: AABB = AABB()
## Solid ground a map builder adds on top of the map's own shape, dug and built on like the
## rest: the soil in a garden's raised beds, and the footings under its beds and under the
## crawlspace's piers (see footing). Stadiums as DensitySampler.WorldDensity.solids describes
## them. Set before the first build (a builder's _ready runs before the deferred rebuild on
## ready, which picks them up); set later, the chunks rebuild.
var solids: Array[Dictionary] = []:
	set(value):
		solids = value
		_invalidate_bake_density()
		if not _chunks.is_empty():
			_request_rebuild()

## A mode's say over edits (edit: Dictionary -> bool): Hold Out refuses building it cannot pay
## for. Invalid means everything goes.
var edit_gate: Callable = Callable()

var _chunks: Dictionary = {}

var _rebuild_queued: bool = false
var _edits: TerrainEdits = TerrainEdits.new()
## Every edit applied this session, in order (see apply_edit).
var _edit_log: Array[Dictionary] = []
var _next_edit_sequence: int = 1
var _dirty_chunks: Dictionary = {}
var _chunk_flush_pending: bool = false
var _continuous_edit_depth: int = 0
var _bake_density: DensitySampler.WorldDensity
## Chunk coordinate -> the world-space box whose samples changed since the chunk was last
## built (an AABB of no volume: the chunk is built whole).
var _pending_rebuild_chunk_coordinates: Dictionary = {}
## Chunk coordinate -> the field and mesh blocks of its last brush rebuild
## (ChunkMeshBuilder.ChunkCache), at most FIELD_CACHE_CHUNKS of them, oldest dropped: the
## next stroke there resamples only what it changed instead of reading forty thousand
## samples again, and meshes only the blocks those samples touch.
var _field_cache: Dictionary = {}
var _pending_rebuild_collision: bool = false
var _async_rebuild_requested: bool = false
var _async_jobs: Dictionary = {}
var _running_async_tasks: int = 0
var _inflight_chunk_coordinates: Dictionary = {}
## The map's build in the background (the game's rebuild on ready): chunks built at full
## detail a few to a task on the worker pool, nearest the build's focus first, placed as
## they come in. Where none stands yet there is no ground at all.
var _world_building: bool = false
## Chunks not yet started, farthest first (the next is popped off the back).
var _world_build_queue: Array[Vector3i] = []
## Task id -> the job of a chunk on the pool.
var _world_build_tasks: Dictionary = {}
var _world_build_settings: SettingsSnapshot = null
var _world_build_grid: Vector3i = Vector3i.ZERO
var _world_build_total: int = 0
var _world_build_placed: int = 0
var _world_build_started_msec: int = 0
## Where the ground is wanted first (focus_build_at): x, y, z and the radius round it.
var _build_focus: Array[Vector4] = []
## The local player's focus, the one the fine pass is ordered round when there is one: the
## latest placement, since a respawn moves it.
var _primary_focus: Array[Vector4] = []
## Whether a focus came since the queue was sorted (it is sorted again before the next
## chunk is started, once for however many came in the frame).
var _queue_stale: bool = false
## Chunk columns (x, z) the focuses cover: their surface bands are ground play waits for.
var _play_columns: Dictionary = {}
## Chunk coordinates within reach of a focus, in three dimensions: the chunks round a
## body, which play waits for too, so a body below the surface band (a saved spot
## underground) gets the cave chunks it stands in and not only the surface over them.
var _play_chunks: Dictionary = {}
## Chunk coordinate -> true for a deep chunk (DEEP_MARGIN under its column's lowest
## surface), during the build.
var _deep: Dictionary = {}
## Chunk coordinate -> true once the map's build (or the brush) placed its chunk.
var _placed: Dictionary = {}
## Per chunk column (x + z * grid.x), how many of its chunks above the deep ones the build
## has still to place: a column at 0 shows all the ground anyone sees there.
var _column_missing: PackedInt32Array = PackedInt32Array()
## Where the build's order is measured from once play has begun (the local player, moved
## every ORDER_EVERY physics frames), and the frames since.
var _order_focus: Array[Vector4] = []
var _order_tick: int = 0
## Streaming (stream_underground): per chunk column (x + z * grid.x), how many of its bottom
## chunks are streamed, measured with the build and kept; the streamed chunks that stand;
## those on the pool, by chunk and by task; the ones the bodies want (chunk -> metres to the
## nearest) and keep (_look_for_streamed_chunks); and the wanted ones not yet started,
## farthest first (the next is popped off the back).
var _stream_floor: PackedInt32Array = PackedInt32Array()
var _stream_grid: Vector3i = Vector3i.ZERO
var _stream_loaded: Dictionary = {}
var _stream_inflight: Dictionary = {}
var _stream_tasks: Dictionary = {}
var _stream_wanted: Dictionary = {}
var _stream_keep: Dictionary = {}
var _stream_queue: Array[Vector3i] = []
var _stream_tick: int = 0
## Whether play still waits on the map's build (play_ground_ready, as of the last progress
## report): until it can begin, the streamed chunks take only a few of the pool's places.
var _play_waiting: bool = true


func _ready() -> void:
	_ensure_world_defaults()
	if is_playable_world:
		add_to_group("terrain_world")
		_register_playable_groups()
	if rebuild_on_ready and not Engine.is_editor_hint():
		call_deferred("begin_build")


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _streaming():
		_poll_stream()
	if _world_building:
		_poll_world_build()
	if _streaming():
		_fill_stream()
	_poll_async_rebuilds()
	if _async_rebuild_requested:
		_async_rebuild_requested = false
		_dispatch_pending_rebuilds()


func _ensure_world_defaults() -> void:
	pass


func _register_playable_groups() -> void:
	pass


func _get_grid_dimensions() -> Vector3i:
	return Vector3i.ONE * 3


func _get_world_log_name() -> String:
	return "Terrain"


func _apply_world_specific_settings(_settings: SettingsSnapshot) -> void:
	pass


func destroy_all() -> void:
	_clear_chunks()
	if Engine.is_editor_hint():
		print("[%s] Destroyed terrain (editor)" % _get_world_log_name())


func rebuild_all_editor() -> void:
	rebuild_all()


## Rebuilds the whole map before returning: every chunk exists after this (the editor, the
## tests rely on that). A map with many chunks takes seconds and no frame is drawn
## meanwhile; the game's rebuild on ready goes through begin_build.
func rebuild_all() -> void:
	_abandon_world_build()
	_invalidate_bake_density()
	_ensure_world_defaults()
	_clear_chunks()
	var settings: SettingsSnapshot = _make_settings_snapshot()
	var grid_dimensions: Vector3i = _get_grid_dimensions()
	_world_build_grid = grid_dimensions
	# The deep marks are only the build's order; what is streamed stays measured.
	_mark_deep_chunks(settings, grid_dimensions)
	_deep.clear()
	_rebuild_all_sync(settings, grid_dimensions)


## Whether the map's background build (see begin_build) is still going. The ground
## comes in nearest the build's focus first, so play starts before the map is done: a
## spawn waits on is_ground_ready_around, the loading screen on play_ground_ready.
func is_building() -> bool:
	return _world_building


## Points the map's build at a spot: the chunks nearest it (and the other spots given so
## far) come first, and the ground within radius of it is ground play waits for: the
## surface band of the columns there and the chunks round the spot itself, in three
## dimensions, which are more than the band when the spot is below it. A spawn calls
## this with where it will stand. The local player's placement is primary: the fine pass
## is ordered round it alone, a later one replaces it, and play waits for the surface
## band play_ring metres each way round it. Takes effect within a few chunks.
func focus_build_at(world_position: Vector3, radius: float = 0.0, primary: bool = false) -> void:
	var focus := Vector4(world_position.x, world_position.y, world_position.z, radius)
	_build_focus.append(focus)
	var reach: float = radius
	if primary:
		_primary_focus.clear()
		_primary_focus.append(focus)
		reach = maxf(radius, play_ring)
	for column: Vector2i in _columns_touching(world_position, reach):
		_play_columns[column] = true
	for chunk_coordinate: Vector3i in _chunks_touching(world_position, radius):
		_play_chunks[chunk_coordinate] = true
	if _world_building:
		_queue_stale = true


## Whether the ground a body within radius of a spot needs stands (_ground_round), with no
## rebuild of it queued or in flight. Always once the map's build is done and, on a map that
## streams its underground, the streamed chunks there stand; and for a spot off the grid.
func is_ground_ready_around(world_position: Vector3, radius: float = 0.0) -> bool:
	if not _world_building and not _streaming():
		return true
	return _ground_complete(_ground_round(world_position, radius))


## Whether the ground play needs stands, so play can begin: the ground every focus asked for
## (the surface band play_ring round the local player's). False while the map builds and no
## focus is set, since nothing says yet where play is.
func play_ground_ready() -> bool:
	if not _world_building:
		return true
	if _play_columns.is_empty():
		return false
	return _ground_complete(_play_ground())


## Metres from a point to the nearest ground the map's build has not laid yet (a column whose
## surface band is not all placed), across the map; INF once the build is done. The haze
## closes in to hide where the built ground ends (Atmosphere).
func get_built_reach(world_position: Vector3) -> float:
	if not _world_building or _column_missing.is_empty():
		return INF
	var extent: float = _build_settings().chunk_world_size
	var origin: Vector3 = global_position + _chunk_corner_local(Vector3i.ZERO, _build_settings())
	var point := Vector2(world_position.x - origin.x, world_position.z - origin.z)
	var nearest: float = INF
	for column_z: int in _world_build_grid.z:
		for column_x: int in _world_build_grid.x:
			if _column_missing[column_x + column_z * _world_build_grid.x] <= 0:
				continue
			var low := Vector2(column_x, column_z) * extent
			var closest: Vector2 = point.clamp(low, low + Vector2.ONE * extent)
			nearest = minf(nearest, point.distance_to(closest))
	return nearest


## The ground a body within radius of a spot needs, as chunk coordinates: the surface
## band of the columns there, and the chunks within radius of the spot itself, which are
## more than the band for a body below it (in a cave, or at a saved spot underground).
func _ground_round(world_position: Vector3, radius: float) -> Dictionary:
	var chunks: Dictionary = {}
	for column: Vector2i in _columns_touching(world_position, radius):
		_add_surface_band(column, chunks)
	for chunk_coordinate: Vector3i in _chunks_touching(world_position, radius):
		chunks[chunk_coordinate] = true
	return chunks


## The ground play waits for, as chunk coordinates: the surface band of every column a
## focus covers and the chunks round every focus.
func _play_ground() -> Dictionary:
	var chunks: Dictionary = _play_chunks.duplicate()
	for column: Vector2i in _play_columns:
		_add_surface_band(column, chunks)
	return chunks


## Adds the chunks of a column that are neither deep nor streamed to a set of chunk
## coordinates.
func _add_surface_band(column: Vector2i, chunks: Dictionary) -> void:
	for chunk_y: int in range(_streamed_below(column), _world_build_grid.y):
		var chunk_coordinate := Vector3i(column.x, chunk_y, column.y)
		if not _deep.has(chunk_coordinate):
			chunks[chunk_coordinate] = true


## Whether every chunk of a set stands, with no rebuild of it queued or in flight: a saved
## world's edits go in on the brush's lane, and until they land the chunk there is
## yesterday's ground.
func _ground_complete(chunks: Dictionary) -> bool:
	for chunk_coordinate: Vector3i in chunks:
		if (
			not _stands(chunk_coordinate)
			or _pending_rebuild_chunk_coordinates.has(chunk_coordinate)
			or _inflight_chunk_coordinates.has(chunk_coordinate)
		):
			return false
	return true


## Whether a chunk stands: a streamed one once it is built, any other once the map's build
## placed it (every one, when the build is done).
func _stands(chunk_coordinate: Vector3i) -> bool:
	if _is_streamed(chunk_coordinate):
		return _stream_loaded.has(chunk_coordinate)
	return not _world_building or _placed.has(chunk_coordinate)


## The settings the build runs on, or the next one would.
func _build_settings() -> SettingsSnapshot:
	return _world_build_settings if _world_build_settings != null else _make_settings_snapshot()


## The game's build of the map: the chunks are meshed at full detail on the worker pool
## while the frames keep coming and placed in the scene as they come in (the loading screen
## draws its bar from build_progress): the ground play waits for first, then the surface
## nearest the player and the deep chunks last (_sort_world_build_queue). Where no chunk
## stands yet there is nothing: a body is held off it (ground_missing_under) and the haze
## hides it (get_built_reach). What the build on ready runs; a world another node
## sets up and drives (a terrarium's terrain) calls it once its settings are set, so its
## ground comes in like any map's. Blocking without threads, as rebuild_all is, and in
## the editor, where nothing polls the pool.
func begin_build() -> void:
	if not _use_threaded_rebuild():
		rebuild_all()
		return
	_abandon_world_build()
	_invalidate_bake_density()
	_ensure_world_defaults()
	_clear_chunks()
	_world_build_settings = _make_settings_snapshot()
	_world_build_grid = _get_grid_dimensions()
	_mark_deep_chunks(_world_build_settings, _world_build_grid)
	_queue_every_chunk()
	_world_build_total = _world_build_queue.size()
	_world_build_placed = 0
	_placed.clear()
	_count_missing_columns()
	_order_focus.clear()
	_order_tick = 0
	_world_build_started_msec = Time.get_ticks_msec()
	_world_building = true
	_sort_world_build_queue()
	_fill_world_build()
	_emit_build_progress()


## Queues every chunk the map's build makes: all of them, but the streamed ones.
func _queue_every_chunk() -> void:
	_world_build_queue.clear()
	for chunk_z: int in _world_build_grid.z:
		for chunk_y: int in _world_build_grid.y:
			for chunk_x: int in _world_build_grid.x:
				var chunk_coordinate := Vector3i(chunk_x, chunk_y, chunk_z)
				if not _is_streamed(chunk_coordinate):
					_world_build_queue.append(chunk_coordinate)


## Marks the build's deep chunks, DEEP_MARGIN under the lowest surface of their column
## (sampled nine times across it): an open terrain's caves and bedrock. Any other world
## has none, since only an open terrain says where its surface is. On a map that streams
## its underground, measures too how many chunks of each column lie STREAM_MARGIN under
## that surface: those are streamed.
func _mark_deep_chunks(settings: SettingsSnapshot, grid: Vector3i) -> void:
	_deep.clear()
	_stream_floor = PackedInt32Array()
	_stream_grid = grid
	var density: DensitySampler.WorldDensity = _get_bake_density()
	if not density.open_terrain_enabled or grid.y < 2:
		return
	var floors := PackedInt32Array()
	if stream_underground:
		floors.resize(grid.x * grid.z)
	var extent: float = settings.chunk_world_size
	var origin: Vector3 = global_position + _chunk_corner_local(Vector3i.ZERO, settings)
	for column_x: int in grid.x:
		for column_z: int in grid.z:
			var lowest: float = INF
			for sample_x: int in 3:
				for sample_z: int in 3:
					lowest = minf(
						lowest,
						density.sample_open_terrain_height(
							origin.x + (float(column_x) + 0.5 * float(sample_x)) * extent,
							origin.z + (float(column_z) + 0.5 * float(sample_z)) * extent
						)
					)
			var streamed: int = 0
			for chunk_y: int in grid.y:
				var top: float = origin.y + float(chunk_y + 1) * extent
				if top <= lowest - DEEP_MARGIN:
					_deep[Vector3i(column_x, chunk_y, column_z)] = true
				if top <= lowest - STREAM_MARGIN:
					streamed = chunk_y + 1
			if stream_underground:
				floors[column_x + column_z * grid.x] = streamed
	_stream_floor = floors


## Counts, per column, the chunks above the deep ones the build has to place.
func _count_missing_columns() -> void:
	_column_missing = PackedInt32Array()
	_column_missing.resize(_world_build_grid.x * _world_build_grid.z)
	for chunk_coordinate: Vector3i in _world_build_queue:
		if not _deep.has(chunk_coordinate):
			_column_missing[chunk_coordinate.x + chunk_coordinate.z * _world_build_grid.x] += 1


## Places the chunks whose tasks are done, within the frame's budget, and starts the next.
## A task's chunks are placed in order; what the budget does not take waits for the next
## frame, the task holding its place on the pool's count meanwhile.
func _poll_world_build() -> void:
	var deadline: int = Time.get_ticks_usec() + PLACE_BUDGET_USEC
	for task_id_variant: Variant in _world_build_tasks.keys():
		if Time.get_ticks_usec() >= deadline:
			break
		var task_id: int = task_id_variant as int
		var job: ChunkMeshBuilder.AsyncRebuildJob = (
			_world_build_tasks[task_id] as ChunkMeshBuilder.AsyncRebuildJob
		)
		if not job.collected:
			if not WorkerThreadPool.is_task_completed(task_id):
				continue
			WorkerThreadPool.wait_for_task_completion(task_id)
			job.collected = true
		while job.placed < job.chunk_coordinates.size() and Time.get_ticks_usec() < deadline:
			_place_built_chunk(job, job.chunk_coordinates[job.placed])
			job.placed += 1
		if job.placed >= job.chunk_coordinates.size():
			_world_build_tasks.erase(task_id)
	_fill_world_build()
	_emit_build_progress()
	if _world_build_placed < _world_build_total or not _world_build_tasks.is_empty():
		return
	_log_rebuild_complete(
		_chunks.size(),
		_world_build_settings,
		_world_build_grid,
		Time.get_ticks_msec() - _world_build_started_msec
	)
	_world_building = false
	_world_build_settings = null
	_build_focus.clear()
	_primary_focus.clear()
	_order_focus.clear()
	_play_columns.clear()
	_play_chunks.clear()
	_deep.clear()
	_column_missing = PackedInt32Array()
	built.emit()


## Puts one chunk of a done build task in the scene, unless the brush got there first with
## a later snapshot.
func _place_built_chunk(job: ChunkMeshBuilder.AsyncRebuildJob, chunk_coordinate: Vector3i) -> void:
	if _placed.has(chunk_coordinate):
		return
	var result: ChunkMeshBuilder.ChunkBuildResult = (
		job.batch_result.chunks[chunk_coordinate] as ChunkMeshBuilder.ChunkBuildResult
	)
	_build_chunk_at(chunk_coordinate, result, job.settings)
	_note_placed_chunk(chunk_coordinate)
	ground_placed.emit(_get_chunk_world_aabb(chunk_coordinate, job.settings))


## A chunk of the map's build stands at a coordinate.
func _note_placed_chunk(chunk_coordinate: Vector3i) -> void:
	if _placed.has(chunk_coordinate):
		return
	_placed[chunk_coordinate] = true
	_world_build_placed += 1
	if not _deep.has(chunk_coordinate) and not _column_missing.is_empty():
		_column_missing[chunk_coordinate.x + chunk_coordinate.z * _world_build_grid.x] -= 1


## Starts tasks off the queue, each of _build_task_chunks chunks, until the pool holds its
## share, the brush's own rebuilds counted in, since GDScript on more threads than that
## runs slower, not faster.
func _fill_world_build() -> void:
	if _queue_stale:
		_sort_world_build_queue()
	# Streamed chunks waiting go first: a body is standing near them. Until play can begin,
	# the ground it waits on keeps all but STREAM_TASKS_BEFORE_PLAY of the places.
	var places: int = WORLD_BUILD_IN_FLIGHT
	if _stream_waiting():
		places -= STREAM_TASKS_BEFORE_PLAY if _play_waiting else WORLD_BUILD_IN_FLIGHT - 1
	while _world_build_tasks.size() < places and _pool_load() < WORLD_BUILD_IN_FLIGHT:
		if _world_build_queue.is_empty():
			return
		var batch: Array[Vector3i] = []
		var wanted: int = _build_task_chunks()
		while batch.size() < wanted and not _world_build_queue.is_empty():
			var chunk_coordinate: Vector3i = _world_build_queue.pop_back()
			if _placed.has(chunk_coordinate) or _inflight_chunk_coordinates.has(chunk_coordinate):
				continue
			# The edits so far go into this chunk's snapshot: a rebuild queued for it
			# before now would only repeat the work.
			_pending_rebuild_chunk_coordinates.erase(chunk_coordinate)
			batch.append(chunk_coordinate)
		if batch.is_empty():
			continue
		var job: ChunkMeshBuilder.AsyncRebuildJob = ChunkMeshBuilder.AsyncRebuildJob.new()
		job.chunk_coordinates = batch
		job.settings = _make_thread_settings_snapshot()
		var task_id: int = WorkerThreadPool.add_task(
			ChunkMeshBuilder.run_async_job.bind(job), true, "%s chunk build" % _get_world_log_name()
		)
		_world_build_tasks[task_id] = job


## The terrain's tasks on the pool: the map's build, the streamed chunks and the brush.
func _pool_load() -> int:
	return _world_build_tasks.size() + _stream_tasks.size() + _running_async_tasks


## Chunks a build task takes: enough samples for the task to outlast the frame it was
## started in (BUILD_TASK_SAMPLES), and no more than a sixty-fourth of the map, so the
## order round the player holds and a small grid still builds in many tasks.
func _build_task_chunks() -> int:
	var cells: int = _world_build_settings.cells_per_axis
	var samples: int = (cells + 1) * (cells + 1) * (cells + 1)
	@warning_ignore("integer_division")
	return clampi(BUILD_TASK_SAMPLES / samples, 1, maxi(_world_build_total / 64, 1))


## Orders the chunks still to start: by group (_build_group), then nearest the focus
## first, then in one column the top chunk first. The queue holds them the other way
## round, since the next is taken off the back.
func _sort_world_build_queue() -> void:
	_queue_stale = false
	var settings: SettingsSnapshot = _world_build_settings
	var extent: float = settings.chunk_world_size
	var origin: Vector3 = global_position + _chunk_corner_local(Vector3i.ZERO, settings)
	var keyed: Array = []
	for chunk_coordinate: Vector3i in _world_build_queue:
		var centre := Vector2(
			origin.x + (float(chunk_coordinate.x) + 0.5) * extent,
			origin.z + (float(chunk_coordinate.z) + 0.5) * extent
		)
		var key: Array = [
			_build_group(chunk_coordinate),
			_focus_distance(centre),
			-chunk_coordinate.y,
			chunk_coordinate.x,
			chunk_coordinate.z,
			chunk_coordinate,
		]
		keyed.append(key)
	keyed.sort()
	_world_build_queue.clear()
	for index: int in range(keyed.size() - 1, -1, -1):
		_world_build_queue.append((keyed[index] as Array)[5] as Vector3i)


## Where a chunk stands in the build: the ground play waits for (0: the surface band of the
## focuses' columns and the chunks round each focus), the deep chunks under those columns
## (1, where the player digs first), the surface band of the rest of the map (2) and its
## deep chunks (3). The surface layer of a map is a third of its build and the cave layer
## two thirds, and nobody sees the caves until they dig, so the ground in view is in three
## times sooner this way.
func _build_group(chunk_coordinate: Vector3i) -> int:
	if _play_chunks.has(chunk_coordinate):
		return 0
	var deep: int = 1 if _deep.has(chunk_coordinate) else 0
	if _play_columns.has(Vector2i(chunk_coordinate.x, chunk_coordinate.z)):
		return deep
	return 2 + deep


## How far a chunk column's centre is from the nearest focus, past its radius: where the
## local player is now once play has begun, else its placement when there is one, else any;
## from the world's centre when none is set.
func _focus_distance(column_centre: Vector2) -> float:
	var foci: Array[Vector4] = _order_focus
	if foci.is_empty():
		foci = _primary_focus if not _primary_focus.is_empty() else _build_focus
	if foci.is_empty():
		return column_centre.distance_to(Vector2(global_position.x, global_position.z))
	var nearest: float = INF
	for focus: Vector4 in foci:
		var distance: float = column_centre.distance_to(Vector2(focus.x, focus.z)) - focus.w
		nearest = minf(nearest, maxf(distance, 0.0))
	return nearest


## The first and last chunk coordinates, on the grid, of the chunks within radius of a
## spot (a box round it, like the chunks): the last before the first for a spot off it.
func _chunk_span(world_position: Vector3, radius: float) -> Array[Vector3i]:
	var settings: SettingsSnapshot = _build_settings()
	var grid: Vector3i = _get_grid_dimensions()
	var extent: float = settings.chunk_world_size
	var origin: Vector3 = global_position + _chunk_corner_local(Vector3i.ZERO, settings)
	var low: Vector3 = ((world_position - Vector3.ONE * radius - origin) / extent).floor()
	var high: Vector3 = ((world_position + Vector3.ONE * radius - origin) / extent).floor()
	return [Vector3i(low).max(Vector3i.ZERO), Vector3i(high).min(grid - Vector3i.ONE)]


## The chunk columns (x, z) within radius of a spot, those on the grid.
func _columns_touching(world_position: Vector3, radius: float) -> Array[Vector2i]:
	var span: Array[Vector3i] = _chunk_span(world_position, radius)
	var columns: Array[Vector2i] = []
	for column_x: int in range(span[0].x, span[1].x + 1):
		for column_z: int in range(span[0].z, span[1].z + 1):
			columns.append(Vector2i(column_x, column_z))
	return columns


## The chunks within radius of a spot, in three dimensions, those on the grid.
func _chunks_touching(world_position: Vector3, radius: float) -> Array[Vector3i]:
	var span: Array[Vector3i] = _chunk_span(world_position, radius)
	var chunks: Array[Vector3i] = []
	for chunk_x: int in range(span[0].x, span[1].x + 1):
		for chunk_y: int in range(span[0].y, span[1].y + 1):
			for chunk_z: int in range(span[0].z, span[1].z + 1):
				chunks.append(Vector3i(chunk_x, chunk_y, chunk_z))
	return chunks


## Until play can begin, the count is of what it waits for: the ground the focuses asked
## for (a ring of columns' worth assumed until a focus says); after, of the whole map.
func _emit_build_progress() -> void:
	_play_waiting = _world_building and not play_ground_ready()
	if not _play_waiting or _world_build_placed >= _world_build_total:
		build_progress.emit(mini(_world_build_placed, _world_build_total), _world_build_total)
		return
	var play_done: int = 0
	var play_total: int = 0
	for chunk_coordinate: Vector3i in _play_ground():
		play_total += 1
		if _stands(chunk_coordinate):
			play_done += 1
	if _play_columns.is_empty():
		var ring: int = ceili(play_ring / _build_settings().chunk_world_size)
		var band: int = ceili(
			float(_world_build_total) / float(maxi(_world_build_grid.x * _world_build_grid.z, 1))
		)
		play_total = (2 * ring + 1) ** 2 * band
	build_progress.emit(play_done, play_total)


## Looks at where the bodies are for the streamed underground, moves the build's order to
## the local player, and holds any body about to walk or fall onto ground not built yet.
func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _streaming():
		_stream_tick += 1
		if _stream_tick % STREAM_EVERY == 1:
			_look_for_streamed_chunks()
	if _world_building and not _play_waiting:
		_order_tick += 1
		if _order_tick % ORDER_EVERY == 1:
			_follow_local_player()
	if _streaming() or _world_building:
		_hold_bodies_off_missing_ground()


## Orders the rest of the build round where the local player is now.
func _follow_local_player() -> void:
	for node: Node in get_tree().get_nodes_in_group("fighter"):
		var body: Node3D = node as Node3D
		if body != null and body.is_inside_tree() and _is_local_body(body):
			var at: Vector3 = body.global_position
			_order_focus.clear()
			_order_focus.append(Vector4(at.x, at.y, at.z, 0.0))
			_queue_stale = true
			return


# --- Streaming the underground -------------------------------------------------------------


## The height the map's surface is laid about (the noise's zero): the builders stand their
## structures on it. The node's own height; an open terrain puts it in a chunk layer of its
## choosing (Surface Layer).
func get_surface_datum_y() -> float:
	return global_position.y


## Whether this world streams its underground now: asked for, measured by the build, and in
## the game (nothing polls the pool in the editor).
func _streaming() -> bool:
	return stream_underground and not _stream_floor.is_empty() and not Engine.is_editor_hint()


## Whether a chunk is one of the streamed ones, under the band the map's build makes.
func _is_streamed(chunk_coordinate: Vector3i) -> bool:
	if _stream_floor.is_empty():
		return false
	if (
		chunk_coordinate.x < 0
		or chunk_coordinate.z < 0
		or chunk_coordinate.x >= _stream_grid.x
		or chunk_coordinate.z >= _stream_grid.z
	):
		return false
	return (
		chunk_coordinate.y < _stream_floor[chunk_coordinate.x + chunk_coordinate.z * _stream_grid.x]
	)


## How many of a column's bottom chunks are streamed (0 when none is).
func _streamed_below(column: Vector2i) -> int:
	if (
		_stream_floor.is_empty()
		or column.x < 0
		or column.y < 0
		or column.x >= _stream_grid.x
		or column.y >= _stream_grid.z
	):
		return 0
	return _stream_floor[column.x + column.y * _stream_grid.x]


## The world position of the grid's low corner.
func _grid_corner() -> Vector3:
	return global_position - Vector3(_stream_grid) * chunk_size * 0.5


## Looks at where the bodies are: the streamed chunks within reach of one (STREAM_VIEW of
## the local player, STREAM_BODY of any other, and of each spot the map's build was told
## to ready) are wanted, nearest first; those a little farther are kept; the rest are freed.
func _look_for_streamed_chunks() -> void:
	var wanted: Dictionary = {}
	var keep: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("fighter"):
		var body: Node3D = node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var reach: float = STREAM_VIEW if _is_local_body(body) else STREAM_BODY
		_want_round(body.global_position, reach, wanted, keep)
	for focus: Vector4 in _build_focus:
		_want_round(
			Vector3(focus.x, focus.y, focus.z), maxf(focus.w, 0.0) + STREAM_BODY, wanted, keep
		)
	for chunk_coordinate: Vector3i in _stream_loaded.keys():
		if not keep.has(chunk_coordinate):
			_free_streamed_chunk(chunk_coordinate)
	_stream_wanted = wanted
	_stream_keep = keep
	var keyed: Array = []
	for chunk_coordinate: Vector3i in wanted:
		if _stream_loaded.has(chunk_coordinate) or _stream_inflight.has(chunk_coordinate):
			continue
		keyed.append([-float(wanted[chunk_coordinate]), chunk_coordinate])
	keyed.sort()
	_stream_queue.clear()
	for key: Array in keyed:
		_stream_queue.append(key[1] as Vector3i)


## Whether a body is the player at this screen (FighterBody.is_local; every body's scene is in
## the "player" group, so the group cannot say), or, for a plain node, in that group.
static func _is_local_body(body: Node3D) -> bool:
	if body is FighterBody:
		return (body as FighterBody).is_local
	return body.is_in_group("player")


## Adds the streamed chunks within reach of a point to wanted (chunk -> metres from the
## point to the chunk, the least of them) and those within reach plus STREAM_KEEP to keep.
func _want_round(point: Vector3, reach: float, wanted: Dictionary, keep: Dictionary) -> void:
	var extent: float = chunk_size
	var corner: Vector3 = _grid_corner()
	var far: float = reach + STREAM_KEEP
	var low: Vector3i = Vector3i(((point - Vector3.ONE * far - corner) / extent).floor())
	var high: Vector3i = Vector3i(((point + Vector3.ONE * far - corner) / extent).floor())
	low = low.max(Vector3i.ZERO)
	high = high.min(_stream_grid - Vector3i.ONE)
	for chunk_x: int in range(low.x, high.x + 1):
		for chunk_z: int in range(low.z, high.z + 1):
			var floor_y: int = _stream_floor[chunk_x + chunk_z * _stream_grid.x]
			for chunk_y: int in range(low.y, mini(high.y, floor_y - 1) + 1):
				var chunk_coordinate := Vector3i(chunk_x, chunk_y, chunk_z)
				var chunk_low: Vector3 = corner + Vector3(chunk_coordinate) * extent
				var nearest: Vector3 = point.clamp(chunk_low, chunk_low + Vector3.ONE * extent)
				var distance: float = point.distance_to(nearest)
				if distance > far:
					continue
				keep[chunk_coordinate] = true
				if distance <= reach and distance < float(wanted.get(chunk_coordinate, INF)):
					wanted[chunk_coordinate] = distance


func _free_streamed_chunk(chunk_coordinate: Vector3i) -> void:
	var chunk: TerrainChunk = _chunks.get(chunk_coordinate) as TerrainChunk
	if chunk != null:
		remove_child(chunk)
		chunk.queue_free()
	_chunks.erase(chunk_coordinate)
	_stream_loaded.erase(chunk_coordinate)
	_field_cache.erase(chunk_coordinate)
	_pending_rebuild_chunk_coordinates.erase(chunk_coordinate)


## Starts the wanted streamed chunks, nearest first, a few to a task, on the pool's free
## places (only STREAM_TASKS_BEFORE_PLAY of them until play can begin).
func _fill_stream() -> void:
	var cells: int = get_cells_per_axis()
	var samples: int = (cells + 1) * (cells + 1) * (cells + 1)
	@warning_ignore("integer_division")
	var per_task: int = clampi(BUILD_TASK_SAMPLES / samples, 1, 8)
	var holding_back: bool = _world_building and _play_waiting
	while _stream_waiting() and _pool_load() < WORLD_BUILD_IN_FLIGHT:
		if holding_back and _stream_tasks.size() >= STREAM_TASKS_BEFORE_PLAY:
			return
		var batch: Array[Vector3i] = []
		while batch.size() < per_task and _stream_waiting():
			var chunk_coordinate: Vector3i = _stream_queue.pop_back()
			if (
				_stream_loaded.has(chunk_coordinate)
				or _stream_inflight.has(chunk_coordinate)
				or _inflight_chunk_coordinates.has(chunk_coordinate)
				or not _stream_wanted.has(chunk_coordinate)
			):
				continue
			# The edits so far go into this chunk's snapshot.
			_pending_rebuild_chunk_coordinates.erase(chunk_coordinate)
			_stream_inflight[chunk_coordinate] = true
			batch.append(chunk_coordinate)
		if batch.is_empty():
			continue
		var job: ChunkMeshBuilder.AsyncRebuildJob = ChunkMeshBuilder.AsyncRebuildJob.new()
		job.chunk_coordinates = batch
		job.settings = _make_thread_settings_snapshot()
		var task_id: int = WorkerThreadPool.add_task(
			ChunkMeshBuilder.run_async_job.bind(job),
			true,
			"%s streamed chunk" % _get_world_log_name()
		)
		_stream_tasks[task_id] = job


## Whether a streamed chunk waits to be started: any, once play has begun; before, only
## one within STREAM_URGENT of a body (the queue is nearest last, so it is the last one).
func _stream_waiting() -> bool:
	if _stream_queue.is_empty():
		return false
	if not (_world_building and _play_waiting):
		return true
	var nearest: Vector3i = _stream_queue[_stream_queue.size() - 1]
	return float(_stream_wanted.get(nearest, INF)) <= STREAM_URGENT


## Places the streamed chunks whose tasks are done, within the frame's budget; one no body
## keeps any more is dropped.
func _poll_stream() -> void:
	var deadline: int = Time.get_ticks_usec() + PLACE_BUDGET_USEC
	for task_id_variant: Variant in _stream_tasks.keys():
		if Time.get_ticks_usec() >= deadline:
			break
		var task_id: int = task_id_variant as int
		var job: ChunkMeshBuilder.AsyncRebuildJob = (
			_stream_tasks[task_id] as ChunkMeshBuilder.AsyncRebuildJob
		)
		if not job.collected:
			if not WorkerThreadPool.is_task_completed(task_id):
				continue
			WorkerThreadPool.wait_for_task_completion(task_id)
			job.collected = true
		while job.placed < job.chunk_coordinates.size() and Time.get_ticks_usec() < deadline:
			var chunk_coordinate: Vector3i = job.chunk_coordinates[job.placed]
			job.placed += 1
			_stream_inflight.erase(chunk_coordinate)
			var result: ChunkMeshBuilder.ChunkBuildResult = (
				job.batch_result.chunks[chunk_coordinate] as ChunkMeshBuilder.ChunkBuildResult
			)
			if not _stream_keep.has(chunk_coordinate) or _stream_loaded.has(chunk_coordinate):
				continue
			_build_chunk_at(chunk_coordinate, result, job.settings)
			_stream_loaded[chunk_coordinate] = true
			ground_placed.emit(_get_chunk_world_aabb(chunk_coordinate, job.settings))
		if job.placed >= job.chunk_coordinates.size():
			_stream_tasks.erase(task_id)


## Drops everything streamed (a rebuild, or the world leaving the tree): the tasks on the
## pool are let finish, since their jobs hold the settings.
func _reset_stream() -> void:
	for task_id_variant: Variant in _stream_tasks.keys():
		var job: ChunkMeshBuilder.AsyncRebuildJob = (
			_stream_tasks[task_id_variant] as ChunkMeshBuilder.AsyncRebuildJob
		)
		if not job.collected:
			WorkerThreadPool.wait_for_task_completion(task_id_variant as int)
	_stream_tasks.clear()
	_stream_inflight.clear()
	_stream_loaded.clear()
	_stream_wanted.clear()
	_stream_keep.clear()
	_stream_queue.clear()
	_stream_tick = 0


## Whether a chunk round a body (within GROUND_HOLD_REACH of its feet, and as far again as
## it falls in a quarter of a second) is not built yet, while the map builds or on a map that
## streams its underground: a body going on would walk off the built ground or fall through.
func ground_missing_under(body: Node3D) -> bool:
	if body == null or not (_world_building or _streaming()):
		return false
	var feet: Vector3 = body.global_position
	var fall: float = 0.0
	if body is CharacterBody3D:
		fall = maxf(-(body as CharacterBody3D).velocity.y, 0.0) * 0.25
	var reach: float = GROUND_HOLD_REACH
	var corner: Vector3 = _grid_corner()
	var low_point := Vector3(feet.x - reach, feet.y - reach - fall, feet.z - reach)
	var high_point := Vector3(feet.x + reach, feet.y + reach, feet.z + reach)
	var low: Vector3i = Vector3i(((low_point - corner) / chunk_size).floor())
	var high: Vector3i = Vector3i(((high_point - corner) / chunk_size).floor())
	low = low.max(Vector3i.ZERO)
	high = high.min(_stream_grid - Vector3i.ONE)
	for chunk_x: int in range(low.x, high.x + 1):
		for chunk_z: int in range(low.z, high.z + 1):
			for chunk_y: int in range(low.y, high.y + 1):
				var chunk_coordinate := Vector3i(chunk_x, chunk_y, chunk_z)
				if not _stands(chunk_coordinate):
					return true
	return false


## Stops any body about to walk or fall onto ground that is not built yet
## (GroundPlayer.hold_for_ground), until it is.
func _hold_bodies_off_missing_ground() -> void:
	for node: Node in get_tree().get_nodes_in_group("fighter"):
		var body: Node3D = node as Node3D
		if body == null or not body.has_method("hold_for_ground"):
			continue
		if ground_missing_under(body):
			body.call("hold_for_ground")


## Drops a background build that is still going (a full rebuild asked for meanwhile takes
## its place, or the world leaves the tree): the chunks on the pool are let finish, since
## their jobs hold the settings, and the rest are forgotten.
func _abandon_world_build() -> void:
	if not _world_building:
		return
	for task_id_variant: Variant in _world_build_tasks.keys():
		var job: ChunkMeshBuilder.AsyncRebuildJob = (
			_world_build_tasks[task_id_variant] as ChunkMeshBuilder.AsyncRebuildJob
		)
		if not job.collected:
			WorkerThreadPool.wait_for_task_completion(task_id_variant as int)
	_world_build_tasks.clear()
	_world_build_queue.clear()
	_world_building = false
	_placed.clear()
	_column_missing = PackedInt32Array()
	_world_build_settings = null
	_build_focus.clear()
	_primary_focus.clear()
	_order_focus.clear()
	_play_columns.clear()
	_play_chunks.clear()
	_deep.clear()
	_queue_stale = false


func _exit_tree() -> void:
	_abandon_world_build()
	_reset_stream()


func _make_world_job(
	settings: SettingsSnapshot, grid_dimensions: Vector3i
) -> ChunkMeshBuilder.ParallelBuildJob:
	var job: ChunkMeshBuilder.ParallelBuildJob = ChunkMeshBuilder.ParallelBuildJob.new()
	job.settings = settings
	for chunk_z: int in grid_dimensions.z:
		for chunk_y: int in grid_dimensions.y:
			for chunk_x: int in grid_dimensions.x:
				var chunk_coordinate := Vector3i(chunk_x, chunk_y, chunk_z)
				if _is_streamed(chunk_coordinate):
					continue
				job.chunk_coordinates.append(chunk_coordinate)
				job.results.append(ChunkMeshBuilder.ChunkBuildResult.new())
	return job


## Blocks until every chunk exists, but meshes the chunks on all WorkerThreadPool threads
## when use_threaded_rebuild is on.
func _rebuild_all_sync(settings: SettingsSnapshot, grid_dimensions: Vector3i) -> void:
	var rebuild_start_milliseconds: int = Time.get_ticks_msec()
	var job: ChunkMeshBuilder.ParallelBuildJob = _make_world_job(settings, grid_dimensions)
	if use_threaded_rebuild and job.chunk_coordinates.size() > 1:
		var group_task_id: int = WorkerThreadPool.add_group_task(
			ChunkMeshBuilder.run_parallel_job_element.bind(job),
			job.chunk_coordinates.size(),
			REBUILD_THREADS,
			true,
			"%s chunk rebuild" % _get_world_log_name()
		)
		WorkerThreadPool.wait_for_group_task_completion(group_task_id)
	else:
		for element_index: int in job.chunk_coordinates.size():
			ChunkMeshBuilder.run_parallel_job_element(element_index, job)
	for element_index: int in job.chunk_coordinates.size():
		_build_chunk_at(job.chunk_coordinates[element_index], job.results[element_index], settings)
	var elapsed_milliseconds: int = Time.get_ticks_msec() - rebuild_start_milliseconds
	_log_rebuild_complete(_chunks.size(), settings, grid_dimensions, elapsed_milliseconds)
	build_progress.emit(job.chunk_coordinates.size() * 2, job.chunk_coordinates.size() * 2)
	built.emit()


func _build_chunk_at(
	chunk_coordinate: Vector3i,
	chunk_build_result: ChunkMeshBuilder.ChunkBuildResult,
	settings: SettingsSnapshot
) -> void:
	var chunk: TerrainChunk = _CHUNK_SCRIPT.new()
	chunk.name = "Chunk_%d_%d_%d" % [chunk_coordinate.x, chunk_coordinate.y, chunk_coordinate.z]
	chunk.chunk_coordinate = chunk_coordinate
	if not is_playable_world:
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(chunk)
	chunk.apply_build_result(chunk_build_result, settings.rebuild_collision)
	if settings.material != null:
		chunk.material_override = settings.material
	_register_editor_scene_node(chunk)
	_chunks[chunk_coordinate] = chunk


func _log_rebuild_complete(
	chunk_count: int, settings: SettingsSnapshot, grid_dimensions: Vector3i, elapsed_ms: int
) -> void:
	print(
		"[%s] Rebuilt " % _get_world_log_name(),
		chunk_count,
		" chunks (",
		settings.cells_per_axis,
		" cells/axis, ",
		grid_dimensions.x,
		"×",
		grid_dimensions.y,
		"×",
		grid_dimensions.z,
		" grid) in ",
		elapsed_ms,
		" ms",
		_world_summary(settings)
	)


func get_chunk_count() -> int:
	return _chunks.size()


func get_total_vertex_count() -> int:
	var total: int = 0
	for chunk_coordinate_variant: Variant in _chunks.keys():
		var chunk: TerrainChunk = _chunks[chunk_coordinate_variant] as TerrainChunk
		if chunk == null or chunk.mesh == null:
			continue
		var array_mesh: ArrayMesh = chunk.mesh as ArrayMesh
		if array_mesh == null:
			continue
		for surface_idx: int in array_mesh.get_surface_count():
			total += array_mesh.surface_get_array_len(surface_idx)
	return total


func get_total_triangle_count() -> int:
	var total_indices: int = 0
	for chunk_coordinate_variant: Variant in _chunks.keys():
		var chunk: TerrainChunk = _chunks[chunk_coordinate_variant] as TerrainChunk
		if chunk == null or chunk.mesh == null:
			continue
		var array_mesh: ArrayMesh = chunk.mesh as ArrayMesh
		if array_mesh == null:
			continue
		for surface_idx: int in array_mesh.get_surface_count():
			total_indices += array_mesh.surface_get_array_index_len(surface_idx)
	return int(total_indices / 3)


func get_edited_voxel_count() -> int:
	return _edits.get_override_count()


func get_grid_dimensions() -> Vector3i:
	return _get_grid_dimensions()


func get_base_cells_per_axis() -> int:
	return maxi(1, int(round(chunk_size / voxel_size)))


func get_cells_per_axis() -> int:
	return get_base_cells_per_axis() * chunk_resolution


func get_voxels_per_chunk() -> int:
	var cells_per_axis: int = get_cells_per_axis()
	return cells_per_axis * cells_per_axis * cells_per_axis


func get_chunk_world_extent() -> float:
	return chunk_size


func get_world_step() -> float:
	return chunk_size / float(get_cells_per_axis())


func get_voxel_size() -> float:
	return get_world_step()


func get_world_extents() -> Vector3:
	var grid_dimensions: Vector3i = _get_grid_dimensions()
	return Vector3(grid_dimensions) * chunk_size


## World Y below which the ground is bedrock: CaveCarver.FLOOR_MARGIN above the bottom of the
## grid, where the caves stop and a footing stands.
func get_bedrock_y() -> float:
	var grid_dimensions: Vector3i = _get_grid_dimensions()
	return CaveCarver.bedrock_y(global_position.y, grid_dimensions.y, chunk_size)


## A footing for a builder to put under a structure: a stadium of the map's own ground (dug
## like the rest, stone and veins and all) from bedrock up to top_y, the dirt the structure
## stands on, so it stands on solid ground whatever the underside would have put there (the
## sponge of 3D noise with solid_underside off, or a cave). The footprint is a box of half_x
## by half_z about center, grown a voxel each way; the stadium's rounded ends reach its
## corners. Goes into solids.
func footing(center: Vector3, half_x: float, half_z: float, top_y: float) -> Dictionary:
	var margin: float = get_voxel_size()
	var along_z: bool = half_z > half_x
	var half_along: float = (half_z if along_z else half_x) + margin
	var half_across: float = (half_x if along_z else half_z) + margin
	var radius: float = half_across * sqrt(2.0)
	var bedrock: float = get_bedrock_y()
	return {
		"center": Vector3(center.x, bedrock, center.z),
		"half_length": half_along - half_across + radius,
		"radius": radius,
		"height": maxf(top_y - bedrock, 0.0),
		"along_z": along_z,
		"ground": true,
	}


func get_settings_snapshot() -> SettingsSnapshot:
	return _make_settings_snapshot()


func get_terrain_edits() -> TerrainEdits:
	return _edits


func begin_continuous_edit() -> void:
	_continuous_edit_depth += 1


func end_continuous_edit() -> void:
	_continuous_edit_depth = maxi(_continuous_edit_depth - 1, 0)
	if _continuous_edit_depth > 0:
		return
	_chunk_flush_pending = false
	if not _pending_rebuild_chunk_coordinates.is_empty():
		_dispatch_pending_rebuilds()


## Warms the chunk cache round a spot the brush may strike next (its hover point): the
## chunks the sphere touches that have no cached field get one built in the background,
## so the first stroke there resamples a few samples instead of reading the whole chunk.
## Cheap to call every frame; nothing is started for a chunk that is cached, in flight or
## queued, or that the map's build has not placed fine yet.
func prepare_edit_around(world_position: Vector3, radius: float) -> void:
	if not _use_threaded_rebuild():
		return
	for chunk_coordinate: Vector3i in _get_chunk_coordinates_intersecting_sphere(
		world_position, radius
	):
		if (
			_field_cache.has(chunk_coordinate)
			or _inflight_chunk_coordinates.has(chunk_coordinate)
			or _pending_rebuild_chunk_coordinates.has(chunk_coordinate)
			or not _chunks.has(chunk_coordinate)
			or not _stands(chunk_coordinate)
		):
			continue
		if _running_async_tasks >= max_concurrent_rebuild_tasks:
			return
		_start_single_chunk_async_rebuild(chunk_coordinate, false, AABB(), true)


## Queues a chunk for a rebuild of the samples inside bounds (world space), or whole when
## the bounds have no volume; a chunk already queued gets the union.
func _queue_chunk_rebuild(chunk_coordinate: Vector3i, bounds: AABB) -> void:
	var queued: Variant = _pending_rebuild_chunk_coordinates.get(chunk_coordinate)
	if queued == null:
		_pending_rebuild_chunk_coordinates[chunk_coordinate] = bounds
		return
	var queued_bounds: AABB = queued as AABB
	if not queued_bounds.has_volume() or not bounds.has_volume():
		_pending_rebuild_chunk_coordinates[chunk_coordinate] = AABB()
	else:
		_pending_rebuild_chunk_coordinates[chunk_coordinate] = queued_bounds.merge(bounds)


## Whether the ground is solid at a point: the map's own density with the players' edits on
## top, so a dug hole reads as air and a built wall as solid. False above the surface, in a
## cave, or on something that is not ground at all (a slab, a duct, a tree).
func is_solid_at(world_position: Vector3) -> bool:
	return density_at(world_position) < iso_level


## The density at a point as the drawn ground has it: the eight samples around it, with the
## edits on each, blended by distance. (An edit overrides whole samples, so reading the one
## nearest sample would call a point solid up to a metre outside a dug wall.) A caller
## asking about many nearby points in one go (the camera's arm) passes a dictionary and
## gets each sample evaluated once.
func density_at(world_position: Vector3, sample_cache: Dictionary = {}) -> float:
	_prepare_edits()
	var density: DensitySampler.WorldDensity = _get_bake_density()
	var step: float = get_world_step()
	var origin: Vector3 = get_grid_world_origin()
	var local: Vector3 = (world_position - origin) / step
	var base: Vector3 = local.floor()
	var frac: Vector3 = local - base
	var value: float = 0.0
	for corner: int in 8:
		var offset := Vector3(float(corner & 1), float((corner >> 1) & 1), float((corner >> 2) & 1))
		var weight: float = (
			(offset.x * frac.x + (1.0 - offset.x) * (1.0 - frac.x))
			* (offset.y * frac.y + (1.0 - offset.y) * (1.0 - frac.y))
			* (offset.z * frac.z + (1.0 - offset.z) * (1.0 - frac.z))
		)
		if weight <= 0.0:
			continue
		var key: Vector3i = Vector3i(base + offset)
		var sample: float
		if sample_cache.has(key):
			sample = sample_cache[key]
		else:
			var sample_position: Vector3 = origin + (base + offset) * step
			sample = density.evaluate(sample_position)
			if _edits != null:
				sample = _edits.apply_to_density(sample, sample_position)
			sample_cache[key] = sample
		value += sample * weight
	return value


## Can the brush (dig, build, explosion) change the terrain here? A builder may fence off part
## of the map (the garden's chain-link) by setting edit_bounds; a zero-size box allows anywhere.
func can_edit_at(world_position: Vector3) -> bool:
	return edit_bounds.size == Vector3.ZERO or edit_bounds.has_point(world_position)


## Carves a sphere (add_solid false) or fills one, with the map's own ground or a placed
## material (TerrainMaterials) that the terrain shader then shows instead of the ground.
func apply_brush(
	world_position: Vector3,
	radius: float,
	add_solid: bool,
	material: TerrainMaterials.Kind = TerrainMaterials.Kind.NATURAL
) -> void:
	apply_edit(sphere_edit(world_position, radius, add_solid, material))


## The block tool: fills (or carves) an axis-aligned box. Snap its centre with snap_to_sample and
## give it half extents of one voxel (plus a hair) for a crisp cube two voxels on a side.
func apply_box(
	center: Vector3,
	half_extents: Vector3,
	add_solid: bool,
	material: TerrainMaterials.Kind = TerrainMaterials.Kind.NATURAL
) -> void:
	apply_edit(box_edit(center, half_extents, add_solid, material))


static func sphere_edit(
	world_position: Vector3, radius: float, add_solid: bool, material: TerrainMaterials.Kind
) -> Dictionary:
	return {
		"kind": "sphere",
		"position": world_position,
		"radius": radius,
		"add": add_solid,
		"material": material
	}


static func box_edit(
	center: Vector3, half_extents: Vector3, add_solid: bool, material: TerrainMaterials.Kind
) -> Dictionary:
	return {
		"kind": "box",
		"position": center,
		"half_extents": half_extents,
		"add": add_solid,
		"material": material
	}


## The one way terrain changes: the brush, the block tool, explosive shots and (later) edits
## from other peers all come through here. An edit is a small dictionary (see sphere_edit and
## box_edit) that the host can validate, number and broadcast. Returns false when the edit was
## refused (outside the editable bounds, or it would bury a fighter) or changed nothing (a shot
## that burst in mid-air, re-carving an existing hole), so the chunks need no rebuild.
func apply_edit(edit: Dictionary) -> bool:
	var position: Vector3 = edit.get("position", Vector3.ZERO)
	var add_solid: bool = bool(edit.get("add", false))
	var material: TerrainMaterials.Kind = (
		int(edit.get("material", TerrainMaterials.Kind.NATURAL)) as TerrainMaterials.Kind
	)
	if not can_edit_at(position):
		return false
	if add_solid and buries_fighter(edit):
		return false
	if not allows_edit(edit):
		return false
	_prepare_edits()
	var density: DensitySampler.WorldDensity = _get_bake_density()
	var procedural_density: Callable = Callable(density, "evaluate")
	var natural_material: Callable = Callable(density, "ground_material")
	var changed: bool
	var reach: float
	if str(edit.get("kind", "sphere")) == "box":
		var half_extents: Vector3 = edit.get("half_extents", Vector3.ONE)
		changed = _edits.add_box(
			position, half_extents, add_solid, procedural_density, material, natural_material
		)
		reach = half_extents.length()
	else:
		var radius: float = float(edit.get("radius", 1.0))
		changed = _edits.add_brush(
			position, radius, add_solid, procedural_density, material, natural_material
		)
		reach = radius
	if not changed:
		return false
	edit["removed"] = _edits.last_removed.duplicate()
	edit["added"] = _edits.last_added
	if not edit.has("sequence"):
		edit["sequence"] = _next_edit_sequence
	_next_edit_sequence = maxi(_next_edit_sequence, int(edit["sequence"]) + 1)
	_edit_log.append(edit)
	_rebuild_changed_chunks()
	brush_applied.emit(position, reach)
	edit_applied.emit(edit)
	return true


## Whether the mode's gate lets an edit through (everything goes without one).
func allows_edit(edit: Dictionary) -> bool:
	return not edit_gate.is_valid() or bool(edit_gate.call(edit))


## Roughly how many voxels an edit's shape covers, before knowing what is already solid.
static func estimate_voxels(edit: Dictionary, voxel_size: float) -> int:
	var volume: float
	if str(edit.get("kind", "sphere")) == "box":
		var half: Vector3 = edit.get("half_extents", Vector3.ONE)
		volume = 8.0 * half.x * half.y * half.z
	else:
		var radius: float = float(edit.get("radius", 1.0))
		volume = 4.0 / 3.0 * PI * radius * radius * radius
	return maxi(ceili(volume / (voxel_size * voxel_size * voxel_size)), 1)


## Every edit applied so far, in sequence order.
func get_edit_log() -> Array[Dictionary]:
	return _edit_log


## The edited voxels as one package for a late joiner (import_edit_state on the other side).
func export_edit_state() -> Dictionary:
	return {"next_sequence": _next_edit_sequence, "edits": _edits.export_state()}


func import_edit_state(state: Dictionary) -> void:
	_prepare_edits()
	_edits.import_state(state.get("edits", {}))
	_next_edit_sequence = int(state.get("next_sequence", 1))
	_edit_log.clear()
	var bounds: AABB = _edits.get_all_bounds()
	if bounds.size == Vector3.ZERO:
		return
	for chunk_coordinate: Vector3i in _get_chunk_coordinates_intersecting_aabb(bounds):
		_queue_chunk_rebuild(chunk_coordinate, AABB())
	_pending_rebuild_collision = true
	_dispatch_pending_rebuilds()


## Would this ADD edit overlap a fighter's capsule? The brush greys its preview on this, and
## apply_edit refuses such edits whoever sent them.
func buries_fighter(edit: Dictionary) -> bool:
	for node: Node in get_tree().get_nodes_in_group("fighter"):
		var body: Node3D = node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		if body is FighterBody and not (body as FighterBody).is_in_play():
			continue
		if _edit_overlaps_body(edit, body):
			return true
	return false


## Points along a body's capsule axis, from the bottom sphere centre to the top one, plus the
## capsule radius. Without a capsule the body is a 0.6 m sphere at its origin.
func _capsule_points(body: Node3D) -> Dictionary:
	var points: PackedVector3Array = PackedVector3Array()
	var collider: CollisionShape3D = null
	for child: Node in body.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is CapsuleShape3D:
			collider = child as CollisionShape3D
			break
	if collider == null:
		points.append(body.global_position + Vector3.UP * 0.6)
		return {"points": points, "radius": 0.6}
	var capsule: CapsuleShape3D = collider.shape as CapsuleShape3D
	var axis: Vector3 = collider.global_basis.y.normalized()
	var half_segment: float = maxf(capsule.height * 0.5 - capsule.radius, 0.0)
	var center: Vector3 = collider.global_position
	for index: int in CAPSULE_SAMPLES:
		var t: float = float(index) / float(CAPSULE_SAMPLES - 1) * 2.0 - 1.0
		points.append(center + axis * (half_segment * t))
	return {"points": points, "radius": capsule.radius}


func _edit_overlaps_body(edit: Dictionary, body: Node3D) -> bool:
	var capsule: Dictionary = _capsule_points(body)
	var center: Vector3 = edit.get("position", Vector3.ZERO)
	var limit: float = (capsule.radius as float) + FIGHTER_CLEARANCE
	if str(edit.get("kind", "sphere")) == "box":
		var half_extents: Vector3 = edit.get("half_extents", Vector3.ONE)
		for point: Vector3 in capsule.points as PackedVector3Array:
			var outside: Vector3 = ((point - center).abs() - half_extents).max(Vector3.ZERO)
			if outside.length() < limit:
				return true
		return false
	var radius: float = float(edit.get("radius", 1.0))
	for point: Vector3 in capsule.points as PackedVector3Array:
		if point.distance_to(center) < radius + limit:
			return true
	return false


## World position of the origin of the sample lattice: samples sit at origin + integer * voxel size.
func get_grid_world_origin() -> Vector3:
	return global_position + get_grid_origin_local()


## Nearest sample position to a world position.
func snap_to_sample(world_position: Vector3) -> Vector3:
	var origin: Vector3 = get_grid_world_origin()
	var step: float = get_voxel_size()
	return origin + ((world_position - origin) / step).round() * step


func _prepare_edits() -> void:
	_edits.set_voxel_size(get_voxel_size())
	_edits.set_grid_origin(get_grid_world_origin())


## Rebuilds only the chunks holding voxels the last edit changed, not every chunk it grazed.
func _rebuild_changed_chunks() -> void:
	var changed: AABB = _edits.get_last_changed_bounds()
	var chunk_coordinates: Array[Vector3i] = _get_chunk_coordinates_intersecting_aabb(changed)
	for chunk_coordinate: Vector3i in chunk_coordinates:
		_queue_chunk_rebuild(chunk_coordinate, changed)
	_pending_rebuild_collision = true
	_dispatch_pending_rebuilds()


func get_grid_origin_local() -> Vector3:
	return -get_world_extents() * 0.5


func _make_settings_snapshot() -> SettingsSnapshot:
	var settings: SettingsSnapshot = SettingsSnapshot.new()
	var grid_dimensions: Vector3i = _get_grid_dimensions()
	var world_step: float = get_world_step()
	settings.chunks_x = grid_dimensions.x
	settings.chunks_y = grid_dimensions.y
	settings.chunks_z = grid_dimensions.z
	settings.cells_per_axis = get_cells_per_axis()
	settings.voxel_size = world_step
	settings.bounds_clip_inset = maxf(chunk_size * 0.05, 0.25)
	settings.chunk_world_size = chunk_size
	settings.chunk_resolution = chunk_resolution
	settings.iso_level = iso_level
	settings.world_origin = global_position
	settings.noise_enabled = noise_enabled
	settings.noise_seed = noise_seed
	settings.noise_frequency = noise_frequency
	settings.noise_amplitude = noise_amplitude
	settings.noise_octaves = noise_octaves
	settings.noise_lacunarity = noise_lacunarity
	settings.noise_gain = noise_gain
	settings.generate_collision = generate_collision
	settings.loose_rock_voxels = loose_rock_voxels
	settings.caves_enabled = caves_enabled
	settings.material = _effective_material()
	settings.bounds_center = global_position
	settings.bounds_half = get_world_extents() * 0.5
	settings.terrain_edits = _edits
	settings.solids = solids
	settings.rebuild_collision = settings.generate_collision
	_apply_world_specific_settings(settings)
	# The chunks are built from this world's own density (caves, terraces and all), on worker
	# threads too: _build_world_density reads the snapshot alone.
	settings.density_factory = _build_world_density
	return settings


## Drops every built chunk. Chunks are matched by name as well as by script, because after
## the editor hot-reloads a terrain script the live chunks can fail the script check and
## would otherwise stay in the scene under the next build, as a second ground cutting through.
## They leave the tree at once and are freed at the end of the frame, in the editor too: the
## renderer gets the old meshes' frees and the new meshes' uploads in order, instead of
## freeing a mesh in the middle of a rebuild that is about to upload twenty-seven more.
func _clear_chunks() -> void:
	for child in get_children():
		if not (child is _CHUNK_SCRIPT or String(child.name).begins_with("Chunk_")):
			continue
		remove_child(child)
		child.queue_free()
	_reset_stream()
	_chunks.clear()
	_field_cache.clear()
	_pending_rebuild_chunk_coordinates.clear()


func _request_rebuild() -> void:
	if not is_node_ready():
		return
	if Engine.is_editor_hint() and not auto_rebuild_in_editor:
		return
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_deferred_rebuild")


func _deferred_rebuild() -> void:
	_rebuild_queued = false
	rebuild_all()


func _use_threaded_rebuild() -> bool:
	return use_threaded_rebuild and not Engine.is_editor_hint()


func _dispatch_pending_rebuilds() -> void:
	if _pending_rebuild_chunk_coordinates.is_empty():
		return
	var rebuild_collision: bool = _pending_rebuild_collision
	if rebuild_collision:
		_pending_rebuild_collision = false
	var deferred_chunk_coordinates: Array[Vector3i] = []
	for chunk_coordinate_variant: Variant in _pending_rebuild_chunk_coordinates.keys():
		var chunk_coordinate: Vector3i = chunk_coordinate_variant as Vector3i
		# A chunk in flight, or one the map's build has not placed yet, keeps its turn. A
		# streamed chunk nobody has built or is building needs none: when it is built, it
		# takes the edits as they are then.
		if (
			_is_streamed(chunk_coordinate)
			and not _chunks.has(chunk_coordinate)
			and not _stream_inflight.has(chunk_coordinate)
		):
			_pending_rebuild_chunk_coordinates.erase(chunk_coordinate)
			continue
		if _inflight_chunk_coordinates.has(chunk_coordinate) or not _chunks.has(chunk_coordinate):
			deferred_chunk_coordinates.append(chunk_coordinate)
			continue
		if _running_async_tasks >= max_concurrent_rebuild_tasks:
			deferred_chunk_coordinates.append(chunk_coordinate)
			continue
		var bounds: AABB = _pending_rebuild_chunk_coordinates[chunk_coordinate] as AABB
		_pending_rebuild_chunk_coordinates.erase(chunk_coordinate)
		_start_single_chunk_async_rebuild(chunk_coordinate, rebuild_collision, bounds)
	for chunk_coordinate: Vector3i in deferred_chunk_coordinates:
		if not _pending_rebuild_chunk_coordinates.has(chunk_coordinate):
			_pending_rebuild_chunk_coordinates[chunk_coordinate] = AABB()
	if rebuild_collision and not deferred_chunk_coordinates.is_empty():
		_pending_rebuild_collision = true


func _schedule_chunk_coordinate_rebuilds(
	chunk_coordinates: Array[Vector3i], rebuild_collision: bool
) -> void:
	if chunk_coordinates.is_empty():
		return
	if _use_threaded_rebuild():
		for chunk_coordinate: Vector3i in chunk_coordinates:
			_queue_chunk_rebuild(chunk_coordinate, AABB())
		if rebuild_collision:
			_pending_rebuild_collision = true
		_dispatch_pending_rebuilds()
	else:
		var settings: SettingsSnapshot = _make_settings_snapshot()
		settings.rebuild_collision = settings.generate_collision and rebuild_collision
		_rebuild_chunk_coordinates(chunk_coordinates, settings)


func _start_single_chunk_async_rebuild(
	chunk_coordinate: Vector3i,
	rebuild_collision: bool,
	bounds: AABB = AABB(),
	prepare_only: bool = false
) -> void:
	_inflight_chunk_coordinates[chunk_coordinate] = true
	var async_rebuild_job: ChunkMeshBuilder.AsyncRebuildJob = ChunkMeshBuilder.AsyncRebuildJob.new()
	async_rebuild_job.chunk_coordinates = [chunk_coordinate]
	async_rebuild_job.rebuild_collision = rebuild_collision
	async_rebuild_job.prepare_only = prepare_only
	async_rebuild_job.settings = _make_thread_settings_snapshot()
	async_rebuild_job.settings.keep_field = true
	if bounds.has_volume() and _field_cache.has(chunk_coordinate):
		var cached: ChunkMeshBuilder.ChunkCache = _field_cache[chunk_coordinate]
		async_rebuild_job.settings.cached_field = cached.field
		async_rebuild_job.settings.cached_blocks = cached.blocks
		async_rebuild_job.settings.resample_bounds = bounds
	# High priority: the pool keeps most of its threads for these, and a stroke's chunks
	# should all be in hand at once.
	async_rebuild_job.task_id = WorkerThreadPool.add_task(
		ChunkMeshBuilder.run_async_job.bind(async_rebuild_job), true, "Chunk rebuild"
	)
	_async_jobs[async_rebuild_job.task_id] = async_rebuild_job
	_running_async_tasks += 1


func _poll_async_rebuilds() -> void:
	if not _async_jobs.is_empty():
		var completed_task_ids: Array[int] = []
		for task_id_variant: Variant in _async_jobs.keys():
			var task_id: int = task_id_variant as int
			if WorkerThreadPool.is_task_completed(task_id):
				completed_task_ids.append(task_id)
		for completed_task_id: int in completed_task_ids:
			var async_rebuild_job: ChunkMeshBuilder.AsyncRebuildJob = (
				_async_jobs[completed_task_id] as ChunkMeshBuilder.AsyncRebuildJob
			)
			_async_jobs.erase(completed_task_id)
			WorkerThreadPool.wait_for_task_completion(completed_task_id)
			_running_async_tasks = maxi(_running_async_tasks - 1, 0)
			_apply_async_job(async_rebuild_job)
	if (
		_running_async_tasks < max_concurrent_rebuild_tasks
		and not _pending_rebuild_chunk_coordinates.is_empty()
	):
		_dispatch_pending_rebuilds()


func _apply_async_job(async_rebuild_job: ChunkMeshBuilder.AsyncRebuildJob) -> void:
	for chunk_coordinate: Vector3i in async_rebuild_job.chunk_coordinates:
		_inflight_chunk_coordinates.erase(chunk_coordinate)
		var chunk: TerrainChunk = _chunks.get(chunk_coordinate) as TerrainChunk
		if chunk == null:
			continue
		var chunk_build_result: ChunkMeshBuilder.ChunkBuildResult = (
			async_rebuild_job.batch_result.chunks.get(chunk_coordinate)
			as ChunkMeshBuilder.ChunkBuildResult
		)
		if chunk_build_result == null:
			continue
		if not async_rebuild_job.prepare_only:
			chunk.apply_build_result(chunk_build_result, generate_collision)
			chunk_rebuilt.emit(_get_chunk_world_aabb(chunk_coordinate, async_rebuild_job.settings))
			if _effective_material() != null:
				chunk.material_override = _effective_material()
		if chunk_build_result.field != null:
			var cached := ChunkMeshBuilder.ChunkCache.new()
			cached.field = chunk_build_result.field
			cached.blocks = chunk_build_result.blocks
			_field_cache.erase(chunk_coordinate)
			_field_cache[chunk_coordinate] = cached
			while _field_cache.size() > FIELD_CACHE_CHUNKS:
				_field_cache.erase(_field_cache.keys()[0])


func _make_thread_settings_snapshot() -> SettingsSnapshot:
	var settings: SettingsSnapshot = _make_settings_snapshot()
	if settings.terrain_edits != null:
		settings.terrain_edits = settings.terrain_edits.duplicate_for_thread()
	return settings


## What this world's ground came out as, for the rebuild log ("" when there is nothing to
## say): an open terrain names its terraces and caves.
func _world_summary(_settings: SettingsSnapshot) -> String:
	return ""


func _build_world_density(settings: SettingsSnapshot) -> DensitySampler.WorldDensity:
	return DensitySampler.WorldDensity.create(
		settings.noise_enabled,
		settings.noise_seed,
		settings.noise_frequency,
		settings.noise_amplitude,
		settings.noise_octaves,
		settings.noise_lacunarity,
		settings.noise_gain,
		settings.bounds_center,
		settings.bounds_half,
		settings.bounds_clip_inset
	)


func _invalidate_bake_density() -> void:
	_bake_density = null


func _get_bake_density() -> DensitySampler.WorldDensity:
	if _bake_density == null:
		var settings: SettingsSnapshot = _make_settings_snapshot()
		_bake_density = _build_world_density(settings)
		_bake_density.solids = settings.solids
	return _bake_density


func _rebuild_chunk_coordinates(
	chunk_coordinates: Array[Vector3i], settings: SettingsSnapshot = null
) -> void:
	if chunk_coordinates.is_empty():
		return
	if settings == null:
		settings = _make_settings_snapshot()
	for chunk_coordinate: Vector3i in chunk_coordinates:
		var chunk: TerrainChunk = _chunks.get(chunk_coordinate) as TerrainChunk
		if chunk == null:
			continue
		chunk.rebuild(settings)
		if settings.material != null:
			chunk.material_override = settings.material


func _get_chunk_coordinates_intersecting_sphere(center: Vector3, radius: float) -> Array[Vector3i]:
	return _get_chunk_coordinates_intersecting_aabb(
		AABB(center - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)
	)


## Chunks whose density samples a world-space box can touch (padded so edge samples shared with
## neighboring chunks count too), from the box's span of the grid: a test of every chunk's
## box costs milliseconds a call on a map of thousands of chunks, and the brush asks every
## frame. While the map builds, chunks not yet placed count too: an edit there waits for
## the chunk and rebuilds it once it stands; otherwise only chunks that stand.
func _get_chunk_coordinates_intersecting_aabb(bounds: AABB) -> Array[Vector3i]:
	var chunk_coordinates: Array[Vector3i] = []
	var settings: SettingsSnapshot = _make_settings_snapshot()
	var search_aabb: AABB = bounds.grow(get_voxel_size() * 2.0)
	var extent: float = settings.chunk_world_size
	var origin: Vector3 = global_position + _chunk_corner_local(Vector3i.ZERO, settings)
	var grid: Vector3i = _world_build_grid if _world_building else _get_grid_dimensions()
	# As AABB.intersects has it, a box that only touches a chunk's face from outside does
	# not reach it: the last chunk is the one holding the box's end, or the one before
	# when the end lies on a seam.
	var low: Vector3i = Vector3i(((search_aabb.position - origin) / extent).floor())
	low = low.max(Vector3i.ZERO)
	var high: Vector3i = Vector3i(((search_aabb.end - origin) / extent).ceil()) - Vector3i.ONE
	high = high.min(grid - Vector3i.ONE)
	for chunk_z: int in range(low.z, high.z + 1):
		for chunk_y: int in range(low.y, high.y + 1):
			for chunk_x: int in range(low.x, high.x + 1):
				var chunk_coordinate := Vector3i(chunk_x, chunk_y, chunk_z)
				if _is_streamed(chunk_coordinate):
					# Built, or being built (it rebuilds once it stands): one nobody has
					# built takes the edits when it is.
					if _chunks.has(chunk_coordinate) or _stream_inflight.has(chunk_coordinate):
						chunk_coordinates.append(chunk_coordinate)
				elif _world_building or _chunks.has(chunk_coordinate):
					chunk_coordinates.append(chunk_coordinate)
	return chunk_coordinates


func _get_chunk_world_aabb(chunk_coordinate: Vector3i, settings: SettingsSnapshot) -> AABB:
	var extent: float = settings.chunk_world_size
	var corner_local: Vector3 = _chunk_corner_local(chunk_coordinate, settings)
	var world_corner: Vector3 = global_position + corner_local
	return AABB(world_corner, Vector3.ONE * extent)


func _chunk_corner_local(chunk_coordinate: Vector3i, settings: SettingsSnapshot) -> Vector3:
	var extent: float = settings.chunk_world_size
	var grid_origin: Vector3 = (
		-Vector3(settings.chunks_x, settings.chunks_y, settings.chunks_z) * extent * 0.5
	)
	return grid_origin + Vector3(chunk_coordinate) * extent


func _effective_material() -> Material:
	return terrain_material


func _register_editor_scene_node(node: Node) -> void:
	if not Engine.is_editor_hint():
		return
	var edited_scene_root: Node = get_tree().edited_scene_root
	if edited_scene_root == null:
		return
	_assign_scene_owner(node, edited_scene_root)


func _assign_scene_owner(node: Node, scene_root: Node) -> void:
	if node != scene_root:
		node.owner = scene_root
	for child in node.get_children():
		_assign_scene_owner(child, scene_root)


class SettingsSnapshot:
	var chunks_x: int = 3
	var chunks_y: int = 3
	var chunks_z: int = 3
	var cells_per_axis: int = 12
	var voxel_size: float = 1.0
	var iso_level: float = 0.0
	var world_origin: Vector3 = Vector3.ZERO
	var chunk_world_size: float = 12.0
	var chunk_resolution: int = 1
	var noise_enabled: bool = true
	var noise_seed: int = 42
	var noise_frequency: float = 0.08
	var noise_amplitude: float = 3.0
	var noise_octaves: int = 3
	var noise_lacunarity: float = 2.0
	var noise_gain: float = 0.5
	var generate_collision: bool = true
	## Floating rock of up to this many voxels is cleared from a chunk's field (LooseRock).
	var loose_rock_voxels: int = 8
	var caves_enabled: bool = false
	var material: Material = null
	var bounds_center: Vector3 = Vector3.ZERO
	var bounds_half: Vector3 = Vector3.ZERO
	var bounds_clip_inset: float = 0.5
	var boxed_in_terrain_enabled: bool = false
	var boxed_in_edges_enabled: bool = true
	var open_terrain_enabled: bool = false
	var open_terrain_edges_enabled: bool = true
	var open_terrain_solid_fill: bool = false
	var open_terrain_heightmap_image: Image = null
	var open_terrain_surface_offset: float = 0.0
	## Terraces on an open terrain (OpenTerrain.Terraces: seeded, always or never), the chance
	## a seed has them, the tread height and strength ranges they are rolled from, and the
	## share of the ground they cover.
	var open_terrain_terraces: int = 0
	var open_terrain_terrace_chance: float = 0.4
	var open_terrain_terrace_step: Vector2 = Vector2(1.5, 5.0)
	var open_terrain_terrace_strength: Vector2 = Vector2(0.35, 1.0)
	var open_terrain_terrace_coverage: float = 0.5
	var open_terrain_character: int = 0
	var open_terrain_character_power: Vector2 = Vector2(0.7, 1.6)
	var open_terrain_character_warp_chance: float = 0.5
	var open_terrain_character_warp: Vector2 = Vector2(10.0, 40.0)
	var open_terrain_character_ridge_chance: float = 0.35
	var open_terrain_character_ridge: Vector2 = Vector2(0.2, 0.5)
	## The cave roll (OpenTerrain.CaveRoll) and, when fixed, the CaveCarver field values the
	## sliders set, by field name.
	var open_terrain_cave_roll: int = 0
	var open_terrain_cave_values: Dictionary = {}
	## The ranges a seeded roll draws from (field name to Vector2), and the shape every
	## seed shares whatever the roll (field name to value), both from the OpenTerrain node.
	var open_terrain_cave_ranges: Dictionary = {}
	var open_terrain_cave_shape: Dictionary = {}
	## The land and cave biomes as data (Biome.to_data, plain values for the worker threads)
	## and the metres across their patches are.
	var open_terrain_land_biomes: Array[Dictionary] = []
	var open_terrain_land_patch: float = 400.0
	var open_terrain_cave_biomes: Array[Dictionary] = []
	var open_terrain_cave_patch: float = 250.0
	## The noise roll (OpenTerrain.NoiseRoll) and the ranges a seed draws its noise from.
	var open_terrain_noise_roll: int = 0
	var open_terrain_roll_frequency: Vector2 = Vector2(0.004, 0.01)
	var open_terrain_roll_amplitude: Vector2 = Vector2(8.0, 40.0)
	var open_terrain_roll_octaves: Vector2i = Vector2i(2, 5)
	var open_terrain_roll_lacunarity: Vector2 = Vector2(1.8, 2.6)
	var open_terrain_roll_gain: Vector2 = Vector2(0.3, 0.65)
	## Regions and the height curve (OpenTerrain.Regions) and their chances and ranges.
	var open_terrain_regions: int = 0
	var open_terrain_region_chance: float = 0.7
	var open_terrain_region_size: Vector2 = Vector2(500.0, 900.0)
	var open_terrain_region_lowland: Vector2 = Vector2(0.1, 0.35)
	var open_terrain_region_ridge: Vector2 = Vector2(0.3, 0.8)
	var open_terrain_region_detail: Vector2 = Vector2(0.1, 0.3)
	var open_terrain_floor_chance: float = 0.6
	var open_terrain_floor_level: Vector2 = Vector2(0.2, 0.45)
	var open_terrain_cliff_chance: float = 0.5
	var open_terrain_cliff_strength: Vector2 = Vector2(0.4, 0.8)
	var open_terrain_cliff_level: Vector2 = Vector2(0.4, 0.6)
	var open_terrain_cliff_width: Vector2 = Vector2(0.08, 0.2)
	## Relief and flat spots (OpenTerrain.Relief) and their chance and ranges.
	var open_terrain_relief: int = 0
	var open_terrain_relief_chance: float = 0.6
	var open_terrain_relief_amplitude: Vector2 = Vector2(1.5, 3.5)
	var open_terrain_flat_spot_count: Vector2i = Vector2i(2, 4)
	var open_terrain_flat_spot_radius: Vector2 = Vector2(8.0, 14.0)
	var terrain_edits: TerrainEdits = null
	## A brush rebuild: the chunk's field as last built and the world-space box whose samples
	## changed, so only those are read again; and whether the built field comes back with the
	## result for the next stroke.
	var cached_field: SignedDensityField = null
	var cached_blocks: ChunkMeshBlocks = null
	var resample_bounds: AABB = AABB()
	var keep_field: bool = false
	## Solid ground a map builder adds on top of the shape (DensitySampler.WorldDensity.solids).
	var solids: Array[Dictionary] = []
	var rebuild_collision: bool = true
	## A world with ground of its own kind builds its density here:
	## a static function taking the snapshot, called on worker threads too. Invalid: the
	## builder picks a density from the flags above.
	var density_factory: Callable = Callable()
