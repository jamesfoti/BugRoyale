class_name LiquidSource
extends Node3D
## Pours a liquid into the terrain's liquids (TerrainLiquids) at its place for a while: a burst
## pipe's sewage, hot or cold water. The volume runs out evenly over the seconds given, poured in
## lumps of at least `LUMP` cubic metres; what does not fit (the cells over the spot are full, or
## the ground there is not built yet) waits for the next frame, up to two seconds' worth.

const LUMP: float = 0.05

var terrain: ChunkedTerrainWorld
var kind: int = TerrainLiquids.KIND_WATER
var cubic_metres_per_second: float = 0.0
var seconds_left: float = 0.0
## Cubic metres poured so far.
var poured: float = 0.0

var _owed: float = 0.0


## Starts pouring `volume` cubic metres of a liquid at a point over `seconds`; null when the
## terrain has no liquids.
static func pour(
	parent: Node,
	terrain_node: ChunkedTerrainWorld,
	at: Vector3,
	liquid: int,
	volume: float,
	seconds: float
) -> LiquidSource:
	if parent == null or terrain_node == null or terrain_node.get_liquids() == null:
		return null
	var source := LiquidSource.new()
	source.name = "LiquidSource"
	source.terrain = terrain_node
	source.kind = liquid
	source.seconds_left = maxf(seconds, 0.01)
	source.cubic_metres_per_second = volume / source.seconds_left
	parent.add_child(source)
	source.global_position = at
	return source


func _physics_process(delta: float) -> void:
	if terrain == null or not is_instance_valid(terrain) or seconds_left <= 0.0:
		queue_free()
		return
	var running: float = minf(delta, seconds_left)
	seconds_left -= running
	_owed = minf(_owed + cubic_metres_per_second * running, cubic_metres_per_second * 2.0)
	if _owed < LUMP and seconds_left > 0.0:
		return
	var fitted: float = terrain.add_liquid(global_position, _owed, kind)
	_owed -= fitted
	poured += fitted
