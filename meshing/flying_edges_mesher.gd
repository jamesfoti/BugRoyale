class_name FlyingEdgesMesher
extends RefCounted
## Flying Edges-style mesher with per-chunk edge→vertex dedup.
## Samples live on a shared world grid (see DensitySampler.build_chunk_field), so vertices and
## normals on a chunk face are computed from identical values by both neighbouring chunks.

## Per-edge lower corner (cell-local) and axis (0 = x, 1 = y, 2 = z), derived from
## FlyingEdgesTables.EDGE_CORNERS with corners 0..7 = (0,0,0) (1,0,0) (1,0,1) (0,0,1)
## (0,1,0) (1,1,0) (1,1,1) (0,1,1).
const _EDGE_LOWER_CORNER: Array[Vector3i] = [
	Vector3i(0, 0, 0),
	Vector3i(1, 0, 0),
	Vector3i(0, 0, 1),
	Vector3i(0, 0, 0),
	Vector3i(0, 1, 0),
	Vector3i(1, 1, 0),
	Vector3i(0, 1, 1),
	Vector3i(0, 1, 0),
	Vector3i(0, 0, 0),
	Vector3i(1, 0, 0),
	Vector3i(1, 0, 1),
	Vector3i(0, 0, 1),
]
const _EDGE_AXIS: PackedInt32Array = [0, 2, 0, 2, 0, 2, 0, 2, 1, 1, 1, 1]


## grid_world_origin + (grid_offset + local sample) * step is each sample's world position;
## vertices are returned relative to chunk_world_center. With a density, normals come from
## central differences of the sample grid; without one, from face normals.
static func build_mesh(
	field: SignedDensityField,
	chunk_extent: float,
	iso_level: float = 0.0,
	grid_offset: Vector3i = Vector3i.ZERO,
	grid_world_origin: Vector3 = Vector3.ZERO,
	chunk_world_center: Vector3 = Vector3.ZERO,
	density: DensitySampler.WorldDensity = null
) -> MeshResult:
	var result := MeshResult.new()
	if not field.is_valid():
		return result
	# Every sample on one side of the surface: no cell can produce triangles.
	if field.min_value >= iso_level or field.max_value < iso_level:
		return result

	var cells: Vector3i = field.cell_counts()
	var world_step: float = chunk_extent / float(cells.x)
	var tri_table: Array[PackedInt32Array] = FlyingEdgesTables.get_tri_table()
	var values: PackedFloat32Array = field.values
	var stride_y: int = field.size.x
	var stride_z: int = field.size.x * field.size.y

	# Placed materials colour the surface; skipped (every vertex natural) while none are placed.
	var material_edits: TerrainEdits = null
	if density != null and density.terrain_edits != null and density.terrain_edits.has_materials():
		material_edits = density.terrain_edits

	var reader: _FieldReader = null
	if density != null:
		reader = _FieldReader.new()
		reader.values = values
		reader.size = field.size
		reader.stride_y = stride_y
		reader.stride_z = stride_z
		reader.density = density
		reader.grid_world_origin = grid_world_origin
		reader.grid_offset = grid_offset
		reader.step = world_step

	# Edge vertex index keyed by (lower sample index * 3 + axis); -1 = not created yet.
	var edge_vertex_index: PackedInt32Array = PackedInt32Array()
	edge_vertex_index.resize(values.size() * 3)
	edge_vertex_index.fill(-1)
	var edge_lower_offset: PackedInt32Array = PackedInt32Array()
	edge_lower_offset.resize(12)
	for edge_id in 12:
		var lower: Vector3i = _EDGE_LOWER_CORNER[edge_id]
		edge_lower_offset[edge_id] = lower.x + lower.y * stride_y + lower.z * stride_z
	var center_offset: Vector3 = chunk_world_center - grid_world_origin
	var cell_edge_vertices: PackedInt32Array = PackedInt32Array()
	cell_edge_vertices.resize(12)

	for z in cells.z:
		for y in cells.y:
			var row_base: int = y * stride_y + z * stride_z
			for x in cells.x:
				var i0: int = row_base + x
				var case_index: int = 0
				if values[i0] < iso_level:
					case_index |= 1
				if values[i0 + 1] < iso_level:
					case_index |= 2
				if values[i0 + 1 + stride_z] < iso_level:
					case_index |= 4
				if values[i0 + stride_z] < iso_level:
					case_index |= 8
				if values[i0 + stride_y] < iso_level:
					case_index |= 16
				if values[i0 + 1 + stride_y] < iso_level:
					case_index |= 32
				if values[i0 + 1 + stride_y + stride_z] < iso_level:
					case_index |= 64
				if values[i0 + stride_y + stride_z] < iso_level:
					case_index |= 128
				if case_index == 0 or case_index == 255:
					continue

				var edge_mask: int = FlyingEdgesTables.EDGE_TABLE[case_index]
				for edge_id in 12:
					if (edge_mask & (1 << edge_id)) == 0:
						cell_edge_vertices[edge_id] = -1
						continue
					var lower_index: int = i0 + edge_lower_offset[edge_id]
					var axis: int = _EDGE_AXIS[edge_id]
					var key: int = lower_index * 3 + axis
					var vertex_index: int = edge_vertex_index[key]
					if vertex_index < 0:
						var lower_corner: Vector3i = Vector3i(x, y, z) + _EDGE_LOWER_CORNER[edge_id]
						vertex_index = _create_edge_vertex(
							values,
							lower_index,
							lower_corner,
							axis,
							stride_y,
							stride_z,
							iso_level,
							grid_offset,
							world_step,
							center_offset,
							reader,
							material_edits,
							grid_world_origin,
							result
						)
						edge_vertex_index[key] = vertex_index
					cell_edge_vertices[edge_id] = vertex_index

				var row: PackedInt32Array = tri_table[case_index]
				var tri_i: int = 0
				while tri_i < row.size() and row[tri_i] != -1:
					var i_a: int = cell_edge_vertices[row[tri_i]]
					var i_b: int = cell_edge_vertices[row[tri_i + 1]]
					var i_c: int = cell_edge_vertices[row[tri_i + 2]]
					if i_a >= 0 and i_b >= 0 and i_c >= 0:
						# Paul Bourke tables wound for "inside = below iso"; flip for Godot CCW outward.
						result.indices.append(i_a)
						result.indices.append(i_c)
						result.indices.append(i_b)
					tri_i += 3

	if reader == null:
		_compute_face_normals(result)
	return result


static func to_array_mesh(mesh_result: MeshResult) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if mesh_result.vertices.is_empty() or mesh_result.indices.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh_result.vertices
	arrays[Mesh.ARRAY_NORMAL] = mesh_result.normals
	if mesh_result.colors.size() == mesh_result.vertices.size():
		arrays[Mesh.ARRAY_COLOR] = mesh_result.colors
	arrays[Mesh.ARRAY_INDEX] = mesh_result.indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _create_edge_vertex(
	values: PackedFloat32Array,
	lower_index: int,
	lower_corner: Vector3i,
	axis: int,
	stride_y: int,
	stride_z: int,
	iso: float,
	grid_offset: Vector3i,
	world_step: float,
	center_offset: Vector3,
	reader: _FieldReader,
	material_edits: TerrainEdits,
	grid_world_origin: Vector3,
	result: MeshResult
) -> int:
	var axis_step: Vector3i = Vector3i.ZERO
	var upper_index: int = lower_index
	match axis:
		0:
			axis_step = Vector3i(1, 0, 0)
			upper_index += 1
		1:
			axis_step = Vector3i(0, 1, 0)
			upper_index += stride_y
		_:
			axis_step = Vector3i(0, 0, 1)
			upper_index += stride_z
	var lower_value: float = values[lower_index]
	var upper_value: float = values[upper_index]
	var denom: float = upper_value - lower_value
	var t: float = 0.5
	if absf(denom) >= 0.00001:
		t = clampf((iso - lower_value) / denom, 0.0, 1.0)

	# Global grid coordinates keep shared-face vertices identical across chunks.
	var global_lower: Vector3 = Vector3(grid_offset + lower_corner)
	var grid_pos: Vector3 = global_lower + Vector3(axis_step) * t
	var index: int = result.vertices.size()
	result.vertices.append(grid_pos * world_step - center_offset)

	# The vertex shows the material of the sample on its solid side.
	var vertex_color: Color = TerrainMaterials.NATURAL_VERTEX_COLOR
	if material_edits != null:
		var solid_corner: Vector3 = global_lower
		if lower_value >= iso:
			solid_corner += Vector3(axis_step)
		vertex_color = TerrainMaterials.vertex_color(
			material_edits.material_at(grid_world_origin + solid_corner * world_step)
		)
	result.colors.append(vertex_color)

	if reader != null:
		var upper_corner: Vector3i = lower_corner + axis_step
		var gradient: Vector3 = (
			reader
			. gradient(lower_corner.x, lower_corner.y, lower_corner.z)
			. lerp(reader.gradient(upper_corner.x, upper_corner.y, upper_corner.z), t)
		)
		if gradient.length_squared() > 0.0000000001:
			result.normals.append(gradient.normalized())
		else:
			result.normals.append(Vector3.UP)
	return index


static func _compute_face_normals(mesh_result: MeshResult) -> void:
	mesh_result.normals.resize(mesh_result.vertices.size())
	mesh_result.normals.fill(Vector3.ZERO)
	for i in mesh_result.indices.size() / 3:
		var i0: int = mesh_result.indices[i * 3]
		var i1: int = mesh_result.indices[i * 3 + 1]
		var i2: int = mesh_result.indices[i * 3 + 2]
		var v0: Vector3 = mesh_result.vertices[i0]
		var v1: Vector3 = mesh_result.vertices[i1]
		var v2: Vector3 = mesh_result.vertices[i2]
		var face_normal := (v1 - v0).cross(v2 - v0)
		mesh_result.normals[i0] += face_normal
		mesh_result.normals[i1] += face_normal
		mesh_result.normals[i2] += face_normal
	for i in mesh_result.normals.size():
		var n: Vector3 = mesh_result.normals[i]
		if n.length_squared() > 0.000001:
			mesh_result.normals[i] = n.normalized()
		else:
			mesh_result.normals[i] = Vector3.UP


class MeshResult:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	## Per vertex: the placed material on the solid side (TerrainMaterials.vertex_color, alpha 0),
	## or plain white where the terrain shader draws its own ground.
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()


## Reads samples by local grid coordinate. Coordinates one step outside the chunk (needed for
## central-difference normals on chunk faces) are evaluated from the density and cached.
class _FieldReader:
	var values: PackedFloat32Array
	var size: Vector3i
	var stride_y: int
	var stride_z: int
	var density: DensitySampler.WorldDensity
	var grid_world_origin: Vector3
	var grid_offset: Vector3i
	var step: float

	var _outside_samples: Dictionary = {}

	func sample(x: int, y: int, z: int) -> float:
		if x >= 0 and y >= 0 and z >= 0 and x < size.x and y < size.y and z < size.z:
			return values[x + y * stride_y + z * stride_z]
		var key: Vector3i = Vector3i(x, y, z)
		var cached: Variant = _outside_samples.get(key)
		if cached != null:
			return cached as float
		var world_pos: Vector3 = DensitySampler.grid_sample_position(
			grid_world_origin, grid_offset + key, step
		)
		var value: float = density.evaluate(world_pos)
		_outside_samples[key] = value
		return value

	func gradient(x: int, y: int, z: int) -> Vector3:
		return Vector3(
			sample(x + 1, y, z) - sample(x - 1, y, z),
			sample(x, y + 1, z) - sample(x, y - 1, z),
			sample(x, y, z + 1) - sample(x, y, z - 1)
		)
