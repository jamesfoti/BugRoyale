#include "flying_edges_mesher.h"

#include "density_sampler.h"
#include "flying_edges_tables.h"
#include "materials.h"

#include <godot_cpp/classes/mesh.hpp>

#include <unordered_map>

namespace godot {

namespace {

// Per-edge lower corner (cell-local) and axis (0 = x, 1 = y, 2 = z), for corners 0..7 =
// (0,0,0) (1,0,0) (1,0,1) (0,0,1) (0,1,0) (1,1,0) (1,1,1) (0,1,1).
const Vector3i EDGE_LOWER_CORNER[12] = {
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
};
const int EDGE_AXIS[12] = { 0, 2, 0, 2, 0, 2, 0, 2, 1, 1, 1, 1 };

// Reads samples by local grid coordinate; up to two steps outside the chunk (the normals on
// and near its faces) they are evaluated from the density and cached.
struct FieldReader {
	const float *values = nullptr;
	Vector3i size;
	int stride_y = 0;
	int stride_z = 0;
	WorldDensity *density = nullptr;
	Vector3 grid_world_origin;
	Vector3i grid_offset;
	double step = 1.0;
	std::unordered_map<Vector3i, double, Vector3iHash> outside;

	double sample(int x, int y, int z) {
		if (x >= 0 && y >= 0 && z >= 0 && x < size.x && y < size.y && z < size.z) {
			return values[x + y * stride_y + z * stride_z];
		}
		Vector3i key(x, y, z);
		auto found = outside.find(key);
		if (found != outside.end()) {
			return found->second;
		}
		Vector3 world_pos = DensitySampler::grid_sample_position(grid_world_origin, grid_offset + key, step);
		double value = density->evaluate(world_pos);
		outside[key] = value;
		return value;
	}

	// Central differences over one step and over two, blended.
	Vector3 gradient(int x, int y, int z) {
		double gx = (sample(x + 1, y, z) - sample(x - 1, y, z)) * 0.5 + (sample(x + 2, y, z) - sample(x - 2, y, z)) * 0.25;
		double gy = (sample(x, y + 1, z) - sample(x, y - 1, z)) * 0.5 + (sample(x, y + 2, z) - sample(x, y - 2, z)) * 0.25;
		double gz = (sample(x, y, z + 1) - sample(x, y, z - 1)) * 0.5 + (sample(x, y, z + 2) - sample(x, y, z - 2)) * 0.25;
		return v3(gx, gy, gz);
	}
};

struct Builder {
	std::vector<Vector3> vertices;
	std::vector<Vector3> normals;
	std::vector<Color> colors;
	std::vector<int32_t> indices;
};

int create_edge_vertex(const float *values, int lower_index, const Vector3i &lower_corner, int axis, int stride_y,
		int stride_z, double iso, const Vector3i &grid_offset, double world_step, const Vector3 &center_offset,
		FieldReader *reader, TerrainEdits *material_edits, TerrainEdits *dug_edits, const Vector3 &grid_world_origin,
		Builder &result) {
	Vector3i axis_step;
	int upper_index = lower_index;
	if (axis == 0) {
		axis_step = Vector3i(1, 0, 0);
		upper_index += 1;
	} else if (axis == 1) {
		axis_step = Vector3i(0, 1, 0);
		upper_index += stride_y;
	} else {
		axis_step = Vector3i(0, 0, 1);
		upper_index += stride_z;
	}
	double lower_value = values[lower_index];
	double upper_value = values[upper_index];
	double denom = upper_value - lower_value;
	double t = 0.5;
	if (std::abs(denom) >= 0.00001) {
		t = tmath::clampd((iso - lower_value) / denom, 0.0, 1.0);
	}
	Vector3i global = grid_offset + lower_corner;
	Vector3 global_lower = Vector3((real_t)global.x, (real_t)global.y, (real_t)global.z);
	Vector3 axis_f = Vector3((real_t)axis_step.x, (real_t)axis_step.y, (real_t)axis_step.z);
	Vector3 grid_pos = global_lower + axis_f * (real_t)t;
	int index = (int)result.vertices.size();
	result.vertices.push_back(grid_pos * (real_t)world_step - center_offset);

	Color vertex_color = mat::natural_vertex_color();
	if (reader != nullptr && reader->density != nullptr) {
		WorldDensity *density = reader->density;
		Vector3 solid_corner = global_lower;
		Vector3 air_corner = global_lower + axis_f;
		double solid_value = lower_value;
		if (lower_value >= iso) {
			solid_corner = air_corner;
			air_corner = global_lower;
			solid_value = upper_value;
		}
		Vector3 solid_position = grid_world_origin + solid_corner * (real_t)world_step;
		int kind = mat::NATURAL;
		if (material_edits != nullptr) {
			kind = material_edits->material_at(solid_position);
		}
		bool dug = false;
		if (kind == mat::NATURAL && dug_edits != nullptr) {
			Vector3 air_position = grid_world_origin + air_corner * (real_t)world_step;
			dug = dug_edits->is_overridden_at(air_position) && density->evaluate(air_position, false) < iso;
			if (dug) {
				Vector3 vertex_position = grid_world_origin + grid_pos * (real_t)world_step;
				kind = density->ground_material(vertex_position, density->evaluate(vertex_position, false));
			}
		}
		if (kind == mat::NATURAL) {
			vertex_color = density->natural_tint(solid_position, solid_value);
			if (dug && vertex_color.a > 0.0f) {
				vertex_color = mat::vertex_color(mat::DIRT);
			}
		} else {
			vertex_color = mat::vertex_color(kind);
		}
	}
	result.colors.push_back(vertex_color);

	if (reader != nullptr) {
		Vector3i upper_corner = lower_corner + axis_step;
		Vector3 gradient = reader->gradient(lower_corner.x, lower_corner.y, lower_corner.z)
								   .lerp(reader->gradient(upper_corner.x, upper_corner.y, upper_corner.z), (real_t)t);
		if (gradient.length_squared() > 0.0000000001) {
			result.normals.push_back(gradient.normalized());
		} else {
			result.normals.push_back(Vector3(0, 1, 0));
		}
	}
	return index;
}

void compute_face_normals(Builder &mesh) {
	mesh.normals.assign(mesh.vertices.size(), Vector3());
	for (size_t i = 0; i < mesh.indices.size() / 3; i++) {
		int i0 = mesh.indices[i * 3];
		int i1 = mesh.indices[i * 3 + 1];
		int i2 = mesh.indices[i * 3 + 2];
		Vector3 v0 = mesh.vertices[i0];
		Vector3 v1 = mesh.vertices[i1];
		Vector3 v2 = mesh.vertices[i2];
		Vector3 face_normal = (v1 - v0).cross(v2 - v0);
		mesh.normals[i0] += face_normal;
		mesh.normals[i1] += face_normal;
		mesh.normals[i2] += face_normal;
	}
	for (Vector3 &n : mesh.normals) {
		if (n.length_squared() > 0.000001) {
			n = n.normalized();
		} else {
			n = Vector3(0, 1, 0);
		}
	}
}

template <typename P, typename T>
P to_packed(const std::vector<T> &source) {
	P out;
	out.resize((int64_t)source.size());
	if (!source.empty()) {
		memcpy(out.ptrw(), source.data(), source.size() * sizeof(T));
	}
	return out;
}

} // namespace

Ref<TerrainMeshResult> FlyingEdgesMesher::build(const Ref<SignedDensityField> &field_ref, double chunk_extent,
		double iso_level, const Vector3i &grid_offset, const Vector3 &grid_world_origin,
		const Vector3 &chunk_world_center, WorldDensity *density, Vector3i cell_first, Vector3i cell_last,
		std::vector<int> *scratch) {
	Ref<TerrainMeshResult> out;
	out.instantiate();
	const SignedDensityField *field = field_ref.ptr();
	if (!field->is_valid()) {
		return out;
	}
	if (field->min_value >= iso_level || field->max_value < iso_level) {
		return out;
	}
	Vector3i cells = field->cell_counts();
	if (cell_last.x < 0) {
		cell_last = cells - Vector3i(1, 1, 1);
	}
	cell_first = cell_first.max(Vector3i());
	cell_last = cell_last.min(cells - Vector3i(1, 1, 1));
	double world_step = chunk_extent / (double)cells.x;
	const float *values = field->values.ptr();
	int stride_y = field->size.x;
	int stride_z = field->size.x * field->size.y;
	int64_t sample_count = field->values.size();

	TerrainEdits *material_edits = nullptr;
	TerrainEdits *dug_edits = nullptr;
	if (density != nullptr && density->terrain_edits.is_valid()) {
		if (density->terrain_edits->has_materials()) {
			material_edits = density->terrain_edits.ptr();
		}
		if (density->terrain_edits->get_override_count() > 0) {
			dug_edits = density->terrain_edits.ptr();
		}
	}
	FieldReader reader_storage;
	FieldReader *reader = nullptr;
	if (density != nullptr) {
		reader = &reader_storage;
		reader->values = values;
		reader->size = field->size;
		reader->stride_y = stride_y;
		reader->stride_z = stride_z;
		reader->density = density;
		reader->grid_world_origin = grid_world_origin;
		reader->grid_offset = grid_offset;
		reader->step = world_step;
	}

	std::vector<int> own_scratch;
	std::vector<int> *edge_vertex_index = scratch;
	if (edge_vertex_index == nullptr || (int64_t)edge_vertex_index->size() != sample_count * 3) {
		own_scratch.assign(sample_count * 3, -1);
		edge_vertex_index = &own_scratch;
	} else {
		for (int z = cell_first.z; z < cell_last.z + 2; z++) {
			for (int y = cell_first.y; y < cell_last.y + 2; y++) {
				int row_start = (cell_first.x + y * stride_y + z * stride_z) * 3;
				int row_end = (cell_last.x + 2 + y * stride_y + z * stride_z) * 3;
				for (int key = row_start; key < row_end; key++) {
					(*edge_vertex_index)[key] = -1;
				}
			}
		}
	}
	int *edge_index = edge_vertex_index->data();
	int edge_lower_offset[12];
	for (int edge_id = 0; edge_id < 12; edge_id++) {
		const Vector3i &lower = EDGE_LOWER_CORNER[edge_id];
		edge_lower_offset[edge_id] = lower.x + lower.y * stride_y + lower.z * stride_z;
	}
	Vector3 center_offset = chunk_world_center - grid_world_origin;
	int cell_edge_vertices[12];
	Builder result;

	for (int z = cell_first.z; z < cell_last.z + 1; z++) {
		for (int y = cell_first.y; y < cell_last.y + 1; y++) {
			int row_base = y * stride_y + z * stride_z;
			for (int x = cell_first.x; x < cell_last.x + 1; x++) {
				int i0 = row_base + x;
				int case_index = 0;
				if ((double)values[i0] < iso_level) {
					case_index |= 1;
				}
				if ((double)values[i0 + 1] < iso_level) {
					case_index |= 2;
				}
				if ((double)values[i0 + 1 + stride_z] < iso_level) {
					case_index |= 4;
				}
				if ((double)values[i0 + stride_z] < iso_level) {
					case_index |= 8;
				}
				if ((double)values[i0 + stride_y] < iso_level) {
					case_index |= 16;
				}
				if ((double)values[i0 + 1 + stride_y] < iso_level) {
					case_index |= 32;
				}
				if ((double)values[i0 + 1 + stride_y + stride_z] < iso_level) {
					case_index |= 64;
				}
				if ((double)values[i0 + stride_y + stride_z] < iso_level) {
					case_index |= 128;
				}
				if (case_index == 0 || case_index == 255) {
					continue;
				}
				int edge_mask = fe_tables::EDGE_TABLE[case_index];
				for (int edge_id = 0; edge_id < 12; edge_id++) {
					if ((edge_mask & (1 << edge_id)) == 0) {
						cell_edge_vertices[edge_id] = -1;
						continue;
					}
					int lower_index = i0 + edge_lower_offset[edge_id];
					int axis = EDGE_AXIS[edge_id];
					int key = lower_index * 3 + axis;
					int vertex_index = edge_index[key];
					if (vertex_index < 0) {
						Vector3i lower_corner = Vector3i(x, y, z) + EDGE_LOWER_CORNER[edge_id];
						vertex_index = create_edge_vertex(values, lower_index, lower_corner, axis, stride_y, stride_z,
								iso_level, grid_offset, world_step, center_offset, reader, material_edits, dug_edits,
								grid_world_origin, result);
						edge_index[key] = vertex_index;
					}
					cell_edge_vertices[edge_id] = vertex_index;
				}
				const int *row = fe_tables::TRI_TABLE[case_index];
				int tri_i = 0;
				while (tri_i < 16 && row[tri_i] != -1) {
					int i_a = cell_edge_vertices[row[tri_i]];
					int i_b = cell_edge_vertices[row[tri_i + 1]];
					int i_c = cell_edge_vertices[row[tri_i + 2]];
					if (i_a >= 0 && i_b >= 0 && i_c >= 0) {
						// Wound for "inside = below iso"; flipped for Godot's outward CCW.
						result.indices.push_back(i_a);
						result.indices.push_back(i_c);
						result.indices.push_back(i_b);
					}
					tri_i += 3;
				}
			}
		}
	}
	if (reader == nullptr) {
		compute_face_normals(result);
	}
	out->vertices = to_packed<PackedVector3Array>(result.vertices);
	out->normals = to_packed<PackedVector3Array>(result.normals);
	out->colors = to_packed<PackedColorArray>(result.colors);
	out->indices = to_packed<PackedInt32Array>(result.indices);
	return out;
}

Ref<TerrainMeshResult> FlyingEdgesMesher::build_mesh(const Ref<SignedDensityField> &field, double chunk_extent,
		double iso_level, const Vector3i &grid_offset, const Vector3 &grid_world_origin,
		const Vector3 &chunk_world_center, const Ref<WorldDensity> &density, const Vector3i &cell_first,
		const Vector3i &cell_last) {
	return build(field, chunk_extent, iso_level, grid_offset, grid_world_origin, chunk_world_center,
			density.is_valid() ? density.ptr() : nullptr, cell_first, cell_last, nullptr);
}

Ref<ArrayMesh> FlyingEdgesMesher::to_array_mesh(const Ref<TerrainMeshResult> &mesh_result) {
	Ref<ArrayMesh> mesh;
	mesh.instantiate();
	if (mesh_result.is_null() || mesh_result->vertices.is_empty() || mesh_result->indices.is_empty()) {
		return mesh;
	}
	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = mesh_result->vertices;
	arrays[Mesh::ARRAY_NORMAL] = mesh_result->normals;
	if (mesh_result->colors.size() == mesh_result->vertices.size()) {
		arrays[Mesh::ARRAY_COLOR] = mesh_result->colors;
	}
	arrays[Mesh::ARRAY_INDEX] = mesh_result->indices;
	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
	return mesh;
}

void TerrainMeshResult::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_vertices"), &TerrainMeshResult::get_vertices);
	ClassDB::bind_method(D_METHOD("set_vertices", "value"), &TerrainMeshResult::set_vertices);
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_VECTOR3_ARRAY, "vertices"), "set_vertices", "get_vertices");
	ClassDB::bind_method(D_METHOD("get_normals"), &TerrainMeshResult::get_normals);
	ClassDB::bind_method(D_METHOD("set_normals", "value"), &TerrainMeshResult::set_normals);
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_VECTOR3_ARRAY, "normals"), "set_normals", "get_normals");
	ClassDB::bind_method(D_METHOD("get_colors"), &TerrainMeshResult::get_colors);
	ClassDB::bind_method(D_METHOD("set_colors", "value"), &TerrainMeshResult::set_colors);
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_COLOR_ARRAY, "colors"), "set_colors", "get_colors");
	ClassDB::bind_method(D_METHOD("get_indices"), &TerrainMeshResult::get_indices);
	ClassDB::bind_method(D_METHOD("set_indices", "value"), &TerrainMeshResult::set_indices);
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_INT32_ARRAY, "indices"), "set_indices", "get_indices");
}

void FlyingEdgesMesher::_bind_methods() {
	ClassDB::bind_static_method("FlyingEdgesMesher",
			D_METHOD("build_mesh", "field", "chunk_extent", "iso_level", "grid_offset", "grid_world_origin",
					"chunk_world_center", "density", "cell_first", "cell_last"),
			&FlyingEdgesMesher::build_mesh, DEFVAL(0.0), DEFVAL(Vector3i()), DEFVAL(Vector3()), DEFVAL(Vector3()),
			DEFVAL(Ref<WorldDensity>()), DEFVAL(Vector3i()), DEFVAL(Vector3i(-1, -1, -1)));
	ClassDB::bind_static_method("FlyingEdgesMesher", D_METHOD("to_array_mesh", "mesh_result"), &FlyingEdgesMesher::to_array_mesh);
}

} // namespace godot
