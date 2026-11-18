class_name LiquidHazards
extends Node
## Hurts the fighters standing in the terrain's harmful liquids (TerrainLiquids): sewage and hot
## water, in half-second pulses so the health bar flashes a few times a second, as the fluid pools
## did. Plain water does no harm (drowning is Breath's). A mode adds one on the host.

const PULSE_SECONDS: float = 0.5
## Damage a second by liquid; a liquid not listed does none.
const DAMAGE_PER_SECOND: Dictionary = {
	TerrainLiquids.KIND_SEWAGE: 6.0,
	TerrainLiquids.KIND_HOT_WATER: 8.0,
}
## How deep in it the feet must be (a film on the ground does not count).
const MIN_DEPTH: float = 0.1
const FIGHTER_GROUP: StringName = &"fighter"

var terrain: ChunkedTerrainWorld

var _pulse: float = 0.0


## Adds the hazards beside a terrain with liquids (one per scene); null without one.
static func attach(scene_root: Node, terrain_node: ChunkedTerrainWorld) -> LiquidHazards:
	if scene_root == null or terrain_node == null or terrain_node.get_liquids() == null:
		return null
	var existing: LiquidHazards = scene_root.get_node_or_null("LiquidHazards") as LiquidHazards
	if existing != null:
		return existing
	var hazards := LiquidHazards.new()
	hazards.name = "LiquidHazards"
	hazards.terrain = terrain_node
	scene_root.add_child(hazards)
	return hazards


## The damage a second a body standing at a point takes from the liquid there.
func damage_at(feet: Vector3) -> float:
	var probe: Vector3 = feet + Vector3.UP * 0.5
	var damage: float = float(DAMAGE_PER_SECOND.get(terrain.liquid_kind_at(probe), 0.0))
	if damage <= 0.0 or terrain.liquid_depth_at(probe) + 0.5 < MIN_DEPTH:
		return 0.0
	return damage


func _physics_process(delta: float) -> void:
	if terrain == null or not is_instance_valid(terrain):
		return
	_pulse += delta
	if _pulse < PULSE_SECONDS:
		return
	_pulse -= PULSE_SECONDS
	for node: Node in get_tree().get_nodes_in_group(FIGHTER_GROUP):
		var body: Node3D = node as Node3D
		if body == null:
			continue
		var damage: float = damage_at(body.global_position)
		if damage <= 0.0:
			continue
		var damageable: Damageable = body.get_node_or_null("Damageable") as Damageable
		if damageable != null and damageable.is_alive():
			damageable.apply_damage(damage * PULSE_SECONDS, self)
