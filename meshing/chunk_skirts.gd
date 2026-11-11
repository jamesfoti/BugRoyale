class_name ChunkSkirts
extends RefCounted
## Skirts: a strip of surface hung from every edge where a chunk's surface meets one of its
## faces, so a crack between two chunks that do not meet (a fine chunk beside a coarse one
## while the map builds, their surfaces a metre or two apart at the seam) is covered by
## whichever side stands higher. A skirt lies in the face's plane and runs from the edge into
## the solid side of the ground, under level ground straight down, into a cliff sideways;
## it stops at the first air the chunk's own samples show, so it never hangs into a cave
## that crosses the seam. Between two chunks that do meet, it lies inside the rock and is
## never seen. It faces out of the chunk only, toward the neighbour a crack is seen from, and
## is drawn but has no collision (the chunk's collision is made before it is added).

## Metres a skirt reaches at most: two coarse voxels, past the widest crack between a fine
## chunk and a coarse one.
const LENGTH: float = 2.0 * ChunkedTerrainWorld.COARSE_VOXEL


## Adds skirts to a chunk's mesh (vertices about the chunk's centre), from the field it was
## meshed from; extent is the chunk's size in metres.
static func add(
	mesh: FlyingEdgesMesher.MeshResult, field: SignedDensityField, extent: float, iso: float
) -> void:
	if mesh.indices.is_empty() or not field.is_valid():
		return
	var half: float = extent * 0.5
	var cells: Vector3i = field.cell_counts()
	var step: float = extent / float(maxi(cells.x, 1))
	var tolerance: float = step * 0.001
	var vertices: PackedVector3Array = mesh.vertices
	var normals: PackedVector3Array = mesh.normals
	var indices: PackedInt32Array = mesh.indices
	# Which faces each vertex lies on, a bit each: -x, +x, -y, +y, -z, +z.
	var on_face := PackedInt32Array()
	on_face.resize(vertices.size())
	for index: int in vertices.size():
		var vertex: Vector3 = vertices[index]
		var faces: int = 0
		for axis: int in 3:
			if absf(vertex[axis] + half) <= tolerance:
				faces |= 1 << (axis * 2)
			elif absf(vertex[axis] - half) <= tolerance:
				faces |= 1 << (axis * 2 + 1)
		on_face[index] = faces
	var done: Dictionary = {}
	for corner: int in indices.size():
		var a: int = indices[corner]
		var b: int = indices[corner - corner % 3 + (corner % 3 + 1) % 3]
		var shared: int = on_face[a] & on_face[b]
		if shared == 0:
			continue
		for bit: int in 6:
			if shared & (1 << bit) == 0:
				continue
			var key := Vector3i(mini(a, b), maxi(a, b), bit)
			if done.has(key):
				continue
			done[key] = true
			_hang(mesh, field, a, b, bit, half, step, iso, vertices, normals)


## Hangs one skirt from the edge a-b on a face (bit: axis * 2, plus 1 on the + side).
static func _hang(
	mesh: FlyingEdgesMesher.MeshResult,
	field: SignedDensityField,
	a: int,
	b: int,
	bit: int,
	half: float,
	step: float,
	iso: float,
	vertices: PackedVector3Array,
	normals: PackedVector3Array
) -> void:
	@warning_ignore("integer_division")
	var axis: int = bit / 2
	var face := Vector3.ZERO
	face[axis] = 1.0 if bit % 2 == 1 else -1.0
	# Into the ground within the face: against the surface's normal, flattened onto the face.
	var outward: Vector3 = normals[a] + normals[b]
	outward -= face * outward.dot(face)
	if outward.length_squared() < 0.000001:
		return
	var into: Vector3 = -outward.normalized()
	var top_a: Vector3 = vertices[a]
	var top_b: Vector3 = vertices[b]
	var reach_a: float = _reach(field, top_a, into, half, step, iso)
	var reach_b: float = _reach(field, top_b, into, half, step, iso)
	if reach_a <= 0.0 and reach_b <= 0.0:
		return
	var low_a: Vector3 = top_a + into * reach_a
	var low_b: Vector3 = top_b + into * reach_b
	# Front faces wind clockwise seen from the front, so (p1 - p0) x (p2 - p0) points away from
	# the viewer: away from the neighbour, into the chunk.
	var corners: Array[Vector3] = [top_a, top_b, low_b, low_a]
	var corner_normals: Array[Vector3] = [normals[a], normals[b], normals[b], normals[a]]
	if (top_b - top_a).cross(low_a - top_a).dot(face) > 0.0:
		corners = [top_b, top_a, low_a, low_b]
		corner_normals = [normals[b], normals[a], normals[a], normals[b]]
	var first: int = mesh.vertices.size()
	var color_a: Color = mesh.colors[a] if a < mesh.colors.size() else Color.WHITE
	var color_b: Color = mesh.colors[b] if b < mesh.colors.size() else Color.WHITE
	var corner_colors: Array[Color] = [color_a, color_b, color_b, color_a]
	if corners[0] != top_a:
		corner_colors = [color_b, color_a, color_a, color_b]
	for index: int in 4:
		mesh.vertices.append(corners[index])
		mesh.normals.append(corner_normals[index])
		if mesh.colors.size() > 0:
			mesh.colors.append(corner_colors[index])
	mesh.indices.append_array(
		PackedInt32Array([first, first + 1, first + 2, first, first + 2, first + 3])
	)


## How far a skirt reaches from a point on the surface along a direction in the face before
## the ground there turns to air (the field's samples, read trilinearly) or the face ends, at
## most LENGTH.
static func _reach(
	field: SignedDensityField,
	start: Vector3,
	direction: Vector3,
	half: float,
	step: float,
	iso: float
) -> float:
	var reached: float = 0.0
	var travelled: float = step
	while travelled <= LENGTH + 0.0001:
		var point: Vector3 = start + direction * travelled
		if (
			absf(point.x) > half + 0.0001
			or absf(point.y) > half + 0.0001
			or absf(point.z) > half + 0.0001
		):
			break
		if _sample(field, point, half, step) >= iso:
			break
		reached = travelled
		travelled += step
	return reached


## The field's value at a point about the chunk's centre, read trilinearly.
static func _sample(field: SignedDensityField, point: Vector3, half: float, step: float) -> float:
	var grid: Vector3 = (point + Vector3.ONE * half) / step
	var size: Vector3i = field.size
	var low := Vector3i(grid.floor()).clamp(Vector3i.ZERO, size - Vector3i(2, 2, 2))
	var t: Vector3 = (grid - Vector3(low)).clamp(Vector3.ZERO, Vector3.ONE)
	var values: PackedFloat32Array = field.values
	var stride_y: int = size.x
	var stride_z: int = size.x * size.y
	var base: int = low.x + low.y * stride_y + low.z * stride_z
	var c000: float = values[base]
	var c100: float = values[base + 1]
	var c010: float = values[base + stride_y]
	var c110: float = values[base + stride_y + 1]
	var c001: float = values[base + stride_z]
	var c101: float = values[base + stride_z + 1]
	var c011: float = values[base + stride_z + stride_y]
	var c111: float = values[base + stride_z + stride_y + 1]
	var x00: float = lerpf(c000, c100, t.x)
	var x10: float = lerpf(c010, c110, t.x)
	var x01: float = lerpf(c001, c101, t.x)
	var x11: float = lerpf(c011, c111, t.x)
	return lerpf(lerpf(x00, x10, t.y), lerpf(x01, x11, t.y), t.z)
