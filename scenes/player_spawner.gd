extends Node
class_name PlayerSpawner
## Spawns the standard or ragdoll player for a playable world scene.


enum WorldKind { PLANET, OPEN_TERRAIN, BOXED_IN_TERRAIN }

@export var world_kind: WorldKind = WorldKind.OPEN_TERRAIN
@export var planet_path: NodePath = ^"../TerrainWorld"
@export var terrain_path: NodePath = ^"../TerrainWorld"

@export var planet_player_scene: PackedScene = preload("res://character/player.tscn")
@export var open_terrain_player_scene: PackedScene = preload("res://character/open_terrain_player.tscn")
@export var boxed_in_terrain_player_scene: PackedScene = preload(
	"res://character/boxed_in_terrain_player.tscn"
)
@export var ragdoll_planet_player_scene: PackedScene = preload(
	"res://character/ragdoll/berry/scenes/ragdoll_planet_player.tscn"
)
@export var ragdoll_flat_terrain_player_scene: PackedScene = preload(
	"res://character/ragdoll/berry/scenes/ragdoll_flat_terrain_player.tscn"
)


func _ready() -> void:
	call_deferred("_spawn_player")


func _spawn_player() -> void:
	await _wait_for_world_ready()
	var player_scene: PackedScene = _pick_player_scene()
	if player_scene == null:
		push_error("[PlayerSpawner] No player scene configured.")
		return
	var player: Node = player_scene.instantiate()
	player.name = "Player"
	_bind_world_references(player)
	get_parent().add_child(player)


func _pick_player_scene() -> PackedScene:
	if LoadingScreen.use_ragdoll_character:
		if world_kind == WorldKind.PLANET:
			return ragdoll_planet_player_scene
		return ragdoll_flat_terrain_player_scene
	match world_kind:
		WorldKind.PLANET:
			return planet_player_scene
		WorldKind.OPEN_TERRAIN:
			return open_terrain_player_scene
		WorldKind.BOXED_IN_TERRAIN:
			return boxed_in_terrain_player_scene
	return null


func _bind_world_references(player: Node) -> void:
	match world_kind:
		WorldKind.PLANET:
			var planet_node: Node3D = get_node_or_null(planet_path) as Node3D
			if player is PlanetPlayer:
				(player as PlanetPlayer).planet = planet_node
			elif player is BerryPlanetPlayer:
				(player as BerryPlanetPlayer).planet = planet_node
		WorldKind.OPEN_TERRAIN, WorldKind.BOXED_IN_TERRAIN:
			var terrain_node: Node3D = get_node_or_null(terrain_path) as Node3D
			if player is OpenTerrainPlayer:
				(player as OpenTerrainPlayer).terrain = terrain_node
			elif player is BoxedInTerrainPlayer:
				(player as BoxedInTerrainPlayer).terrain = terrain_node
			elif player is BerryFlatTerrainPlayer:
				(player as BerryFlatTerrainPlayer).terrain = terrain_node


func _wait_for_world_ready() -> void:
	var terrain_node: Node3D = get_node_or_null(terrain_path) as Node3D
	if terrain_node is TerrariumRoom:
		var terrarium_room: TerrariumRoom = terrain_node as TerrariumRoom
		if terrarium_room.rebuild_on_ready:
			await terrarium_room.content_rebuilt
