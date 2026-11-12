#include "loose_rock.h"

#include "density_sampler.h"
#include "materials.h"

#include <vector>

namespace godot {

namespace {

constexpr int UNKNOWN = 0;
constexpr int AIR = 1;
constexpr int ROCK = 2;
constexpr int FIRST_LUMP = 3;
constexpr int HALO = LooseRock::HALO;

struct Pass {
	SignedDensityField *field = nullptr;
	WorldDensity *density = nullptr;
	Vector3 grid_world_origin;
	Vector3i grid_offset;
	double step = 1.0;
	int cells = 1;
	double iso = 0.0;
	int max_voxels = 0;
	float *values = nullptr;
	Vector3i padded;
	int stride_y = 0;
	int stride_z = 0;
	std::vector<int> state;
	std::vector<int> queue;
	std::vector<int> pending;

	Vector3i coordinates(int cell) const {
		return Vector3i(cell % stride_y, (cell % stride_z) / stride_y, cell / stride_z);
	}

	Vector3 world_position(int cell) const {
		return DensitySampler::grid_sample_position(grid_world_origin,
				grid_offset + coordinates(cell) - Vector3i(1, 1, 1) * HALO, step);
	}

	// Reaches a sample's six neighbours. False as soon as the lump is too big to clear or joins
	// rock already kept.
	bool spread(int cell, int lump) {
		int x = cell % stride_y;
		int y = (cell % stride_z) / stride_y;
		int z = cell / stride_z;
		int neighbours[6];
		bool present[6] = { x > 0, x < padded.x - 1, y > 0, y < padded.y - 1, z > 0, z < padded.z - 1 };
		neighbours[0] = cell - 1;
		neighbours[1] = cell + 1;
		neighbours[2] = cell - stride_y;
		neighbours[3] = cell + stride_y;
		neighbours[4] = cell - stride_z;
		neighbours[5] = cell + stride_z;
		for (int i = 0; i < 6; i++) {
			if (!present[i]) {
				continue;
			}
			int next = neighbours[i];
			int s = state[next];
			if (s == UNKNOWN) {
				pending.push_back(next);
			} else if (s == ROCK) {
				state[next] = lump;
				queue.push_back(next);
			} else if (s != AIR && s != lump) {
				return false;
			}
		}
		return (int)queue.size() <= max_voxels;
	}

	bool reach_into_halo(int lump) {
		while (!pending.empty()) {
			int halo_cell = pending.back();
			pending.pop_back();
			if (state[halo_cell] != UNKNOWN) {
				continue;
			}
			if (density->evaluate(world_position(halo_cell)) >= iso) {
				state[halo_cell] = AIR;
				continue;
			}
			state[halo_cell] = lump;
			queue.push_back(halo_cell);
			return true;
		}
		return false;
	}

	bool within_sight() const {
		Vector3i lowest = coordinates(queue[0]);
		Vector3i highest = lowest;
		for (int cell : queue) {
			Vector3i at = coordinates(cell);
			lowest = lowest.min(at);
			highest = highest.max(at);
		}
		for (int axis = 0; axis < 3; axis++) {
			int low = lowest[axis] - HALO + grid_offset[axis];
			int high = highest[axis] - HALO + grid_offset[axis];
			int first_chunk = -tmath::floor_div(-low, cells) - 1;
			int last_chunk = tmath::floor_div(high, cells);
			if (high > (first_chunk + 1) * cells + 1 || low < last_chunk * cells - 1) {
				return false;
			}
		}
		return true;
	}

	bool built() const {
		TerrainEdits *edits = density->terrain_edits.ptr();
		if (edits == nullptr || (edits->get_override_count() == 0 && !edits->has_materials())) {
			return false;
		}
		for (int cell : queue) {
			Vector3 at = world_position(cell);
			if (edits->material_at(at) != mat::NATURAL) {
				return true;
			}
			if (edits->is_overridden_at(at) && density->evaluate(at, false) >= iso) {
				return true;
			}
		}
		return false;
	}

	bool trace(int start, int lump) {
		queue.clear();
		pending.clear();
		queue.push_back(start);
		state[start] = lump;
		size_t head = 0;
		while (true) {
			while (head < queue.size()) {
				if (!spread(queue[head], lump)) {
					return false;
				}
				head += 1;
			}
			if (!within_sight()) {
				return false;
			}
			if (!reach_into_halo(lump)) {
				return !built();
			}
			if ((int)queue.size() > max_voxels) {
				return false;
			}
		}
		return false;
	}

	int clear_lump() {
		int cleared = 0;
		Vector3i size = field->size;
		for (int cell : queue) {
			state[cell] = AIR;
			Vector3i at = coordinates(cell) - Vector3i(1, 1, 1) * HALO;
			if (at.x < 0 || at.y < 0 || at.z < 0 || at.x >= size.x || at.y >= size.y || at.z >= size.z) {
				continue;
			}
			int index = at.x + at.y * size.x + at.z * size.x * size.y;
			values[index] = (float)(iso + (iso - (double)values[index]));
			field->mark_changed(at);
			cleared += 1;
		}
		return cleared;
	}

	int run() {
		Vector3i size = field->size;
		padded = size + Vector3i(1, 1, 1) * (HALO * 2);
		stride_y = padded.x;
		stride_z = padded.x * padded.y;
		state.assign(padded.x * padded.y * padded.z, UNKNOWN);
		int index = 0;
		for (int z = 0; z < size.z; z++) {
			for (int y = 0; y < size.y; y++) {
				int row = HALO + (y + HALO) * stride_y + (z + HALO) * stride_z;
				for (int x = 0; x < size.x; x++) {
					state[row + x] = (double)values[index] < iso ? ROCK : AIR;
					index += 1;
				}
			}
		}
		int cleared = 0;
		int lump = FIRST_LUMP;
		for (int z = 0; z < size.z; z++) {
			for (int y = 0; y < size.y; y++) {
				int row = HALO + (y + HALO) * stride_y + (z + HALO) * stride_z;
				for (int x = 0; x < size.x; x++) {
					int cell = row + x;
					if (state[cell] != ROCK) {
						continue;
					}
					int kept = state[cell - 1];
					if (kept < FIRST_LUMP) {
						kept = state[cell - stride_y];
						if (kept < FIRST_LUMP) {
							kept = state[cell - stride_z];
						}
					}
					if (kept >= FIRST_LUMP) {
						state[cell] = kept;
						continue;
					}
					if (trace(cell, lump)) {
						cleared += clear_lump();
					}
					lump += 1;
				}
			}
		}
		return cleared;
	}
};

} // namespace

int LooseRock::clear(const Ref<SignedDensityField> &field, const Ref<WorldDensity> &density,
		const Vector3 &grid_world_origin, const Vector3i &grid_offset, double step, int cells_per_axis,
		double iso_level, int max_voxels) {
	if (max_voxels <= 0 || !field->is_valid()) {
		return 0;
	}
	Pass pass;
	pass.field = field.ptr();
	pass.density = density.ptr();
	pass.grid_world_origin = grid_world_origin;
	pass.grid_offset = grid_offset;
	pass.step = step;
	pass.cells = cells_per_axis;
	pass.iso = iso_level;
	pass.max_voxels = max_voxels;
	PackedFloat32Array values = field->values;
	pass.values = values.ptrw();
	int cleared = pass.run();
	if (cleared > 0) {
		field->values = values;
		double min_value = tmath::INF_D;
		double max_value = -tmath::INF_D;
		const float *read = values.ptr();
		for (int64_t i = 0; i < values.size(); i++) {
			min_value = tmath::mind(min_value, read[i]);
			max_value = tmath::maxd(max_value, read[i]);
		}
		field->min_value = min_value;
		field->max_value = max_value;
	}
	return cleared;
}

void LooseRock::_bind_methods() {
	ClassDB::bind_static_method("LooseRock",
			D_METHOD("clear", "field", "density", "grid_world_origin", "grid_offset", "step", "cells_per_axis",
					"iso_level", "max_voxels"),
			&LooseRock::clear);
}

} // namespace godot
