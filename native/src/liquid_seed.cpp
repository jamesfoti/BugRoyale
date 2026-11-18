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
	if (p_density == nullptr || field->sky || p_density->caves.is_null() ||
			p_density->caves->water_top == -tmath::INF_D) {
		return seed;
	}
	CaveCarver *caves = p_density->caves.ptr();
	Vector3i grid_offset = p_chunk_coordinate * p_cells;
	double bottom_y = (double)p_grid_world_origin.y + (double)grid_offset.y * p_step - p_step * 0.5;
	if (caves->water_top < bottom_y) {
		return seed;
	}
	PackedFloat32Array mass;
	PackedByteArray kind;
	bool any_water = false;
	for (int z = 0; z < p_cells; z++) {
		double world_z = (double)p_grid_world_origin.z + (double)(grid_offset.z + z) * p_step;
		for (int x = 0; x < p_cells; x++) {
			double world_x = (double)p_grid_world_origin.x + (double)(grid_offset.x + x) * p_step;
			double level = caves->water_level(world_x, world_z);
			if (level == -tmath::INF_D || level <= bottom_y) {
				continue;
			}
			if (p_density->open_terrain_enabled) {
				level = tmath::mind(level, p_density->sample_open_terrain_height(world_x, world_z) - SURFACE_MARGIN);
			}
			for (int y = 0; y < p_cells; y++) {
				double cell_bottom = bottom_y + (double)y * p_step;
				double fill = tmath::clampd((level - cell_bottom) / p_step, 0.0, 1.0);
				if (fill < (double)TerrainLiquids::MIN_MASS) {
					break;
				}
				int cell = seed->index(x, y, z);
				if (solid[cell] != 0) {
					continue;
				}
				if (!any_water) {
					any_water = true;
					mass.resize(p_cells * p_cells * p_cells);
					mass.fill(0.0f);
					kind.resize(p_cells * p_cells * p_cells);
					kind.fill(TerrainLiquids::KIND_NONE);
				}
				mass.set(cell, (float)fill);
				kind.set(cell, TerrainLiquids::KIND_WATER);
			}
		}
	}
	if (any_water) {
		seed->mass = mass;
		seed->kind = kind;
	}
	return seed;
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
	ClassDB::bind_method(D_METHOD("set_solid_at", "cell", "solid"), &LiquidSeed::set_solid_at);
	ClassDB::bind_method(D_METHOD("is_solid_at", "cell"), &LiquidSeed::is_solid_at);
	ClassDB::bind_method(D_METHOD("set_liquid_at", "cell", "mass", "kind"), &LiquidSeed::set_liquid_at);
	ClassDB::bind_method(D_METHOD("get_mass_at", "cell"), &LiquidSeed::get_mass_at);
	ClassDB::bind_method(D_METHOD("is_dry"), &LiquidSeed::is_dry);
	ClassDB::bind_method(D_METHOD("get_chunk_coordinate"), &LiquidSeed::get_chunk_coordinate);
	ClassDB::bind_method(D_METHOD("get_cells"), &LiquidSeed::get_cells);
}

} // namespace godot
