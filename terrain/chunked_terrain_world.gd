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

const _CHUNK_SCRIPT = preload("res://terrain/terrain_chunk.gd")
## Worker threads a full rebuild is split over. GDScript on many threads contends in the
## engine (object lookups, reference counts) rather than scaling: measured 2026-11-09 on a
## 20-core machine, 48 garden-sized chunks took 784 ms on one thread, 315 ms on four and
## 1641 ms on all twenty. Four is the sweet spot by a wide margin either side.
const REBUILD_THREADS: int = 4
## How many edited chunks keep their last field for the next stroke (about 150 KB each at
## 32 cells).
const FIELD_CACHE_CHUNKS: int = 64

## Metres of air an ADD edit must leave around a fighter's capsule to be allowed. Terrain
## collision is one-sided, so a fighter sealed inside new rock falls out of the world.
const FIGHTER_CLEARANCE: float = 0.1
## Points tested along a capsule's axis when checking an edit against it.
const CAPSULE_SAMPLES: int = 6
## Main-thread time a frame gives to placing built chunks in the scene (mesh upload and
## collision) during the map's background build.
const PLACE_BUDGET_USEC: int = 8000
## Chunks of the map's background build on the pool at once: the four threads the build
## scales to, plus one queued so no thread waits for the next frame's poll.
const WORLD_BUILD_IN_FLIGHT: int = 5
## The map's build first lays the whole map at this voxel size, a few seconds' work, so
## the ground looks complete and holds a body from the first frame; the fine build then
## replaces it chunk by chunk, the surface nearest the player first
## (_sort_world_build_queue).
const COARSE_VOXEL: float = 4.0
## The ground play waits for round the local player's spawn: this many chunks each way,
## so a sprint from the spawn stays on fine ground. A bot waits for its own column only.
const PLAY_RING_CHUNKS: int = 2
## A chunk whose top lies this far under the lowest surface of its column is deep: caves
## and bedrock, which nobody sees until they dig, so the fine pass lays the surface of the
## whole map before them. Two coarse voxels, so the coarse chunk under a fine surface
## chunk stays buried.
const DEEP_MARGIN: float = 2.0 * COARSE_VOXEL

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
## and lower the other. The surface sits at the box's centre and chunks above the top are
## not built, so amplitude plus offset must stay under half the box height (48 m on the
## maps' three 32 m chunks), or the peaks come out flat-topped.
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
## The map's build in the background (the game's rebuild on ready): each chunk its own
## task on the worker pool, nearest the build's focus first, placed as it comes in.
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
## Chunk columns (x, z) the focuses cover: the ground play waits for.
var _play_columns: Dictionary = {}
## Chunk column (x, z) -> fine chunks of its surface band placed so far, during the
## background build (the deep chunks under it are not waited for).
var _placed_in_column: Dictionary = {}
## Chunk coordinate -> true for a deep chunk (DEEP_MARGIN under its column's lowest
## surface), and chunk column (x, z) -> how many of its chunks are, during the build.
var _deep: Dictionary = {}
var _deep_in_column: Dictionary = {}
## The coarse pass of the map's build (COARSE_VOXEL): whether its chunks are still being
## handed out, how many stand, and how many it has in all (0 when the map is that coarse
## already or its chunks too small for it).
var _coarse_pass: bool = false
var _coarse_placed: int = 0
var _coarse_total: int = 0
## Chunk coordinate -> true once its fine chunk stands (the coarse one, if any, replaced).
var _placed_fine: Dictionary = {}
## Chunk coordinate -> true once any chunk stands there, coarse or fine, and chunk column
## (x, z) -> how many of its chunks do.
var _placed_any: Dictionary = {}
var _standing_in_column: Dictionary = {}
## Boxes of fine chunks that replaced coarse ones: a body standing there is lifted onto
## the new ground a physics step or two later, since the fine surface can sit higher.
var _lift_pending: Array[AABB] = []
var _lift_checks: Array[AABB] = []


func _ready() -> void:
	_ensure_world_defaults()
	if is_playable_world:
		add_to_group("terrain_world")
		_register_playable_groups()
	if rebuild_on_ready and not Engine.is_editor_hint():
		call_deferred("_begin_ready_build")


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _world_building:
		_poll_world_build()
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
## tests and the terrarium's room rely on that). A map with many chunks takes seconds and no
## frame is drawn meanwhile; the game's rebuild on ready goes through _begin_ready_build.
func rebuild_all() -> void:
	_abandon_world_build()
	_invalidate_bake_density()
	_ensure_world_defaults()
	_clear_chunks()
	var settings: SettingsSnapshot = _make_settings_snapshot()
	var grid_dimensions: Vector3i = _get_grid_dimensions()
	_rebuild_all_sync(settings, grid_dimensions)


## Whether the map's background build (see _begin_ready_build) is still going. The ground
## comes in nearest the build's focus first, so play starts before the map is done: a
## spawn waits on is_ground_ready_around, the loading screen on play_ground_ready.
func is_building() -> bool:
	return _world_building


## Points the map's build at a spot: the chunks nearest it (and the other spots given so
## far) come first, and the columns within radius of it are ground play waits for. A
## spawn calls this with where it will stand. The local player's placement is primary:
## the fine pass is ordered round it alone, a later one replaces it, and play waits for
## the ground PLAY_RING_CHUNKS each way round it. Takes effect within a few chunks.
func focus_build_at(world_position: Vector3, radius: float = 0.0, primary: bool = false) -> void:
	var focus := Vector4(world_position.x, world_position.y, world_position.z, radius)
	_build_focus.append(focus)
	var reach: float = radius
	if primary:
		_primary_focus.clear()
		_primary_focus.append(focus)
		reach = maxf(radius, float(PLAY_RING_CHUNKS) * _build_settings().chunk_world_size)
	for column: Vector2i in _columns_touching(world_position, reach):
		_play_columns[column] = true
	if _world_building:
		_queue_stale = true


## Whether every chunk column within radius of a spot stands, coarse or fine (its surface
## band fine, with fine: the deep chunks under it come later): always once the map's
## build is done, and for a spot off the grid. A body can stand on coarse ground; it is
## lifted onto the fine surface when that comes.
func is_ground_ready_around(
	world_position: Vector3, radius: float = 0.0, fine: bool = false
) -> bool:
	if not _world_building:
		return true
	for column: Vector2i in _columns_touching(world_position, radius):
		if fine:
			if not _column_fine(column):
				return false
		elif int(_standing_in_column.get(column, 0)) < _world_build_grid.y:
			return false
	return true


## Whether the ground play needs stands, so play can begin: the whole map coarse and the
## surface band of the columns every focus asked for fine. False while the map builds and
## no focus is set, since nothing says yet where play is.
func play_ground_ready() -> bool:
	if not _world_building:
		return true
	if _coarse_placed < _coarse_total or _play_columns.is_empty():
		return false
	for column: Vector2i in _play_columns:
		if not _column_fine(column):
			return false
	return true


## Whether a chunk stands at every coordinate of the map, coarse or fine, so a body can
## walk anywhere without stepping off the ground into a column that has none yet. Always
## once the map's build is done.
func ground_stands_everywhere() -> bool:
	return not _world_building or _placed_any.size() >= _world_build_total


## The chunks of a column that are not deep: what fine ground there means.
func _surface_chunks(column: Vector2i) -> int:
	return _world_build_grid.y - int(_deep_in_column.get(column, 0))


func _column_fine(column: Vector2i) -> bool:
	return int(_placed_in_column.get(column, 0)) >= _surface_chunks(column)


## The settings the build runs on, or the next one would.
func _build_settings() -> SettingsSnapshot:
	return _world_build_settings if _world_build_settings != null else _make_settings_snapshot()


## The game's build of the map: each chunk is meshed on the worker pool as a task of its
## own while the frames keep coming and placed in the scene as it comes in (the loading
## screen draws its bar from build_progress). The whole map goes in coarse first
## (COARSE_VOXEL), then fine: the surface nearest the player first and the deep chunks
## last (_sort_world_build_queue). Without threads it builds blocking, as rebuild_all does.
func _begin_ready_build() -> void:
	if not use_threaded_rebuild:
		rebuild_all()
		return
	_abandon_world_build()
	_invalidate_bake_density()
	_ensure_world_defaults()
	_clear_chunks()
	_world_build_settings = _make_settings_snapshot()
	_world_build_grid = _get_grid_dimensions()
	_mark_deep_chunks()
	_queue_every_chunk()
	_world_build_total = _world_build_queue.size()
	_world_build_placed = 0
	_placed_in_column.clear()
	_placed_fine.clear()
	_placed_any.clear()
	_standing_in_column.clear()
	_lift_pending.clear()
	_lift_checks.clear()
	var coarse_cells: int = int(floor(_world_build_settings.chunk_world_size / COARSE_VOXEL))
	_coarse_pass = _world_build_settings.voxel_size < COARSE_VOXEL and coarse_cells >= 2
	_coarse_total = _world_build_total if _coarse_pass else 0
	_coarse_placed = 0
	_world_build_started_msec = Time.get_ticks_msec()
	_world_building = true
	_sort_world_build_queue()
	_fill_world_build()
	_emit_build_progress()


func _queue_every_chunk() -> void:
	_world_build_queue.clear()
	for chunk_z: int in _world_build_grid.z:
		for chunk_y: int in _world_build_grid.y:
			for chunk_x: int in _world_build_grid.x:
				_world_build_queue.append(Vector3i(chunk_x, chunk_y, chunk_z))


## Marks the build's deep chunks, DEEP_MARGIN under the lowest surface of their column
## (sampled nine times across it): an open terrain's caves and bedrock. Any other world
## has none, since only an open terrain says where its surface is.
func _mark_deep_chunks() -> void:
	_deep.clear()
	_deep_in_column.clear()
	var density: DensitySampler.WorldDensity = _get_bake_density()
	if not density.open_terrain_enabled or _world_build_grid.y < 2:
		return
	var settings: SettingsSnapshot = _world_build_settings
	var extent: float = settings.chunk_world_size
	var origin: Vector3 = global_position + _chunk_corner_local(Vector3i.ZERO, settings)
	for column_x: int in _world_build_grid.x:
		for column_z: int in _world_build_grid.z:
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
			var column := Vector2i(column_x, column_z)
			for chunk_y: int in _world_build_grid.y:
				if origin.y + float(chunk_y + 1) * extent <= lowest - DEEP_MARGIN:
					_deep[Vector3i(column_x, chunk_y, column_z)] = true
					_deep_in_column[column] = int(_deep_in_column.get(column, 0)) + 1


## Places the chunks whose tasks are done, within the frame's budget, and starts the next.
func _poll_world_build() -> void:
	var deadline: int = Time.get_ticks_usec() + PLACE_BUDGET_USEC
	var completed: Array[int] = []
	for task_id_variant: Variant in _world_build_tasks.keys():
		var task_id: int = task_id_variant as int
		if WorkerThreadPool.is_task_completed(task_id):
			completed.append(task_id)
	for task_id: int in completed:
		if Time.get_ticks_usec() >= deadline:
			break
		var job: ChunkMeshBuilder.AsyncRebuildJob = (
			_world_build_tasks[task_id] as ChunkMeshBuilder.AsyncRebuildJob
		)
		WorkerThreadPool.wait_for_task_completion(task_id)
		_world_build_tasks.erase(task_id)
		var chunk_coordinate: Vector3i = job.chunk_coordinates[0]
		var result: ChunkMeshBuilder.ChunkBuildResult = (
			job.batch_result.chunks[chunk_coordinate] as ChunkMeshBuilder.ChunkBuildResult
		)
		if job.coarse:
			_coarse_placed += 1
			if not _placed_fine.has(chunk_coordinate):
				_build_chunk_at(chunk_coordinate, result, job.settings)
				_note_standing_chunk(chunk_coordinate)
			continue
		if _placed_fine.has(chunk_coordinate):
			# The brush got there first, with a later snapshot.
			continue
		var coarse_chunk: TerrainChunk = _chunks.get(chunk_coordinate) as TerrainChunk
		if coarse_chunk != null:
			remove_child(coarse_chunk)
			coarse_chunk.queue_free()
			_lift_pending.append(_get_chunk_world_aabb(chunk_coordinate, job.settings))
		_build_chunk_at(chunk_coordinate, result, job.settings)
		_note_standing_chunk(chunk_coordinate)
		_note_fine_chunk(chunk_coordinate)
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
	_play_columns.clear()
	_deep.clear()
	_deep_in_column.clear()
	built.emit()


## A chunk, coarse or fine, stands at a coordinate for the first time.
func _note_standing_chunk(chunk_coordinate: Vector3i) -> void:
	if _placed_any.has(chunk_coordinate):
		return
	_placed_any[chunk_coordinate] = true
	var column := Vector2i(chunk_coordinate.x, chunk_coordinate.z)
	_standing_in_column[column] = int(_standing_in_column.get(column, 0)) + 1


## A fine chunk stands at a coordinate (placed by the map's build or by the brush).
func _note_fine_chunk(chunk_coordinate: Vector3i) -> void:
	if _placed_fine.has(chunk_coordinate):
		return
	_placed_fine[chunk_coordinate] = true
	_world_build_placed += 1
	if _deep.has(chunk_coordinate):
		return
	var column := Vector2i(chunk_coordinate.x, chunk_coordinate.z)
	_placed_in_column[column] = int(_placed_in_column.get(column, 0)) + 1


## Starts chunks off the queue until the pool holds its share, the brush's own rebuilds
## counted in, since GDScript on more threads than that runs slower, not faster. When the
## coarse pass is all handed out, the fine pass is queued behind it.
func _fill_world_build() -> void:
	if _queue_stale:
		_sort_world_build_queue()
	while _world_build_tasks.size() + _running_async_tasks < WORLD_BUILD_IN_FLIGHT:
		if _world_build_queue.is_empty():
			if not _coarse_pass:
				return
			_coarse_pass = false
			_queue_every_chunk()
			_sort_world_build_queue()
			if _world_build_queue.is_empty():
				return
		var chunk_coordinate: Vector3i = _world_build_queue.pop_back()
		if (
			not _coarse_pass
			and (
				_placed_fine.has(chunk_coordinate)
				or _inflight_chunk_coordinates.has(chunk_coordinate)
			)
		):
			continue
		# The edits so far go into this chunk's snapshot: a rebuild queued for it before
		# now would only repeat the work.
		_pending_rebuild_chunk_coordinates.erase(chunk_coordinate)
		var job: ChunkMeshBuilder.AsyncRebuildJob = ChunkMeshBuilder.AsyncRebuildJob.new()
		job.chunk_coordinates = [chunk_coordinate]
		job.settings = _make_thread_settings_snapshot()
		job.coarse = _coarse_pass
		if _coarse_pass:
			_coarsen(job.settings)
		var task_id: int = WorkerThreadPool.add_task(
			ChunkMeshBuilder.run_async_job.bind(job), true, "%s chunk build" % _get_world_log_name()
		)
		_world_build_tasks[task_id] = job


## The coarse pass's settings: COARSE_VOXEL voxels, as near as divides the chunk, and no
## loose rock pass, since at that size a lump is a boulder.
func _coarsen(settings: SettingsSnapshot) -> void:
	settings.cells_per_axis = int(floor(settings.chunk_world_size / COARSE_VOXEL))
	settings.voxel_size = settings.chunk_world_size / float(settings.cells_per_axis)
	settings.loose_rock_voxels = 0


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


## Where a chunk stands in the fine pass: the surface band of the columns play waits for
## (0), the deep chunks under those (1, where the player digs first), the surface band of
## the rest of the map (2) and its deep chunks (3). The surface layer of a map is a third
## of its build and the cave layer two thirds, and nobody sees the caves until they dig,
## so the ground in view is fine three times sooner this way. The coarse pass is one
## group, nearest first.
func _build_group(chunk_coordinate: Vector3i) -> int:
	if _coarse_pass:
		return 0
	var deep: int = 1 if _deep.has(chunk_coordinate) else 0
	if _play_columns.has(Vector2i(chunk_coordinate.x, chunk_coordinate.z)):
		return deep
	return 2 + deep


## How far a chunk column's centre is from the nearest focus, past its radius: the local
## player's when there is one, else any; from the world's centre when none is set.
func _focus_distance(column_centre: Vector2) -> float:
	var foci: Array[Vector4] = _primary_focus if not _primary_focus.is_empty() else _build_focus
	if foci.is_empty():
		return column_centre.distance_to(Vector2(global_position.x, global_position.z))
	var nearest: float = INF
	for focus: Vector4 in foci:
		var distance: float = column_centre.distance_to(Vector2(focus.x, focus.z)) - focus.w
		nearest = minf(nearest, maxf(distance, 0.0))
	return nearest


## The chunk columns (x, z) within radius of a spot, those on the grid.
func _columns_touching(world_position: Vector3, radius: float) -> Array[Vector2i]:
	var settings: SettingsSnapshot = _build_settings()
	var grid: Vector3i = _get_grid_dimensions()
	var extent: float = settings.chunk_world_size
	var origin: Vector3 = global_position + _chunk_corner_local(Vector3i.ZERO, settings)
	var first_x: int = maxi(floori((world_position.x - radius - origin.x) / extent), 0)
	var last_x: int = mini(floori((world_position.x + radius - origin.x) / extent), grid.x - 1)
	var first_z: int = maxi(floori((world_position.z - radius - origin.z) / extent), 0)
	var last_z: int = mini(floori((world_position.z + radius - origin.z) / extent), grid.z - 1)
	var columns: Array[Vector2i] = []
	for column_x: int in range(first_x, last_x + 1):
		for column_z: int in range(first_z, last_z + 1):
			columns.append(Vector2i(column_x, column_z))
	return columns


## Until play can begin, the count is of what it waits for: the coarse map and the fine
## surface band of the focuses' columns (a ring of columns' worth assumed until a focus
## says).
func _emit_build_progress() -> void:
	if _world_build_placed >= _world_build_total:
		build_progress.emit(_world_build_total, _world_build_total)
		return
	if not play_ground_ready():
		var play_done: int = 0
		var play_total: int = 0
		for column: Vector2i in _play_columns:
			play_done += mini(int(_placed_in_column.get(column, 0)), _surface_chunks(column))
			play_total += _surface_chunks(column)
		if _play_columns.is_empty():
			play_total = (2 * PLAY_RING_CHUNKS + 1) ** 2 * _world_build_grid.y
		build_progress.emit(_coarse_placed + play_done, _coarse_total + play_total)
		return
	build_progress.emit(_world_build_placed, _world_build_total)


## A body standing where a fine chunk just replaced a coarse one may be under the new
## surface, since the fine ground can sit higher: it is lifted onto it, two physics steps
## after the chunk went in so its collision is in the space.
func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _lift_checks.is_empty():
		var boxes: Array[AABB] = _lift_checks
		_lift_checks = []
		for node: Node in get_tree().get_nodes_in_group("fighter"):
			var body: Node3D = node as Node3D
			if body == null or not body.has_method("unstick"):
				continue
			for box: AABB in boxes:
				if box.grow(1.0).has_point(body.global_position):
					_lift_onto_ground(body)
					break
	if not _lift_pending.is_empty():
		_lift_checks = _lift_pending
		_lift_pending = []


func _lift_onto_ground(body: Node3D) -> void:
	var from: Vector3 = body.global_position + Vector3.UP * 4.0
	var to: Vector3 = body.global_position - Vector3.UP * 1.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	if body is CollisionObject3D:
		query.exclude = [(body as CollisionObject3D).get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not is_ancestor_of(hit["collider"] as Node):
		return
	var clearance_value: Variant = body.get("spawn_clearance")
	var clearance: float = float(clearance_value) if clearance_value != null else 1.0
	var ground: Vector3 = hit["position"] as Vector3
	if ground.y > body.global_position.y - clearance * 0.5:
		body.call("unstick", ground + Vector3.UP * clearance)


## Drops a background build that is still going (a full rebuild asked for meanwhile takes
## its place, or the world leaves the tree): the chunks on the pool are let finish, since
## their jobs hold the settings, and the rest are forgotten.
func _abandon_world_build() -> void:
	if not _world_building:
		return
	for task_id_variant: Variant in _world_build_tasks.keys():
		WorkerThreadPool.wait_for_task_completion(task_id_variant as int)
	_world_build_tasks.clear()
	_world_build_queue.clear()
	_world_building = false
	_coarse_pass = false
	_coarse_total = 0
	_coarse_placed = 0
	_placed_fine.clear()
	_placed_any.clear()
	_standing_in_column.clear()
	_lift_pending.clear()
	_lift_checks.clear()
	_world_build_settings = null
	_build_focus.clear()
	_primary_focus.clear()
	_play_columns.clear()
	_deep.clear()
	_deep_in_column.clear()
	_queue_stale = false


func _exit_tree() -> void:
	_abandon_world_build()


func _make_world_job(
	settings: SettingsSnapshot, grid_dimensions: Vector3i
) -> ChunkMeshBuilder.ParallelBuildJob:
	var job: ChunkMeshBuilder.ParallelBuildJob = ChunkMeshBuilder.ParallelBuildJob.new()
	job.settings = settings
	for chunk_z: int in grid_dimensions.z:
		for chunk_y: int in grid_dimensions.y:
			for chunk_x: int in grid_dimensions.x:
				job.chunk_coordinates.append(Vector3i(chunk_x, chunk_y, chunk_z))
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
			or (_world_building and not _placed_fine.has(chunk_coordinate))
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
		# A chunk in flight, or one the map's build has not placed yet, keeps its turn.
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
			if _effective_material() != null:
				chunk.material_override = _effective_material()
			if _world_building and not _placed_fine.has(chunk_coordinate):
				# A coarse chunk just turned fine under the brush: whoever stands on it may
				# now be under its surface.
				_lift_pending.append(
					_get_chunk_world_aabb(chunk_coordinate, async_rebuild_job.settings)
				)
				_note_fine_chunk(chunk_coordinate)
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
## neighboring chunks count too).
func _get_chunk_coordinates_intersecting_aabb(bounds: AABB) -> Array[Vector3i]:
	var chunk_coordinates: Array[Vector3i] = []
	var settings: SettingsSnapshot = _make_settings_snapshot()
	var padding: float = get_voxel_size() * 2.0
	var search_aabb: AABB = bounds.grow(padding)
	# While the map builds, chunks not yet placed count too: an edit there waits for the
	# chunk and rebuilds it once it stands.
	var candidates: Array = _chunks.keys()
	if _world_building:
		candidates = []
		for chunk_z: int in _world_build_grid.z:
			for chunk_y: int in _world_build_grid.y:
				for chunk_x: int in _world_build_grid.x:
					candidates.append(Vector3i(chunk_x, chunk_y, chunk_z))
	for chunk_coordinate_variant: Variant in candidates:
		var chunk_coordinate: Vector3i = chunk_coordinate_variant as Vector3i
		if _get_chunk_world_aabb(chunk_coordinate, settings).intersects(search_aabb):
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
