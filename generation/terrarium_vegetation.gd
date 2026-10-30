class_name TerrariumVegetation
extends Node3D
## Procedural terrarium garden: moss cushions, ferns, red nerve plants, mushrooms, slate rocks,
## driftwood and small branching trees, grown over the terrain the same way the terrain is grown
## from noise. Placement samples the terrain's analytic surface height (no physics needed) with a
## seeded RNG, so a terrarium always grows the same garden. Every plant kind draws through one
## MultiMesh; trees, logs and rocks get simple collision so bugs walk around them. Carving the
## terrain (pickaxe, explosions) clears whatever grew in the hole.

const EDGE_MARGIN: float = 1.5
const PLACEMENT_TRIES: int = 12
## Instances per 100 m² of terrarium floor at density 1.0.
const MOSS_PER_100M2: float = 11.0
const FERNS_PER_100M2: float = 3.0
const RED_PLANTS_PER_100M2: float = 1.2
const ROCKS_PER_100M2: float = 0.4
const LOGS_PER_100M2: float = 0.13
const TREES_PER_100M2: float = 0.25
const MUSHROOM_CLUSTERS_PER_100M2: float = 1.4

const MOSS_TINTS: Array[Color] = [
	Color(0.36, 0.64, 0.2),
	Color(0.27, 0.5, 0.15),
	Color(0.52, 0.7, 0.22),
	Color(0.22, 0.42, 0.13),
]
const LEAF_TINTS: Array[Color] = [
	Color(0.3, 0.56, 0.2), Color(0.23, 0.46, 0.16), Color(0.4, 0.62, 0.22)
]
const FERN_TINTS: Array[Color] = [
	Color(0.3, 0.6, 0.22), Color(0.36, 0.66, 0.26), Color(0.24, 0.5, 0.2)
]
const BARK_COLOR: Color = Color(0.3, 0.22, 0.15)
const DRIFTWOOD_COLOR: Color = Color(0.46, 0.37, 0.27)
const ROCK_COLOR: Color = Color(0.32, 0.35, 0.4)

var _rng := RandomNumberGenerator.new()
var _terrain: TerrariumTerrain
var _water_y: float = -INF
var _bounds: AABB = AABB()
var _density: float = 1.0
var _patches: Dictionary = {}
var _props: Array[Prop] = []
## Collision bodies of placed props, skipped by ground probes.
var _exclude: Array[RID] = []
## Fish bowl glass sphere (radius 0 for a box terrarium): probes start inside it.
var _bowl_radius: float = 0.0
var _bowl_center: Vector3 = Vector3.ZERO


## Configures a garden for a terrain; add it to the tree, then call grow().
static func build(
	terrain: TerrariumTerrain, water: TerrariumWater, garden_seed: int, density: float
) -> TerrariumVegetation:
	var vegetation := TerrariumVegetation.new()
	vegetation.name = "TerrariumVegetation"
	vegetation._terrain = terrain
	vegetation._water_y = water.get_water_surface_y() if water != null else -INF
	vegetation._density = maxf(density, 0.0)
	vegetation._rng.seed = garden_seed
	return vegetation


## Fish bowl terrariums: keep plants inside the sphere and probe from under its glass.
func set_bowl(center: Vector3, radius: float) -> void:
	_bowl_center = center
	_bowl_radius = maxf(radius, 0.0)


## Grows once the terrain's fresh collision is queryable (the physics server registers new
## bodies on its next step).
func grow_when_ready() -> void:
	if not is_inside_tree():
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	grow()


func grow() -> void:
	if _terrain == null or not is_inside_tree():
		return
	var extents: Vector3 = _terrain.get_world_extents()
	_bounds = AABB(_terrain.global_position - extents * 0.5, extents)
	var floor_100m2: float = extents.x * extents.z / 100.0 * _density
	_grow_moss(int(round(MOSS_PER_100M2 * floor_100m2)))
	_grow_ferns(int(round(FERNS_PER_100M2 * floor_100m2)))
	_grow_red_plants(int(round(RED_PLANTS_PER_100M2 * floor_100m2)))
	_grow_rocks(int(round(ROCKS_PER_100M2 * floor_100m2)))
	_grow_logs(int(round(LOGS_PER_100M2 * floor_100m2)))
	_grow_trees(int(round(TREES_PER_100M2 * floor_100m2)))
	_grow_mushrooms(int(round(MUSHROOM_CLUSTERS_PER_100M2 * floor_100m2)))
	var total: int = 0
	for patch: Patch in _patches.values():
		_commit_patch(patch)
		total += patch.transforms.size()
	if _terrain.has_signal("brush_applied"):
		_terrain.brush_applied.connect(_on_brush_applied)
	if total == 0 and _props.is_empty():
		push_warning(
			"[TerrariumVegetation] Nothing grew: no terrain collision found under the terrarium."
		)
	print("[TerrariumVegetation] Grew %d plants and %d props" % [total, _props.size()])


# --- Placement --------------------------------------------------------------------------------


## A spot on the ground: flat enough (min_up = minimum surface normal Y), above the water by
## water_margin, inside the glass with a margin, optionally within spread of a point, and with
## the ground still there under a footprint radius (so wide plants don't hang off cliff lips).
func _find_spot(
	min_up: float,
	water_margin: float,
	near: Vector3 = Vector3.INF,
	spread: float = 0.0,
	footprint: float = 0.0
) -> Dictionary:
	# Wide plants keep their whole footprint off the glass.
	var margin: float = EDGE_MARGIN + footprint * 0.7
	for _try: int in PLACEMENT_TRIES:
		var x: float
		var z: float
		if near == Vector3.INF and _bowl_radius > 0.0:
			var angle: float = _rng.randf() * TAU
			var distance: float = sqrt(_rng.randf()) * maxf(_bowl_radius - margin, 0.0)
			x = _bowl_center.x + cos(angle) * distance
			z = _bowl_center.z + sin(angle) * distance
		elif near == Vector3.INF:
			x = _rng.randf_range(_bounds.position.x + margin, _bounds.end.x - margin)
			z = _rng.randf_range(_bounds.position.z + margin, _bounds.end.z - margin)
		else:
			var angle: float = _rng.randf() * TAU
			var distance: float = _rng.randf_range(0.0, spread)
			x = near.x + cos(angle) * distance
			z = near.z + sin(angle) * distance
			if (
				x < _bounds.position.x + margin
				or x > _bounds.end.x - margin
				or z < _bounds.position.z + margin
				or z > _bounds.end.z - margin
			):
				continue
		var ground: Dictionary = _ground(x, z)
		if ground.is_empty():
			continue
		if ground.position.y < _water_y + water_margin:
			continue
		if ground.normal.y < min_up:
			continue
		if footprint > 0.0 and not _footprint_supported(ground.position, footprint):
			continue
		return ground
	return {}


## True when the ground around a point stays within reach of the plant's base: no probe is
## missing and none drops more than a fraction of the footprint below the center.
func _footprint_supported(position: Vector3, footprint: float) -> bool:
	var reach: float = footprint * 0.7
	for offset: Vector2 in [
		Vector2(reach, 0.0), Vector2(-reach, 0.0), Vector2(0.0, reach), Vector2(0.0, -reach)
	]:
		var around: Dictionary = _ground(position.x + offset.x, position.z + offset.y)
		if around.is_empty() or position.y - around.position.y > footprint * 0.45:
			return false
	return true


## The built terrain mesh directly below a column (position and face normal), from a raycast
## against the chunk collision. The heightmap alone would float plants: the mesher carves
## below it with 3D noise and snaps the surface to voxel cells. Props already placed are
## excluded so later plants don't land on a rock or a trunk.
func _ground(x: float, z: float) -> Dictionary:
	var top: float = _bounds.end.y - 0.5
	if _bowl_radius > 0.0:
		var horizontal: float = Vector2(x - _bowl_center.x, z - _bowl_center.z).length()
		if horizontal >= _bowl_radius - 1.0:
			return {}
		top = minf(
			top, _bowl_center.y + sqrt(_bowl_radius * _bowl_radius - horizontal * horizontal) - 0.3
		)
	var from := Vector3(x, top, z)
	var to := Vector3(x, _bounds.position.y - 1.0, z)
	var query := PhysicsRayQueryParameters3D.create(from, to, MapInfo.TERRAIN_LAYER, _exclude)
	query.collide_with_areas = false
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	return {"position": hit.position, "normal": hit.normal}


## Basis whose Y is up, spun by yaw and scaled.
func _ground_basis(up: Vector3, yaw: float, scale: Vector3) -> Basis:
	var reference: Vector3 = (
		Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	)
	var x_axis: Vector3 = up.cross(reference).normalized()
	var z_axis: Vector3 = x_axis.cross(up).normalized()
	return Basis(x_axis, up, z_axis).rotated(up, yaw) * Basis.from_scale(scale)


func _random_unit() -> Vector3:
	return Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()).normalized()


func _perpendicular(direction: Vector3) -> Vector3:
	var reference: Vector3 = Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	return direction.cross(reference).normalized()


# --- Patches (one MultiMesh per plant kind) ---------------------------------------------------


func _patch(key: StringName, mesh: Mesh, material: Material, shadows: bool) -> Patch:
	if _patches.has(key):
		return _patches[key]
	var patch := Patch.new()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	patch.multimesh_instance = MultiMeshInstance3D.new()
	patch.multimesh_instance.name = String(key)
	patch.multimesh_instance.multimesh = multimesh
	patch.multimesh_instance.material_override = material
	patch.multimesh_instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if shadows
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	# Instance transforms are written in world space.
	patch.multimesh_instance.top_level = true
	add_child(patch.multimesh_instance)
	patch.multimesh_instance.global_transform = Transform3D.IDENTITY
	_patches[key] = patch
	return patch


func _place(patch: Patch, transform: Transform3D, color: Color, radius: float) -> int:
	patch.transforms.append(transform)
	patch.colors.append(color)
	patch.radii.append(radius)
	return patch.transforms.size() - 1


func _commit_patch(patch: Patch) -> void:
	var multimesh: MultiMesh = patch.multimesh_instance.multimesh
	multimesh.instance_count = patch.transforms.size()
	for index: int in patch.transforms.size():
		multimesh.set_instance_transform(index, patch.transforms[index])
		multimesh.set_instance_color(index, patch.colors[index])


func _make_material(double_sided: bool, albedo: Color = Color.WHITE) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	material.cull_mode = BaseMaterial3D.CULL_DISABLED if double_sided else BaseMaterial3D.CULL_BACK
	return material


func _vary(tint: Color, amount: float) -> Color:
	return tint * _rng.randf_range(1.0 - amount, 1.0 + amount)


# --- Plants -----------------------------------------------------------------------------------


## Moss grows in clumps of cushions of a shared shade, hugging the ground.
func _grow_moss(count: int) -> void:
	var patch: Patch = _patch(&"Moss", _make_moss_mesh(), _make_material(false), false)
	var placed: int = 0
	var clumps_left: int = count
	while placed < count and clumps_left > 0:
		clumps_left -= 1
		var clump: Dictionary = _find_spot(0.35, 0.1)
		if clump.is_empty():
			continue
		var tint: Color = MOSS_TINTS[_rng.randi() % MOSS_TINTS.size()]
		var clump_size: int = mini(_rng.randi_range(4, 9), count - placed)
		for _cushion: int in clump_size:
			var radius: float = _rng.randf_range(0.8, 2.2)
			var scale := Vector3(
				radius * _rng.randf_range(0.85, 1.25),
				radius * _rng.randf_range(0.35, 0.65),
				radius * _rng.randf_range(0.85, 1.25)
			)
			var spot: Dictionary = _find_spot(
				0.35, 0.1, clump.position, 3.5, maxf(scale.x, scale.z)
			)
			if spot.is_empty():
				continue
			var basis: Basis = _ground_basis(spot.normal, _rng.randf() * TAU, scale)
			# Sunk a little so the cushion's rim meets the dirt.
			var origin: Vector3 = spot.position - spot.normal * scale.y * 0.1
			_place(patch, Transform3D(basis, origin), _vary(tint, 0.12), maxf(scale.x, scale.z))
			placed += 1


func _grow_ferns(count: int) -> void:
	var patch: Patch = _patch(&"Ferns", _make_fern_mesh(), _make_material(true), false)
	for _fern: int in count:
		var size: float = _rng.randf_range(1.1, 2.6)
		var spot: Dictionary = _find_spot(0.5, 0.3, Vector3.INF, 0.0, size * 0.5)
		if spot.is_empty():
			continue
		var up: Vector3 = Vector3.UP.slerp(spot.normal, 0.3).normalized()
		var basis: Basis = _ground_basis(up, _rng.randf() * TAU, Vector3.ONE * size)
		var tint: Color = FERN_TINTS[_rng.randi() % FERN_TINTS.size()]
		_place(patch, Transform3D(basis, spot.position), _vary(tint, 0.1), size * 0.8)


func _grow_red_plants(count: int) -> void:
	var patch: Patch = _patch(&"NervePlants", _make_nerve_plant_mesh(), _make_material(true), false)
	for _plant: int in count:
		var size: float = _rng.randf_range(1.0, 1.8)
		var spot: Dictionary = _find_spot(0.5, 0.3, Vector3.INF, 0.0, size * 0.4)
		if spot.is_empty():
			continue
		var up: Vector3 = Vector3.UP.slerp(spot.normal, 0.4).normalized()
		var basis: Basis = _ground_basis(up, _rng.randf() * TAU, Vector3.ONE * size)
		_place(patch, Transform3D(basis, spot.position), _vary(Color.WHITE, 0.1), size * 0.5)


## Mushrooms: clusters of toadstools, buttons and ink caps on damp, level ground. Big ones get
## a stem and a cap to collide with, so bugs can climb a stem and stand on a cap.
func _grow_mushrooms(clusters: int) -> void:
	var kinds: Array = [
		[MushroomMeshBuilder.Species.TOADSTOOL, &"Toadstools", 1.2, 2.8, 0.3],
		[MushroomMeshBuilder.Species.BUTTON, &"ButtonMushrooms", 0.6, 1.6, 0.4],
		[MushroomMeshBuilder.Species.INKCAP, &"InkCaps", 0.8, 1.8, 0.3],
	]
	var builds: Dictionary = {}
	for cluster: int in clusters:
		var pick: float = _rng.randf()
		var kind: Array = (
			kinds[0]
			if pick < kinds[0][4]
			else (kinds[1] if pick < kinds[0][4] + kinds[1][4] else kinds[2])
		)
		var variant: int = _rng.randi() % 3
		var key: StringName = StringName("%s%d" % [kind[1], variant])
		if not builds.has(key):
			builds[key] = MushroomMeshBuilder.build(hash(key) + _rng.seed, kind[0])
		var built: Dictionary = builds[key]
		var patch: Patch = _patch(key, built["mesh"], _make_material(false), true)
		var center: Dictionary = _find_spot(0.55, 0.25)
		if center.is_empty():
			continue
		var count: int = _rng.randi_range(1, 5)
		for index: int in count:
			var size: float = _rng.randf_range(kind[2], kind[3])
			var spot: Dictionary = (
				center if index == 0 else _find_spot(0.55, 0.25, center.position, 1.2 + size, 0.0)
			)
			if spot.is_empty():
				continue
			var up: Vector3 = Vector3.UP.slerp(spot.normal, 0.25).normalized()
			var basis: Basis = _ground_basis(
				up, _rng.randf() * TAU, Vector3(size, size * _rng.randf_range(0.9, 1.15), size)
			)
			var cap_radius: float = float(built["cap_radius"]) * size
			var transform := Transform3D(basis, spot.position - up * 0.04)
			_place(patch, transform, _vary(Color.WHITE, 0.08), cap_radius)
			if cap_radius >= 0.75:
				_add_mushroom_collision(transform, built, basis.get_scale())


## A cylinder for the stem and a flat one for the cap, sized in world units under an unscaled
## node. (Shapes under the mushroom's scaled transform were scaled a second time, which gave
## every big mushroom an invisible stem and cap far wider than the one on screen: bugs walked
## into walls they could not see and got wedged under them.)
func _add_mushroom_collision(transform: Transform3D, built: Dictionary, scale: Vector3) -> void:
	var width: float = maxf(scale.x, scale.z)
	var height: float = scale.y
	var stem := CylinderShape3D.new()
	stem.radius = maxf(float(built["stem_radius"]) * width, 0.15)
	stem.height = float(built["cap_y"]) * height
	var unscaled := Transform3D(Basis(transform.basis.get_rotation_quaternion()), transform.origin)
	var prop: Prop = _add_prop(
		"Mushroom",
		unscaled,
		stem,
		Transform3D(Basis.IDENTITY, Vector3(0.0, stem.height * 0.5, 0.0))
	)
	var cap := CylinderShape3D.new()
	cap.radius = float(built["cap_radius"]) * width * 0.9
	cap.height = maxf(float(built["cap_height"]) * height * 0.6, 0.2)
	var cap_shape := CollisionShape3D.new()
	cap_shape.shape = cap
	cap_shape.position = Vector3(
		0.0, (float(built["cap_y"]) + float(built["cap_height"]) * 0.3) * height, 0.0
	)
	prop.node.get_child(0).add_child(cap_shape)
	prop.radius = float(built["cap_radius"]) * width


## Slate rocks: noisy icospheres, flattened and half-buried, with convex collision.
func _grow_rocks(count: int) -> void:
	var rock: Dictionary = AsteroidMeshBuilder.build(_rng.randi(), 1.0, 2, 0.3)
	var rock_mesh: ArrayMesh = rock["mesh"] as ArrayMesh
	var rock_points: PackedVector3Array = (rock["shape"] as ConvexPolygonShape3D).points
	var patch: Patch = _patch(&"Rocks", rock_mesh, _make_material(false, ROCK_COLOR), true)
	for _rock: int in count:
		var radius: float = _rng.randf_range(1.2, 3.2)
		var scale := Vector3(
			radius * _rng.randf_range(0.8, 1.4),
			radius * _rng.randf_range(0.55, 1.1),
			radius * _rng.randf_range(0.8, 1.4)
		)
		var spot: Dictionary = _find_spot(0.0, -0.5, Vector3.INF, 0.0, maxf(scale.x, scale.z) * 0.8)
		if spot.is_empty():
			continue
		var tilt: Vector3 = Vector3.UP.slerp(_random_unit(), 0.25).normalized()
		var unscaled: Basis = _ground_basis(tilt, _rng.randf() * TAU, Vector3.ONE)
		var origin: Vector3 = spot.position - Vector3.UP * scale.y * 0.35
		var transform := Transform3D(unscaled * Basis.from_scale(scale), origin)
		_place(patch, transform, _vary(Color.WHITE, 0.15), maxf(scale.x, scale.z))

		var scaled_points := PackedVector3Array()
		for point: Vector3 in rock_points:
			scaled_points.append(point * scale)
		var shape := ConvexPolygonShape3D.new()
		shape.points = scaled_points
		var prop: Prop = _add_prop(
			"Rock", Transform3D(unscaled, origin), shape, Transform3D.IDENTITY
		)
		prop.radius = maxf(scale.x, scale.z)


## Driftwood: a short, mostly horizontal branch system lying half in the dirt.
func _grow_logs(count: int) -> void:
	var bark: StandardMaterial3D = _make_material(false, DRIFTWOOD_COLOR)
	for _log: int in count:
		var spot: Dictionary = _find_spot(0.6, 0.3, Vector3.INF, 0.0, 3.0)
		if spot.is_empty():
			continue
		var yaw: float = _rng.randf() * TAU
		var pitch: float = deg_to_rad(_rng.randf_range(-4.0, 14.0))
		var direction := Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch))
		var radius: float = _rng.randf_range(0.45, 0.75)
		var segments: Array[Segment] = []
		var tips := PackedVector3Array()
		_grow_branches(
			Vector3.ZERO,
			direction,
			_rng.randf_range(4.0, 6.5),
			radius,
			2,
			segments,
			tips,
			32.0,
			0.2,
			0.05
		)
		var trunk: Segment = segments[0]
		var shape := CapsuleShape3D.new()
		shape.radius = trunk.radius_start * 0.9
		shape.height = trunk.start.distance_to(trunk.end) + shape.radius * 2.0
		var origin: Vector3 = spot.position - Vector3.UP * radius * 0.35
		var prop: Prop = _add_prop(
			"Driftwood", Transform3D(Basis.IDENTITY, origin), shape, _segment_shape_transform(trunk)
		)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = _make_branch_mesh(segments, 7)
		mesh_instance.material_override = bark
		prop.node.add_child(mesh_instance)
		prop.radius = radius * 1.5


## Small trees: a stochastic branching system with leaf clusters at every tip.
func _grow_trees(count: int) -> void:
	var bark: StandardMaterial3D = _make_material(false, BARK_COLOR)
	var canopy: Patch = _patch(&"Canopy", _make_canopy_mesh(), _make_material(false), true)
	for _tree: int in count:
		var spot: Dictionary = _find_spot(0.75, 0.6, Vector3.INF, 0.0, 1.5)
		if spot.is_empty():
			continue
		var trunk_radius: float = _rng.randf_range(0.3, 0.5)
		var lean: Vector3 = (Vector3.UP + _random_unit() * 0.12).normalized()
		var segments: Array[Segment] = []
		var tips := PackedVector3Array()
		_grow_branches(
			Vector3.DOWN * 0.4,
			lean,
			_rng.randf_range(3.0, 5.0),
			trunk_radius,
			3,
			segments,
			tips,
			40.0,
			0.22,
			0.3
		)
		var trunk: Segment = segments[0]
		var shape := CylinderShape3D.new()
		shape.radius = trunk.radius_start
		shape.height = trunk.start.distance_to(trunk.end)
		var prop: Prop = _add_prop(
			"Tree",
			Transform3D(Basis.IDENTITY, spot.position),
			shape,
			_segment_shape_transform(trunk)
		)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = _make_branch_mesh(segments, 6)
		mesh_instance.material_override = bark
		prop.node.add_child(mesh_instance)
		prop.radius = trunk_radius * 2.5
		var tint: Color = LEAF_TINTS[_rng.randi() % LEAF_TINTS.size()]
		for tip: Vector3 in tips:
			var size: float = _rng.randf_range(1.1, 2.0)
			var basis: Basis = _ground_basis(
				Vector3.UP,
				_rng.randf() * TAU,
				Vector3(size, size * _rng.randf_range(0.65, 0.85), size)
			)
			var index: int = _place(
				canopy, Transform3D(basis, spot.position + tip), _vary(tint, 0.14), size
			)
			prop.canopy_indices.append(index)


## Recursive branching: each branch ends in 2-3 children that are shorter, thinner and splayed
## out by up to spread_degrees, nudged upward by upward_bias and wobbled by bend.
func _grow_branches(
	origin: Vector3,
	direction: Vector3,
	length: float,
	radius: float,
	depth: int,
	segments: Array[Segment],
	tips: PackedVector3Array,
	spread_degrees: float,
	bend: float,
	upward_bias: float
) -> void:
	var grow_direction: Vector3 = (direction + _random_unit() * bend).normalized()
	var segment := Segment.new()
	segment.start = origin
	segment.end = origin + grow_direction * length
	segment.radius_start = radius
	segment.radius_end = radius * (0.62 if depth > 0 else 0.2)
	segments.append(segment)
	if depth <= 0:
		tips.append(segment.end)
		return
	var child_count: int = _rng.randi_range(2, 3)
	var base_roll: float = _rng.randf() * TAU
	for child: int in child_count:
		var roll: float = base_roll + TAU * child / child_count + _rng.randf_range(-0.4, 0.4)
		var pitch: float = deg_to_rad(spread_degrees * _rng.randf_range(0.5, 1.0))
		var axis: Vector3 = _perpendicular(grow_direction).rotated(grow_direction, roll)
		var child_direction: Vector3 = grow_direction.rotated(axis, pitch)
		child_direction = (child_direction + Vector3.UP * upward_bias).normalized()
		_grow_branches(
			segment.end,
			child_direction,
			length * _rng.randf_range(0.6, 0.78),
			segment.radius_end,
			depth - 1,
			segments,
			tips,
			spread_degrees,
			bend,
			upward_bias
		)


## A prop node with a static collider on the terrain layer, so ground probes and bugs treat it
## like terrain.
func _add_prop(
	prop_name: String, transform: Transform3D, shape: Shape3D, shape_transform: Transform3D
) -> Prop:
	var prop := Prop.new()
	prop.node = Node3D.new()
	prop.node.name = prop_name
	add_child(prop.node)
	prop.node.global_transform = transform
	prop.position = transform.origin
	var body := StaticBody3D.new()
	body.collision_layer = MapInfo.TERRAIN_LAYER
	body.collision_mask = 0
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = shape
	collision_shape.transform = shape_transform
	body.add_child(collision_shape)
	prop.node.add_child(body)
	_exclude.append(body.get_rid())
	_props.append(prop)
	return prop


## Places a capsule/cylinder (Y axis) along a segment.
func _segment_shape_transform(segment: Segment) -> Transform3D:
	var axis: Vector3 = (segment.end - segment.start).normalized()
	var basis: Basis = _ground_basis(axis, 0.0, Vector3.ONE)
	return Transform3D(basis, (segment.start + segment.end) * 0.5)


# --- Carving ----------------------------------------------------------------------------------


## Clears plants and props inside a terrain brush, so nothing floats over a fresh hole.
func _on_brush_applied(world_position: Vector3, radius: float) -> void:
	for patch: Patch in _patches.values():
		for index: int in patch.transforms.size():
			if patch.radii[index] < 0.0:
				continue
			if (
				patch.transforms[index].origin.distance_to(world_position)
				< radius + patch.radii[index] * 0.5
			):
				_clear_instance(patch, index)
	for prop: Prop in _props:
		if prop.node == null or not is_instance_valid(prop.node):
			continue
		if prop.position.distance_to(world_position) < radius + prop.radius:
			prop.node.queue_free()
			prop.node = null
			var canopy: Patch = _patches.get(&"Canopy")
			if canopy != null:
				for index: int in prop.canopy_indices:
					_clear_instance(canopy, index)


func _clear_instance(patch: Patch, index: int) -> void:
	patch.radii[index] = -1.0
	patch.multimesh_instance.multimesh.set_instance_transform(
		index, Transform3D(Basis.from_scale(Vector3.ZERO), patch.transforms[index].origin)
	)


# --- Meshes -----------------------------------------------------------------------------------


## Adds a triangle, winding it so its front faces along `outward` (Godot front faces are
## clockwise seen from outside, so the right-hand normal points inward).
func _triangle(
	st: SurfaceTool,
	points: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray
) -> void:
	var outward: Vector3 = normals[0] + normals[1] + normals[2]
	var order: PackedInt32Array = PackedInt32Array([0, 1, 2])
	if (points[1] - points[0]).cross(points[2] - points[0]).dot(outward) > 0.0:
		order = PackedInt32Array([0, 2, 1])
	for index: int in order:
		st.set_color(colors[index])
		st.set_normal(normals[index])
		st.add_vertex(points[index])


func _quad(
	st: SurfaceTool,
	points: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray
) -> void:
	_triangle(
		st,
		PackedVector3Array([points[0], points[1], points[2]]),
		PackedVector3Array([normals[0], normals[1], normals[2]]),
		PackedColorArray([colors[0], colors[1], colors[2]])
	)
	_triangle(
		st,
		PackedVector3Array([points[0], points[2], points[3]]),
		PackedVector3Array([normals[0], normals[2], normals[3]]),
		PackedColorArray([colors[0], colors[2], colors[3]])
	)


## Unit moss cushion: a bumpy dome, bright on top and shaded at the rim (vertex colors act as a
## brightness mask under the per-instance tint).
func _make_moss_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 1.6
	var rings: int = 7
	var segments: int = 14
	var ring_points: Array[PackedVector3Array] = []
	for ring: int in rings + 1:
		# From just below the apex to a little under the ground, so the rim sits in the dirt.
		var phi: float = deg_to_rad(lerpf(14.0, 104.0, float(ring) / rings))
		var points := PackedVector3Array()
		for segment: int in segments:
			var theta: float = TAU * segment / segments
			var direction := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			points.append(direction * (1.0 + noise.get_noise_3dv(direction * 2.0) * 0.22))
		ring_points.append(points)
	var apex := Vector3(0.0, 1.0 + noise.get_noise_3d(0.0, 2.0, 0.0) * 0.15, 0.0)
	for segment: int in segments:
		var a: Vector3 = ring_points[0][segment]
		var b: Vector3 = ring_points[0][(segment + 1) % segments]
		_triangle(
			st,
			PackedVector3Array([apex, a, b]),
			PackedVector3Array([Vector3.UP, a.normalized(), b.normalized()]),
			PackedColorArray([_moss_shade(apex), _moss_shade(a), _moss_shade(b)])
		)
	for ring: int in rings:
		for segment: int in segments:
			var next: int = (segment + 1) % segments
			var points := PackedVector3Array(
				[
					ring_points[ring][segment],
					ring_points[ring][next],
					ring_points[ring + 1][next],
					ring_points[ring + 1][segment],
				]
			)
			var normals := PackedVector3Array()
			var colors := PackedColorArray()
			for point: Vector3 in points:
				normals.append(point.normalized())
				colors.append(_moss_shade(point))
			_quad(st, points, normals, colors)
	# Closed underneath, so a cushion hanging over a ledge shows a dark underside instead of
	# the inside of the dome.
	var rim: PackedVector3Array = ring_points[rings]
	var rim_center := Vector3.ZERO
	for point: Vector3 in rim:
		rim_center += point
	rim_center /= rim.size()
	var underside: Color = _moss_shade(Vector3.ZERO) * 0.6
	underside.a = 1.0
	for segment: int in segments:
		_triangle(
			st,
			PackedVector3Array([rim_center, rim[(segment + 1) % segments], rim[segment]]),
			PackedVector3Array([Vector3.DOWN, Vector3.DOWN, Vector3.DOWN]),
			PackedColorArray([underside, underside, underside])
		)
	return st.commit()


func _moss_shade(point: Vector3) -> Color:
	var height: float = clampf(point.y, 0.0, 1.0)
	return Color(0.5, 0.55, 0.42).lerp(Color.WHITE, height * height)


## Unit fern: seven fronds that arch outward and droop, each a rachis with paired leaflets.
func _make_fern_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var frond_count: int = 7
	for frond: int in frond_count:
		var yaw: float = TAU * frond / frond_count + rng.randf_range(-0.25, 0.25)
		var tilt: float = deg_to_rad(rng.randf_range(32.0, 62.0))
		var length: float = rng.randf_range(0.8, 1.1)
		var direction := Vector3(cos(yaw) * cos(tilt), sin(tilt), sin(yaw) * cos(tilt))
		var side := Vector3(-sin(yaw), 0.0, cos(yaw))
		var stations: int = 9
		var previous: Vector3 = Vector3.ZERO
		for station: int in stations + 1:
			var t: float = float(station) / stations
			var point: Vector3 = direction * t * length + Vector3.DOWN * 0.55 * t * t * length
			var shade: Color = Color(0.55, 0.6, 0.45).lerp(Color.WHITE, t)
			if station > 0:
				var tangent: Vector3 = (point - previous).normalized()
				var normal: Vector3 = side.cross(tangent).normalized()
				if normal.y < 0.0:
					normal = -normal
				var half_width: Vector3 = side * 0.02
				_quad(
					st,
					PackedVector3Array(
						[
							previous - half_width,
							previous + half_width,
							point + half_width,
							point - half_width
						]
					),
					PackedVector3Array([normal, normal, normal, normal]),
					PackedColorArray([shade, shade, shade, shade])
				)
				if station < stations:
					var leaflet: float = (
						length * 0.42 * sin(PI * (0.12 + 0.88 * t)) * (1.0 - 0.3 * t)
					)
					for sign: float in [-1.0, 1.0]:
						var outward: Vector3 = side * sign
						var tip: Vector3 = (
							point
							+ outward * leaflet
							+ Vector3.UP * leaflet * 0.12
							+ tangent * leaflet * 0.3
						)
						var mid_front: Vector3 = (
							point + outward * leaflet * 0.45 + tangent * leaflet * 0.3
						)
						var mid_back: Vector3 = (
							point + outward * leaflet * 0.45 - tangent * leaflet * 0.08
						)
						var tip_shade: Color = shade.lerp(Color.WHITE, 0.4)
						_triangle(
							st,
							PackedVector3Array([point, mid_front, tip]),
							PackedVector3Array([normal, normal, normal]),
							PackedColorArray([shade, shade, tip_shade])
						)
						_triangle(
							st,
							PackedVector3Array([point, tip, mid_back]),
							PackedVector3Array([normal, normal, normal]),
							PackedColorArray([shade, tip_shade, shade])
						)
			previous = point
	return st.commit()


## Unit nerve plant (Fittonia): a low rosette of broad leaves, red along the midrib fading to
## green at the edges.
func _make_nerve_plant_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	var red := Color(0.78, 0.12, 0.2)
	var green := Color(0.26, 0.5, 0.2)
	var leaf_count: int = 9
	for leaf: int in leaf_count:
		var yaw: float = TAU * leaf / leaf_count + rng.randf_range(-0.2, 0.2)
		var tilt: float = deg_to_rad(rng.randf_range(12.0, 42.0))
		var length: float = rng.randf_range(0.34, 0.5)
		var width: float = length * 0.6
		var direction := Vector3(cos(yaw) * cos(tilt), sin(tilt), sin(yaw) * cos(tilt))
		var side := Vector3(-sin(yaw), 0.0, cos(yaw))
		var normal: Vector3 = side.cross(direction).normalized()
		if normal.y < 0.0:
			normal = -normal
		var steps: int = 3
		for step: int in steps:
			var t0: float = float(step) / steps
			var t1: float = float(step + 1) / steps
			var c0: Vector3 = direction * t0 * length + Vector3.DOWN * 0.3 * t0 * t0 * length
			var c1: Vector3 = direction * t1 * length + Vector3.DOWN * 0.3 * t1 * t1 * length
			var w0: float = sin(PI * t0) * width * 0.5
			var w1: float = sin(PI * t1) * width * 0.5
			for sign: float in [-1.0, 1.0]:
				var outward: Vector3 = side * sign
				_quad(
					st,
					PackedVector3Array([c0, c0 + outward * w0, c1 + outward * w1, c1]),
					PackedVector3Array([normal, normal, normal, normal]),
					PackedColorArray([red, green, green, red])
				)
	return st.commit()


## Leaf cluster: a lumpy sphere, a little brighter on top.
func _make_canopy_mesh() -> ArrayMesh:
	var blob: ArrayMesh = AsteroidMeshBuilder.build(5, 1.0, 1, 0.28)["mesh"] as ArrayMesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var arrays: Array = blob.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index: int in vertices.size():
		st.set_color(
			Color(0.62, 0.66, 0.5).lerp(
				Color.WHITE, clampf(vertices[index].y * 0.5 + 0.5, 0.0, 1.0)
			)
		)
		st.set_normal(normals[index])
		st.add_vertex(vertices[index])
	return st.commit()


## Tapered tubes for every branch segment, with a little per-branch bark variation.
func _make_branch_mesh(segments: Array[Segment], sides: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment: Segment in segments:
		var axis: Vector3 = (segment.end - segment.start).normalized()
		var u: Vector3 = _perpendicular(axis)
		var v: Vector3 = axis.cross(u).normalized()
		var shade: Color = Color.WHITE * _rng.randf_range(0.8, 1.05)
		shade.a = 1.0
		for side: int in sides:
			var angle0: float = TAU * side / sides
			var angle1: float = TAU * (side + 1) / sides
			var d0: Vector3 = u * cos(angle0) + v * sin(angle0)
			var d1: Vector3 = u * cos(angle1) + v * sin(angle1)
			_quad(
				st,
				PackedVector3Array(
					[
						segment.start + d0 * segment.radius_start,
						segment.start + d1 * segment.radius_start,
						segment.end + d1 * segment.radius_end,
						segment.end + d0 * segment.radius_end,
					]
				),
				PackedVector3Array([d0, d1, d1, d0]),
				PackedColorArray([shade, shade, shade, shade])
			)
			# Capped ends, so a log or branch poking over a drop isn't a hollow tube.
			_triangle(
				st,
				PackedVector3Array(
					[
						segment.start,
						segment.start + d1 * segment.radius_start,
						segment.start + d0 * segment.radius_start
					]
				),
				PackedVector3Array([-axis, -axis, -axis]),
				PackedColorArray([shade, shade, shade])
			)
			_triangle(
				st,
				PackedVector3Array(
					[
						segment.end,
						segment.end + d0 * segment.radius_end,
						segment.end + d1 * segment.radius_end
					]
				),
				PackedVector3Array([axis, axis, axis]),
				PackedColorArray([shade, shade, shade])
			)
	return st.commit()


## All instances of one plant kind: a MultiMesh plus the data needed to clear them later.
class Patch:
	var multimesh_instance: MultiMeshInstance3D
	var transforms: Array[Transform3D] = []
	var colors: PackedColorArray = PackedColorArray()
	## Footprint radius per instance; negative once the instance has been cleared.
	var radii: PackedFloat32Array = PackedFloat32Array()


## One tapered branch of a tree or log.
class Segment:
	var start: Vector3
	var end: Vector3
	var radius_start: float
	var radius_end: float


## A tree, log or rock: a node with its own mesh and collision, plus (trees) its leaf clusters.
class Prop:
	var node: Node3D
	var position: Vector3
	var radius: float
	var canopy_indices: PackedInt32Array = PackedInt32Array()
