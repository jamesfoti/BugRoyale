class_name PlantMeshes
extends RefCounted
## The plants' built-in meshes (PlantFeature.Shape), built in code: 1 m tall (scaled so the top of
## the drooping blades or the crown is at 1 m, so a feature's height is the plant's) with the foot
## at the origin and the colours in the vertices, the feature's colour for leaves, petals and stone
## and the shape's own for trunks, stems and seed heads. Solid parts face outward (each triangle is
## wound by the way it should face, so lighting is right with culling off). The colours are stored
## linear: the toon shader multiplies vertex colours in as they are, so colours picked in sRGB
## would come out washed pale.

const STEM := Color(0.34, 0.5, 0.2)
const BARK := Color(0.38, 0.28, 0.19)
const CATTAIL := Color(0.36, 0.22, 0.11)
const FLOWER_EYE := Color(0.96, 0.8, 0.22)


## The mesh of a shape in a colour; the same seed builds the same mesh.
static func build(shape: PlantFeature.Shape, color: Color, mesh_seed: int = 7) -> ArrayMesh:
	var roll := RandomNumberGenerator.new()
	roll.seed = mesh_seed
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	match shape:
		PlantFeature.Shape.GRASS:
			_tuft(surface, roll, 7, 0.07, Vector2(0.15, 0.45), 0.15, color)
		PlantFeature.Shape.TALL_GRASS:
			_tuft(
				surface, roll, 12, 0.04, Vector2(0.2, 0.6), 0.3, color, color.lerp(Color.WHITE, 0.3)
			)
		PlantFeature.Shape.FLOWERS:
			_flowers(surface, roll, color)
		PlantFeature.Shape.FERN:
			_fern(surface, roll, color)
		PlantFeature.Shape.SHRUB:
			_shrub(surface, roll, color)
		PlantFeature.Shape.BOULDER:
			_boulder(surface, roll, color)
		PlantFeature.Shape.REEDS:
			_reeds(surface, roll, color)
		PlantFeature.Shape.CACTUS:
			_cactus(surface, roll, color)
		PlantFeature.Shape.TREE:
			_tree(surface, roll, color)
		PlantFeature.Shape.MUSHROOM:
			_mushroom(surface, roll)
	var arrays: Array = surface.commit_to_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var top: float = 0.0
	for vertex: Vector3 in vertices:
		top = maxf(top, vertex.y)
	if top > 0.01:
		for index: int in vertices.size():
			vertices[index] /= top
		arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- Shapes -----------------------------------------------------------------------------------


static func _tuft(
	surface: SurfaceTool,
	roll: RandomNumberGenerator,
	count: int,
	width: float,
	lean: Vector2,
	bend: float,
	color: Color,
	tip: Color = Color(0, 0, 0, 0)
) -> void:
	var tip_color: Color = tip if tip.a > 0.0 else color.lightened(0.2)
	for index: int in count:
		var yaw: float = TAU * float(index) / float(count) + roll.randf_range(-0.4, 0.4)
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		var direction: Vector3 = (out * roll.randf_range(lean.x, lean.y) + Vector3.UP).normalized()
		var foot: Vector3 = out * roll.randf_range(0.0, 0.08)
		_blade(
			surface,
			foot,
			direction,
			roll.randf_range(0.75, 1.0),
			width,
			color.darkened(0.35),
			tip_color,
			bend
		)


static func _flowers(surface: SurfaceTool, roll: RandomNumberGenerator, color: Color) -> void:
	for index: int in 3:
		var yaw: float = TAU * float(index) / 3.0 + roll.randf_range(-0.5, 0.5)
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		_blade(
			surface,
			Vector3.ZERO,
			(out * 0.5 + Vector3.UP).normalized(),
			0.35,
			0.06,
			STEM,
			STEM,
			0.3
		)
	for index: int in 4:
		var yaw: float = TAU * float(index) / 4.0 + roll.randf_range(-0.4, 0.4)
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		var direction: Vector3 = (out * roll.randf_range(0.05, 0.25) + Vector3.UP).normalized()
		var foot: Vector3 = out * roll.randf_range(0.02, 0.1)
		var length: float = roll.randf_range(0.75, 0.95)
		_blade(surface, foot, direction, length, 0.025, STEM.darkened(0.2), STEM, 0.05)
		var head: Vector3 = foot + direction * length
		var petal_turn: float = roll.randf() * TAU
		for petal: int in 5:
			var first: float = petal_turn + TAU * float(petal) / 5.0
			var second: float = first + TAU / 5.0 * 0.8
			var lift := Vector3(0.0, 0.02, 0.0)
			_face(
				surface,
				[
					head,
					head + Vector3(cos(first), 0.0, sin(first)) * 0.1 + lift,
					head + Vector3(cos(second), 0.0, sin(second)) * 0.1 + lift
				],
				[color, color.lightened(0.15), color.lightened(0.15)],
				Vector3.UP
			)
		_face(
			surface,
			[
				head + Vector3(0.025, 0.025, 0.0),
				head + Vector3(-0.02, 0.025, 0.02),
				head + Vector3(-0.02, 0.025, -0.02)
			],
			[FLOWER_EYE, FLOWER_EYE, FLOWER_EYE],
			Vector3.UP
		)


static func _fern(surface: SurfaceTool, roll: RandomNumberGenerator, color: Color) -> void:
	var fronds: int = 7
	for index: int in fronds:
		var yaw: float = TAU * float(index) / float(fronds) + roll.randf_range(-0.25, 0.25)
		var tilt: float = deg_to_rad(roll.randf_range(40.0, 65.0))
		var direction := Vector3(cos(yaw) * cos(tilt), sin(tilt), sin(yaw) * cos(tilt))
		_blade(
			surface,
			Vector3.ZERO,
			direction,
			roll.randf_range(1.0, 1.25),
			0.22,
			color.darkened(0.3),
			color.lightened(0.15),
			0.55,
			6
		)


static func _shrub(surface: SurfaceTool, roll: RandomNumberGenerator, color: Color) -> void:
	_cylinder(surface, Vector3.ZERO, Vector3(0.0, 0.3, 0.0), 0.06, 0.04, 6, BARK, false)
	var blobs: int = roll.randi_range(4, 6)
	for index: int in blobs:
		var radius: float = roll.randf_range(0.22, 0.34)
		var turn: float = roll.randf() * TAU
		var out: float = roll.randf_range(0.0, 0.22)
		var middle := Vector3(cos(turn) * out, roll.randf_range(0.38, 0.66), sin(turn) * out)
		var blob: ArrayMesh = RockMeshBuilder.build(roll.randi(), 1.0, 1, 0.3)["mesh"]
		_append_mesh(
			surface,
			blob,
			Transform3D(Basis.from_scale(Vector3.ONE * radius), middle),
			color,
			middle.y - radius,
			middle.y + radius
		)


static func _boulder(surface: SurfaceTool, roll: RandomNumberGenerator, color: Color) -> void:
	var rock: ArrayMesh = RockMeshBuilder.build(roll.randi(), 1.0, 2, 0.35)["mesh"]
	var size := Vector3(0.62, 0.55, 0.55)
	_append_mesh(
		surface,
		rock,
		Transform3D(Basis.from_scale(size), Vector3(0.0, 0.42, 0.0)),
		color,
		-0.1,
		0.95
	)


static func _reeds(surface: SurfaceTool, roll: RandomNumberGenerator, color: Color) -> void:
	for index: int in 10:
		var yaw: float = roll.randf() * TAU
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		var foot: Vector3 = out * roll.randf_range(0.0, 0.18)
		var leaf: bool = index % 3 == 2
		var direction: Vector3 = (
			(
				(out * roll.randf_range(0.25, 0.5) if leaf else out * roll.randf_range(0.0, 0.08))
				+ Vector3.UP
			)
			. normalized()
		)
		var length: float = roll.randf_range(0.6, 0.8) if leaf else roll.randf_range(0.85, 1.0)
		_blade(
			surface,
			foot,
			direction,
			length,
			0.05 if leaf else 0.03,
			color.darkened(0.3),
			color.lightened(0.1),
			0.3 if leaf else 0.02
		)
		if not leaf and index % 2 == 0:
			var top: Vector3 = foot + direction * length * 0.86
			_cylinder(surface, top - direction * 0.14, top, 0.028, 0.028, 6, CATTAIL, true)


static func _cactus(surface: SurfaceTool, roll: RandomNumberGenerator, color: Color) -> void:
	var dark: Color = color.darkened(0.15)
	_cylinder(surface, Vector3.ZERO, Vector3(0.0, 0.9, 0.0), 0.13, 0.11, 10, dark, false)
	_dome(surface, Vector3(0.0, 0.9, 0.0), 0.11, 0.1, 10, color)
	var arms: int = roll.randi_range(1, 2)
	var first_turn: float = roll.randf() * TAU
	for index: int in arms:
		var turn: float = first_turn + PI * float(index)
		var out := Vector3(cos(turn), 0.0, sin(turn))
		var elbow_height: float = roll.randf_range(0.35, 0.55)
		var root := Vector3(0.0, elbow_height, 0.0)
		var elbow: Vector3 = root + out * roll.randf_range(0.24, 0.3)
		var top: Vector3 = elbow + Vector3(0.0, roll.randf_range(0.2, 0.32), 0.0)
		_cylinder(surface, root, elbow, 0.075, 0.07, 8, dark, false)
		_cylinder(surface, elbow - Vector3(0.0, 0.05, 0.0), top, 0.07, 0.065, 8, dark, false)
		_dome(surface, top, 0.065, 0.06, 8, color)


static func _tree(surface: SurfaceTool, roll: RandomNumberGenerator, color: Color) -> void:
	_cylinder(surface, Vector3.ZERO, Vector3(0.0, 0.62, 0.0), 0.055, 0.03, 8, BARK, false)
	for index: int in 2:
		var turn: float = roll.randf() * TAU
		var start := Vector3(0.0, roll.randf_range(0.4, 0.55), 0.0)
		var end: Vector3 = start + Vector3(cos(turn) * 0.16, 0.14, sin(turn) * 0.16)
		_cylinder(surface, start, end, 0.022, 0.012, 6, BARK, false)
	var blobs: int = roll.randi_range(4, 6)
	for index: int in blobs:
		var radius: float = roll.randf_range(0.16, 0.24)
		var turn: float = roll.randf() * TAU
		var out: float = roll.randf_range(0.0, 0.17) if index > 0 else 0.0
		var middle := Vector3(cos(turn) * out, roll.randf_range(0.66, 0.8), sin(turn) * out)
		var blob: ArrayMesh = RockMeshBuilder.build(roll.randi(), 1.0, 1, 0.28)["mesh"]
		_append_mesh(
			surface,
			blob,
			Transform3D(Basis.from_scale(Vector3.ONE * radius), middle),
			color,
			0.5,
			1.0
		)


static func _mushroom(surface: SurfaceTool, roll: RandomNumberGenerator) -> void:
	var built: Dictionary = MushroomMeshBuilder.build(
		roll.randi(), MushroomMeshBuilder.Species.TOADSTOOL
	)
	var tall: float = maxf(float(built.get("height", 1.0)), 0.01)
	_append_mesh(
		surface,
		built["mesh"] as ArrayMesh,
		Transform3D(Basis.from_scale(Vector3.ONE / tall), Vector3.ZERO),
		Color(0, 0, 0, 0),
		0.0,
		1.0
	)


# --- Pieces -----------------------------------------------------------------------------------


## A strip from `foot` along `direction`, narrowing to its tip and drooping by `bend` toward
## its end, darker at the foot.
static func _blade(
	surface: SurfaceTool,
	foot: Vector3,
	direction: Vector3,
	length: float,
	width: float,
	foot_color: Color,
	tip_color: Color,
	bend: float,
	stations: int = 4
) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	var side: Vector3 = (
		Vector3.UP.cross(flat).normalized() if flat.length() > 0.01 else Vector3.RIGHT
	)
	var points: Array[Vector3] = []
	for station: int in stations + 1:
		var share: float = float(station) / float(stations)
		var droop: float = bend * share * share * length
		points.append(
			(
				foot
				+ direction * length * share
				+ flat.normalized() * droop * 0.5
				+ Vector3.DOWN * droop
			)
		)
	for station: int in stations:
		var near_share: float = float(station) / float(stations)
		var far_share: float = float(station + 1) / float(stations)
		var near: Vector3 = points[station]
		var far: Vector3 = points[station + 1]
		var near_half: float = width * 0.5 * (1.0 - near_share * 0.85)
		var far_half: float = width * 0.5 * (1.0 - far_share * 0.85)
		var along: Vector3 = (far - near).normalized()
		var facing: Vector3 = side.cross(along).normalized()
		if facing.y < 0.0:
			facing = -facing
		var near_color: Color = foot_color.lerp(tip_color, near_share)
		var far_color: Color = foot_color.lerp(tip_color, far_share)
		if station == stations - 1:
			_face(
				surface,
				[near - side * near_half, near + side * near_half, far],
				[near_color, near_color, far_color],
				facing
			)
			continue
		_face(
			surface,
			[near - side * near_half, near + side * near_half, far + side * far_half],
			[near_color, near_color, far_color],
			facing
		)
		_face(
			surface,
			[near - side * near_half, far + side * far_half, far - side * far_half],
			[near_color, far_color, far_color],
			facing
		)


## A tapered tube from `from` to `to`, with a flat cap at the top when asked.
static func _cylinder(
	surface: SurfaceTool,
	from: Vector3,
	to: Vector3,
	from_radius: float,
	to_radius: float,
	sides: int,
	color: Color,
	capped: bool
) -> void:
	var axis: Vector3 = (to - from).normalized()
	var across: Vector3 = axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT)
	across = across.normalized()
	var other: Vector3 = axis.cross(across).normalized()
	var low_color: Color = color.darkened(0.15)
	for index: int in sides:
		var first: float = TAU * float(index) / float(sides)
		var second: float = TAU * float(index + 1) / float(sides)
		var first_out: Vector3 = across * cos(first) + other * sin(first)
		var second_out: Vector3 = across * cos(second) + other * sin(second)
		var outward: Vector3 = (first_out + second_out).normalized()
		var bottom_first: Vector3 = from + first_out * from_radius
		var bottom_second: Vector3 = from + second_out * from_radius
		var top_first: Vector3 = to + first_out * to_radius
		var top_second: Vector3 = to + second_out * to_radius
		_face(
			surface,
			[bottom_first, bottom_second, top_second],
			[low_color, low_color, color],
			outward,
			[first_out, second_out, second_out]
		)
		_face(
			surface,
			[bottom_first, top_second, top_first],
			[low_color, color, color],
			outward,
			[first_out, second_out, first_out]
		)
		if capped:
			_face(surface, [to, top_first, top_second], [color, color, color], axis)


## A rounded top: a ring of `sides` rising to a point `rise` above `base`.
static func _dome(
	surface: SurfaceTool, base: Vector3, radius: float, rise: float, sides: int, color: Color
) -> void:
	var tip: Vector3 = base + Vector3.UP * rise
	for index: int in sides:
		var first: float = TAU * float(index) / float(sides)
		var second: float = TAU * float(index + 1) / float(sides)
		var first_out := Vector3(cos(first), 0.0, sin(first))
		var second_out := Vector3(cos(second), 0.0, sin(second))
		var middle_first: Vector3 = base + first_out * radius * 0.75 + Vector3.UP * rise * 0.6
		var middle_second: Vector3 = base + second_out * radius * 0.75 + Vector3.UP * rise * 0.6
		var outward: Vector3 = (first_out + second_out).normalized()
		_face(
			surface,
			[base + first_out * radius, base + second_out * radius, middle_second],
			[color, color, color],
			(outward + Vector3.UP * 0.3).normalized()
		)
		_face(
			surface,
			[base + first_out * radius, middle_second, middle_first],
			[color, color, color],
			(outward + Vector3.UP * 0.3).normalized()
		)
		_face(
			surface,
			[middle_first, middle_second, tip],
			[color.lightened(0.1), color.lightened(0.1), color.lightened(0.1)],
			(outward + Vector3.UP).normalized()
		)


## Another mesh's triangles, moved by a transform. With a colour (alpha above 0) they take it,
## darker toward `low` and lighter toward `high` (heights after the move); without one they keep
## the mesh's own colours.
static func _append_mesh(
	surface: SurfaceTool, mesh: ArrayMesh, place: Transform3D, color: Color, low: float, high: float
) -> void:
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = (
		arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	)
	var indices: PackedInt32Array = (
		arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	)
	var order: PackedInt32Array = indices
	if order.is_empty():
		order.resize(vertices.size())
		for index: int in vertices.size():
			order[index] = index
	var normal_basis: Basis = place.basis.inverse().transposed()
	for index: int in order:
		var point: Vector3 = place * vertices[index]
		if color.a > 0.0:
			var share: float = clampf((point.y - low) / maxf(high - low, 0.001), 0.0, 1.0)
			surface.set_color(
				color.darkened(0.3 * (1.0 - share)).lightened(0.12 * share).srgb_to_linear()
			)
		elif not colors.is_empty():
			surface.set_color(colors[index])
		else:
			surface.set_color(Color.WHITE)
		if not normals.is_empty():
			surface.set_normal((normal_basis * normals[index]).normalized())
		surface.add_vertex(point)


## One triangle, wound so its front faces `outward` (Godot's front faces are clockwise), with
## its own normals or `outward` for all three.
static func _face(
	surface: SurfaceTool,
	points: Array[Vector3],
	colors: Array[Color],
	outward: Vector3,
	normals: Array[Vector3] = []
) -> void:
	var order: Array[int] = [0, 1, 2]
	var front: Vector3 = (points[2] - points[0]).cross(points[1] - points[0])
	if front.dot(outward) < 0.0:
		order = [0, 2, 1]
	for index: int in order:
		surface.set_color(colors[index].srgb_to_linear())
		surface.set_normal(normals[index] if not normals.is_empty() else outward)
		surface.add_vertex(points[index])
