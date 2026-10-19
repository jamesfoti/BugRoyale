class_name DuctBuilder
extends RefCounted
## Procedural rectangular HVAC ductwork for the crawlspace, grown like a tree: a furnace on the
## dirt feeds a trunk duct down the length of the space, branches leave the trunk at right
## angles toward the rooms above, some fork again, and each run ends in a riser up to a floor
## register under the subfloor. Every run is hollow (thin wall panels with openings cut where
## runs join), so bugs can fight inside. Ways in: the furnace's access panel is off, and a couple
## of runs have come off their straps and slope down to the dirt with an open end.
##
## Runs are laid out to thread between the piers, girder rows and the utility lines, and all
## panels collide on the structure layer (bugs bump into them, ground probes look through).

const WIDTH: float = 2.8
const HEIGHT: float = 2.0
const WALL: float = 0.1
## Duct centerline height above the dirt's mean level; the top stays under the utility lines.
const CENTER_ABOVE_DIRT: float = 2.9
const BOOT_LENGTH: float = 9.0
const MAX_DROPPED_BOOTS: int = 2
const METAL_COLOR: Color = Color(0.74, 0.76, 0.78)
const REGISTER_COLOR: Color = Color(0.25, 0.25, 0.27)
const FURNACE_COLOR: Color = Color(0.72, 0.72, 0.7)
const FURNACE_SIZE: Vector3 = Vector3(6.0, 6.0, 8.0)


## One straight hollow run between two centerline points.
class Run:
	var start: Vector3
	var end: Vector3
	var open_start: bool = false
	var open_end: bool = false
	## Openings in a wall: {"at": distance from start, "width": float, "face": "r+"|"r-"|"u+"|"u-"}
	## where r is the run's right vector and u its up vector.
	var cuts: Array = []
	var register_end: bool = false


class Context:
	var root: Node3D
	var rng: RandomNumberGenerator
	var ground: Callable
	var center: Vector3
	var half: Vector3
	var inset: float
	var duct_y: float
	var ceiling_bottom: float
	var pier_rows: Array
	var pier_xs: Array
	var blocked_zs: Array
	var metal: StandardMaterial3D
	var register: StandardMaterial3D
	var furnace: StandardMaterial3D
	var dropped_boots: int = 0
	var runs: Array[Run] = []
	## Where branches leave their parent: {"parent": Run, "at": float, "child": Run}.
	var junctions: Array = []
	## Dropped runs: {"branch": Run, "boot": Run}.
	var boot_pairs: Array = []
	var furnace_ramp_bottom: Vector3
	var furnace_ramp_top: Vector3
	var furnace_access_outside: Vector3


## Builds the ductwork under `parent`. ground(x, z) gives the dirt height; blocked_zs are the z
## positions of utility lines running along X that risers and branches must avoid.
static func build(
	parent: Node3D,
	center: Vector3,
	half: Vector3,
	wall_thickness: float,
	ground: Callable,
	trunk_x: float,
	pier_rows: Array,
	pier_xs: Array,
	blocked_zs: Array,
	ceiling_bottom: float,
	rng: RandomNumberGenerator
) -> DuctNetwork:
	var context := Context.new()
	context.root = DuctNetwork.new()
	context.root.name = "Ductwork"
	parent.add_child(context.root)
	context.rng = rng
	context.ground = ground
	context.center = center
	context.half = half
	context.inset = wall_thickness + 1.5
	context.duct_y = center.y + CENTER_ABOVE_DIRT
	context.ceiling_bottom = ceiling_bottom
	context.pier_rows = pier_rows
	context.pier_xs = pier_xs
	context.blocked_zs = blocked_zs
	context.metal = _material(METAL_COLOR, 0.45)
	context.register = _material(REGISTER_COLOR, 0.8)
	context.furnace = _material(FURNACE_COLOR, 0.6)

	var furnace_z: float = center.z - half.z + context.inset + FURNACE_SIZE.z * 0.5
	var furnace_dirt: float = ground.call(trunk_x, furnace_z)
	_build_furnace(context, Vector3(trunk_x, furnace_dirt, furnace_z))

	# Trunk from the furnace outlet to near the far wall.
	var trunk := Run.new()
	trunk.start = Vector3(trunk_x, context.duct_y, furnace_z + FURNACE_SIZE.z * 0.5)
	trunk.end = Vector3(trunk_x, context.duct_y, center.z + half.z - context.inset - 1.0)
	trunk.open_start = true
	context.runs.append(trunk)
	_grow_branches(context, trunk, Vector3.RIGHT, 2)

	var boots: Array = []
	var network: DuctNetwork = context.root as DuctNetwork
	for run: Run in context.runs:
		_build_run(context, run)
		network.obstacles.append(_run_bounds(run))
		if run.open_end and run.start.y > run.end.y:
			boots.append(run.end)
	_build_graph(context)
	# Where to find the ways in, for anything that wants to point at them.
	context.root.set_meta("furnace_access", Vector3(trunk_x + FURNACE_SIZE.x * 0.5, furnace_dirt, furnace_z - FURNACE_SIZE.z * 0.5 + 0.6 + (WIDTH - 0.2) * 0.5))
	context.root.set_meta("trunk_start", trunk.start)
	context.root.set_meta("boot_ends", boots)
	print("[Ductwork] %d runs, %d dropped boots" % [context.runs.size(), context.dropped_boots])
	return context.root


# --- Growing ----------------------------------------------------------------------------------

## Branches off a run at intervals, alternating sides, along `axis` (RIGHT for branches off a Z
## trunk, FORWARD for sub-branches off an X branch). depth counts remaining forks.
static func _grow_branches(context: Context, trunk: Run, axis: Vector3, depth: int) -> void:
	var forward: Vector3 = (trunk.end - trunk.start).normalized()
	var length: float = trunk.start.distance_to(trunk.end)
	var side: float = 1.0 if context.rng.randf() < 0.5 else -1.0
	var at: float = context.rng.randf_range(8.0, 12.0)
	while at < length - 6.0:
		# Nudge the station along the run until it clears the piers and lines.
		var clear_at: float = -1.0
		for nudge: float in [0.0, 2.0, -2.0, 4.0, -4.0, 6.0]:
			var candidate: float = at + nudge
			if candidate < 6.0 or candidate > length - 6.0:
				continue
			if _station_clear(context, trunk.start + forward * candidate, axis):
				clear_at = candidate
				break
		if clear_at >= 0.0:
			var station: Vector3 = trunk.start + forward * clear_at
			var direction: Vector3 = axis * side
			var branch_length: float = context.rng.randf_range(12.0, 30.0) if depth == 2 else context.rng.randf_range(8.0, 16.0)
			branch_length = _clamp_length(context, station, direction, branch_length)
			if branch_length >= 8.0:
				_add_branch(context, trunk, clear_at, station, direction, branch_length, depth)
				side = -side
		at += context.rng.randf_range(12.0, 17.0)


static func _add_branch(context: Context, trunk: Run, at: float, station: Vector3, direction: Vector3, length: float, depth: int) -> void:
	var forward: Vector3 = (trunk.end - trunk.start).normalized()
	var right: Vector3 = _right_of(forward)
	trunk.cuts.append({"at": at, "width": WIDTH, "face": "r+" if direction.dot(right) > 0.0 else "r-"})
	var branch := Run.new()
	branch.start = station + direction * (WIDTH * 0.5)
	branch.open_start = true
	context.junctions.append({"parent": trunk, "at": at, "child": branch})
	var drop: bool = context.dropped_boots < MAX_DROPPED_BOOTS and context.rng.randf() < 0.4 and length >= BOOT_LENGTH + 8.0
	if drop:
		# The run ends short; the last stretch has fallen to the dirt with its end open.
		branch.end = branch.start + direction * (length - BOOT_LENGTH)
		branch.open_end = true
		var boot := Run.new()
		boot.start = branch.end
		var landing: Vector3 = branch.start + direction * length
		landing.y = context.ground.call(landing.x, landing.z) + HEIGHT * 0.5 + 0.1
		boot.end = landing
		boot.open_start = true
		boot.open_end = true
		context.runs.append(branch)
		context.runs.append(boot)
		context.boot_pairs.append({"branch": branch, "boot": boot})
		context.dropped_boots += 1
	else:
		branch.end = branch.start + direction * length
		context.runs.append(branch)
		_add_riser(context, branch)
	if depth > 1 and not drop and context.rng.randf() < 0.6:
		# Fork once more, perpendicular, from partway along this branch.
		var sub_axis: Vector3 = Vector3.FORWARD if absf(direction.x) > 0.5 else Vector3.RIGHT
		_grow_sub_branch(context, branch, sub_axis)


static func _grow_sub_branch(context: Context, branch: Run, axis: Vector3) -> void:
	var forward: Vector3 = (branch.end - branch.start).normalized()
	var length: float = branch.start.distance_to(branch.end)
	var at: float = length * context.rng.randf_range(0.4, 0.7)
	var station: Vector3 = branch.start + forward * at
	# Runs along Z must thread between the piers: snap to the nearest gap midway between them.
	if absf(axis.z) > 0.5:
		station.x = _nearest_pier_gap(context, station.x)
		if absf(station.x - (branch.start + forward * at).x) > length * 0.3:
			return
		at = (station - branch.start).dot(forward)
	var side: float = 1.0 if context.rng.randf() < 0.5 else -1.0
	for attempt: int in 2:
		var direction: Vector3 = axis * side
		var sub_length: float = _clamp_length(context, station, direction, context.rng.randf_range(8.0, 16.0))
		if sub_length >= 8.0 and _station_clear(context, station, axis):
			_add_branch(context, branch, at, station, direction, sub_length, 1)
			return
		side = -side


## A riser from the end of a run up to the subfloor, closed by a register.
static func _add_riser(context: Context, run: Run) -> void:
	var forward: Vector3 = (run.end - run.start).normalized()
	var length: float = run.start.distance_to(run.end)
	run.cuts.append({"at": length - WIDTH * 0.5, "width": WIDTH, "face": "u+"})
	var riser := Run.new()
	var top_of_run: Vector3 = run.end - forward * (WIDTH * 0.5) + Vector3.UP * (HEIGHT * 0.5)
	riser.start = top_of_run
	riser.end = Vector3(top_of_run.x, context.ceiling_bottom, top_of_run.z)
	riser.open_start = true
	riser.register_end = true
	context.runs.append(riser)


## True when a branch leaving `station` along `axis` won't sit on a pier row, a girder, or a
## utility line.
static func _station_clear(context: Context, station: Vector3, axis: Vector3) -> bool:
	if absf(axis.x) > 0.5:
		# A run along X: its z must dodge pier rows and the lines that also run along X.
		for row_z: float in context.pier_rows:
			if absf(station.z - row_z) < WIDTH * 0.5 + 1.6:
				return false
		for blocked_z: float in context.blocked_zs:
			if absf(station.z - blocked_z) < WIDTH * 0.5 + 0.8:
				return false
	return true


static func _clamp_length(context: Context, station: Vector3, direction: Vector3, wanted: float) -> float:
	var limit: float
	if absf(direction.x) > 0.5:
		limit = (context.center.x + direction.x * (context.half.x - context.inset) - station.x) * direction.x
	else:
		limit = (context.center.z + direction.z * (context.half.z - context.inset) - station.z) * direction.z
	return minf(wanted, limit - WIDTH)


static func _nearest_pier_gap(context: Context, x: float) -> float:
	if context.pier_xs.size() < 2:
		return x
	var best: float = x
	var best_distance: float = INF
	for index: int in context.pier_xs.size() - 1:
		var gap: float = (float(context.pier_xs[index]) + float(context.pier_xs[index + 1])) * 0.5
		if absf(gap - x) < best_distance:
			best_distance = absf(gap - x)
			best = gap
	return best


# --- Panels -----------------------------------------------------------------------------------

## Four wall panels (split around any cuts) plus end caps, in the run's own frame.
static func _build_run(context: Context, run: Run) -> void:
	var forward: Vector3 = (run.end - run.start).normalized()
	var right: Vector3 = _right_of(forward)
	var up: Vector3 = right.cross(forward).normalized()
	var length: float = run.start.distance_to(run.end)
	var basis := Basis(right, up, forward)
	var faces: Array = [
		["r+", right, WIDTH * 0.5, Vector3(WALL, HEIGHT, 0.0)],
		["r-", -right, WIDTH * 0.5, Vector3(WALL, HEIGHT, 0.0)],
		["u+", up, HEIGHT * 0.5, Vector3(WIDTH, WALL, 0.0)],
		["u-", -up, HEIGHT * 0.5, Vector3(WIDTH, WALL, 0.0)],
	]
	for face: Array in faces:
		var gaps: Array = []
		for cut: Dictionary in run.cuts:
			if cut["face"] == face[0]:
				gaps.append([cut["at"] - cut["width"] * 0.5, cut["at"] + cut["width"] * 0.5])
		gaps.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var cursor: float = 0.0
		for gap: Array in gaps:
			_panel_span(context, run, basis, face, cursor, gap[0])
			cursor = gap[1]
		_panel_span(context, run, basis, face, cursor, length)
	if not run.open_start:
		_panel(context, run.start + forward * (WALL * 0.5), basis, Vector3(WIDTH, HEIGHT, WALL), context.metal)
	if not run.open_end:
		_panel(context, run.end - forward * (WALL * 0.5), basis, Vector3(WIDTH, HEIGHT, WALL), context.register if run.register_end else context.metal)
	if run.register_end:
		# Light from the room above leaks through the register grille into the duct.
		var leak := OmniLight3D.new()
		leak.name = "RegisterLight"
		leak.light_color = Color(1.0, 0.95, 0.85)
		leak.light_energy = 1.2
		leak.omni_range = 14.0
		leak.position = run.end - forward * 0.6
		context.root.add_child(leak)


static func _panel_span(context: Context, run: Run, basis: Basis, face: Array, from: float, to: float) -> void:
	if to - from < 0.02:
		return
	var forward: Vector3 = basis.z
	var normal: Vector3 = face[1]
	var size: Vector3 = face[3]
	size.z = to - from
	var position: Vector3 = run.start + forward * ((from + to) * 0.5) + normal * (float(face[2]) - WALL * 0.5)
	_panel(context, position, basis, size, context.metal)


## One wall panel: a box mesh with a matching collider on the structure layer.
static func _panel(context: Context, position: Vector3, basis: Basis, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "DuctPanel"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.transform = Transform3D(basis, position)
	context.root.add_child(mesh_instance)
	var body := StaticBody3D.new()
	body.collision_layer = MapInfo.STRUCTURE_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	mesh_instance.add_child(body)
	return mesh_instance


## The furnace: a hollow cabinet on the dirt with its front access panel missing and the trunk
## leaving through the back, plus a ramp inside up to the trunk's floor and a flue on top.
static func _build_furnace(context: Context, base: Vector3) -> void:
	var size: Vector3 = FURNACE_SIZE
	var center: Vector3 = base + Vector3.UP * size.y * 0.5
	var identity := Basis.IDENTITY
	# Top, the front (-Z, toward the wall) and the -X side.
	_panel(context, center + Vector3.UP * (size.y * 0.5 - WALL * 0.5), identity, Vector3(size.x, WALL, size.z), context.furnace)
	_panel(context, center + Vector3(0.0, 0.0, -(size.z * 0.5 - WALL * 0.5)), identity, Vector3(size.x, size.y, WALL), context.furnace)
	_panel(context, center + Vector3.RIGHT * -(size.x * 0.5 - WALL * 0.5), identity, Vector3(WALL, size.y, size.z), context.furnace)
	# +X side: the access panel is off, an opening at the dirt near the front. Back (+Z): the
	# trunk outlet.
	var access_width: float = WIDTH - 0.2
	var access_height: float = HEIGHT + 0.4
	var access_z: float = base.z - size.z * 0.5 + 0.6 + access_width * 0.5
	var side_x: float = center.x + size.x * 0.5 - WALL * 0.5
	var side_pieces: Array = [
		[base.z - size.z * 0.5, access_z - access_width * 0.5, base.y, base.y + size.y],
		[access_z + access_width * 0.5, base.z + size.z * 0.5, base.y, base.y + size.y],
		[access_z - access_width * 0.5, access_z + access_width * 0.5, base.y + access_height, base.y + size.y],
	]
	for piece: Array in side_pieces:
		if piece[1] - piece[0] < 0.02 or piece[3] - piece[2] < 0.02:
			continue
		_panel(
			context, Vector3(side_x, (piece[2] + piece[3]) * 0.5, (piece[0] + piece[1]) * 0.5), identity,
			Vector3(WALL, piece[3] - piece[2], piece[1] - piece[0]), context.furnace
		)
	_wall_with_hole(context, center + Vector3(0.0, 0.0, size.z * 0.5 - WALL * 0.5), size.x, size.y, base.y, Vector2(0.0, context.duct_y), Vector2(WIDTH, HEIGHT), context.furnace)
	# Ramp from the access opening up to the trunk floor.
	var ramp_start := Vector3(base.x, base.y + 0.1, base.z - size.z * 0.5 + 0.6)
	var ramp_end := Vector3(base.x, context.duct_y - HEIGHT * 0.5 + 0.05, base.z + size.z * 0.5 - 0.6)
	context.furnace_ramp_bottom = Vector3(base.x, base.y + 0.1, access_z)
	context.furnace_ramp_top = ramp_end
	context.furnace_access_outside = Vector3(side_x + 2.5, base.y, access_z)
	(context.root as DuctNetwork).obstacles.append(AABB(base - Vector3(size.x * 0.5, 0.0, size.z * 0.5), size))
	var ramp_forward: Vector3 = (ramp_end - ramp_start).normalized()
	var ramp_right: Vector3 = _right_of(ramp_forward)
	var ramp_basis := Basis(ramp_right, ramp_right.cross(ramp_forward).normalized(), ramp_forward)
	_panel(context, (ramp_start + ramp_end) * 0.5, ramp_basis, Vector3(WIDTH - 0.3, 0.15, ramp_start.distance_to(ramp_end)), context.metal)
	# Flue up to the joists.
	var flue := MeshInstance3D.new()
	flue.name = "Flue"
	var pipe := CylinderMesh.new()
	pipe.top_radius = 0.45
	pipe.bottom_radius = 0.45
	pipe.height = maxf(context.ceiling_bottom - (base.y + size.y), 0.2)
	flue.mesh = pipe
	flue.material_override = context.metal
	flue.position = Vector3(base.x + 1.5, base.y + size.y + pipe.height * 0.5, base.z - 1.5)
	context.root.add_child(flue)


## A vertical wall in the XY plane (normal along Z) with one rectangular hole: four panels.
static func _wall_with_hole(context: Context, center: Vector3, width: float, height: float, bottom_y: float, hole_center: Vector2, hole_size: Vector2, material: Material) -> void:
	var top_y: float = bottom_y + height
	var left: float = center.x - width * 0.5
	var right: float = center.x + width * 0.5
	var hole_left: float = center.x + hole_center.x - hole_size.x * 0.5
	var hole_right: float = center.x + hole_center.x + hole_size.x * 0.5
	var hole_bottom: float = hole_center.y - hole_size.y * 0.5
	var hole_top: float = hole_center.y + hole_size.y * 0.5
	var pieces: Array = [
		[left, hole_left, bottom_y, top_y],
		[hole_right, right, bottom_y, top_y],
		[hole_left, hole_right, bottom_y, hole_bottom],
		[hole_left, hole_right, hole_top, top_y],
	]
	for piece: Array in pieces:
		var piece_width: float = piece[1] - piece[0]
		var piece_height: float = piece[3] - piece[2]
		if piece_width < 0.02 or piece_height < 0.02:
			continue
		_panel(
			context, Vector3((piece[0] + piece[1]) * 0.5, (piece[2] + piece[3]) * 0.5, center.z), Basis.IDENTITY,
			Vector3(piece_width, piece_height, WALL), material
		)


# --- AI data ----------------------------------------------------------------------------------

## World-space box a run occupies (its oriented box's bounds).
static func _run_bounds(run: Run) -> AABB:
	var forward: Vector3 = (run.end - run.start).normalized()
	var right: Vector3 = _right_of(forward)
	var up: Vector3 = right.cross(forward).normalized()
	var mid: Vector3 = (run.start + run.end) * 0.5
	var half_length: float = run.start.distance_to(run.end) * 0.5
	var bounds := AABB(mid, Vector3.ZERO)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				bounds = bounds.expand(mid + right * (sx * WIDTH * 0.5) + up * (sy * HEIGHT * 0.5) + forward * (sz * half_length))
	return bounds


## Waypoint at bug-feet height on a run's floor, under a centerline point.
static func _feet(run: Run, point: Vector3) -> Vector3:
	var forward: Vector3 = (run.end - run.start).normalized()
	var up: Vector3 = _right_of(forward).cross(forward).normalized()
	return point - up * (HEIGHT * 0.5 - 0.1)


## The interior waypoint graph: a point just inside each end of every walkable run, one at each
## junction, chained along the run and linked into the branch; plus the ways in.
static func _build_graph(context: Context) -> void:
	var network: DuctNetwork = context.root as DuctNetwork
	var inset: float = 1.5
	var run_nodes: Dictionary = {}
	for run: Run in context.runs:
		if run.register_end:
			continue
		var forward: Vector3 = (run.end - run.start).normalized()
		run_nodes[run] = {
			"start": network.add_point(_feet(run, run.start + forward * inset)),
			"end": network.add_point(_feet(run, run.end - forward * inset)),
			"stations": [],
		}
	for junction: Dictionary in context.junctions:
		var parent: Run = junction["parent"]
		var child: Run = junction["child"]
		if not run_nodes.has(parent) or not run_nodes.has(child):
			continue
		var forward: Vector3 = (parent.end - parent.start).normalized()
		var station: int = network.add_point(_feet(parent, parent.start + forward * float(junction["at"])))
		run_nodes[parent]["stations"].append([float(junction["at"]), station])
		network.link(station, run_nodes[child]["start"])
	for run: Run in run_nodes:
		var sequence: Array = [[0.0, run_nodes[run]["start"]]]
		sequence.append_array(run_nodes[run]["stations"])
		sequence.append([run.start.distance_to(run.end), run_nodes[run]["end"]])
		sequence.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for index: int in sequence.size() - 1:
			network.link(sequence[index][1], sequence[index + 1][1])
	for pair: Dictionary in context.boot_pairs:
		var branch: Run = pair["branch"]
		var boot: Run = pair["boot"]
		network.link(run_nodes[branch]["end"], run_nodes[boot]["start"])
		var forward: Vector3 = (boot.end - boot.start).normalized()
		var outward: Vector3 = Vector3(forward.x, 0.0, forward.z).normalized()
		var outside: Vector3 = boot.end + outward * 2.5
		outside.y = float(context.ground.call(outside.x, outside.z)) + 0.1
		var entry: int = network.add_point(outside)
		network.link(run_nodes[boot]["end"], entry)
		network.entries.append(entry)
	# The furnace: outside the access, the ramp bottom, the ramp top, then the trunk.
	var trunk: Run = context.runs[0]
	var access: int = network.add_point(context.furnace_access_outside)
	var ramp_bottom: int = network.add_point(context.furnace_ramp_bottom)
	var ramp_top: int = network.add_point(context.furnace_ramp_top)
	network.link(access, ramp_bottom)
	network.link(ramp_bottom, ramp_top)
	network.link(ramp_top, run_nodes[trunk]["start"])
	network.entries.append(access)


static func _right_of(forward: Vector3) -> Vector3:
	var right: Vector3 = forward.cross(Vector3.UP)
	if right.length_squared() < 0.001:
		right = forward.cross(Vector3.FORWARD)
	return right.normalized()


static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
