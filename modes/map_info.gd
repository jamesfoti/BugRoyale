extends RefCounted
class_name MapInfo
## Answers map questions the same way on every map (celestial body, open battlefield, terrarium) so game
## modes, bots and hornets don't care which one they are on: which way is up, how high above the
## ground a point is, the playable bounds, random spawn points, and the terrarium's water.

enum Kind { FLAT, CELESTIAL_BODY, TERRARIUM }

## Collision layers: terrain and walls are on layer 1; players and bots ("fighters") on layer 2
## so ground probes ignore them; hornets use layer 4.
const TERRAIN_LAYER: int = 1
const FIGHTER_LAYER: int = 2
## Built structure (a crawlspace's joists, piers and walls): fighters collide with it, but ground
## probes look through it, so spawns and flight heights come from the dirt.
const STRUCTURE_LAYER: int = 16

const _SPAWN_TRIES: int = 24

var kind: Kind = Kind.FLAT
var world: Node3D
var body_center: Vector3 = Vector3.ZERO
var body_radius: float = 18.0
## Playable box for flat maps and the terrarium (unused on the celestial body).
var bounds: AABB = AABB()
var water: TerrariumWater
## Fish-bowl terrarium: the glass sphere (radius 0 on a box terrarium or other maps).
var bowl_radius: float = 0.0
var bowl_center: Vector3 = Vector3.ZERO
## World Y of an overhead ceiling (a crawlspace's joists), INF on open maps. Flyers stay under it.
var ceiling_y: float = INF

var _space: PhysicsDirectSpaceState3D


## Builds the info for a loaded map scene (looks at its PlayerSpawner's terrain).
static func from_scene(scene_root: Node) -> MapInfo:
	var info := MapInfo.new()
	var spawner: PlayerSpawner = scene_root.find_children("*", "PlayerSpawner", true, false).front() as PlayerSpawner
	if spawner != null:
		info.world = spawner.get_node_or_null(spawner.terrain_path) as Node3D
	if info.world == null:
		info.world = scene_root.get_tree().get_first_node_in_group("terrain_world") as Node3D
	info._space = (scene_root as Node3D).get_world_3d().direct_space_state if scene_root is Node3D else null
	if info._space == null and info.world != null:
		info._space = info.world.get_world_3d().direct_space_state

	if info.world is CelestialBody:
		var celestial_body: CelestialBody = info.world as CelestialBody
		info.kind = Kind.CELESTIAL_BODY
		info.body_center = celestial_body.get_body_center_world()
		info.body_radius = celestial_body.get_sphere_radius()
	elif info.world is TerrariumRoom:
		var room: TerrariumRoom = info.world as TerrariumRoom
		info.kind = Kind.TERRARIUM
		var terrain: TerrariumTerrain = room.get_playable_terrain()
		var terrain_center: Vector3 = terrain.global_position if terrain != null else room.global_position
		var size: Vector3 = room.get_world_extents()
		# Slightly inside the glass walls.
		info.bounds = AABB(terrain_center - size * 0.5, size).grow(-0.6)
		info.bowl_radius = room.get_bowl_radius()
		info.bowl_center = room.get_bowl_center()
	elif info.world != null and info.world.has_method("get_world_extents"):
		var size: Vector3 = info.world.get_world_extents()
		info.bounds = AABB(info.world.global_position - size * 0.5, size).grow(-1.0)
		# A map with overhead structure (CrawlspaceBuilder) caps flight at the top of the bounds,
		# which is where the builder hangs its joists.
		if not scene_root.get_tree().get_nodes_in_group("map_ceiling").is_empty():
			info.ceiling_y = info.bounds.end.y
	# Any map may carry a body of water (the terrariums' pools, the crawlspace's flood).
	var waters: Array[Node] = scene_root.find_children("*", "TerrariumWater", true, false)
	if not waters.is_empty():
		info.water = waters[0] as TerrariumWater
	return info


func up_at(position: Vector3) -> Vector3:
	if kind == Kind.CELESTIAL_BODY:
		var radial: Vector3 = position - body_center
		return radial.normalized() if radial.length_squared() > 0.0001 else Vector3.UP
	return Vector3.UP


## Height of a point above the ground directly beneath it.
func altitude(position: Vector3) -> float:
	var ground: Dictionary = ground_hit(position)
	if ground.is_empty():
		if kind == Kind.CELESTIAL_BODY:
			return position.distance_to(body_center) - body_radius
		return position.y - bounds.position.y
	return (position - ground.position).dot(up_at(position))


## Raycast from high above a point down to the ground (empty if nothing below).
func ground_hit(position: Vector3) -> Dictionary:
	var up: Vector3 = up_at(position)
	var from: Vector3
	var to: Vector3
	if kind == Kind.CELESTIAL_BODY:
		from = body_center + up * (body_radius + 60.0)
		to = body_center
	else:
		var top: float = bounds.end.y + 40.0 if bounds.size != Vector3.ZERO else position.y + 100.0
		if kind == Kind.TERRARIUM:
			# Start under the glass lid, which would otherwise count as "ground".
			top = bounds.end.y
			if bowl_radius > 0.0:
				# Fish bowl: start just inside the curved glass over this column.
				var inner_top: float = bowl_inner_top(position)
				if inner_top == -INF:
					return {}
				top = minf(top, inner_top)
		var bottom: float = bounds.position.y - 40.0 if bounds.size != Vector3.ZERO else position.y - 200.0
		from = Vector3(position.x, top, position.z)
		to = Vector3(position.x, bottom, position.z)
	return _cast(from, to)


## Height of a fish bowl's inner glass above a column, or -INF when the column misses the bowl.
func bowl_inner_top(position: Vector3) -> float:
	var horizontal: float = Vector2(position.x - bowl_center.x, position.z - bowl_center.z).length()
	if horizontal >= bowl_radius - 0.3:
		return -INF
	return bowl_center.y + sqrt(bowl_radius * bowl_radius - horizontal * horizontal) - 0.3


## Center of the playable area (on the celestial body: the point on the surface facing +Y).
func center() -> Vector3:
	if kind == Kind.CELESTIAL_BODY:
		return body_center + Vector3.UP * body_radius
	return bounds.get_center()


## Which half of the map a point is in (-1 or +1), used to split teams.
func side_of(position: Vector3) -> float:
	if kind == Kind.CELESTIAL_BODY:
		return signf((position - body_center).x)
	return signf(position.x - bounds.get_center().x)


## Random spot on the ground (plus clearance). side: 0 = anywhere, -1/+1 = that half of the map.
## min_height: only accept ground at least this high (world Y; ignored on the celestial body).
func random_surface_point(clearance: float = 1.2, side: float = 0.0, min_height: float = -INF) -> Vector3:
	var best: Vector3 = center() + up_at(center()) * clearance
	for attempt: int in _SPAWN_TRIES:
		var hit: Dictionary = {}
		if kind == Kind.CELESTIAL_BODY:
			var direction := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
			if side != 0.0:
				direction.x = absf(direction.x) * side
				direction = direction.normalized()
			hit = _cast(body_center + direction * (body_radius + 60.0), body_center)
		else:
			var margin: float = 0.12
			var x_min: float = lerpf(bounds.position.x, bounds.end.x, margin)
			var x_max: float = lerpf(bounds.position.x, bounds.end.x, 1.0 - margin)
			if side < 0.0:
				x_max = bounds.get_center().x - bounds.size.x * 0.1
			elif side > 0.0:
				x_min = bounds.get_center().x + bounds.size.x * 0.1
			var column := Vector3(
				randf_range(x_min, x_max),
				0.0,
				randf_range(lerpf(bounds.position.z, bounds.end.z, margin), lerpf(bounds.position.z, bounds.end.z, 1.0 - margin))
			)
			if bowl_radius > 0.0:
				# Fish bowl: columns inside the opening, so the probe enters through the top.
				var angle: float = randf_range(0.0, TAU)
				var distance: float = sqrt(randf()) * bowl_radius * 0.75
				column = Vector3(bowl_center.x + cos(angle) * distance, 0.0, bowl_center.z + sin(angle) * distance)
				if side != 0.0:
					column.x = bowl_center.x + absf(column.x - bowl_center.x) * side
			hit = ground_hit(column)
		if hit.is_empty():
			continue
		var point: Vector3 = hit.position + up_at(hit.position) * clearance
		if kind != Kind.CELESTIAL_BODY and point.y < min_height:
			best = point
			continue
		return point
	return best


func water_surface_y() -> float:
	return water.get_water_surface_y() if water != null else -INF


## True when a point is below the water surface (always false off the terrarium).
func is_underwater(position: Vector3) -> bool:
	return water != null and position.y < water.get_water_surface_y()


## Keeps a flying point inside the playable box (terrarium glass, battlefield edges).
func clamp_to_bounds(position: Vector3) -> Vector3:
	if kind == Kind.CELESTIAL_BODY or bounds.size == Vector3.ZERO:
		return position
	var clamped: Vector3 = position.clamp(bounds.position, bounds.end)
	if bowl_radius > 0.0:
		var offset: Vector3 = clamped - bowl_center
		var limit: float = bowl_radius - 0.8
		if offset.length() > limit:
			clamped = bowl_center + offset.normalized() * limit
	return clamped


## Fell off the map (below the playable box, or inside the celestial body).
func is_out_of_bounds(position: Vector3) -> bool:
	if kind == Kind.CELESTIAL_BODY:
		return position.distance_to(body_center) < body_radius * 0.4
	return bounds.size != Vector3.ZERO and position.y < bounds.position.y - 25.0


func _cast(from: Vector3, to: Vector3) -> Dictionary:
	if _space == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	# Terrain only: skip players, bots and hornets (layers 2+).
	query.collision_mask = TERRAIN_LAYER
	return _space.intersect_ray(query)
