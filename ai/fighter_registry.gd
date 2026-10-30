class_name FighterRegistry
extends RefCounted
## One list of everyone a bot might hunt, built once per physics frame and shared by every brain,
## instead of each bot walking the scene groups and asking every node for its health. Entries are
## the bodies in the "fighter" group that are in play and alive, and the live birds, with their
## team and position. It also answers how far a point is from the nearest human, which the
## physics, rendering and ghost tiers use to decide how much a bot deserves.

const FIGHTER_GROUP: StringName = &"fighter"
const BIRD_GROUP: StringName = &"bird"

static var _frame: int = -1
static var _nodes: Array[Node3D] = []
static var _positions: PackedVector3Array = PackedVector3Array()
static var _teams: PackedInt32Array = PackedInt32Array()
static var _groups: Array[StringName] = []
static var _human_positions: PackedVector3Array = PackedVector3Array()


## The nearest live member of any of the groups within max_distance that is not on `team` (a
## NO_TEAM hunter takes anyone), excluding one node (the hunter itself). Null if none.
static func nearest_enemy(
	tree: SceneTree,
	from: Vector3,
	team: int,
	groups: Array[StringName],
	max_distance: float,
	exclude: Node3D
) -> Node3D:
	_refresh(tree)
	var best: Node3D = null
	var best_distance_sq: float = max_distance * max_distance
	for index: int in _nodes.size():
		if _nodes[index] == exclude or not groups.has(_groups[index]):
			continue
		if team != Damageable.NO_TEAM and _teams[index] == team:
			continue
		var distance_sq: float = from.distance_squared_to(_positions[index])
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best = _nodes[index]
	return best


## Distance from a point to the nearest human in play (INF when there is none).
static func distance_to_nearest_human(tree: SceneTree, point: Vector3) -> float:
	_refresh(tree)
	var best_sq: float = INF
	for human_position: Vector3 in _human_positions:
		best_sq = minf(best_sq, point.distance_squared_to(human_position))
	return sqrt(best_sq) if best_sq < INF else INF


## Rebuilds the lists once per physics frame; later callers in the frame share them.
static func _refresh(tree: SceneTree) -> void:
	var frame: int = Engine.get_physics_frames()
	if frame == _frame:
		return
	_frame = frame
	_nodes.clear()
	_positions.clear()
	_teams.clear()
	_groups.clear()
	_human_positions.clear()
	for node: Node in tree.get_nodes_in_group(FIGHTER_GROUP):
		var body: FighterBody = node as FighterBody
		if body == null or not body.is_inside_tree() or not body.is_in_play():
			continue
		var health: Damageable = body.get_node_or_null("Damageable") as Damageable
		if health == null or not health.is_alive():
			continue
		_add(body, health.team, FIGHTER_GROUP)
		if not (body.controller is BotBrain):
			_human_positions.append(body.global_position)
	for node: Node in tree.get_nodes_in_group(BIRD_GROUP):
		var bird: Node3D = node as Node3D
		if bird == null or not bird.is_inside_tree():
			continue
		var health: Damageable = bird.get_node_or_null("Damageable") as Damageable
		if health == null or not health.is_alive():
			continue
		_add(bird, health.team, BIRD_GROUP)


static func _add(node: Node3D, team: int, group: StringName) -> void:
	_nodes.append(node)
	_positions.append(node.global_position)
	_teams.append(team)
	_groups.append(group)
