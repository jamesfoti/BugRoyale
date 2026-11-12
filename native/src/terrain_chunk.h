// One meshed chunk: its mesh, its pools' sheet as a child, and its collision.
#pragma once

#include "chunk_mesh_builder.h"

#include <godot_cpp/classes/mesh_instance3d.hpp>

namespace godot {

class TerrainChunk : public MeshInstance3D {
	GDCLASS(TerrainChunk, MeshInstance3D)

protected:
	static void _bind_methods();

public:
	Vector3i chunk_coordinate;

	void rebuild(const Ref<TerrainSettings> &settings);
	// Takes a built mesh, and the collision for it unless this is the editor (nothing in the
	// editor walks on the ground, and every editor collision shape is drawn twice over).
	void apply_build_result(const Ref<ChunkBuildResult> &result, bool rebuild_collision);
	void update_collision();

	void set_chunk_coordinate(const Vector3i &v) { chunk_coordinate = v; }
	Vector3i get_chunk_coordinate() const { return chunk_coordinate; }

private:
	void apply_water(const Ref<TerrainMeshResult> &water_mesh_result);
	bool wants_collision() const;
	void create_trimesh_collision(const PackedVector3Array &faces);
};

} // namespace godot
