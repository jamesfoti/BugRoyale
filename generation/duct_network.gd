class_name DuctNetwork
extends Node3D
## The ductwork's root, carrying what the AI needs to use it: a waypoint graph of the duct
## interiors (centerline points at every run end and junction, plus the outside points at each
## way in), and the solid boxes every run, the furnace and the piers occupy. Bots route through
## the graph whenever they or their goal are inside the ductwork; the hornet flock steers around
## the boxes and is never allowed inside them.

## Waypoints at bug-feet height, in world space.
var points: PackedVector3Array = PackedVector3Array()
## Adjacency: for each point, the indices it connects to.
var links: Array[PackedInt32Array] = []
## Indices of the outside points at each way in.
var entries: PackedInt32Array = PackedInt32Array()
## Solid volumes (world space) that flyers must stay out of.
var obstacles: Array[AABB] = []


func _ready() -> void:
	add_to_group("duct_network")


func add_point(point: Vector3) -> int:
	points.append(point)
	links.append(PackedInt32Array())
	return points.size() - 1


func link(a: int, b: int) -> void:
	links[a].append(b)
	links[b].append(a)


## True when a point lies inside any of the ductwork's volumes.
func is_inside(point: Vector3) -> bool:
	for box: AABB in obstacles:
		if box.has_point(point):
			return true
	return false


## A random waypoint inside the ducts (never an entry).
func random_interior_point() -> Vector3:
	var interior: Array[int] = _interior_indices()
	if interior.is_empty():
		return Vector3.INF
	return points[interior[randi() % interior.size()]]


## Waypoints from `from` to `to` through the graph. A point outside the ductwork joins the graph
## at its nearest entry; a point inside joins at its nearest interior waypoint. Empty when the
## graph has nothing to offer.
func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var start: int = _nearest_node(from, is_inside(from))
	var goal: int = _nearest_node(to, is_inside(to))
	if start < 0 or goal < 0:
		return PackedVector3Array()
	var path: PackedInt32Array = _path(start, goal)
	var result := PackedVector3Array()
	for index: int in path:
		result.append(points[index])
	return result


func _interior_indices() -> Array[int]:
	var interior: Array[int] = []
	for index: int in points.size():
		if not entries.has(index):
			interior.append(index)
	return interior


func _nearest_node(point: Vector3, interior: bool) -> int:
	var candidates: Array = _interior_indices() if interior else Array(entries)
	var best: int = -1
	var best_distance: float = INF
	for index: int in candidates:
		var distance: float = Vector2(points[index].x - point.x, points[index].z - point.z).length()
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


## Breadth-first path between two points (the graph is tiny).
func _path(from: int, to: int) -> PackedInt32Array:
	var previous: Dictionary = {from: -1}
	var queue: Array[int] = [from]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		if current == to:
			break
		for next: int in links[current]:
			if not previous.has(next):
				previous[next] = current
				queue.append(next)
	if not previous.has(to):
		return PackedInt32Array()
	var path := PackedInt32Array()
	var cursor: int = to
	while cursor != -1:
		path.insert(0, cursor)
		cursor = previous[cursor]
	return path
