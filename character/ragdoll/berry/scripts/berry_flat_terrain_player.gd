extends BerryRagdollController
class_name BerryFlatTerrainPlayer
## Active ragdoll on flat heightmap terrain (open or boxed-in worlds).


const _SPAWN_ATTEMPTS: int = 12
const _SPAWN_RAY_HEIGHT: float = 80.0

@export var terrain: Node3D
@export var spawn_clearance: float = 1.2

var _terrain_world: ChunkedTerrainWorld
var _walk_surface: Node3D
var _spawned: bool = false


func respawn_random() -> void:
	_cache_terrain_refs()
	_apply_spawn(_find_random_surface_spawn())


func _cache_terrain_refs() -> void:
	if terrain == null:
		terrain = get_tree().get_first_node_in_group("terrain_world") as Node3D
	if terrain == null:
		terrain = get_tree().get_first_node_in_group("boxed_in_terrain") as Node3D
	if terrain is ChunkedTerrainWorld:
		_terrain_world = terrain as ChunkedTerrainWorld
		_walk_surface = terrain
	elif terrain is InteriorRoom:
		_walk_surface = terrain as InteriorRoom
	elif terrain != null and terrain.has_method("get_surface_height_at"):
		_walk_surface = terrain


func _snap_to_ground_when_ready() -> void:
	_cache_terrain_refs()
	if terrain == null:
		push_warning("[BerryFlatTerrainPlayer] No terrain assigned.")
		return
	var spawn_data: Dictionary = _find_random_surface_spawn()
	for _attempt: int in range(_SPAWN_ATTEMPTS):
		await get_tree().physics_frame
		spawn_data = _find_random_surface_spawn()
		if spawn_data.get("from_raycast_hit", false):
			break
	_apply_spawn(spawn_data)


func _apply_spawn(spawn_data: Dictionary) -> void:
	global_position = spawn_data.get("position", Vector3.ZERO)
	global_rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	_spawned = true


func _find_random_surface_spawn() -> Dictionary:
	var spawn_data: Dictionary = {
		"position": Vector3.ZERO,
		"from_raycast_hit": false,
	}
	if terrain is InteriorRoom:
		spawn_data.position = (terrain as InteriorRoom).get_spawn_position()
		spawn_data.from_raycast_hit = true
		return spawn_data
	if _walk_surface == null:
		spawn_data.position = Vector3(0.0, spawn_clearance, 0.0)
		return spawn_data

	var world_extents: Vector3 = _walk_surface.get_world_extents()
	var half_extent_x: float = world_extents.x * 0.4
	var half_extent_z: float = world_extents.z * 0.4
	var random_offset: Vector3 = Vector3(
		randf_range(-half_extent_x, half_extent_x),
		0.0,
		randf_range(-half_extent_z, half_extent_z)
	)
	var world_center: Vector3 = _walk_surface.global_position
	var ray_origin: Vector3 = world_center + random_offset + Vector3.UP * _SPAWN_RAY_HEIGHT
	var ray_end: Vector3 = world_center + random_offset - Vector3.UP * _SPAWN_RAY_HEIGHT
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin, ray_end
	)
	ray_query.collide_with_areas = false
	var raycast_hit: Dictionary = space.intersect_ray(ray_query)
	if raycast_hit.is_empty() or not _is_terrain_collider(raycast_hit.get("collider")):
		var fallback_height: float = _walk_surface.get_surface_height_at(world_center + random_offset)
		spawn_data.position = Vector3(
			world_center.x + random_offset.x,
			fallback_height + spawn_clearance,
			world_center.z + random_offset.z
		)
		return spawn_data

	spawn_data.position = raycast_hit.position + Vector3.UP * spawn_clearance
	spawn_data.from_raycast_hit = true
	return spawn_data


func _is_terrain_collider(collider: Variant) -> bool:
	if terrain == null or not (collider is Node):
		return false
	var node: Node = collider as Node
	return terrain == node or terrain.is_ancestor_of(node)
