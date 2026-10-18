extends GroundPlayer
class_name OpenTerrainPlayer
## Bug controller for open heightmap terrain (movement, climbing and flight live in GroundPlayer).

var _open_terrain: OpenTerrain


func _cache_terrain_refs() -> void:
	if terrain == null:
		terrain = get_tree().get_first_node_in_group("open_terrain") as Node3D
	if terrain is OpenTerrain:
		_open_terrain = terrain as OpenTerrain


func _find_random_surface_spawn() -> Dictionary:
	return _raycast_spawn_over(_open_terrain)
