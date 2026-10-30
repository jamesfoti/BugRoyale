class_name MushroomMeshBuilder
extends RefCounted
## Procedural mushrooms, grown from a seed the way the terrain is grown from noise: a stem
## lathed from a tapered, slightly bent profile, a cap lathed from a species profile (dome,
## button or bell) with gills underneath, and vertex colours doing the painting: cap tint
## shading toward the apex, noise-placed spots on a toadstool, alternating gill stripes, and
## a pale stem. Everything is one mesh in unit scale (stem length 1), so callers scale it to
## the mushroom they want and get back the cap size for collision.

enum Species { TOADSTOOL, BUTTON, INKCAP }

const SIDES: int = 18
const STEM_RINGS: int = 6
const CAP_RINGS: int = 7
const GILL_RINGS: int = 3


## Builds one mushroom: {"mesh": ArrayMesh, "height", "cap_radius", "cap_y", "cap_height",
## "stem_radius"} in unit scale.
static func build(seed: int, species: Species) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 2.6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var stem_height: float
	var stem_top: float
	var cap_radius: float
	var cap_height: float
	var round_top: float
	var point_top: float
	var cap_color: Color
	var apex_color: Color
	var gill_color: Color
	var stem_color: Color
	var spots: bool = false
	var ring: bool = false
	match species:
		Species.TOADSTOOL:
			stem_height = 1.0
			stem_top = rng.randf_range(0.11, 0.14)
			cap_radius = rng.randf_range(0.55, 0.8)
			cap_height = cap_radius * rng.randf_range(0.5, 0.7)
			round_top = 1.0
			point_top = 1.0
			cap_color = Color(0.86, 0.14, 0.08)
			apex_color = Color(0.95, 0.28, 0.1)
			gill_color = Color(0.95, 0.9, 0.78)
			stem_color = Color(0.93, 0.9, 0.82)
			spots = true
			ring = true
		Species.BUTTON:
			stem_height = rng.randf_range(0.55, 0.7)
			stem_top = rng.randf_range(0.14, 0.18)
			cap_radius = rng.randf_range(0.42, 0.6)
			cap_height = cap_radius * rng.randf_range(0.75, 0.95)
			round_top = 1.25
			point_top = 0.9
			cap_color = Color(0.74, 0.55, 0.34)
			apex_color = Color(0.5, 0.33, 0.19)
			gill_color = Color(0.62, 0.42, 0.36)
			stem_color = Color(0.9, 0.84, 0.72)
		_:
			stem_height = rng.randf_range(1.3, 1.5)
			stem_top = rng.randf_range(0.07, 0.09)
			cap_radius = rng.randf_range(0.26, 0.36)
			cap_height = cap_radius * rng.randf_range(1.5, 1.9)
			round_top = 0.6
			point_top = 1.3
			cap_color = Color(0.74, 0.7, 0.62)
			apex_color = Color(0.45, 0.42, 0.38)
			gill_color = Color(0.32, 0.3, 0.32)
			stem_color = Color(0.86, 0.86, 0.82)

	# Stem: tapers up from a bulbous foot and leans a little.
	var lean := Vector2(rng.randf_range(-0.14, 0.14), rng.randf_range(-0.14, 0.14))
	var stem: Array = []
	for index: int in STEM_RINGS + 1:
		var t: float = float(index) / STEM_RINGS
		var radius: float = lerpf(stem_top * 1.45, stem_top, pow(t, 0.6))
		var shade: Color = stem_color * lerpf(0.78, 1.0, t)
		shade.a = 1.0
		stem.append({"r": radius, "y": t * stem_height, "color": shade, "offset": lean * t * t})
	_lathe(st, stem, true)
	if ring:
		var skirt: Array = [
			{
				"r": stem_top * 1.05,
				"y": stem_height * 0.74,
				"color": stem_color,
				"offset": lean * 0.55
			},
			{
				"r": stem_top * 1.9,
				"y": stem_height * 0.66,
				"color": stem_color * 0.92,
				"offset": lean * 0.55
			},
		]
		_lathe(st, skirt, true)

	# Gills: from the stem out to the rim, dished a little, in alternating stripes.
	var cap_offset: Vector2 = lean
	var rim_y: float = stem_height + cap_radius * 0.12
	var gills: Array = []
	for index: int in GILL_RINGS + 1:
		var t: float = float(index) / GILL_RINGS
		var radius: float = lerpf(stem_top, cap_radius, t)
		gills.append(
			{
				"r": radius,
				"y": lerpf(stem_height - 0.015, rim_y, t * t),
				"color": gill_color,
				"offset": cap_offset,
				"stripes": true
			}
		)
	_lathe(st, gills, false)

	# Cap: a lathed profile from the rim to the apex, tinted toward the apex, spotted by noise.
	var cap: Array = []
	for index: int in CAP_RINGS + 1:
		var a: float = float(index) / CAP_RINGS
		var angle: float = a * PI * 0.5
		var radius: float = cap_radius * pow(cos(angle), round_top)
		var y: float = rim_y + cap_height * pow(sin(angle), point_top)
		var shade: Color = cap_color.lerp(apex_color, a)
		cap.append(
			{
				"r": radius,
				"y": y,
				"color": shade,
				"offset": cap_offset,
				"spots": spots,
				"noise": noise
			}
		)
	_lathe(st, cap, true)

	st.index()
	return {
		"mesh": st.commit(),
		"height": rim_y + cap_height,
		"cap_radius": cap_radius,
		"cap_y": rim_y,
		"cap_height": cap_height,
		"stem_radius": stem_top,
	}


## Spins a profile of rings (radius, height, colour, sideways offset) into a surface. Normals
## come from the profile's slope; `outward` false flips them for an underside.
static func _lathe(st: SurfaceTool, profile: Array, outward: bool) -> void:
	var count: int = profile.size()
	for index: int in count - 1:
		var a: Dictionary = profile[index]
		var b: Dictionary = profile[index + 1]
		var slope_a: Vector2 = _slope(profile, index)
		var slope_b: Vector2 = _slope(profile, index + 1)
		for side: int in SIDES:
			var angle0: float = TAU * side / SIDES
			var angle1: float = TAU * (side + 1) / SIDES
			var points := PackedVector3Array(
				[
					_ring_point(a, angle0),
					_ring_point(a, angle1),
					_ring_point(b, angle1),
					_ring_point(b, angle0),
				]
			)
			var normals := PackedVector3Array(
				[
					_ring_normal(slope_a, angle0, outward),
					_ring_normal(slope_a, angle1, outward),
					_ring_normal(slope_b, angle1, outward),
					_ring_normal(slope_b, angle0, outward),
				]
			)
			var colors := PackedColorArray(
				[
					_ring_color(a, points[0], side),
					_ring_color(a, points[1], side),
					_ring_color(b, points[2], side),
					_ring_color(b, points[3], side),
				]
			)
			if float(b["r"]) < 0.0001:
				_triangle(
					st,
					PackedVector3Array([points[0], points[1], points[2]]),
					PackedVector3Array([normals[0], normals[1], normals[2]]),
					PackedColorArray([colors[0], colors[1], colors[2]])
				)
			else:
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


static func _ring_point(ring: Dictionary, angle: float) -> Vector3:
	var offset: Vector2 = ring.get("offset", Vector2.ZERO)
	return Vector3(
		cos(angle) * float(ring["r"]) + offset.x,
		float(ring["y"]),
		sin(angle) * float(ring["r"]) + offset.y
	)


## The profile's (dr, dy) direction at a ring, from its neighbours.
static func _slope(profile: Array, index: int) -> Vector2:
	var before: Dictionary = profile[maxi(index - 1, 0)]
	var after: Dictionary = profile[mini(index + 1, profile.size() - 1)]
	var slope := Vector2(
		float(after["r"]) - float(before["r"]), float(after["y"]) - float(before["y"])
	)
	if slope.length_squared() < 0.000001:
		return Vector2(0.0, 1.0)
	return slope.normalized()


## Surface normal for a lathed profile: perpendicular to the slope, spun to the side's angle.
static func _ring_normal(slope: Vector2, angle: float, outward: bool) -> Vector3:
	var radial: float = slope.y
	var vertical: float = -slope.x
	if not outward:
		radial = -radial
		vertical = -vertical
	return Vector3(cos(angle) * radial, vertical, sin(angle) * radial).normalized()


static func _ring_color(ring: Dictionary, point: Vector3, side: int) -> Color:
	var color: Color = ring["color"]
	if ring.get("stripes", false) and side % 2 == 1:
		color = color * 0.82
		color.a = 1.0
	if ring.get("spots", false):
		var noise: FastNoiseLite = ring["noise"]
		var sample: float = noise.get_noise_3d(point.x * 4.0, point.y * 4.0, point.z * 4.0)
		if sample > 0.28:
			color = color.lerp(Color(0.97, 0.95, 0.88), 0.9)
	return color


## Winds a triangle so its front faces along the given normals.
static func _triangle(
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
