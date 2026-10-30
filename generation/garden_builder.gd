class_name GardenBuilder
extends Node3D
## Builds a backyard vegetable garden over an OpenTerrain lawn: galvanised raised beds with
## corrugated walls and rounded ends, filled with soil and planted with lettuce, bush beans,
## peppers and marigolds; wire arch panels and obelisks in the beds; grass tufts across the
## lawn; and a house, a chain-link fence and trees beyond the edge for scenery.
##
## Every size here is a real-world metre, built at structure_scale times that while the bugs
## stay their own size (like the crawlspace). At the default 80 a 17-inch bed is a 34 m
## corrugated wall: climb it (hold forward into it) to reach the soil and the plants on top.
## Bed walls, rims and soil collide on MapInfo.TERRAIN_LAYER, so ground probes, spawns and the
## minimap treat a bed top as ground.

enum Plant { LETTUCE, RED_LETTUCE, BEAN, PEPPER, MARIGOLD, GRASS }
enum Trellis { NONE, ARCHES, OBELISK }

## Bed wall finishes, after the Birdies Garden Products range (Colorbond names in brackets):
## Zincalume (Aluzinc), Merino (Paperbark / Light Clay), Mist Green (Pale Eucalypt),
## Slate Grey (Woodland Grey) and Monolith (Monument).
const BED_FINISHES: Dictionary = {
	"Zincalume": Color(0.78, 0.8, 0.8),
	"Merino": Color(0.8, 0.76, 0.66),
	"Mist Green": Color(0.49, 0.6, 0.53),
	"Slate Grey": Color(0.31, 0.33, 0.31),
	"Monolith": Color(0.2, 0.24, 0.26),
}
const SOIL_COLOR := Color(0.22, 0.16, 0.11)
const WIRE_COLOR := Color(0.09, 0.09, 0.09)
const GRASS_COLOR := Color(0.42, 0.66, 0.26)
const SIDING_COLOR := Color(0.82, 0.8, 0.74)
const ROOF_COLOR := Color(0.32, 0.3, 0.28)
const WINDOW_COLOR := Color(0.18, 0.24, 0.34)
const BARK_COLOR := Color(0.36, 0.28, 0.2)
const CANOPY_COLORS: Array[Color] = [
	Color(0.25, 0.48, 0.2), Color(0.32, 0.56, 0.24), Color(0.2, 0.42, 0.18)
]
const FENCE_COLOR := Color(0.55, 0.57, 0.58)
## Chain-link fabric: diamonds of wire, cut out between them. See shaders/chain_link.gdshader.
const CHAIN_LINK_SHADER: Shader = preload("res://shaders/chain_link.gdshader")
## How far inside the edge of the dirt the chain-link stands, in real metres.
const FENCE_INSET: float = 0.5
## The lip turned in around the top of a bed, and how far the soil sits below the rim.
const RIM_LIP: float = 0.03
const SOIL_DROP: float = 0.06

## The beds, in real metres from the garden's centre: centre, length (along the bed), width,
## whether the long side runs along z, what grows in it (plant: share of the planting grid)
## and the trellis in it. Laid out like a backyard: two big beds up front with arches, a
## lettuce bed in the middle, a long narrow bed behind, two square beds with obelisks at the
## back, and a narrow bed down each side.
const BEDS: Array[Dictionary] = [
	{
		"center": Vector2(-1.4, 1.7),
		"length": 2.4,
		"width": 1.2,
		"along_z": false,
		"trellis": Trellis.ARCHES,
		"plants": {Plant.BEAN: 0.85, Plant.MARIGOLD: 0.15},
		"spacing": 0.17
	},
	{
		"center": Vector2(1.4, 1.7),
		"length": 2.4,
		"width": 1.2,
		"along_z": false,
		"trellis": Trellis.ARCHES,
		"plants": {Plant.BEAN: 0.9, Plant.MARIGOLD: 0.1},
		"spacing": 0.16
	},
	{
		"center": Vector2(0.0, 0.0),
		"length": 2.4,
		"width": 1.2,
		"along_z": false,
		"trellis": Trellis.NONE,
		"plants": {Plant.LETTUCE: 0.55, Plant.RED_LETTUCE: 0.3, Plant.MARIGOLD: 0.15},
		"spacing": 0.22
	},
	{
		"center": Vector2(0.0, -1.3),
		"length": 3.0,
		"width": 0.6,
		"along_z": false,
		"trellis": Trellis.NONE,
		"plants": {Plant.PEPPER: 0.75, Plant.MARIGOLD: 0.25},
		"spacing": 0.27
	},
	{
		"center": Vector2(-2.0, -2.0),
		"length": 1.2,
		"width": 1.2,
		"along_z": false,
		"trellis": Trellis.OBELISK,
		"plants": {Plant.PEPPER: 0.7, Plant.MARIGOLD: 0.3},
		"spacing": 0.27
	},
	{
		"center": Vector2(2.0, -2.0),
		"length": 1.2,
		"width": 1.2,
		"along_z": false,
		"trellis": Trellis.OBELISK,
		"plants": {Plant.PEPPER: 0.7, Plant.MARIGOLD: 0.3},
		"spacing": 0.27
	},
	{
		"center": Vector2(0.0, -2.3),
		"length": 2.0,
		"width": 0.6,
		"along_z": false,
		"trellis": Trellis.NONE,
		"plants": {Plant.LETTUCE: 0.5, Plant.RED_LETTUCE: 0.5},
		"spacing": 0.21
	},
	{
		"center": Vector2(-2.3, -0.2),
		"length": 2.2,
		"width": 0.6,
		"along_z": true,
		"trellis": Trellis.NONE,
		"plants": {Plant.LETTUCE: 0.7, Plant.MARIGOLD: 0.3},
		"spacing": 0.21
	},
	{
		"center": Vector2(2.3, -0.2),
		"length": 2.2,
		"width": 0.6,
		"along_z": true,
		"trellis": Trellis.NONE,
		"plants": {Plant.BEAN: 1.0},
		"spacing": 0.17
	},
]

@export var terrain_path: NodePath = ^"../TerrainWorld"
## World metres per real metre.
@export_range(1.0, 200.0, 1.0) var structure_scale: float = 80.0
## Bed wall height in real metres (a 17-inch bed).
@export var bed_height: float = 0.43
## Corrugation: one rib every rib_pitch metres, bulging rib_depth outward.
@export var rib_pitch: float = 0.085
@export var rib_depth: float = 0.008
## Grass tufts scattered over the lawn.
@export var grass_tufts: int = 3000
## Give each bed a random finish from the Birdies range. Off: every bed is Zincalume.
@export var random_bed_finishes: bool = true
## Lawn ground. Replaces the terrain's material when the scene left it on the planet shader,
## which colours flat ground by distance from the origin and turns a backyard to rock.
@export var lawn_material: Material = preload("res://materials/garden_lawn.tres")
@export var garden_seed: int = 11

var _terrain: OpenTerrain
var _center: Vector3
var _half: Vector3
var _s: float = 80.0
var _rng := RandomNumberGenerator.new()
## Finish name per bed, dealt by _deal_finishes.
var _finishes: Array[String] = []
var _materials: Dictionary = {}
## Plant kind -> {"mesh": ArrayMesh, "transforms": Array[Transform3D], "colors": Array[Color]}.
var _plantings: Dictionary = {}
## Bed footprints in world space, for keeping lawn grass out: {"center": Vector3, "length", "width",
## "along_z"}.
var _footprints: Array[Dictionary] = []
var _built: bool = false


func _ready() -> void:
	add_to_group("map_ceiling")
	add_to_group("map_bounds")
	add_to_group("garden")
	_lay_lawn()
	call_deferred("build")


## Give the terrain the lawn material before its deferred first build, unless the scene set
## a ground material of its own.
func _lay_lawn() -> void:
	var terrain: OpenTerrain = get_node_or_null(terrain_path) as OpenTerrain
	if terrain == null or lawn_material == null:
		return
	var current: ShaderMaterial = terrain.terrain_material as ShaderMaterial
	var planet: bool = (
		current != null
		and current.shader != null
		and current.shader.resource_path == "res://shaders/terrain_spherical.gdshader"
	)
	if terrain.terrain_material == null or planet:
		terrain.terrain_material = lawn_material


## Open sky: flyers and the playable box reach this high (above the tallest obelisk).
func get_ceiling_y() -> float:
	return _center.y + 3.2 * _s


## The yard inside the chain-link: play, spawns and terrain edits stay in here. The dirt runs
## on past the fence so there is lawn, not void, on the other side.
func get_play_bounds() -> AABB:
	var terrain: OpenTerrain = (
		_terrain if _terrain != null else get_node_or_null(terrain_path) as OpenTerrain
	)
	if terrain == null:
		return AABB()
	var half: Vector3 = terrain.get_world_extents() * 0.5
	var inset: float = FENCE_INSET * structure_scale
	var center: Vector3 = terrain.global_position
	return AABB(
		Vector3(center.x - half.x + inset, center.y - half.y - 100.0, center.z - half.z + inset),
		Vector3(
			(half.x - inset) * 2.0,
			half.y * 2.0 + 200.0 + 3.2 * structure_scale,
			(half.z - inset) * 2.0
		)
	)


func build() -> void:
	_terrain = get_node_or_null(terrain_path) as OpenTerrain
	if _terrain == null:
		push_warning("[Garden] No OpenTerrain at %s; nothing built." % terrain_path)
		return
	for child: Node in get_children():
		child.queue_free()
	var seed_value: int = garden_seed + int(_terrain.noise_seed)
	if LoadingScreen.last_terrain_seed == 0:
		seed_value += randi() % 1000000
	_rng.seed = seed_value
	_s = structure_scale
	var extents: Vector3 = _terrain.get_world_extents()
	_center = _terrain.global_position
	_half = extents * 0.5
	_plantings.clear()
	_footprints.clear()

	_deal_finishes()
	var beds := Node3D.new()
	beds.name = "Beds"
	add_child(beds)
	for index: int in BEDS.size():
		_build_bed(beds, BEDS[index], index + 1)
	_commit_plantings()
	_build_lawn()
	_build_house()
	_build_fence()
	_build_trees()
	_built = true
	print(
		(
			"[Garden] Built %.0fx%.0f m backyard at 1:%.0f: %d raised beds %.0f m tall (%s), %d grass tufts"
			% [
				extents.x,
				extents.z,
				_s,
				BEDS.size(),
				bed_height * _s,
				", ".join(_finishes.slice(0, BEDS.size())),
				grass_tufts
			]
		)
	)


# --- Raised beds ------------------------------------------------------------------------------


## The finish of each bed in order: a shuffled deck with every finish dealt before any repeats,
## so neighbours differ and the whole range shows up. All Zincalume when random finishes are off.
func _deal_finishes() -> void:
	_finishes.clear()
	if not random_bed_finishes:
		_finishes.append("Zincalume")
		return
	var names: Array = BED_FINISHES.keys()
	while _finishes.size() < BEDS.size():
		var deck: Array = names.duplicate()
		for index: int in range(deck.size() - 1, 0, -1):
			var swap: int = _rng.randi_range(0, index)
			var held: Variant = deck[index]
			deck[index] = deck[swap]
			deck[swap] = held
		# Don't let a new deck open with the finish the last one ended on.
		if not _finishes.is_empty() and deck[0] == _finishes[-1] and deck.size() > 1:
			deck.append(deck.pop_front())
		for finish: String in deck:
			_finishes.append(finish)


func _build_bed(parent: Node3D, bed: Dictionary, number: int) -> void:
	var length: float = float(bed["length"]) * _s
	var width: float = float(bed["width"]) * _s
	var along_z: bool = bool(bed["along_z"])
	var center2: Vector2 = bed["center"] as Vector2
	var center := Vector3(_center.x + center2.x * _s, 0.0, _center.z + center2.y * _s)
	# The wall stands on the lowest dirt under its footprint, sunk a little, so no gap shows
	# at the high side of a slope.
	var base_y: float = INF
	var outline: Dictionary = _stadium(length, width)
	for point: Vector2 in outline["points"]:
		var world: Vector3 = center + _bed_local_to_world(Vector3(point.x, 0.0, point.y), along_z)
		base_y = minf(base_y, _dirt_height(world))
	base_y = minf(base_y, _dirt_height(center)) - 0.4
	center.y = base_y
	_footprints.append({"center": center, "length": length, "width": width, "along_z": along_z})

	var root := Node3D.new()
	root.name = "Bed%d" % number
	parent.add_child(root)
	root.global_position = center
	if along_z:
		root.rotation.y = PI * 0.5
	var height: float = bed_height * _s
	# Sink depth plus a little, so the wall reaches the dirt everywhere.
	var wall_bottom: float = -0.5
	var finish: String = _finishes[(number - 1) % _finishes.size()]
	var wall := MeshInstance3D.new()
	wall.name = "Wall"
	wall.mesh = _corrugated_wall_mesh(outline, wall_bottom, height, BED_FINISHES[finish])
	wall.material_override = _material(Color.WHITE, 0.35 if finish == "Zincalume" else 0.55, true)
	wall.set_meta("finish", finish)
	root.add_child(wall)

	var soil_top: float = height - SOIL_DROP * _s
	var soil := MeshInstance3D.new()
	soil.name = "Soil"
	soil.mesh = _cap_mesh(
		_stadium(length - RIM_LIP * 2.0 * _s, width - RIM_LIP * 2.0 * _s), soil_top, SOIL_COLOR
	)
	soil.material_override = _material(SOIL_COLOR, 1.0, true)
	root.add_child(soil)

	_bed_collision(root, outline, length, width, wall_bottom, height, soil_top)
	_plant_bed(bed, root, length, width, soil_top)
	match int(bed["trellis"]):
		Trellis.ARCHES:
			for side: int in 2:
				_build_arch_panel(
					root,
					Vector3(length * (0.5 * side - 0.25), soil_top, 0.0),
					width * 0.8,
					side + 1
				)
		Trellis.OBELISK:
			_build_obelisk(root, Vector3(0.0, soil_top, 0.0))


## Points around a stadium (a rectangle with semicircular ends) of a length along x and a
## width along z, with the outward normal at each point.
func _stadium(
	length: float, width: float, end_segments: int = 14, side_segments: int = 10
) -> Dictionary:
	var r: float = width * 0.5
	var c: float = maxf(length * 0.5 - r, 0.0)
	var points := PackedVector2Array()
	var normals := PackedVector2Array()
	for index: int in end_segments + 1:
		var angle: float = -PI * 0.5 + PI * float(index) / float(end_segments)
		points.append(Vector2(c + r * cos(angle), r * sin(angle)))
		normals.append(Vector2(cos(angle), sin(angle)))
	if c > 0.0:
		for index: int in range(1, side_segments):
			points.append(Vector2(c - 2.0 * c * float(index) / float(side_segments), r))
			normals.append(Vector2(0.0, 1.0))
	for index: int in end_segments + 1:
		var angle: float = PI * 0.5 + PI * float(index) / float(end_segments)
		points.append(Vector2(-c + r * cos(angle), r * sin(angle)))
		normals.append(Vector2(cos(angle), sin(angle)))
	if c > 0.0:
		for index: int in range(1, side_segments):
			points.append(Vector2(-c + 2.0 * c * float(index) / float(side_segments), -r))
			normals.append(Vector2(0.0, -1.0))
	return {"points": points, "normals": normals}


## The corrugated wall: rings of the outline from the bottom to the rim, each pushed out by
## the rib profile at its height, then a lip turned inward at the top and a short inner wall.
func _corrugated_wall_mesh(
	outline: Dictionary, bottom: float, top: float, color: Color
) -> ArrayMesh:
	var points: PackedVector2Array = outline["points"]
	var normals: PackedVector2Array = outline["normals"]
	var pitch: float = rib_pitch * _s
	var depth: float = rib_depth * _s
	var ring_step: float = pitch * 0.25
	var ring_count: int = maxi(int(ceil((top - bottom) / ring_step)), 2) + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	var ring_normals: Array[PackedVector3Array] = []
	for ring: int in ring_count:
		var h: float = lerpf(bottom, top, float(ring) / float(ring_count - 1))
		var phase: float = TAU * (h - bottom) / pitch
		var bulge: float = depth * (0.5 - 0.5 * cos(phase))
		var slope: float = depth * 0.5 * sin(phase) * TAU / pitch
		var ring_points := PackedVector3Array()
		var ring_norms := PackedVector3Array()
		for index: int in points.size():
			var n: Vector2 = normals[index]
			ring_points.append(
				Vector3(points[index].x + n.x * bulge, h, points[index].y + n.y * bulge)
			)
			ring_norms.append(Vector3(n.x, -slope, n.y).normalized())
		rings.append(ring_points)
		ring_normals.append(ring_norms)
	for ring: int in ring_count - 1:
		_stitch_rings(
			st, rings[ring], rings[ring + 1], ring_normals[ring], ring_normals[ring + 1], color
		)
	# Lip and inner wall.
	var lip: float = RIM_LIP * _s
	var outer_top: PackedVector3Array = rings[ring_count - 1]
	var inner_top := PackedVector3Array()
	var inner_down := PackedVector3Array()
	var up_norms := PackedVector3Array()
	var in_norms := PackedVector3Array()
	for index: int in points.size():
		var n: Vector2 = normals[index]
		inner_top.append(Vector3(points[index].x - n.x * lip, top, points[index].y - n.y * lip))
		inner_down.append(
			Vector3(
				points[index].x - n.x * lip, top - SOIL_DROP * _s - 0.5, points[index].y - n.y * lip
			)
		)
		up_norms.append(Vector3.UP)
		in_norms.append(Vector3(-n.x, 0.0, -n.y))
	_stitch_rings(st, outer_top, inner_top, up_norms, up_norms, color)
	_stitch_rings(st, inner_top, inner_down, in_norms, in_norms, color * 0.85)
	return st.commit()


## Triangles between two rings of equal length (closed loops).
func _stitch_rings(
	st: SurfaceTool,
	a: PackedVector3Array,
	b: PackedVector3Array,
	na: PackedVector3Array,
	nb: PackedVector3Array,
	color: Color
) -> void:
	var count: int = a.size()
	for index: int in count:
		var next: int = (index + 1) % count
		_triangle(st, [a[index], b[index], a[next]], [na[index], nb[index], na[next]], color)
		_triangle(st, [a[next], b[index], b[next]], [na[next], nb[index], nb[next]], color)


func _triangle(st: SurfaceTool, points: Array, normals: Array, color: Color) -> void:
	for index: int in 3:
		st.set_color(color)
		st.set_normal(normals[index])
		st.add_vertex(points[index])


## A flat cap over a stadium outline (a fan from the centre), facing up.
func _cap_mesh(outline: Dictionary, y: float, color: Color) -> ArrayMesh:
	var points: PackedVector2Array = outline["points"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0.0, y, 0.0)
	for index: int in points.size():
		var next: int = (index + 1) % points.size()
		var a := Vector3(points[index].x, y, points[index].y)
		var b := Vector3(points[next].x, y, points[next].y)
		var shade: float = _rng.randf_range(0.9, 1.05)
		_triangle(st, [center, b, a], [Vector3.UP, Vector3.UP, Vector3.UP], color * shade)
	return st.commit()


## Collision for a bed: a smooth (rib-free) trimesh of the outer wall, the lip and the inner
## wall, and the soil as a box plus two cylinders, all on the terrain layer.
func _bed_collision(
	root: Node3D,
	outline: Dictionary,
	length: float,
	width: float,
	bottom: float,
	top: float,
	soil_top: float
) -> void:
	var points: PackedVector2Array = outline["points"]
	var normals: PackedVector2Array = outline["normals"]
	var lip: float = RIM_LIP * _s
	var faces := PackedVector3Array()
	var count: int = points.size()
	for index: int in count:
		var next: int = (index + 1) % count
		var p: Vector2 = points[index]
		var q: Vector2 = points[next]
		var pn: Vector2 = p - normals[index] * lip
		var qn: Vector2 = q - normals[next] * lip
		var quads: Array = [
			[
				Vector3(p.x, bottom, p.y),
				Vector3(p.x, top, p.y),
				Vector3(q.x, bottom, q.y),
				Vector3(q.x, top, q.y)
			],
			[
				Vector3(p.x, top, p.y),
				Vector3(pn.x, top, pn.y),
				Vector3(q.x, top, q.y),
				Vector3(qn.x, top, qn.y)
			],
			[
				Vector3(pn.x, top, pn.y),
				Vector3(pn.x, soil_top - 0.5, pn.y),
				Vector3(qn.x, top, qn.y),
				Vector3(qn.x, soil_top - 0.5, qn.y)
			],
		]
		for quad: Array in quads:
			faces.append_array(
				PackedVector3Array([quad[0], quad[1], quad[2], quad[2], quad[1], quad[3]])
			)
	var body := StaticBody3D.new()
	body.name = "WallCollider"
	body.collision_layer = MapInfo.TERRAIN_LAYER
	body.collision_mask = 0
	var wall_shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(faces)
	concave.backface_collision = true
	wall_shape.shape = concave
	body.add_child(wall_shape)
	# Soil: the straight middle as a box, each rounded end as a cylinder.
	var soil_height: float = soil_top - bottom
	var inner_width: float = width - lip * 2.0
	var r: float = inner_width * 0.5
	var c: float = maxf(length * 0.5 - width * 0.5, 0.0)
	if c > 0.0:
		var box := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(c * 2.0, soil_height, inner_width)
		box.shape = box_shape
		box.position = Vector3(0.0, bottom + soil_height * 0.5, 0.0)
		body.add_child(box)
	for side: float in [-1.0, 1.0]:
		var end := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = r
		cylinder.height = soil_height
		end.shape = cylinder
		end.position = Vector3(c * side, bottom + soil_height * 0.5, 0.0)
		body.add_child(end)
	root.add_child(body)


func _bed_local_to_world(local: Vector3, along_z: bool) -> Vector3:
	return Vector3(-local.z, local.y, local.x) if along_z else local


# --- Planting ---------------------------------------------------------------------------------


## Fills a bed's soil on a jittered grid, each cell drawing a plant kind by the bed's shares.
func _plant_bed(
	bed: Dictionary, root: Node3D, length: float, width: float, soil_top: float
) -> void:
	var shares: Dictionary = bed["plants"]
	var spacing: float = float(bed["spacing"]) * _s
	var inset: float = (RIM_LIP + 0.08) * _s
	var r: float = (width - inset * 2.0) * 0.5
	var c: float = maxf(length * 0.5 - width * 0.5, 0.0)
	var columns: int = maxi(int((length - inset * 2.0) / spacing), 1)
	var rows: int = maxi(int((width - inset * 2.0) / spacing), 1)
	for column: int in columns:
		for row: int in rows:
			var x: float = lerpf(
				-(length * 0.5 - inset),
				length * 0.5 - inset,
				(float(column) + 0.5) / float(columns)
			)
			var z: float = lerpf(-r, r, (float(row) + 0.5) / float(rows))
			x += _rng.randf_range(-0.3, 0.3) * spacing
			z += _rng.randf_range(-0.3, 0.3) * spacing
			# Inside the rounded ends too.
			var end_x: float = maxf(absf(x) - c, 0.0)
			if end_x * end_x + z * z > r * r:
				continue
			var kind: Plant = _draw_plant(shares)
			var size: float = _s * _rng.randf_range(0.85, 1.15)
			var basis: Basis = (
				Basis(Vector3.UP, _rng.randf() * TAU)
				* Basis.from_scale(Vector3(size, size * _rng.randf_range(0.9, 1.1), size))
			)
			var transform: Transform3D = (
				root.global_transform * Transform3D(basis, Vector3(x, soil_top, z))
			)
			_queue_plant(kind, transform, Color.WHITE * _rng.randf_range(0.88, 1.0))


func _draw_plant(shares: Dictionary) -> Plant:
	var total: float = 0.0
	for share: float in shares.values():
		total += share
	var pick: float = _rng.randf() * total
	for kind: int in shares:
		pick -= float(shares[kind])
		if pick <= 0.0:
			return kind as Plant
	return shares.keys().back() as Plant


func _queue_plant(kind: Plant, transform: Transform3D, tint: Color) -> void:
	if not _plantings.has(kind):
		_plantings[kind] = {"mesh": _plant_mesh(kind), "transforms": [], "colors": []}
	var planting: Dictionary = _plantings[kind]
	planting["transforms"].append(transform)
	tint.a = 1.0
	planting["colors"].append(tint)


## One MultiMesh per plant kind, so a whole garden is a handful of draw calls.
func _commit_plantings() -> void:
	var plants := Node3D.new()
	plants.name = "Plants"
	add_child(plants)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for kind: int in _plantings:
		var planting: Dictionary = _plantings[kind]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = planting["mesh"]
		multimesh.instance_count = planting["transforms"].size()
		for index: int in multimesh.instance_count:
			multimesh.set_instance_transform(index, planting["transforms"][index])
			multimesh.set_instance_color(index, planting["colors"][index])
		var instance := MultiMeshInstance3D.new()
		instance.name = Plant.keys()[kind].capitalize()
		instance.multimesh = multimesh
		instance.material_override = material
		plants.add_child(instance)


## Plant meshes in real metres (the instance scale makes them world size).
func _plant_mesh(kind: Plant) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		Plant.LETTUCE:
			_lettuce(st, Color(0.47, 0.72, 0.27), Color(0.72, 0.88, 0.45))
		Plant.RED_LETTUCE:
			_lettuce(st, Color(0.42, 0.12, 0.17), Color(0.6, 0.25, 0.25))
		Plant.BEAN:
			_bush(st, 0.32, 14, 0.075, 0.065, Color(0.3, 0.58, 0.22), Color(0.42, 0.7, 0.3))
		Plant.PEPPER:
			_pepper(st)
		Plant.MARIGOLD:
			_marigold(st)
		Plant.GRASS:
			_grass_tuft(st)
	st.generate_normals()
	return st.commit()


## A rosette: an inner whorl of short upright leaves and an outer whorl of long flat ones.
func _lettuce(st: SurfaceTool, color: Color, edge: Color) -> void:
	for whorl: int in 2:
		var count: int = 7 + whorl * 3
		for index: int in count:
			var yaw: float = (
				TAU * (float(index) + whorl * 0.5) / float(count) + _rng.randf_range(-0.1, 0.1)
			)
			var out := Vector3(cos(yaw), 0.0, sin(yaw))
			var pitch: float = (
				deg_to_rad(_rng.randf_range(55.0, 70.0))
				if whorl == 0
				else deg_to_rad(_rng.randf_range(15.0, 35.0))
			)
			var direction: Vector3 = (out * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
			var length: float = (
				_rng.randf_range(0.09, 0.12) if whorl == 0 else _rng.randf_range(0.13, 0.18)
			)
			_leaf(
				st,
				Vector3(0.0, 0.01, 0.0) + out * 0.01,
				direction,
				length,
				length * 0.6,
				color,
				edge,
				0.6,
				5
			)
	# A heart of pale leaves in the middle.
	_blob(st, Vector3(0.0, 0.05, 0.0), 0.045, edge.lerp(color, 0.4))


## A bushy plant: leaves on short stalks all around a stem.
func _bush(
	st: SurfaceTool,
	height: float,
	leaves: int,
	leaf_length: float,
	leaf_width: float,
	color: Color,
	edge: Color
) -> void:
	_stem(st, Vector3.ZERO, Vector3(0.0, height, 0.0), 0.006, color * 0.8)
	for index: int in leaves:
		var t: float = _rng.randf_range(0.25, 1.0)
		var yaw: float = _rng.randf() * TAU
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		var base := Vector3(0.0, height * t, 0.0)
		var reach: float = _rng.randf_range(0.05, 0.12) * (1.4 - t * 0.6)
		var stalk_end: Vector3 = base + out * reach + Vector3.UP * _rng.randf_range(-0.02, 0.05)
		_stem(st, base, stalk_end, 0.003, color * 0.8)
		var tilt: Vector3 = (out * 0.7 + Vector3.UP * _rng.randf_range(-0.3, 0.3)).normalized()
		for offset: float in [-0.9, 0.0, 0.9]:
			var leaf_dir: Vector3 = tilt.rotated(Vector3.UP, offset).normalized()
			_leaf(st, stalk_end, leaf_dir, leaf_length, leaf_width, color, edge, 0.35, 3)


## A pepper plant: an upright stem with narrow leaves and a few ripening fruits.
func _pepper(st: SurfaceTool) -> void:
	var color := Color(0.26, 0.5, 0.22)
	var edge := Color(0.36, 0.62, 0.3)
	var height: float = 0.45
	_stem(st, Vector3.ZERO, Vector3(0.0, height, 0.0), 0.007, color * 0.7)
	for index: int in 12:
		var t: float = _rng.randf_range(0.3, 1.0)
		var yaw: float = _rng.randf() * TAU
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		var base := Vector3(0.0, height * t, 0.0)
		var direction: Vector3 = (out * 0.8 + Vector3.UP * _rng.randf_range(-0.2, 0.4)).normalized()
		_leaf(st, base, direction, _rng.randf_range(0.07, 0.11), 0.035, color, edge, 0.25, 3)
	var fruit_colors: Array[Color] = [
		Color(0.85, 0.15, 0.08), Color(0.95, 0.5, 0.08), Color(0.35, 0.6, 0.2)
	]
	for index: int in 4:
		var yaw: float = _rng.randf() * TAU
		var hang := (
			Vector3(cos(yaw), 0.0, sin(yaw)) * _rng.randf_range(0.04, 0.09)
			+ Vector3(0.0, height * _rng.randf_range(0.4, 0.8), 0.0)
		)
		_stem(st, Vector3(0.0, hang.y + 0.03, 0.0), hang, 0.002, color * 0.7)
		_blob(
			st,
			hang - Vector3(0.0, 0.02, 0.0),
			0.022,
			fruit_colors[_rng.randi() % fruit_colors.size()],
			1.6
		)


## A marigold: a short stem, feathery leaves and an orange pompom with a yellow crown.
func _marigold(st: SurfaceTool) -> void:
	var color := Color(0.28, 0.5, 0.2)
	var height: float = 0.22
	_stem(st, Vector3.ZERO, Vector3(0.0, height, 0.0), 0.004, color * 0.8)
	for index: int in 7:
		var yaw: float = _rng.randf() * TAU
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		var base := Vector3(0.0, height * _rng.randf_range(0.2, 0.7), 0.0)
		_leaf(
			st,
			base,
			(out * 0.8 + Vector3.UP * 0.3).normalized(),
			0.06,
			0.018,
			color,
			color * 1.2,
			0.3,
			3
		)
	var orange := Color(0.95, 0.5, 0.08)
	_blob(st, Vector3(0.0, height + 0.02, 0.0), 0.032, orange)
	_blob(st, Vector3(0.0, height + 0.04, 0.0), 0.018, Color(0.98, 0.8, 0.15))
	_blob(st, Vector3(0.0, height - 0.005, 0.0), 0.014, color)


## A tuft of lawn grass: a few blades leaning out from one spot.
func _grass_tuft(st: SurfaceTool) -> void:
	for index: int in 5:
		var yaw: float = TAU * float(index) / 5.0 + _rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		var direction: Vector3 = (out * _rng.randf_range(0.2, 0.5) + Vector3.UP).normalized()
		var length: float = _rng.randf_range(0.05, 0.09)
		_leaf(
			st,
			Vector3.ZERO,
			direction,
			length,
			0.008,
			GRASS_COLOR * _rng.randf_range(0.85, 1.05),
			GRASS_COLOR * 1.15,
			0.5,
			3
		)


## A leaf: a strip `segments` long from `origin` along `direction`, widest in the middle,
## drooping by `bend`, coloured `color` in the middle and `edge` at the edges.
func _leaf(
	st: SurfaceTool,
	origin: Vector3,
	direction: Vector3,
	length: float,
	width: float,
	color: Color,
	edge: Color,
	bend: float,
	segments: int
) -> void:
	var side: Vector3 = direction.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var previous_left: Vector3 = origin
	var previous_right: Vector3 = origin
	for segment: int in range(1, segments + 1):
		var t: float = float(segment) / float(segments)
		var droop: float = bend * length * t * t
		var spine: Vector3 = origin + direction * length * t - Vector3.UP * droop
		var half: float = width * 0.5 * sin(PI * minf(t * 1.15, 1.0))
		var left: Vector3 = spine - side * half
		var right: Vector3 = spine + side * half
		var mid: Color = color.lerp(edge, t * 0.6)
		_triangle(
			st, [previous_left, previous_right, left], [Vector3.UP, Vector3.UP, Vector3.UP], mid
		)
		_triangle(st, [previous_right, right, left], [Vector3.UP, Vector3.UP, Vector3.UP], mid)
		previous_left = left
		previous_right = right


## A thin square-section stem between two points.
func _stem(st: SurfaceTool, from: Vector3, to: Vector3, radius: float, color: Color) -> void:
	var axis: Vector3 = (to - from).normalized()
	var side: Vector3 = (
		axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.FORWARD).normalized() * radius
	)
	var other: Vector3 = axis.cross(side).normalized() * radius
	var corners: Array = [side, other, -side, -other]
	for index: int in 4:
		var a: Vector3 = corners[index]
		var b: Vector3 = corners[(index + 1) % 4]
		var normal: Vector3 = (a + b).normalized()
		_triangle(st, [from + a, from + b, to + a], [normal, normal, normal], color)
		_triangle(st, [to + a, from + b, to + b], [normal, normal, normal], color)


## A lumpy ball (a lettuce heart, a flower head, a pepper), stretched by `tall`.
func _blob(
	st: SurfaceTool, center: Vector3, radius: float, color: Color, tall: float = 1.0
) -> void:
	var rings: int = 4
	var sides: int = 7
	var previous := PackedVector3Array()
	for ring: int in rings + 1:
		var lat: float = PI * float(ring) / float(rings)
		var current := PackedVector3Array()
		for side: int in sides:
			var lon: float = TAU * float(side) / float(sides)
			var wobble: float = 1.0 + 0.08 * sin(lon * 3.0 + lat * 2.0)
			current.append(
				(
					center
					+ (
						Vector3(sin(lat) * cos(lon), cos(lat) * tall, sin(lat) * sin(lon))
						* radius
						* wobble
					)
				)
			)
		if ring > 0:
			for side: int in sides:
				var next: int = (side + 1) % sides
				var n: Vector3 = (current[side] - center).normalized()
				_triangle(st, [previous[side], current[side], previous[next]], [n, n, n], color)
				_triangle(st, [previous[next], current[side], current[next]], [n, n, n], color)
		previous = current


# --- Trellises --------------------------------------------------------------------------------


## An arched wire panel standing across a bed: verticals every 12 cm rising into a half-round
## top, horizontals every 20 cm. Legs collide so a bug can climb a rod.
func _build_arch_panel(root: Node3D, base: Vector3, width: float, number: int) -> void:
	var panel := Node3D.new()
	panel.name = "ArchPanel%d" % number
	panel.position = base
	root.add_child(panel)
	var rod: float = 0.004 * _s
	var square_top: float = 0.9 * _s
	var r: float = width * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	body.name = "Rods"
	body.collision_layer = MapInfo.TERRAIN_LAYER
	body.collision_mask = 0
	var verticals: int = 6
	for index: int in verticals:
		var z: float = lerpf(-r * 0.92, r * 0.92, float(index) / float(verticals - 1))
		var top: float = square_top + sqrt(maxf(r * r - z * z, 0.0))
		_rod(st, Vector3(0.0, -0.3 * _s, z), Vector3(0.0, top, z), rod)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(rod * 2.0, top + 0.3 * _s, rod * 2.0)
		shape.shape = box
		shape.position = Vector3(0.0, (top - 0.3 * _s) * 0.5, z)
		body.add_child(shape)
	var level: float = 0.2 * _s
	while level < square_top + 0.01:
		_rod(st, Vector3(0.0, level, -r), Vector3(0.0, level, r), rod)
		level += 0.2 * _s
	var arc_segments: int = 12
	var previous := Vector3(0.0, square_top, -r)
	for index: int in range(1, arc_segments + 1):
		var angle: float = PI - PI * float(index) / float(arc_segments)
		var point := Vector3(0.0, square_top + sin(angle) * r, -cos(angle) * r)
		_rod(st, previous, point, rod)
		previous = point
	var mesh := MeshInstance3D.new()
	mesh.name = "Wire"
	mesh.mesh = st.commit()
	mesh.material_override = _material(WIRE_COLOR, 0.6)
	panel.add_child(mesh)
	panel.add_child(body)


## A four-legged obelisk tapering to a finial, with square rings up its height.
func _build_obelisk(root: Node3D, base: Vector3) -> void:
	var obelisk := Node3D.new()
	obelisk.name = "Obelisk"
	obelisk.position = base
	root.add_child(obelisk)
	var rod: float = 0.006 * _s
	var height: float = 1.8 * _s
	var foot: float = 0.22 * _s
	var head: float = 0.05 * _s
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	body.name = "Legs"
	body.collision_layer = MapInfo.TERRAIN_LAYER
	body.collision_mask = 0
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for corner: Vector2 in corners:
		var from := Vector3(corner.x * foot, -0.3 * _s, corner.y * foot)
		var to := Vector3(corner.x * head, height, corner.y * head)
		_rod(st, from, to, rod)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(rod * 2.0, from.distance_to(to), rod * 2.0)
		shape.shape = box
		shape.transform = Transform3D(
			Basis(Quaternion(Vector3.UP, (to - from).normalized())), (from + to) * 0.5
		)
		body.add_child(shape)
	for fraction: float in [0.3, 0.55, 0.8]:
		var y: float = height * fraction
		var half: float = lerpf(foot, head, fraction + 0.3 * _s / height)
		for index: int in 4:
			var a: Vector2 = corners[index] * half
			var b: Vector2 = corners[(index + 1) % 4] * half
			_rod(st, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), rod * 0.8)
	_blob(st, Vector3(0.0, height + 0.04 * _s, 0.0), 0.035 * _s, WIRE_COLOR, 1.3)
	var mesh := MeshInstance3D.new()
	mesh.name = "Wire"
	mesh.mesh = st.commit()
	mesh.material_override = _material(WIRE_COLOR, 0.6)
	obelisk.add_child(mesh)
	obelisk.add_child(body)


## A six-sided rod between two points.
func _rod(st: SurfaceTool, from: Vector3, to: Vector3, radius: float) -> void:
	var axis: Vector3 = (to - from).normalized()
	var side: Vector3 = (
		axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.FORWARD).normalized()
	)
	var other: Vector3 = axis.cross(side).normalized()
	var sides: int = 6
	for index: int in sides:
		var a0: float = TAU * float(index) / float(sides)
		var a1: float = TAU * float(index + 1) / float(sides)
		var oa: Vector3 = (side * cos(a0) + other * sin(a0)) * radius
		var ob: Vector3 = (side * cos(a1) + other * sin(a1)) * radius
		var normal: Vector3 = (oa + ob).normalized()
		_triangle(st, [from + oa, from + ob, to + oa], [normal, normal, normal], WIRE_COLOR)
		_triangle(st, [to + oa, from + ob, to + ob], [normal, normal, normal], WIRE_COLOR)


# --- Lawn and scenery -------------------------------------------------------------------------


## Grass tufts over the lawn, clear of the beds.
func _build_lawn() -> void:
	var margin: float = 0.15 * _s
	var placed: int = 0
	var attempts: int = 0
	while placed < grass_tufts and attempts < grass_tufts * 3:
		attempts += 1
		var x: float = _center.x + _rng.randf_range(-_half.x + margin, _half.x - margin)
		var z: float = _center.z + _rng.randf_range(-_half.z + margin, _half.z - margin)
		var spot := Vector3(x, 0.0, z)
		if _in_any_bed(spot, 0.12 * _s):
			continue
		spot.y = _dirt_height(spot) - 0.05
		var size: float = _s * _rng.randf_range(0.7, 1.3)
		var basis: Basis = (
			Basis(Vector3.UP, _rng.randf() * TAU) * Basis.from_scale(Vector3(size, size, size))
		)
		_queue_plant(
			Plant.GRASS, Transform3D(basis, spot), Color.WHITE * _rng.randf_range(0.85, 1.0)
		)
		placed += 1
	# The lawn joins the garden's planting node (one more MultiMesh).
	var plants: Node3D = get_node("Plants")
	var planting: Dictionary = _plantings[Plant.GRASS]
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = planting["mesh"]
	multimesh.instance_count = planting["transforms"].size()
	for index: int in multimesh.instance_count:
		multimesh.set_instance_transform(index, planting["transforms"][index])
		multimesh.set_instance_color(index, planting["colors"][index])
	var instance := MultiMeshInstance3D.new()
	instance.name = "Lawn"
	instance.multimesh = multimesh
	instance.material_override = (
		plants.get_child(0).material_override if plants.get_child_count() > 0 else null
	)
	plants.add_child(instance)


func _in_any_bed(spot: Vector3, grow: float) -> bool:
	for footprint: Dictionary in _footprints:
		var local: Vector3 = spot - footprint["center"]
		if footprint["along_z"]:
			local = Vector3(local.z, 0.0, -local.x)
		var length: float = float(footprint["length"]) + grow * 2.0
		var width: float = float(footprint["width"]) + grow * 2.0
		var r: float = width * 0.5
		var c: float = maxf(length * 0.5 - r, 0.0)
		var end_x: float = maxf(absf(local.x) - c, 0.0)
		if end_x * end_x + local.z * local.z <= r * r:
			return true
	return false


## The house beyond the west edge: siding, a gable roof and a row of windows facing the garden.
func _build_house() -> void:
	var house := Node3D.new()
	house.name = "House"
	add_child(house)
	var depth: float = 4.5 * _s
	var length: float = 9.0 * _s
	var wall_height: float = 2.6 * _s
	var x_near: float = _center.x - _half.x - 0.6 * _s
	var ground_y: float = (
		_dirt_height(Vector3(_center.x - _half.x + 1.0, 0.0, _center.z)) - 0.2 * _s
	)
	var center := Vector3(x_near - depth * 0.5, ground_y + wall_height * 0.5, _center.z + 0.8 * _s)
	_box(house, "Walls", Vector3(depth, wall_height, length), center, _material(SIDING_COLOR, 0.9))
	# Roof: a prism along z.
	var ridge: float = 1.5 * _s
	var overhang: float = 0.3 * _s
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx: float = depth * 0.5 + overhang
	var hz: float = length * 0.5 + overhang
	var eave_y: float = wall_height * 0.5
	var peak := Vector3(0.0, eave_y + ridge, 0.0)
	for sign_z: float in [-1.0, 1.0]:
		var a := Vector3(-hx, eave_y, sign_z * hz)
		var b := Vector3(hx, eave_y, sign_z * hz)
		var p: Vector3 = peak + Vector3(0.0, 0.0, sign_z * hz)
		_triangle(
			st,
			[a, b, p],
			[Vector3(0, 0, sign_z), Vector3(0, 0, sign_z), Vector3(0, 0, sign_z)],
			ROOF_COLOR
		)
	for sign_x: float in [-1.0, 1.0]:
		var n := Vector3(sign_x * ridge, hx, 0.0).normalized()
		var low_a := Vector3(sign_x * hx, eave_y, -hz)
		var low_b := Vector3(sign_x * hx, eave_y, hz)
		_triangle(st, [low_a, low_b, peak + Vector3(0, 0, -hz)], [n, n, n], ROOF_COLOR)
		_triangle(
			st, [low_b, peak + Vector3(0, 0, hz), peak + Vector3(0, 0, -hz)], [n, n, n], ROOF_COLOR
		)
	var roof := MeshInstance3D.new()
	roof.name = "Roof"
	roof.mesh = st.commit()
	roof.material_override = _material(ROOF_COLOR, 0.95, true)
	roof.position = center
	house.add_child(roof)
	# Windows and a door on the garden side.
	for offset: float in [-2.8, -0.9, 2.6]:
		_box(
			house,
			"Window",
			Vector3(0.04 * _s, 1.0 * _s, 0.9 * _s),
			Vector3(x_near + 0.02 * _s, ground_y + 1.5 * _s, center.z + offset * _s),
			_material(WINDOW_COLOR, 0.3)
		)
		_box(
			house,
			"Trim",
			Vector3(0.03 * _s, 1.12 * _s, 1.02 * _s),
			Vector3(x_near + 0.01 * _s, ground_y + 1.5 * _s, center.z + offset * _s),
			_material(Color(0.95, 0.95, 0.93), 0.8)
		)
	_box(
		house,
		"Door",
		Vector3(0.05 * _s, 2.0 * _s, 0.9 * _s),
		Vector3(x_near + 0.02 * _s, ground_y + 1.0 * _s, center.z + 1.0 * _s),
		_material(Color(0.35, 0.22, 0.14), 0.8)
	)


## Chain-link around the whole yard, a little inside the edge of the dirt: posts, a top rail, a
## tension wire and the diamond fabric, plus an invisible barrier up to the sky so nothing walks,
## climbs or flies out over the lawn beyond. Bugs bump into it but cannot climb it.
func _build_fence() -> void:
	var fence := Node3D.new()
	fence.name = "Fence"
	add_child(fence)
	var height: float = 1.2 * _s
	var post_radius: float = 0.03 * _s
	var yard: AABB = get_play_bounds()
	var corners: Array[Vector3] = [
		Vector3(yard.position.x, 0.0, yard.position.z),
		Vector3(yard.end.x, 0.0, yard.position.z),
		Vector3(yard.end.x, 0.0, yard.end.z),
		Vector3(yard.position.x, 0.0, yard.end.z),
	]
	var barrier_top: float = get_ceiling_y() + 2.0 * _s
	for run: int in corners.size():
		var from: Vector3 = corners[run]
		var to: Vector3 = corners[(run + 1) % corners.size()]
		var along: Vector3 = to - from
		var span: float = along.length()
		var direction: Vector3 = along / span
		var posts: int = maxi(int(span / (3.0 * _s)), 1)
		# The last post of this run is the first of the next.
		for index: int in posts:
			var at: Vector3 = from + direction * span * float(index) / float(posts)
			var post_ground: float = _dirt_height(at) - 0.1 * _s
			_cylinder(
				fence,
				"Post",
				post_radius,
				height + 0.3 * _s,
				Vector3(at.x, post_ground + height * 0.5, at.z),
				Vector3.ZERO,
				_material(FENCE_COLOR, 0.5)
			)
		var mid: Vector3 = (from + to) * 0.5
		var ground_y: float = (
			minf(minf(_dirt_height(from), _dirt_height(to)), _dirt_height(mid)) - 0.1 * _s
		)
		var yaw: float = atan2(direction.x, direction.z)
		_cylinder(
			fence,
			"Rail",
			post_radius * 0.6,
			span,
			Vector3(mid.x, ground_y + height, mid.z),
			Vector3(PI * 0.5, yaw, 0.0),
			_material(FENCE_COLOR, 0.5)
		)
		_cylinder(
			fence,
			"TensionWire",
			post_radius * 0.3,
			span,
			Vector3(mid.x, ground_y + 0.05 * _s, mid.z),
			Vector3(PI * 0.5, yaw, 0.0),
			_material(FENCE_COLOR, 0.5)
		)
		var sheet := MeshInstance3D.new()
		sheet.name = "Fabric"
		var quad := QuadMesh.new()
		quad.size = Vector2(span, height)
		sheet.mesh = quad
		var fabric := ShaderMaterial.new()
		fabric.shader = CHAIN_LINK_SHADER
		fabric.set_shader_parameter("sheet_size", Vector2(span, height))
		fabric.set_shader_parameter("mesh_pitch", 0.05 * _s)
		fabric.set_shader_parameter("wire_width", 0.0035 * _s)
		fabric.set_shader_parameter("wire_color", FENCE_COLOR)
		sheet.material_override = fabric
		sheet.position = Vector3(mid.x, ground_y + height * 0.5, mid.z)
		sheet.rotation = Vector3(0.0, yaw + PI * 0.5, 0.0)
		fence.add_child(sheet)
		# The barrier: fence-thick, reaching from under the dirt to above the sky cap.
		var barrier := StaticBody3D.new()
		barrier.name = "Barrier%d" % (run + 1)
		barrier.collision_layer = MapInfo.STRUCTURE_LAYER
		barrier.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var bottom: float = ground_y - 2.0 * _s
		box.size = Vector3(span + post_radius * 2.0, barrier_top - bottom, post_radius * 2.0)
		shape.shape = box
		barrier.add_child(shape)
		barrier.position = Vector3(mid.x, (barrier_top + bottom) * 0.5, mid.z)
		barrier.rotation = Vector3(0.0, yaw + PI * 0.5, 0.0)
		fence.add_child(barrier)
	_terrain.edit_bounds = yard


## Big backyard trees beyond the fence: a trunk and a few canopy balls each.
func _build_trees() -> void:
	var trees := Node3D.new()
	trees.name = "Trees"
	add_child(trees)
	var spots: Array[Vector2] = [
		Vector2(-2.0, -5.5),
		Vector2(1.5, -6.0),
		Vector2(4.5, -4.5),
		Vector2(6.0, -0.5),
		Vector2(5.5, 3.5),
		Vector2(-1.5, -9.0),
	]
	for spot: Vector2 in spots:
		var at := Vector3(_center.x + spot.x * _s, 0.0, _center.z + spot.y * _s)
		at.y = _dirt_height(_center) - 0.3 * _s
		var trunk_height: float = _rng.randf_range(4.0, 6.0) * _s
		var trunk_radius: float = _rng.randf_range(0.22, 0.32) * _s
		_cylinder(
			trees,
			"Trunk",
			trunk_radius,
			trunk_height,
			at + Vector3(0.0, trunk_height * 0.5, 0.0),
			Vector3.ZERO,
			_material(BARK_COLOR, 0.95, true)
		)
		var canopy_center: Vector3 = at + Vector3(0.0, trunk_height, 0.0)
		for index: int in 5:
			var radius: float = _rng.randf_range(1.8, 3.0) * _s
			var offset := (
				Vector3(
					_rng.randf_range(-1.6, 1.6),
					_rng.randf_range(-0.4, 1.6),
					_rng.randf_range(-1.6, 1.6)
				)
				* _s
			)
			var ball := MeshInstance3D.new()
			ball.name = "Canopy"
			var sphere := SphereMesh.new()
			sphere.radius = radius
			sphere.height = radius * 1.8
			sphere.radial_segments = 14
			sphere.rings = 8
			ball.mesh = sphere
			ball.material_override = _material(
				CANOPY_COLORS[_rng.randi() % CANOPY_COLORS.size()], 0.95
			)
			ball.position = canopy_center + offset
			trees.add_child(ball)


# --- Helpers ----------------------------------------------------------------------------------


func _dirt_height(point: Vector3) -> float:
	return _terrain.get_surface_height_at(Vector3(point.x, 0.0, point.z))


func _box(
	parent: Node3D, box_name: String, size: Vector3, position: Vector3, material: Material
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = box_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.position = position
	parent.add_child(mesh_instance)
	return mesh_instance


func _cylinder(
	parent: Node3D,
	cylinder_name: String,
	radius: float,
	length: float,
	position: Vector3,
	rotation_radians: Vector3,
	material: Material
) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = cylinder_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.position = position
	mesh_instance.rotation = rotation_radians
	parent.add_child(mesh_instance)


## A shared material per colour and roughness; vertex-coloured meshes multiply their colours in.
func _material(
	color: Color, roughness: float = 0.95, vertex_colors: bool = false
) -> StandardMaterial3D:
	var key: String = "%s|%.2f|%s" % [color.to_html(), roughness, vertex_colors]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE if vertex_colors else color
	material.vertex_color_use_as_albedo = vertex_colors
	material.roughness = roughness
	material.cull_mode = BaseMaterial3D.CULL_DISABLED if vertex_colors else BaseMaterial3D.CULL_BACK
	_materials[key] = material
	return material
