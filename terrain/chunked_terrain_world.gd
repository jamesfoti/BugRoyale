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

const _CHUNK_SCRIPT = preload("res://terrain/terrain_chunk.gd")
## Worker threads a full rebuild is split over. GDScript on many threads contends in the
## engine (object lookups, reference counts) rather than scaling: measured 2026-11-09 on a
## 20-core machine, 48 garden-sized chunks took 784 ms on one thread, 315 ms on four and
## 1641 ms on all twenty. Four is the sweet spot by a wide margin either side.
const REBUILD_THREADS: int = 4

## Metres of air an ADD edit must leave around a fighter's capsule to be allowed. Terrain
## collision is one-sided, so a fighter sealed inside new rock falls out of the world.
const FIGHTER_CLEARANCE: float = 0.1
## Points tested along a capsule's axis when checking an edit against it.
const CAPSULE_SAMPLES: int = 6

## Called from the blocking rebuild as the chunks come in, with (chunks built, chunks in
## all, this world), and once more when every chunk stands: the loading screen draws its
## bar from it, since nothing else gets a frame while a map builds. Invalid: no one watches.
static var build_watcher: Callable = Callable()

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
var _pending_rebuild_chunk_coordinates: Dictionary = {}
var _pending_rebuild_collision: bool = false
var _async_rebuild_requested: bool = false
var _async_jobs: Dictionary = {}
var _running_async_tasks: int = 0
var _inflight_chunk_coordinates: Dictionary = {}


func _ready() -> void:
	_ensure_world_defaults()
	if is_playable_world:
		add_to_group("terrain_world")
		_register_playable_groups()
	if rebuild_on_ready and not Engine.is_editor_hint():
		call_deferred("rebuild_all")


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
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


func rebuild_all() -> void:
	_invalidate_bake_density()
	_ensure_world_defaults()
	_clear_chunks()
	var settings: SettingsSnapshot = _make_settings_snapshot()
	var grid_dimensions: Vector3i = _get_grid_dimensions()
	_rebuild_all_sync(settings, grid_dimensions)


## Blocks until every chunk exists (callers such as spawning rely on that), but meshes the
## chunks on all WorkerThreadPool threads when use_threaded_rebuild is on.
func _rebuild_all_sync(settings: SettingsSnapshot, grid_dimensions: Vector3i) -> void:
	var rebuild_start_milliseconds: int = Time.get_ticks_msec()
	var job: ChunkMeshBuilder.ParallelBuildJob = ChunkMeshBuilder.ParallelBuildJob.new()
	job.settings = settings
	for chunk_z: int in grid_dimensions.z:
		for chunk_y: int in grid_dimensions.y:
			for chunk_x: int in grid_dimensions.x:
				job.chunk_coordinates.append(Vector3i(chunk_x, chunk_y, chunk_z))
				job.results.append(ChunkMeshBuilder.ChunkBuildResult.new())
	if use_threaded_rebuild and job.chunk_coordinates.size() > 1:
		var group_task_id: int = WorkerThreadPool.add_group_task(
			ChunkMeshBuilder.run_parallel_job_element.bind(job),
			job.chunk_coordinates.size(),
			REBUILD_THREADS,
			true,
			"%s chunk rebuild" % _get_world_log_name()
		)
		if build_watcher.is_valid():
			while not WorkerThreadPool.is_group_task_completed(group_task_id):
				OS.delay_msec(50)
				build_watcher.call(job.completed(), job.chunk_coordinates.size(), self)
		WorkerThreadPool.wait_for_group_task_completion(group_task_id)
	else:
		for element_index: int in job.chunk_coordinates.size():
			ChunkMeshBuilder.run_parallel_job_element(element_index, job)
			if build_watcher.is_valid():
				build_watcher.call(element_index + 1, job.chunk_coordinates.size(), self)
	for element_index: int in job.chunk_coordinates.size():
		_build_chunk_at(job.chunk_coordinates[element_index], job.results[element_index], settings)
	if build_watcher.is_valid():
		build_watcher.call(job.chunk_coordinates.size(), job.chunk_coordinates.size(), self)
	var elapsed_milliseconds: int = Time.get_ticks_msec() - rebuild_start_milliseconds
	_log_rebuild_complete(_chunks.size(), settings, grid_dimensions, elapsed_milliseconds)


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
		_pending_rebuild_chunk_coordinates[chunk_coordinate] = true
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
	var chunk_coordinates: Array[Vector3i] = _get_chunk_coordinates_intersecting_aabb(
		_edits.get_last_changed_bounds()
	)
	for chunk_coordinate: Vector3i in chunk_coordinates:
		_pending_rebuild_chunk_coordinates[chunk_coordinate] = true
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
		if _inflight_chunk_coordinates.has(chunk_coordinate):
			deferred_chunk_coordinates.append(chunk_coordinate)
			continue
		if _running_async_tasks >= max_concurrent_rebuild_tasks:
			deferred_chunk_coordinates.append(chunk_coordinate)
			continue
		_pending_rebuild_chunk_coordinates.erase(chunk_coordinate)
		_start_single_chunk_async_rebuild(chunk_coordinate, rebuild_collision)
	for chunk_coordinate: Vector3i in deferred_chunk_coordinates:
		_pending_rebuild_chunk_coordinates[chunk_coordinate] = true
	if rebuild_collision and not deferred_chunk_coordinates.is_empty():
		_pending_rebuild_collision = true


func _schedule_chunk_coordinate_rebuilds(
	chunk_coordinates: Array[Vector3i], rebuild_collision: bool
) -> void:
	if chunk_coordinates.is_empty():
		return
	if _use_threaded_rebuild():
		for chunk_coordinate: Vector3i in chunk_coordinates:
			_pending_rebuild_chunk_coordinates[chunk_coordinate] = true
		if rebuild_collision:
			_pending_rebuild_collision = true
		_dispatch_pending_rebuilds()
	else:
		var settings: SettingsSnapshot = _make_settings_snapshot()
		settings.rebuild_collision = settings.generate_collision and rebuild_collision
		_rebuild_chunk_coordinates(chunk_coordinates, settings)


func _start_single_chunk_async_rebuild(chunk_coordinate: Vector3i, rebuild_collision: bool) -> void:
	_inflight_chunk_coordinates[chunk_coordinate] = true
	var async_rebuild_job: ChunkMeshBuilder.AsyncRebuildJob = ChunkMeshBuilder.AsyncRebuildJob.new()
	async_rebuild_job.chunk_coordinates = [chunk_coordinate]
	async_rebuild_job.rebuild_collision = rebuild_collision
	async_rebuild_job.settings = _make_thread_settings_snapshot()
	async_rebuild_job.task_id = WorkerThreadPool.add_task(
		ChunkMeshBuilder.run_async_job.bind(async_rebuild_job)
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
		chunk.apply_build_result(chunk_build_result, generate_collision)
		if _effective_material() != null:
			chunk.material_override = _effective_material()


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
	for chunk_coordinate_variant: Variant in _chunks.keys():
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
	## Solid ground a map builder adds on top of the shape (DensitySampler.WorldDensity.solids).
	var solids: Array[Dictionary] = []
	var rebuild_collision: bool = true
	## A world with ground of its own kind builds its density here:
	## a static function taking the snapshot, called on worker threads too. Invalid: the
	## builder picks a density from the flags above.
	var density_factory: Callable = Callable()
