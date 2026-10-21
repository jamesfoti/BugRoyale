@tool
class_name GlassBowl
extends Node3D
## Round glass terrarium: a sphere with its top cut open, like a fish bowl. Built from a sphere
## band mesh (two-sided glass) with matching trimesh collision so bugs can't crawl out. The node
## sits at the bowl's center.

const WALL_COLLISION_LAYER: int = 1
const RINGS: int = 22
const SEGMENTS: int = 40

var radius: float = 1.0
## Opening radius as a fraction of the sphere radius (0.8 cuts the top at 60% of the height).
var opening_ratio: float = 0.8


static func create(bowl_radius: float, bowl_opening_ratio: float = 0.8) -> GlassBowl:
	var bowl := GlassBowl.new()
	bowl.name = "GlassBowl"
	bowl.radius = maxf(bowl_radius, 0.1)
	bowl.opening_ratio = clampf(bowl_opening_ratio, 0.2, 0.98)
	bowl.rebuild()
	return bowl


## Height of the rim above the bowl's center.
func get_rim_height() -> float:
	return radius * sqrt(1.0 - opening_ratio * opening_ratio)


func rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	add_sphere_band(st, radius, -radius, get_rim_height(), RINGS, SEGMENTS, false)
	var mesh: ArrayMesh = st.commit()

	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	glass.mesh = mesh
	glass.material_override = GlassBox._create_glass_material(true)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)

	var body := StaticBody3D.new()
	body.name = "GlassCollider"
	body.collision_layer = WALL_COLLISION_LAYER
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())
	# Trimesh collision is one-sided and these faces point outward; bugs are on the inside.
	shape.backface_collision = true
	shape_node.shape = shape
	body.add_child(shape_node)
	add_child(body)


## Adds the part of a sphere (centered at origin) between two heights (relative to the center)
## as triangles with outward normals, wound for Godot's clockwise front faces (flipped if
## inside_out).
static func add_sphere_band(
	st: SurfaceTool,
	sphere_radius: float,
	y_bottom: float,
	y_top: float,
	rings: int,
	segments: int,
	inside_out: bool,
	origin: Vector3 = Vector3.ZERO
) -> void:
	var phi_top: float = acos(clampf(y_top / sphere_radius, -1.0, 1.0))
	var phi_bottom: float = acos(clampf(y_bottom / sphere_radius, -1.0, 1.0))
	for ring: int in rings:
		var phi0: float = lerpf(phi_top, phi_bottom, float(ring) / rings)
		var phi1: float = lerpf(phi_top, phi_bottom, float(ring + 1) / rings)
		for segment: int in segments:
			var theta0: float = TAU * segment / segments
			var theta1: float = TAU * (segment + 1) / segments
			var a: Vector3 = _sphere_point(phi0, theta0)
			var b: Vector3 = _sphere_point(phi0, theta1)
			var c: Vector3 = _sphere_point(phi1, theta1)
			var d: Vector3 = _sphere_point(phi1, theta0)
			_sphere_triangle(st, sphere_radius, a, b, c, inside_out, origin)
			_sphere_triangle(st, sphere_radius, a, c, d, inside_out, origin)


## Adds a flat disc at a height, facing up (or down).
static func add_disc(st: SurfaceTool, disc_radius: float, y: float, segments: int, face_up: bool) -> void:
	var normal: Vector3 = Vector3.UP if face_up else Vector3.DOWN
	var center := Vector3(0.0, y, 0.0)
	for segment: int in segments:
		var theta0: float = TAU * segment / segments
		var theta1: float = TAU * (segment + 1) / segments
		var a := Vector3(cos(theta0) * disc_radius, y, sin(theta0) * disc_radius)
		var b := Vector3(cos(theta1) * disc_radius, y, sin(theta1) * disc_radius)
		var points: Array[Vector3] = [center, a, b]
		if not face_up:
			points = [center, b, a]
		for point: Vector3 in points:
			st.set_normal(normal)
			st.set_uv(Vector2(point.x, point.z) / maxf(disc_radius * 2.0, 0.001) + Vector2(0.5, 0.5))
			st.add_vertex(point)


static func _sphere_point(phi: float, theta: float) -> Vector3:
	return Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))


static func _sphere_triangle(
	st: SurfaceTool, sphere_radius: float, a: Vector3, b: Vector3, c: Vector3, inside_out: bool, origin: Vector3
) -> void:
	# Unit directions double as normals. Godot front faces wind clockwise seen from outside, so
	# the right-hand normal of a front face points inward; flip when it doesn't.
	var outward: Vector3 = a + b + c
	var right_hand: Vector3 = (b - a).cross(c - a)
	var flip: bool = right_hand.dot(outward) > 0.0
	if inside_out:
		flip = not flip
	var order: Array[Vector3] = [a, b, c]
	if flip:
		order = [a, c, b]
	for direction: Vector3 in order:
		st.set_normal(-direction if inside_out else direction)
		st.set_uv(Vector2(atan2(direction.z, direction.x) / TAU + 0.5, acos(clampf(direction.y, -1.0, 1.0)) / PI))
		st.add_vertex(origin + direction * sphere_radius)
