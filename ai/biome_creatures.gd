class_name BiomeCreatures
extends Node3D
## Spawns the creatures of a map's biomes (CreatureFeature) once its terrain is built, and again
## after each rebuild: for each creature the terrain lists under Biome Features, a group at each
## home (a site of its Home feature, or of a 64 m grid without one) whose biome lists the
## creature, at that biome's density, up to the creature's cap. The same seed puts the same
## groups in the same places. Creatures are not a mode's fighters: no team of a mode, no score,
## no respawn; a dead one is cleared away after a while.

## The spacing of homes for a creature without a Home feature.
const GRID: float = 64.0
## How long a dead creature lies before it is cleared away.
const CORPSE_SECONDS: float = 8.0

var terrain: OpenTerrain
var map: MapInfo

var _bodies: Array[FighterBody] = []


## Adds the spawner beside a terrain (one per scene); null without a terrain.
static func attach(scene_root: Node, terrain_node: OpenTerrain) -> BiomeCreatures:
	if scene_root == null or terrain_node == null:
		return null
	var existing: BiomeCreatures = scene_root.get_node_or_null("BiomeCreatures") as BiomeCreatures
	if existing != null:
		return existing
	var creatures := BiomeCreatures.new()
	creatures.name = "BiomeCreatures"
	creatures.terrain = terrain_node
	scene_root.add_child(creatures)
	return creatures


## The creature features a terrain lists.
static func creatures_of(terrain_node: OpenTerrain) -> Array[CreatureFeature]:
	var out: Array[CreatureFeature] = []
	for feature: Variant in terrain_node.biome_features:
		if feature is CreatureFeature:
			out.append(feature as CreatureFeature)
	return out


## The homes of a creature: its Home feature's sites (termite mounds' feet) or a grid's.
static func homes_of(
	creature: CreatureFeature, density: WorldDensity, area: AABB, seed_value: int
) -> PackedVector3Array:
	var out := PackedVector3Array()
	if creature.home is TermiteMoundFeature:
		for mound: Dictionary in density.termite_mounds_in(area):
			out.append(mound.base)
		return out
	if creature.home != null:
		push_warning(
			"[BiomeCreatures] %s: no homes from a %s." % [creature.feature_name, creature.home]
		)
		return out
	var first_x: int = floori(area.position.x / GRID)
	var first_z: int = floori(area.position.z / GRID)
	for cell_z: int in range(first_z, ceili(area.end.z / GRID)):
		for cell_x: int in range(first_x, ceili(area.end.x / GRID)):
			var roll := RandomNumberGenerator.new()
			roll.seed = hash([seed_value, cell_x, cell_z])
			var x: float = (cell_x + roll.randf_range(0.15, 0.85)) * GRID
			var z: float = (cell_z + roll.randf_range(0.15, 0.85)) * GRID
			if x > area.position.x and x < area.end.x and z > area.position.z and z < area.end.z:
				out.append(Vector3(x, area.get_center().y, z))
	return out


## The density the biome at a point gives a creature (0 when it does not list it).
static func density_at(density: WorldDensity, creature: CreatureFeature, point: Vector3) -> float:
	var kind: Dictionary = density.land_biome(point.x, point.z)
	for entry: Dictionary in kind.get("features", []):
		if int(entry.get("id", 0)) == creature.get_instance_id():
			return float(entry.get("density", 0.0))
	return 0.0


func _ready() -> void:
	if terrain == null:
		return
	terrain.built.connect(spawn)
	if not terrain.is_building() and terrain.get_child_count() > 0:
		spawn.call_deferred()


## The creatures now standing.
func bodies() -> Array[FighterBody]:
	var out: Array[FighterBody] = []
	for body: FighterBody in _bodies:
		if is_instance_valid(body):
			out.append(body)
	return out


## Clears the creatures and spawns them afresh for the terrain as built.
func spawn() -> void:
	clear()
	var density: WorldDensity = terrain._get_bake_density()
	if density == null:
		return
	map = MapInfo.from_scene(get_parent())
	var extents: Vector3 = terrain.get_world_extents()
	var area := AABB(terrain.global_position - extents * 0.5, extents)
	for creature: CreatureFeature in creatures_of(terrain):
		var homes: PackedVector3Array = homes_of(creature, density, area, terrain.noise_seed)
		var count: int = 0
		var groups: int = 0
		for index: int in homes.size():
			var home: Vector3 = homes[index]
			var roll := RandomNumberGenerator.new()
			roll.seed = hash([terrain.noise_seed, creature.feature_name, index])
			if roll.randf() >= density_at(density, creature, home):
				continue
			var members: int = roll.randi_range(creature.group_size.x, creature.group_size.y)
			groups += 1
			for member: int in members:
				if count >= creature.max_count:
					break
				if _spawn_one(creature, home, roll) != null:
					count += 1
		print(
			(
				"[BiomeCreatures] %d %s in %d groups (%d homes)"
				% [count, creature.feature_name, groups, homes.size()]
			)
		)


## Frees every creature.
func clear() -> void:
	for body: FighterBody in _bodies:
		if is_instance_valid(body):
			body.queue_free()
	_bodies.clear()


func _spawn_one(
	creature: CreatureFeature, home: Vector3, roll: RandomNumberGenerator
) -> FighterBody:
	var brain := CreatureBrain.new()
	brain.name = "CreatureBrain"
	brain.map = map
	brain.weapon = creature.bite()
	brain.home = home
	brain.wander_radius = creature.wander_radius
	brain.anger_seconds = creature.anger_seconds
	brain.call_radius = creature.call_radius
	var factory := PlayerSpawner.new()
	var body: FighterBody = factory.create_fighter_body(
		creature.character, brain, creature.skin_path
	)
	factory.free()
	if body == null:
		return null
	if body is OpenTerrainPlayer:
		(body as OpenTerrainPlayer).terrain = terrain
	body.name = "%s_%d" % [creature.feature_name.to_pascal_case(), _bodies.size()]
	body.collision_layer = MapInfo.FIGHTER_LAYER
	body.collision_mask = MapInfo.TERRAIN_LAYER | MapInfo.FIGHTER_LAYER | MapInfo.STRUCTURE_LAYER
	body.add_to_group(CreatureFeature.GROUP)
	add_child(body)
	var health: Damageable = body.get_node_or_null("Damageable") as Damageable
	health.team = CreatureFeature.TEAM
	body.respawn_at(_spawn_point(home, creature, roll))
	health.revive()
	brain.on_respawn()
	body.apply_hand_item(PlayerItems.Item.NONE)
	health.died.connect(_on_died.bind(body))
	_bodies.append(body)
	return body


## A spot on the ground near home: round a termite mound's foot, a few metres out from it.
func _spawn_point(home: Vector3, creature: CreatureFeature, roll: RandomNumberGenerator) -> Vector3:
	var turn: float = roll.randf() * TAU
	var out_by: float = roll.randf_range(0.3, 0.6) * creature.wander_radius
	if creature.home is TermiteMoundFeature:
		out_by = roll.randf_range(14.0, 20.0)
	var column: Vector3 = home + Vector3(cos(turn), 0.0, sin(turn)) * out_by
	var ground: Dictionary = map.ground_hit(column) if map != null else {}
	if not ground.is_empty():
		return ground.position + Vector3.UP * 1.0
	return Vector3(column.x, terrain.get_surface_height_at(column) + 1.0, column.z)


func _on_died(body: FighterBody) -> void:
	if not is_instance_valid(body):
		return
	body.set_in_play(false)
	get_tree().create_timer(CORPSE_SECONDS).timeout.connect(
		func() -> void:
			if is_instance_valid(body):
				_bodies.erase(body)
				body.queue_free()
	)
