// Flying Edges-style mesher with per-chunk edge to vertex dedup. Samples live on a shared
// world grid (DensitySampler.build_chunk_field), so vertices and normals on a chunk face are
// computed from identical values by both neighbouring chunks.
#pragma once

#include "common.h"
#include "signed_density_field.h"
#include "world_density.h"

#include <godot_cpp/classes/array_mesh.hpp>

#include <vector>

namespace godot {

// A mesh as arrays (FlyingEdgesMesher.MeshResult in the scripts).
class TerrainMeshResult : public RefCounted {
	GDCLASS(TerrainMeshResult, RefCounted)

protected:
	static void _bind_methods();

public:
	PackedVector3Array vertices;
	PackedVector3Array normals;
	// Per vertex: the placed material on the solid side, or the ground's tint.
	PackedColorArray colors;
	PackedInt32Array indices;

	PackedVector3Array get_vertices() const { return vertices; }
	void set_vertices(const PackedVector3Array &v) { vertices = v; }
	PackedVector3Array get_normals() const { return normals; }
	void set_normals(const PackedVector3Array &v) { normals = v; }
	PackedColorArray get_colors() const { return colors; }
	void set_colors(const PackedColorArray &v) { colors = v; }
	PackedInt32Array get_indices() const { return indices; }
	void set_indices(const PackedInt32Array &v) { indices = v; }
};

class FlyingEdgesMesher : public RefCounted {
	GDCLASS(FlyingEdgesMesher, RefCounted)

protected:
	static void _bind_methods();

public:
	// Meshes the cells cell_first..cell_last (inclusive; a negative cell_last: all). With a
	// density, normals come from central differences of the sample grid and the colours from
	// the ground; without one, face normals. scratch (three ints a sample, -1 filled) is shared
	// by the blocks of one field; null makes one.
	static Ref<TerrainMeshResult> build(const Ref<SignedDensityField> &field, double chunk_extent, double iso_level,
			const Vector3i &grid_offset, const Vector3 &grid_world_origin, const Vector3 &chunk_world_center,
			WorldDensity *density, Vector3i cell_first, Vector3i cell_last, std::vector<int> *scratch);

	static Ref<TerrainMeshResult> build_mesh(const Ref<SignedDensityField> &field, double chunk_extent,
			double iso_level = 0.0, const Vector3i &grid_offset = Vector3i(), const Vector3 &grid_world_origin = Vector3(),
			const Vector3 &chunk_world_center = Vector3(), const Ref<WorldDensity> &density = Ref<WorldDensity>(),
			const Vector3i &cell_first = Vector3i(), const Vector3i &cell_last = Vector3i(-1, -1, -1));
	static Ref<ArrayMesh> to_array_mesh(const Ref<TerrainMeshResult> &mesh_result);
};

} // namespace godot
