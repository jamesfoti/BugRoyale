// A chunk's surface meshed in blocks of BLOCK_CELLS cells a side. A brush rebuild meshes only
// the blocks whose samples changed and keeps the rest from the chunk's last build; the blocks
// merge into one mesh for the chunk. A vertex on a block face is made by both blocks from the
// same samples, so the surface and its normals meet without a seam.
#pragma once

#include "flying_edges_mesher.h"

#include <vector>

namespace godot {

class ChunkMeshBlocks : public RefCounted {
	GDCLASS(ChunkMeshBlocks, RefCounted)

protected:
	static void _bind_methods();

public:
	static constexpr int BLOCK_CELLS = 8;

	Vector3i per_axis;
	std::vector<Ref<TerrainMeshResult>> blocks;

	static Ref<ChunkMeshBlocks> build_native(const Ref<SignedDensityField> &field, double chunk_extent, double iso_level,
			const Vector3i &grid_offset, const Vector3 &grid_world_origin, const Vector3 &chunk_world_center,
			WorldDensity *density, const Ref<ChunkMeshBlocks> &previous);
	static Ref<ChunkMeshBlocks> build(const Ref<SignedDensityField> &field, double chunk_extent, double iso_level,
			const Vector3i &grid_offset, const Vector3 &grid_world_origin, const Vector3 &chunk_world_center,
			const Ref<WorldDensity> &density, const Ref<ChunkMeshBlocks> &previous = Ref<ChunkMeshBlocks>());
	int meshed_count() const;
	Ref<TerrainMeshResult> merge() const;

	Vector3i get_per_axis() const { return per_axis; }
	TypedArray<TerrainMeshResult> get_blocks() const;

private:
	static bool touches(const Vector3i &first, const Vector3i &last, const SignedDensityField *field);
};

// The pools in the caves: a chunk's water surface, meshed from the aquifer levels its carver
// gives each column, as the zero crossing of height minus level, then cut back to where the
// ground's own field is air well under the surface.
class CaveWaterMesher : public RefCounted {
	GDCLASS(CaveWaterMesher, RefCounted)

protected:
	static void _bind_methods();

public:
	static constexpr double SURFACE_MARGIN = 4.0;
	static constexpr double DRY = 1000000.0;

	static Ref<TerrainMeshResult> build_native(const Ref<SignedDensityField> &field, WorldDensity *density,
			const Vector3 &grid_world_origin, const Vector3i &grid_offset, double step, double chunk_extent,
			const Vector3 &chunk_world_center);
	static Ref<TerrainMeshResult> build(const Ref<SignedDensityField> &field, const Ref<WorldDensity> &density,
			const Vector3 &grid_world_origin, const Vector3i &grid_offset, double step, double chunk_extent,
			const Vector3 &chunk_world_center);
	static double surface_margin() { return SURFACE_MARGIN; }
};

} // namespace godot
