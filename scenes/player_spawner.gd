class_name PlayerSpawner
extends Node
## Spawns the local player (with the selected class's stats) for a playable world scene, and
## builds bodies for everyone else (bots now, remote players later) from the same player scene,
## so every fighter on the map is the same kind of body.

enum WorldKind { CELESTIAL_BODY, OPEN_TERRAIN, BOXED_IN_TERRAIN }

## Nodes only the local player needs: the camera rig and the terrain editing tools.
const _LOCAL_ONLY_NODES: Array[String] = ["OrbitCamera", "TerrainBrush"]

@export var world_kind: WorldKind = WorldKind.OPEN_TERRAIN
@export var celestial_body_path: NodePath = ^"../TerrainWorld"
@export var terrain_path: NodePath = ^"../TerrainWorld"

@export var celestial_body_player_scene: PackedScene = preload("res://character/player.tscn")
@export
var open_terrain_player_scene: PackedScene = preload("res://character/open_terrain_player.tscn")
@export var boxed_in_terrain_player_scene: PackedScene = preload(
	"res://character/boxed_in_terrain_player.tscn"
)


func _ready() -> void:
	call_deferred("_spawn_player")


func _spawn_player() -> void:
	await _wait_for_world_ready()
	var player: FighterBody = create_fighter_body(LoadingScreen.selected_player_character, null)
	if player == null:
		return
	player.name = "Player"
	player.add_to_group("player")
	get_parent().add_child(player)
	# Every playable map gets the minimap; it renders the real scene, so it needs no map data.
	Minimap.attach(player, get_parent())


## A body for a fighter of a class, not yet in the tree. With a controller (a BotBrain, later a
## network pilot) it is a lightweight body: no camera rig, no terrain tools, the class's bot
## skin, and a weapon that leaves the terrain alone. Without one it is the local player.
func create_fighter_body(
	character: LoadingScreen.PlayerCharacter, controller: FighterController, skin_path: String = ""
) -> FighterBody:
	var player_scene: PackedScene = _pick_player_scene()
	if player_scene == null:
		push_error("[PlayerSpawner] No player scene configured.")
		return null
	var body: FighterBody = player_scene.instantiate() as FighterBody
	if body == null:
		push_error("[PlayerSpawner] The player scene's root is not a FighterBody.")
		return null
	var is_local: bool = controller == null
	body.character = character
	body.use_bot_skin = not is_local
	body.skin_override_path = skin_path
	body.auto_spawn = is_local
	if not is_local:
		for node_name: String in _LOCAL_ONLY_NODES:
			var node: Node = body.get_node_or_null(node_name)
			if node != null:
				body.remove_child(node)
				node.free()
		var shooter: Node = body.get_node_or_null("ShooterTest")
		if shooter != null and "lightweight_impacts" in shooter:
			shooter.set("lightweight_impacts", true)
		body.add_child(controller)
	_bind_world_references(body)
	_attach_damageable(body)
	if is_local:
		_attach_breath(body)
	CharacterSkin.apply_class_stats(
		body, body.get_node_or_null("Damageable") as Damageable, character
	)
	return body


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
