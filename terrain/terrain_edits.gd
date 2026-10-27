class_name TerrainEdits
extends RefCounted
## Baked voxel density overrides. Negative density = solid. Voxels built from a placed material
## (see TerrainMaterials) also remember which one, so the mesher can colour them.


var _voxel_size: float = 1.0
var _overrides: Dictionary = {}
## Voxel key -> TerrainMaterials.Kind for voxels built from a placed material; absent = natural.
var _materials: Dictionary = {}
## Read-only copy shared by worker-thread rebuilds; dropped whenever the edits change.
var _thread_snapshot: TerrainEdits = null
## World-space box around the voxels the last add_brush actually changed (one voxel of padding).
var _last_changed_bounds: AABB = AABB()


func set_voxel_size(voxel_size: float) -> void:
	_voxel_size = maxf(voxel_size, 0.001)


## Carves (or fills) a sphere. Filling with a placed material also tags every voxel in the sphere
## with it, so painting stone over existing ground re-skins that ground. Returns false when no
## voxel changed, e.g. a shot that hit a hornet in mid-air: the caller can then skip rebuilding
## chunks that would come out identical.
func add_brush(
	world_position: Vector3,
	radius: float,
	add_solid: bool,
	procedural_density: Callable,
	material: TerrainMaterials.Kind = TerrainMaterials.Kind.NATURAL
) -> bool:
	var brush_radius: float = maxf(radius, 0.1)
	var extent_voxels: int = int(ceil(brush_radius / _voxel_size)) + 1
	var center_key: Vector3i = position_to_key(world_position, _voxel_size)
	var radius_squared: float = brush_radius * brush_radius
	var changed: bool = false
	var changed_min: Vector3i = Vector3i.ZERO
	var changed_max: Vector3i = Vector3i.ZERO

	for offset_z: int in range(-extent_voxels, extent_voxels + 1):
		for offset_y: int in range(-extent_voxels, extent_voxels + 1):
			for offset_x: int in range(-extent_voxels, extent_voxels + 1):
				var voxel_key: Vector3i = center_key + Vector3i(offset_x, offset_y, offset_z)
				var sample_position: Vector3 = key_to_position(voxel_key, _voxel_size)
				if sample_position.distance_squared_to(world_position) > radius_squared:
					continue
				var density_value: float
				if _overrides.has(voxel_key):
					density_value = _overrides[voxel_key] as float
				else:
					density_value = procedural_density.call(sample_position) as float
				var sphere_sdf: float = sample_position.distance_to(world_position) - brush_radius
				var new_density_value: float
				if add_solid:
					new_density_value = minf(density_value, sphere_sdf)
				else:
					new_density_value = maxf(density_value, -sphere_sdf)
				var voxel_changed: bool = not is_equal_approx(new_density_value, density_value)
				if voxel_changed:
					_overrides[voxel_key] = new_density_value
				# Every voxel in a filled sphere ends up solid, so it takes the brush's material;
				# a carved one ends up air and forgets its material.
				if add_solid:
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
		var bounds_min: Vector3 = key_to_position(changed_min - padding, _voxel_size)
		var bounds_max: Vector3 = key_to_position(changed_max + padding, _voxel_size)
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
	var voxel_key: Vector3i = position_to_key(world_position, _voxel_size)
	if _overrides.has(voxel_key):
		return _overrides[voxel_key] as float
	return density


## Placed material of the voxel at a world position; NATURAL for untouched or carved ground.
func material_at(world_position: Vector3) -> TerrainMaterials.Kind:
	if _materials.is_empty():
		return TerrainMaterials.Kind.NATURAL
	var voxel_key: Vector3i = position_to_key(world_position, _voxel_size)
	return _materials.get(voxel_key, TerrainMaterials.Kind.NATURAL) as TerrainMaterials.Kind


## False when every voxel is natural, so the mesher can skip material lookups entirely.
func has_materials() -> bool:
	return not _materials.is_empty()


func get_override_count() -> int:
	return _overrides.size()


## Returns a copy that worker threads may read while the main thread keeps editing. The copy is
## reused across rebuild jobs until the next brush change, so it must not be modified.
func duplicate_for_thread() -> TerrainEdits:
	if _thread_snapshot != null and is_equal_approx(_thread_snapshot._voxel_size, _voxel_size):
		return _thread_snapshot
	var thread_copy: TerrainEdits = TerrainEdits.new()
	thread_copy._voxel_size = _voxel_size
	thread_copy._overrides = _overrides.duplicate()
	thread_copy._materials = _materials.duplicate()
	_thread_snapshot = thread_copy
	return thread_copy


static func position_to_key(world_position: Vector3, voxel_size: float) -> Vector3i:
	var inverse_voxel_size: float = 1.0 / maxf(voxel_size, 0.001)
	return Vector3i(
		int(round(world_position.x * inverse_voxel_size)),
		int(round(world_position.y * inverse_voxel_size)),
		int(round(world_position.z * inverse_voxel_size))
	)


static func key_to_position(voxel_key: Vector3i, voxel_size: float) -> Vector3:
	return Vector3(voxel_key) * voxel_size
