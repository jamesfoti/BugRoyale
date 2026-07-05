class_name PlanetEdits
extends RefCounted
## Baked voxel density overrides. Negative density = solid.


var _voxel_size: float = 1.0
var _overrides: Dictionary = {}


func set_voxel_size(voxel_size: float) -> void:
	_voxel_size = maxf(voxel_size, 0.001)


func add_brush(
	world_position: Vector3,
	radius: float,
	add_solid: bool,
	procedural_density: Callable
) -> void:
	var brush_radius: float = maxf(radius, 0.1)
	var extent_voxels: int = int(ceil(brush_radius / _voxel_size)) + 1
	var center_key: Vector3i = position_to_key(world_position, _voxel_size)
	var radius_squared: float = brush_radius * brush_radius

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
				if is_equal_approx(new_density_value, density_value):
					continue
				_overrides[voxel_key] = new_density_value


func apply_to_density(density: float, world_position: Vector3) -> float:
	var voxel_key: Vector3i = position_to_key(world_position, _voxel_size)
	if _overrides.has(voxel_key):
		return _overrides[voxel_key] as float
	return density


func get_override_count() -> int:
	return _overrides.size()


func duplicate_for_thread() -> PlanetEdits:
	var thread_copy: PlanetEdits = PlanetEdits.new()
	thread_copy._voxel_size = _voxel_size
	for key: Variant in _overrides.keys():
		thread_copy._overrides[key] = _overrides[key]
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
