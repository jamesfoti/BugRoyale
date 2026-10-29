class_name TerrainEdits
extends RefCounted
## Baked voxel density overrides. Negative density = solid. Voxels built from a placed material
## (see TerrainMaterials) also remember which one, so the mesher can colour them.


var _voxel_size: float = 1.0
## World position of voxel key (0, 0, 0): the sample lattice of the terrain, so keys land on samples.
var _grid_origin: Vector3 = Vector3.ZERO
var _overrides: Dictionary = {}
## Voxel key -> TerrainMaterials.Kind for voxels built from a placed material; absent = natural.
var _materials: Dictionary = {}
## Read-only copy shared by worker-thread rebuilds; dropped whenever the edits change.
var _thread_snapshot: TerrainEdits = null
## World-space box around the voxels the last add_brush actually changed (one voxel of padding).
var _last_changed_bounds: AABB = AABB()


func set_voxel_size(voxel_size: float) -> void:
	_voxel_size = maxf(voxel_size, 0.001)


func set_grid_origin(origin: Vector3) -> void:
	if origin.is_equal_approx(_grid_origin):
		return
	_grid_origin = origin
	_thread_snapshot = null


## Carves (or fills) a sphere. Filling with a placed material also tags every voxel in the sphere
## with it, so painting stone over existing ground re-skins that ground. Returns false when no
## voxel changed, e.g. a shot that hit a hornet in mid-air: the caller can then skip rebuilding
## chunks that would come out identical.
##
## The sphere's signed distance is also written into the shell of voxels one voxel beyond its
## radius (where it is positive, so nothing there turns solid). Without that, the air samples
## next to a new bump keep their natural density, which grows with height above the ground and
## drags the drawn surface down onto the last solid sample; on a 2 m voxel map a bump built by
## repeated stamps then stalled a few metres up because the next stamp could not reach the next
## sample. With the shell the surface lands where the sphere really is and stacking goes on.
func add_brush(
	world_position: Vector3,
	radius: float,
	add_solid: bool,
	procedural_density: Callable,
	material: TerrainMaterials.Kind = TerrainMaterials.Kind.NATURAL
) -> bool:
	var brush_radius: float = maxf(radius, 0.1)
	return _stamp(world_position, Vector3.ONE * brush_radius, false, add_solid, procedural_density, material)


## Carves (or fills) an axis-aligned box: the block tool. Same rules as add_brush. A box whose
## faces lie on sample planes, pushed out by a hair so those samples count as solid, meshes as a
## crisp cube with its vertices on the samples.
func add_box(
	center: Vector3,
	half_extents: Vector3,
	add_solid: bool,
	procedural_density: Callable,
	material: TerrainMaterials.Kind = TerrainMaterials.Kind.NATURAL
) -> bool:
	return _stamp(center, half_extents.abs().max(Vector3.ONE * 0.1), true, add_solid, procedural_density, material)


## Shared stamp: half_extents is the sphere radius on every axis, or the half size of the box.
func _stamp(
	center: Vector3,
	half_extents: Vector3,
	box: bool,
	add_solid: bool,
	procedural_density: Callable,
	material: TerrainMaterials.Kind
) -> bool:
	var reach: Vector3 = half_extents + Vector3.ONE * _voxel_size
	var extent_voxels: Vector3i = Vector3i((reach / _voxel_size).ceil()) + Vector3i.ONE
	var center_key: Vector3i = _world_to_key(center)
	var changed: bool = false
	var changed_min: Vector3i = Vector3i.ZERO
	var changed_max: Vector3i = Vector3i.ZERO

	for offset_z: int in range(-extent_voxels.z, extent_voxels.z + 1):
		for offset_y: int in range(-extent_voxels.y, extent_voxels.y + 1):
			for offset_x: int in range(-extent_voxels.x, extent_voxels.x + 1):
				var voxel_key: Vector3i = center_key + Vector3i(offset_x, offset_y, offset_z)
				var sample_position: Vector3 = _key_to_world(voxel_key)
				var sphere_sdf: float
				if box:
					var q: Vector3 = (sample_position - center).abs() - half_extents
					sphere_sdf = q.max(Vector3.ZERO).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)
				else:
					sphere_sdf = sample_position.distance_to(center) - half_extents.x
				# Inside the shape or in its one-voxel shell; beyond that nothing changes.
				if sphere_sdf > _voxel_size:
					continue
				var density_value: float
				if _overrides.has(voxel_key):
					density_value = _overrides[voxel_key] as float
				else:
					density_value = procedural_density.call(sample_position) as float
				var new_density_value: float
				if add_solid:
					new_density_value = minf(density_value, sphere_sdf)
				else:
					new_density_value = maxf(density_value, -sphere_sdf)
				var voxel_changed: bool = not is_equal_approx(new_density_value, density_value)
				if voxel_changed:
					_overrides[voxel_key] = new_density_value
				# A voxel the fill leaves solid takes the brush's material; one the carve leaves
				# as air forgets its material. Shell voxels that stay as they were keep theirs,
				# so a stone block does not skin the ground around it stone.
				if new_density_value < 0.0:
					if add_solid and sphere_sdf <= 0.0:
						voxel_changed = _set_material(voxel_key, material) or voxel_changed
				elif _materials.erase(voxel_key):
					voxel_changed = true
				if not voxel_changed:
					continue
				_thread_snapshot = null
				if changed:
					changed_min = changed_min.min(voxel_key)
					changed_max = changed_max.max(voxel_key)
				else:
					changed = true
					changed_min = voxel_key
					changed_max = voxel_key
	if changed:
		var padding: Vector3i = Vector3i.ONE
		var bounds_min: Vector3 = _key_to_world(changed_min - padding)
		var bounds_max: Vector3 = _key_to_world(changed_max + padding)
		_last_changed_bounds = AABB(bounds_min, bounds_max - bounds_min)
	else:
		_last_changed_bounds = AABB()
	return changed


## Records (or, for NATURAL, clears) a voxel's material; true when that was a change.
func _set_material(voxel_key: Vector3i, material: TerrainMaterials.Kind) -> bool:
	if material == TerrainMaterials.Kind.NATURAL:
		return _materials.erase(voxel_key)
	if _materials.get(voxel_key, TerrainMaterials.Kind.NATURAL) == material:
		return false
	_materials[voxel_key] = material
	return true


## World-space bounds of the voxels changed by the last add_brush (zero-size if none).
func get_last_changed_bounds() -> AABB:
	return _last_changed_bounds


func apply_to_density(density: float, world_position: Vector3) -> float:
	if _overrides.is_empty():
		return density
	var voxel_key: Vector3i = _world_to_key(world_position)
	if _overrides.has(voxel_key):
		return _overrides[voxel_key] as float
	return density


## Placed material of the voxel at a world position; NATURAL for untouched or carved ground.
func material_at(world_position: Vector3) -> TerrainMaterials.Kind:
	if _materials.is_empty():
		return TerrainMaterials.Kind.NATURAL
	var voxel_key: Vector3i = _world_to_key(world_position)
	return _materials.get(voxel_key, TerrainMaterials.Kind.NATURAL) as TerrainMaterials.Kind


## False when every voxel is natural, so the mesher can skip material lookups entirely.
func has_materials() -> bool:
	return not _materials.is_empty()


func get_override_count() -> int:
	return _overrides.size()


## Everything a late joiner needs to rebuild this terrain's edits: the overridden voxels and
## their placed materials. Plain dictionaries keyed by voxel, so it serialises as is.
func export_state() -> Dictionary:
	return {"overrides": _overrides.duplicate(), "materials": _materials.duplicate()}


func import_state(state: Dictionary) -> void:
	_overrides = (state.get("overrides", {}) as Dictionary).duplicate()
	_materials = (state.get("materials", {}) as Dictionary).duplicate()
	_thread_snapshot = null
	_last_changed_bounds = get_all_bounds()


## World-space bounds of every overridden voxel (zero-size when there are none).
func get_all_bounds() -> AABB:
	if _overrides.is_empty():
		return AABB()
	var key_min: Vector3i = Vector3i.ZERO
	var key_max: Vector3i = Vector3i.ZERO
	var first: bool = true
	for voxel_key_variant: Variant in _overrides.keys():
		var voxel_key: Vector3i = voxel_key_variant as Vector3i
		if first:
			key_min = voxel_key
			key_max = voxel_key
			first = false
		else:
			key_min = key_min.min(voxel_key)
			key_max = key_max.max(voxel_key)
	var padding: Vector3i = Vector3i.ONE
	var bounds_min: Vector3 = _key_to_world(key_min - padding)
	var bounds_max: Vector3 = _key_to_world(key_max + padding)
	return AABB(bounds_min, bounds_max - bounds_min)


## Returns a copy that worker threads may read while the main thread keeps editing. The copy is
## reused across rebuild jobs until the next brush change, so it must not be modified.
func duplicate_for_thread() -> TerrainEdits:
	if _thread_snapshot != null and is_equal_approx(_thread_snapshot._voxel_size, _voxel_size):
		return _thread_snapshot
	var thread_copy: TerrainEdits = TerrainEdits.new()
	thread_copy._voxel_size = _voxel_size
	thread_copy._grid_origin = _grid_origin
	thread_copy._overrides = _overrides.duplicate()
	thread_copy._materials = _materials.duplicate()
	_thread_snapshot = thread_copy
	return thread_copy


func _world_to_key(world_position: Vector3) -> Vector3i:
	return position_to_key(world_position - _grid_origin, _voxel_size)


func _key_to_world(voxel_key: Vector3i) -> Vector3:
	return _grid_origin + key_to_position(voxel_key, _voxel_size)


static func position_to_key(world_position: Vector3, voxel_size: float) -> Vector3i:
	var inverse_voxel_size: float = 1.0 / maxf(voxel_size, 0.001)
	return Vector3i(
		int(round(world_position.x * inverse_voxel_size)),
		int(round(world_position.y * inverse_voxel_size)),
		int(round(world_position.z * inverse_voxel_size))
	)


static func key_to_position(voxel_key: Vector3i, voxel_size: float) -> Vector3:
	return Vector3(voxel_key) * voxel_size
