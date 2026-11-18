#include "liquid_seed.h"

#include "cave_carver.h"
#include "chunk_mesh_builder.h"
#include "density_sampler.h"
#include "loose_rock.h"
#include "terrain_liquids.h"

namespace godot {

Ref<LiquidSeed> LiquidSeed::make(const Vector3i &p_chunk_coordinate, int p_cells) {
	Ref<LiquidSeed> seed;
	seed.instantiate();
	seed->chunk_coordinate = p_chunk_coordinate;
	seed->cells = MAX(p_cells, 1);
	seed->solid.resize(seed->cells * seed->cells * seed->cells);
	seed->solid.fill(0);
	return seed;
}

Ref<LiquidSeed> LiquidSeed::from_field(const Ref<SignedDensityField> &p_field, WorldDensity *p_density,
		const Vector3i &p_chunk_coordinate, int p_cells, const Vector3 &p_grid_world_origin, double p_step,
		double p_iso_level) {
	Ref<LiquidSeed> seed = make(p_chunk_coordinate, p_cells);
	const SignedDensityField *field = p_field.ptr();
	if (field == nullptr || !field->is_valid() || field->size.x < p_cells || field->size.y < p_cells ||
			field->size.z < p_cells) {
		return seed;
	}
	uint8_t *solid = seed->solid.ptrw();
	const float *values = field->values.ptr();
	for (int z = 0; z < p_cells; z++) {
		for (int y = 0; y < p_cells; y++) {
			for (int x = 0; x < p_cells; x++) {
				solid[seed->index(x, y, z)] = (double)values[field->index(x, y, z)] < p_iso_level ? 1 : 0;
			}
		}
	}
	if (p_density == nullptr) {
		return seed;
	}
	CaveCarver *caves = nullptr;
	if (!field->sky && p_density->caves.is_valid() && p_density->caves->water_top > -tmath::INF_D) {
		caves = p_density->caves.ptr();
	}
	LakeMap *lakes = p_density->lakes.is_valid() && p_density->lakes->get_lake_count() > 0 ? p_density->lakes.ptr() : nullptr;
	Vector3i grid_offset = p_chunk_coordinate * p_cells;
	double bottom_y = (double)p_grid_world_origin.y + (double)grid_offset.y * p_step - p_step * 0.5;
	double top_y = bottom_y + (double)p_cells * p_step;
	if (caves != nullptr && caves->water_top < bottom_y) {
		caves = nullptr;
	}
	if (caves == nullptr && lakes == nullptr) {
		return seed;
	}
	LocalVector<float> mass;
	bool any_water = false;
	for (int z = 0; z < p_cells; z++) {
		double world_z = (double)p_grid_world_origin.z + (double)(grid_offset.z + z) * p_step;
		for (int x = 0; x < p_cells; x++) {
			double world_x = (double)p_grid_world_origin.x + (double)(grid_offset.x + x) * p_step;
			double ground = p_density->open_terrain_enabled ? p_density->sample_open_terrain_height(world_x, world_z)
															 : tmath::INF_D;
			// The aquifer's pool: its cave air under the level, well under the surface.
			double level = caves != nullptr ? caves->water_level(world_x, world_z) : -tmath::INF_D;
			if (level > bottom_y) {
				level = tmath::mind(level, ground - SURFACE_MARGIN);
				for (int y = 0; y < p_cells; y++) {
					double fill = tmath::clampd((level - (bottom_y + (double)y * p_step)) / p_step, 0.0, 1.0);
					if (fill < (double)TerrainLiquids::MIN_MASS) {
						break;
					}
					int cell = seed->index(x, y, z);
					if (solid[cell] == 0) {
						fill_cell(mass, any_water, p_cells, cell, fill);
					}
				}
			}
			// The lake's water: the open cells from its level down to the ground, in a chunk that
			// reaches up near the ground at least (a cave under a lake's bed stays dry).
			double lake = lakes != nullptr ? lakes->level_at(world_x, world_z) : -tmath::INF_D;
			if (lake > bottom_y && top_y > ground - LAKE_REACH) {
				for (int y = p_cells - 1; y >= 0; y--) {
					double fill = tmath::clampd((lake - (bottom_y + (double)y * p_step)) / p_step, 0.0, 1.0);
					if (fill < (double)TerrainLiquids::MIN_MASS) {
						continue;
					}
					int cell = seed->index(x, y, z);
					if (solid[cell] != 0) {
						break;
					}
					fill_cell(mass, any_water, p_cells, cell, fill);
				}
			}
		}
	}
	if (any_water) {
		int count = p_cells * p_cells * p_cells;
		seed->mass.resize(count);
		seed->kind.resize(count);
		float *mass_out = seed->mass.ptrw();
		uint8_t *kind_out = seed->kind.ptrw();
		for (int cell = 0; cell < count; cell++) {
			mass_out[cell] = mass[cell];
			kind_out[cell] = mass[cell] > 0.0f ? TerrainLiquids::KIND_WATER : TerrainLiquids::KIND_NONE;
		}
	}
	return seed;
}

void LiquidSeed::fill_cell(LocalVector<float> &r_mass, bool &r_any_water, int p_cells, int p_cell, double p_fill) {
	if (!r_any_water) {
		r_any_water = true;
		r_mass.resize(p_cells * p_cells * p_cells);
		for (uint32_t cell = 0; cell < r_mass.size(); cell++) {
			r_mass[cell] = 0.0f;
		}
	}
	r_mass[p_cell] = MAX(r_mass[p_cell], (float)p_fill);
}

Ref<LiquidSeed> LiquidSeed::from_field_for(const Ref<SignedDensityField> &p_field, const Ref<WorldDensity> &p_density,
		const Vector3i &p_chunk_coordinate, int p_cells, const Vector3 &p_grid_world_origin, double p_step,
		double p_iso_level) {
	return from_field(p_field, p_density.ptr(), p_chunk_coordinate, p_cells, p_grid_world_origin, p_step, p_iso_level);
}

Ref<LiquidSeed> LiquidSeed::build(const Vector3i &p_chunk_coordinate, const Ref<TerrainSettings> &p_settings) {
	int cells = p_settings->cells_per_axis;
	double step = p_settings->chunk_world_size / (double)cells;
	Vector3 grid_world_origin = p_settings->world_origin + ChunkMeshBuilder::chunk_corner_local(Vector3i(), p_settings);
	Vector3i grid_offset = p_chunk_coordinate * cells;
	Ref<WorldDensity> density = ChunkMeshBuilder::density_for(p_settings);
	Ref<SignedDensityField> field = DensitySampler::build_chunk_field(density, Vector3i(1, 1, 1) * (cells + 1),
			grid_world_origin, grid_offset, step);
	if (p_settings->loose_rock_voxels > 0 && !field->sky && field->min_value < p_settings->iso_level &&
			field->max_value >= p_settings->iso_level) {
		LooseRock::clear(field, density, grid_world_origin, grid_offset, step, cells, p_settings->iso_level,
				p_settings->loose_rock_voxels);
	}
	return from_field(field, density.ptr(), p_chunk_coordinate, cells, grid_world_origin, step,
			p_settings->iso_level);
}

void LiquidSeed::set_solid_at(const Vector3i &p_cell, bool p_solid) {
	solid.set(index(p_cell.x, p_cell.y, p_cell.z), p_solid ? 1 : 0);
}

bool LiquidSeed::is_solid_at(const Vector3i &p_cell) const {
	return solid[index(p_cell.x, p_cell.y, p_cell.z)] != 0;
}

void LiquidSeed::set_liquid_at(const Vector3i &p_cell, double p_mass, int p_kind) {
	if (mass.is_empty()) {
		mass.resize(cells * cells * cells);
		mass.fill(0.0f);
		kind.resize(cells * cells * cells);
		kind.fill(TerrainLiquids::KIND_NONE);
	}
	int cell = index(p_cell.x, p_cell.y, p_cell.z);
	mass.set(cell, (float)p_mass);
	kind.set(cell, (uint8_t)p_kind);
}

double LiquidSeed::get_mass_at(const Vector3i &p_cell) const {
	if (mass.is_empty()) {
		return 0.0;
	}
	return mass[index(p_cell.x, p_cell.y, p_cell.z)];
}

void LiquidSeed::_bind_methods() {
	ClassDB::bind_static_method("LiquidSeed", D_METHOD("make", "chunk_coordinate", "cells"), &LiquidSeed::make);
	ClassDB::bind_static_method("LiquidSeed", D_METHOD("build", "chunk_coordinate", "settings"), &LiquidSeed::build);
	ClassDB::bind_static_method("LiquidSeed",
			D_METHOD("from_field", "field", "density", "chunk_coordinate", "cells", "grid_world_origin", "step",
					"iso_level"),
			&LiquidSeed::from_field_for);
	ClassDB::bind_method(D_METHOD("set_solid_at", "cell", "solid"), &LiquidSeed::set_solid_at);
	ClassDB::bind_method(D_METHOD("is_solid_at", "cell"), &LiquidSeed::is_solid_at);
	ClassDB::bind_method(D_METHOD("set_liquid_at", "cell", "mass", "kind"), &LiquidSeed::set_liquid_at);
	ClassDB::bind_method(D_METHOD("get_mass_at", "cell"), &LiquidSeed::get_mass_at);
	ClassDB::bind_method(D_METHOD("is_dry"), &LiquidSeed::is_dry);
	ClassDB::bind_method(D_METHOD("get_chunk_coordinate"), &LiquidSeed::get_chunk_coordinate);
	ClassDB::bind_method(D_METHOD("get_cells"), &LiquidSeed::get_cells);
}

} // namespace godot
