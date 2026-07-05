extends MeshInstance3D
class_name TerrainEditCursor
## Ring decal aligned to terrain surface under the mouse.


@export var edit_radius: float = 1.5
@export var ring_segments: int = 64
@export var ring_width: float = 0.25
@export var surface_lift: float = 0.08

var _destroy_color: Color = Color(1.0, 0.45, 0.15, 0.92)
var _add_color: Color = Color(0.25, 0.85, 1.0, 0.92)


func _ready() -> void:
	mesh = _build_ring_mesh()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true

	var standard_material: StandardMaterial3D = StandardMaterial3D.new()
	standard_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	standard_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	standard_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	standard_material.albedo_color = _destroy_color
	material_override = standard_material
	visible = false


func show_at(hit_position: Vector3, normal: Vector3, add_mode: bool) -> void:
	visible = true
	var surface_up: Vector3 = normal.normalized()
	var tangent: Vector3 = surface_up.cross(Vector3.UP)
	if tangent.length_squared() < 0.0001:
		tangent = surface_up.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var bitangent: Vector3 = tangent.cross(surface_up).normalized()
	global_transform = Transform3D(
		Basis(tangent, surface_up, bitangent),
		hit_position + surface_up * surface_lift
	)

	if material_override is StandardMaterial3D:
		var standard_material: StandardMaterial3D = material_override as StandardMaterial3D
		standard_material.albedo_color = _add_color if add_mode else _destroy_color


func hide_cursor() -> void:
	visible = false


func _build_ring_mesh() -> ArrayMesh:
	var inner_radius: float = maxf(edit_radius - ring_width, edit_radius * 0.5)
	var outer_radius: float = edit_radius
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()

	for segment_index: int in range(ring_segments + 1):
		var angle: float = TAU * float(segment_index) / float(ring_segments)
		var direction: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		vertices.append(direction * inner_radius)
		vertices.append(direction * outer_radius)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)

	for segment_index: int in range(ring_segments):
		var base_index: int = segment_index * 2
		indices.append_array([
			base_index,
			base_index + 1,
			base_index + 2,
			base_index + 1,
			base_index + 3,
			base_index + 2,
		])

	var mesh_arrays: Array = []
	mesh_arrays.resize(Mesh.ARRAY_MAX)
	mesh_arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh_arrays[Mesh.ARRAY_NORMAL] = normals
	mesh_arrays[Mesh.ARRAY_INDEX] = indices

	var ring_mesh: ArrayMesh = ArrayMesh.new()
	ring_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)
	return ring_mesh
