#include "chunk_mesh_blocks.h"

#include "density_sampler.h"

namespace godot {

Ref<ChunkMeshBlocks> ChunkMeshBlocks::build_native(const Ref<SignedDensityField> &field, double chunk_extent,
		double iso_level, const Vector3i &grid_offset, const Vector3 &grid_world_origin,
		const Vector3 &chunk_world_center, WorldDensity *density, const Ref<ChunkMeshBlocks> &previous) {
	Ref<ChunkMeshBlocks> out;
	out.instantiate();
	Vector3i cells = field->cell_counts();
	out->per_axis = Vector3i(tmath::ceili((double)cells.x / BLOCK_CELLS), tmath::ceili((double)cells.y / BLOCK_CELLS),
			tmath::ceili((double)cells.z / BLOCK_CELLS));
	int count = out->per_axis.x * out->per_axis.y * out->per_axis.z;
	bool reuse = previous.is_valid() && previous->per_axis == out->per_axis && (int)previous->blocks.size() == count;
	std::vector<int> scratch(field->values.size() * 3, -1);
	int index = 0;
	for (int block_z = 0; block_z < out->per_axis.z; block_z++) {
		for (int block_y = 0; block_y < out->per_axis.y; block_y++) {
			for (int block_x = 0; block_x < out->per_axis.x; block_x++) {
				Vector3i first = Vector3i(block_x, block_y, block_z) * BLOCK_CELLS;
				Vector3i last = (first + Vector3i(1, 1, 1) * (BLOCK_CELLS - 1)).min(cells - Vector3i(1, 1, 1));
				if (reuse && !touches(first, last, field.ptr())) {
					out->blocks.push_back(previous->blocks[index]);
				} else {
					out->blocks.push_back(FlyingEdgesMesher::build(field, chunk_extent, iso_level, grid_offset,
							grid_world_origin, chunk_world_center, density, first, last, &scratch));
				}
				index += 1;
			}
		}
	}
	return out;
}

Ref<ChunkMeshBlocks> ChunkMeshBlocks::build(const Ref<SignedDensityField> &field, double chunk_extent,
		double iso_level, const Vector3i &grid_offset, const Vector3 &grid_world_origin,
		const Vector3 &chunk_world_center, const Ref<WorldDensity> &density, const Ref<ChunkMeshBlocks> &previous) {
	return build_native(field, chunk_extent, iso_level, grid_offset, grid_world_origin, chunk_world_center,
			density.is_valid() ? density.ptr() : nullptr, previous);
}

bool ChunkMeshBlocks::touches(const Vector3i &first, const Vector3i &last, const SignedDensityField *field) {
	return first.x <= field->changed_last.x && last.x + 1 >= field->changed_first.x &&
			first.y <= field->changed_last.y && last.y + 1 >= field->changed_first.y &&
			first.z <= field->changed_last.z && last.z + 1 >= field->changed_first.z;
}

int ChunkMeshBlocks::meshed_count() const {
	int count = 0;
	for (const Ref<TerrainMeshResult> &block : blocks) {
		if (!block->indices.is_empty()) {
			count += 1;
		}
	}
	return count;
}

Ref<TerrainMeshResult> ChunkMeshBlocks::merge() const {
	Ref<TerrainMeshResult> out;
	out.instantiate();
	int64_t vertex_total = 0;
	int64_t index_total = 0;
	for (const Ref<TerrainMeshResult> &block : blocks) {
		if (block->indices.is_empty()) {
			continue;
		}
		vertex_total += block->vertices.size();
		index_total += block->indices.size();
	}
	out->vertices.resize(vertex_total);
	out->normals.resize(vertex_total);
	out->colors.resize(vertex_total);
	out->indices.resize(index_total);
	Vector3 *vertices = out->vertices.ptrw();
	Vector3 *normals = out->normals.ptrw();
	Color *colors = out->colors.ptrw();
	int32_t *indices = out->indices.ptrw();
	int64_t base = 0;
	int64_t at = 0;
	for (const Ref<TerrainMeshResult> &block : blocks) {
		if (block->indices.is_empty()) {
			continue;
		}
		int64_t n = block->vertices.size();
		memcpy(vertices + base, block->vertices.ptr(), n * sizeof(Vector3));
		memcpy(normals + base, block->normals.ptr(), n * sizeof(Vector3));
		memcpy(colors + base, block->colors.ptr(), n * sizeof(Color));
		const int32_t *source = block->indices.ptr();
		for (int64_t i = 0; i < block->indices.size(); i++) {
			indices[at + i] = source[i] + (int32_t)base;
		}
		at += block->indices.size();
		base += n;
	}
	return out;
}

TypedArray<TerrainMeshResult> ChunkMeshBlocks::get_blocks() const {
	TypedArray<TerrainMeshResult> out;
	for (const Ref<TerrainMeshResult> &block : blocks) {
		out.push_back(block);
	}
	return out;
}

void ChunkMeshBlocks::_bind_methods() {
	ClassDB::bind_static_method("ChunkMeshBlocks",
			D_METHOD("build", "field", "chunk_extent", "iso_level", "grid_offset", "grid_world_origin",
					"chunk_world_center", "density", "previous"),
			&ChunkMeshBlocks::build, DEFVAL(Ref<ChunkMeshBlocks>()));
	ClassDB::bind_method(D_METHOD("meshed_count"), &ChunkMeshBlocks::meshed_count);
	ClassDB::bind_method(D_METHOD("merge"), &ChunkMeshBlocks::merge);
	ClassDB::bind_method(D_METHOD("get_per_axis"), &ChunkMeshBlocks::get_per_axis);
	ClassDB::bind_method(D_METHOD("get_blocks"), &ChunkMeshBlocks::get_blocks);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3I, "per_axis"), "", "get_per_axis");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "blocks"), "", "get_blocks");
	ClassDB::bind_integer_constant(get_class_static(), "", "BLOCK_CELLS", BLOCK_CELLS);
}

// --- Cave water ------------------------------------------------------------------------------

static Ref<TerrainMeshResult> cut_to_the_caves(const Ref<TerrainMeshResult> &sheet, const Ref<SignedDensityField> &field,
		WorldDensity *density, const Vector3 &corner, double step, const Vector3 &chunk_world_center) {
	Ref<TerrainMeshResult> kept;
	kept.instantiate();
	if (sheet->indices.is_empty()) {
		return kept;
	}
	int64_t vertex_count = sheet->vertices.size();
	const Vector3 *vertices = sheet->vertices.ptr();
	const Vector3 *normals = sheet->normals.ptr();
	std::vector<uint8_t> in_pool(vertex_count, 0);
	for (int64_t vertex = 0; vertex < vertex_count; vertex++) {
		Vector3 world = chunk_world_center + vertices[vertex];
		if (field->sample_world(world, corner, step) < 0.0) {
			continue;
		}
		double depth = density->sample_open_terrain_height(world.x, world.z) - (double)world.y;
		if (depth < CaveWaterMesher::SURFACE_MARGIN) {
			continue;
		}
		in_pool[vertex] = 1;
	}
	std::vector<int> remap(vertex_count, -1);
	const int32_t *indices = sheet->indices.ptr();
	int64_t index_count = sheet->indices.size();
	int64_t triangle = 0;
	while (triangle + 2 < index_count) {
		int a = indices[triangle];
		int b = indices[triangle + 1];
		int c = indices[triangle + 2];
		triangle += 3;
		if (in_pool[a] == 0 || in_pool[b] == 0 || in_pool[c] == 0) {
			continue;
		}
		Vector3 facing = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]);
		if (std::abs((double)facing.y) < 0.7 * (double)facing.length()) {
			continue;
		}
		int corners[3] = { a, b, c };
		for (int old : corners) {
			if (remap[old] < 0) {
				remap[old] = (int)kept->vertices.size();
				kept->vertices.push_back(vertices[old]);
				kept->normals.push_back(normals[old]);
			}
			kept->indices.push_back(remap[old]);
		}
	}
	return kept;
}

Ref<TerrainMeshResult> CaveWaterMesher::build_native(const Ref<SignedDensityField> &field, WorldDensity *density,
		const Vector3 &grid_world_origin, const Vector3i &grid_offset, double step, double chunk_extent,
		const Vector3 &chunk_world_center) {
	Ref<TerrainMeshResult> empty;
	empty.instantiate();
	if (density->caves.is_null()) {
		return empty;
	}
	CaveCarver *caves = density->caves.ptr();
	if (caves->water_top == -tmath::INF_D || !field->is_valid()) {
		return empty;
	}
	Vector3i size = field->size;
	Vector3 corner = DensitySampler::grid_sample_position(grid_world_origin, grid_offset, step);
	double bottom = (double)corner.y - step;
	double top = (double)corner.y + (double)(size.y - 1) * step + step;
	std::vector<float> levels(size.x * size.z);
	bool any_level = false;
	for (int z = 0; z < size.z; z++) {
		for (int x = 0; x < size.x; x++) {
			double level = caves->water_level((double)corner.x + (double)x * step, (double)corner.z + (double)z * step);
			levels[x + z * size.x] = (float)level;
			if (level > bottom && level < top) {
				any_level = true;
			}
		}
	}
	if (!any_level) {
		return empty;
	}
	Ref<SignedDensityField> water = SignedDensityField::make(size);
	PackedFloat32Array values = water->values;
	float *out = values.ptrw();
	double lowest = tmath::INF_D;
	double highest = -tmath::INF_D;
	int index = 0;
	for (int z = 0; z < size.z; z++) {
		for (int y = 0; y < size.y; y++) {
			double world_y = (double)corner.y + (double)y * step;
			for (int x = 0; x < size.x; x++) {
				double level = levels[x + z * size.x];
				double value = level == -tmath::INF_D ? DRY : world_y - level;
				out[index] = (float)value;
				lowest = tmath::mind(lowest, value);
				highest = tmath::maxd(highest, value);
				index += 1;
			}
		}
	}
	water->values = values;
	water->min_value = lowest;
	water->max_value = highest;
	Ref<TerrainMeshResult> sheet = FlyingEdgesMesher::build(water, chunk_extent, 0.0, grid_offset, grid_world_origin,
			chunk_world_center, nullptr, Vector3i(), Vector3i(-1, -1, -1), nullptr);
	return cut_to_the_caves(sheet, field, density, corner, step, chunk_world_center);
}

Ref<TerrainMeshResult> CaveWaterMesher::build(const Ref<SignedDensityField> &field, const Ref<WorldDensity> &density,
		const Vector3 &grid_world_origin, const Vector3i &grid_offset, double step, double chunk_extent,
		const Vector3 &chunk_world_center) {
	return build_native(field, density.ptr(), grid_world_origin, grid_offset, step, chunk_extent, chunk_world_center);
}

void CaveWaterMesher::_bind_methods() {
	ClassDB::bind_static_method("CaveWaterMesher",
			D_METHOD("build", "field", "density", "grid_world_origin", "grid_offset", "step", "chunk_extent",
					"chunk_world_center"),
			&CaveWaterMesher::build);
	ClassDB::bind_static_method("CaveWaterMesher", D_METHOD("surface_margin"), &CaveWaterMesher::surface_margin);
}

} // namespace godot
