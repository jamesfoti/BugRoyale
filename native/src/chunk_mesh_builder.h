// Thread-safe chunk mesh generation (no scene tree access): a chunk's field, its loose rock
// cleared, its mesh (in blocks for a brush rebuild), its collision triangles and its pools.
#pragma once

#include "chunk_mesh_blocks.h"
#include "common.h"
#include "flying_edges_mesher.h"
#include "terrain_settings.h"

#include <atomic>
#include <unordered_map>
#include <vector>

namespace godot {

class ChunkBuildResult : public RefCounted {
	GDCLASS(ChunkBuildResult, RefCounted)

protected:
	static void _bind_methods();

public:
	Ref<TerrainMeshResult> mesh_result;
	// The chunk's field as meshed, kept when the settings ask (a brush rebuild).
	Ref<SignedDensityField> field;
	// The chunk's mesh in blocks, kept with the field for the next stroke's partial remesh.
	Ref<ChunkMeshBlocks> blocks;
	// The pools' water sheet in this chunk, empty when there is none.
	Ref<TerrainMeshResult> water_mesh_result;
	Vector3 local_position;
	// The mesh's triangles for its collision shape, made on the worker.
	PackedVector3Array collision_faces;

	ChunkBuildResult();

	Ref<TerrainMeshResult> get_mesh_result() const { return mesh_result; }
	Ref<SignedDensityField> get_field() const { return field; }
	Ref<ChunkMeshBlocks> get_blocks() const { return blocks; }
	Ref<TerrainMeshResult> get_water_mesh_result() const { return water_mesh_result; }
	Vector3 get_local_position() const { return local_position; }
	PackedVector3Array get_collision_faces() const { return collision_faces; }
};

// A task's chunks and what came of them (the scripts' AsyncRebuildJob).
struct BuildJob {
	std::vector<Vector3i> chunk_coordinates;
	Ref<TerrainSettings> settings;
	std::vector<Ref<ChunkBuildResult>> results;
	bool rebuild_collision = false;
	// Build the field and mesh blocks for the chunk cache only (prepare_edit_around).
	bool prepare_only = false;
	int64_t task_id = -1;
	// The map's build: whether the results were taken off the pool, and how many of its
	// chunks the main thread has placed since.
	bool collected = false;
	int placed = 0;

	static void run(void *userdata);
};

class ChunkMeshBuilder : public RefCounted {
	GDCLASS(ChunkMeshBuilder, RefCounted)

protected:
	static void _bind_methods();

public:
	static Ref<ChunkBuildResult> build_chunk(const Vector3i &chunk_coordinate, const Ref<TerrainSettings> &settings);
	static void build_chunk_into(const Ref<ChunkBuildResult> &result, const Vector3i &chunk_coordinate,
			const Ref<TerrainSettings> &settings);
	static PackedVector3Array collision_faces(const Ref<TerrainMeshResult> &mesh_result);
	static Vector3 chunk_corner_local(const Vector3i &chunk_coordinate, const Ref<TerrainSettings> &settings);
	static Ref<WorldDensity> density_for(const Ref<TerrainSettings> &settings);
};

} // namespace godot
