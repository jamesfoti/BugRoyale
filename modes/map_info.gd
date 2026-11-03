class_name MapInfo
extends RefCounted
## Answers map questions the same way on every map (celestial body, open battlefield, terrarium) so
## game modes, bots and hornets don't care which one they are on: which way is up, how high above
## the ground a point is, the playable bounds, random spawn points, and the terrarium's water.

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
## World Y of an overhead ceiling (a crawlspace's joists), INF on open maps. Flyers stay under it.
var ceiling_y: float = INF

var _space: PhysicsDirectSpaceState3D

## Builds the info for a loaded map scene (looks at its PlayerSpawner's terrain).


static func from_scene(scene_root: Node) -> MapInfo:
	var info := MapInfo.new()
	var spawner: PlayerSpawner = (
		scene_root.find_children("*", "PlayerSpawner", true, false).front() as PlayerSpawner
	)
	if spawner != null:
		info.world = spawner.get_node_or_null(spawner.terrain_path) as Node3D
	if info.world == null:
		info.world = scene_root.get_tree().get_first_node_in_group("terrain_world") as Node3D
	info._space = (
		(scene_root as Node3D).get_world_3d().direct_space_state if scene_root is Node3D else null
	)
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
		var terrain_center: Vector3 = (
			terrain.global_position if terrain != null else room.global_position
		)
		var size: Vector3 = room.get_world_extents()
		# Slightly inside the glass walls.
		info.bounds = AABB(terrain_center - size * 0.5, size).grow(-0.6)
	elif info.world != null and info.world.has_method("get_world_extents"):
		var size: Vector3 = info.world.get_world_extents()
		info.bounds = AABB(info.world.global_position - size * 0.5, size).grow(-1.0)
		# A builder may fence off part of the dirt (the garden's chain-link): play stays inside
		# its footprint, keeping the terrain's own vertical range.
		for bounds_node: Node in scene_root.get_tree().get_nodes_in_group("map_bounds"):
			if bounds_node.has_method("get_play_bounds"):
				var play: AABB = bounds_node.call("get_play_bounds")
				info.bounds = AABB(
					Vector3(play.position.x, info.bounds.position.y, play.position.z),
					Vector3(play.size.x, info.bounds.size.y, play.size.z)
				)
		# A map with overhead structure (CrawlspaceBuilder) caps flight at its ceiling, which may
		# sit well above the dirt's voxel volume; the playable box grows up to meet it.
		for ceiling_node: Node in scene_root.get_tree().get_nodes_in_group("map_ceiling"):
			info.ceiling_y = (
				float(ceiling_node.call("get_ceiling_y"))
				if ceiling_node.has_method("get_ceiling_y")
				else info.bounds.end.y
			)
			if info.ceiling_y > info.bounds.end.y:
				info.bounds.size.y = info.ceiling_y - info.bounds.position.y
	# A map may carry a body of water (the terrarium's pool).
	var waters: Array[Node] = scene_root.find_children("*", "TerrariumWater", true, false)
	if not waters.is_empty():
		info.water = waters[0] as TerrariumWater
	return info


## The terrain the pickaxe edits on this map: the world itself, a terrarium's playable
## terrain, or whatever is in the terrain_world group. Null on a map without one.
func editable_terrain() -> ChunkedTerrainWorld:
	if world is ChunkedTerrainWorld:
		return world as ChunkedTerrainWorld
	if world is TerrariumRoom:
		return (world as TerrariumRoom).get_playable_terrain()
	if world != null and world.is_inside_tree():
		return world.get_tree().get_first_node_in_group("terrain_world") as ChunkedTerrainWorld
	return null


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
		var bottom: float = (
			bounds.position.y - 40.0 if bounds.size != Vector3.ZERO else position.y - 200.0
		)
		from = Vector3(position.x, top, position.z)
		to = Vector3(position.x, bottom, position.z)
	return _cast(from, to)


## The ground directly under a point (a short cast down from just above it), empty if there is
## none within reach. Unlike ground_hit this starts at the point, so a tree canopy or a joist
## overhead is not mistaken for the ground.
func ground_below(position: Vector3, reach: float = 6.0) -> Dictionary:
	var up: Vector3 = up_at(position)
	return _cast(position + up * 0.5, position - up * reach)


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
func random_surface_point(
	clearance: float = 1.2, side: float = 0.0, min_height: float = -INF
) -> Vector3:
	var best: Vector3 = center() + up_at(center()) * clearance
	for attempt: int in _SPAWN_TRIES:
		var hit: Dictionary = {}
		if kind == Kind.CELESTIAL_BODY:
			var direction := (
				Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
			)
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
				randf_range(
					lerpf(bounds.position.z, bounds.end.z, margin),
					lerpf(bounds.position.z, bounds.end.z, 1.0 - margin)
				)
			)
			hit = ground_hit(column)
		if hit.is_empty():
			continue
		var point: Vector3 = hit.position + up_at(hit.position) * clearance
		if kind != Kind.CELESTIAL_BODY and point.y < min_height:
			best = point
			continue
		return point
	return best


## A spot on the ground a few metres from a point (clearance above the ground).
func ground_point_near(
	point: Vector3, min_distance: float, max_distance: float, clearance: float
) -> Vector3:
	var up: Vector3 = up_at(point)
	var offset: Vector3 = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD)
	offset = offset.normalized().rotated(up, randf_range(0.0, TAU))
	offset *= randf_range(min_distance, max_distance)
	var ground: Dictionary = ground_hit(point + offset)
	if ground.is_empty():
		return point + up * clearance
	return ground.position + up_at(ground.position) * clearance


## Heights above the ground flyers keep to (hornets, the dragonfly on station): low under the
## terrarium glass, lower still under a crawlspace's joists.
func flight_band() -> Vector2:
	var band := Vector2(8.0, 16.0)
	match kind:
		Kind.TERRARIUM:
			band = Vector2(3.0, 9.0)
		Kind.CELESTIAL_BODY:
			band = Vector2(6.0, 13.0)
	if ceiling_y < INF:
		var dirt: Dictionary = ground_hit(center())
		var dirt_y: float = dirt.position.y if not dirt.is_empty() else bounds.position.y
		band = Vector2(2.0, clampf(ceiling_y - dirt_y - 3.0, 3.0, 40.0))
	return band


## Solid boxes flyers steer around and are pushed out of: a crawlspace's ducts, furnace and
## piers. Empty on open maps.
func flying_obstacles() -> Array[AABB]:
	var result: Array[AABB] = []
	if world == null or not world.is_inside_tree():
		return result
	var network: DuctNetwork = (
		world.get_tree().get_first_node_in_group("duct_network") as DuctNetwork
	)
	if network != null:
		result.assign(network.obstacles)
	return result


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
