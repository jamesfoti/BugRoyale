extends Node
class_name PlayerSpawner
## Spawns the player (with the selected class's stats) for a playable world scene.


enum WorldKind { CELESTIAL_BODY, OPEN_TERRAIN, BOXED_IN_TERRAIN }

@export var world_kind: WorldKind = WorldKind.OPEN_TERRAIN
@export var celestial_body_path: NodePath = ^"../TerrainWorld"
@export var terrain_path: NodePath = ^"../TerrainWorld"

@export var celestial_body_player_scene: PackedScene = preload("res://character/player.tscn")
@export var open_terrain_player_scene: PackedScene = preload("res://character/open_terrain_player.tscn")
@export var boxed_in_terrain_player_scene: PackedScene = preload(
	"res://character/boxed_in_terrain_player.tscn"
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
	player.add_to_group("player")
	_bind_world_references(player)
	_attach_damageable(player)
	_attach_breath(player)
	CharacterSkin.apply_class_stats(player, player.get_node_or_null("Damageable") as Damageable)
	get_parent().add_child(player)


func _pick_player_scene() -> PackedScene:
	match world_kind:
		WorldKind.CELESTIAL_BODY:
			return celestial_body_player_scene
		WorldKind.OPEN_TERRAIN:
			return open_terrain_player_scene
		WorldKind.BOXED_IN_TERRAIN:
			return boxed_in_terrain_player_scene
	return null


func _bind_world_references(player: Node) -> void:
	match world_kind:
		WorldKind.CELESTIAL_BODY:
			var body_node: Node3D = get_node_or_null(celestial_body_path) as Node3D
			if player is CelestialBodyPlayer:
				(player as CelestialBodyPlayer).celestial_body = body_node
		WorldKind.OPEN_TERRAIN, WorldKind.BOXED_IN_TERRAIN:
			var terrain_node: Node3D = get_node_or_null(terrain_path) as Node3D
			if player is OpenTerrainPlayer:
				(player as OpenTerrainPlayer).terrain = terrain_node
			elif player is BoxedInTerrainPlayer:
				(player as BoxedInTerrainPlayer).terrain = terrain_node


func _wait_for_world_ready() -> void:
	var terrain_node: Node3D = get_node_or_null(terrain_path) as Node3D
	if terrain_node is TerrariumRoom:
		var terrarium_room: TerrariumRoom = terrain_node as TerrariumRoom
		if terrarium_room.rebuild_on_ready:
			await terrarium_room.content_rebuilt


func _attach_damageable(player: Node) -> void:
	if player.get_node_or_null("Damageable") != null:
		return
	var damageable := Damageable.new()
	damageable.name = "Damageable"
	player.add_child(damageable)


## Air supply: drowning damage after too long under the terrarium water.
func _attach_breath(player: Node) -> void:
	if player.get_node_or_null("Breath") != null:
		return
	var breath := Breath.new()
	breath.name = "Breath"
	player.add_child(breath)
