extends GroundPlayer
class_name BoxedInTerrainPlayer
## Bug controller for boxed-in and terrarium terrain (movement, climbing and flight live in
## GroundPlayer).

var _walk_surface: Node3D


func _cache_terrain_refs() -> void:
	if terrain == null:
		terrain = get_tree().get_first_node_in_group("boxed_in_terrain") as Node3D
	if terrain is TerrariumRoom:
		var terrarium_room: TerrariumRoom = terrain as TerrariumRoom
		var playable: TerrariumTerrain = terrarium_room.get_playable_terrain()
		_walk_surface = playable if playable != null else terrarium_room
	elif terrain is OpenTerrain:
		_walk_surface = terrain as OpenTerrain
	elif terrain is BoxedInTerrain:
		_walk_surface = terrain as BoxedInTerrain
	elif terrain != null and terrain.has_method("get_surface_height_at"):
		_walk_surface = terrain


func _find_random_surface_spawn() -> Dictionary:
	if terrain is TerrariumRoom:
		var terrarium_room: TerrariumRoom = terrain as TerrariumRoom
		var playable: TerrariumTerrain = terrarium_room.get_playable_terrain()
		if playable != null:
			_walk_surface = playable
		return {
			"position": terrarium_room.get_spawn_position(spawn_clearance),
			"from_raycast_hit": playable != null,
		}
	return _raycast_spawn_over(_walk_surface)


func _is_terrain_collider(collider: Variant) -> bool:
	if terrain is TerrariumRoom:
		if not (collider is Node):
			return false
		var playable: TerrariumTerrain = (terrain as TerrariumRoom).get_playable_terrain()
		var node: Node = collider as Node
		return playable != null and (playable == node or playable.is_ancestor_of(node))
	return super._is_terrain_collider(collider)
