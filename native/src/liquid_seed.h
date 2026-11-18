// What a chunk build hands the liquids (`TerrainLiquids`): which of the chunk's own cells are
// solid ground, and the liquid the map starts with in them (the aquifers' water in the caves,
// the lakes' on the ground), made on the worker from the field the chunk was meshed from. A
// chunk owns `cells` samples a side from its corner; the last sample of its field belongs to the
// next chunk.
#pragma once

#include "common.h"

#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

namespace godot {

class SignedDensityField;
class TerrainSettings;
class WorldDensity;

class LiquidSeed : public RefCounted {
	GDCLASS(LiquidSeed, RefCounted)

protected:
	static void _bind_methods();

public:
	// How far under the surface the aquifers' water may come: the open ground keeps its own.
	static constexpr double SURFACE_MARGIN = 4.0;
	// A chunk holds a lake's water only when its top reaches this near the ground (the height
	// function lies a few metres off the ground's own bumps).
	static constexpr double LAKE_REACH = 4.0;

	Vector3i chunk_coordinate;
	int cells = 0;
	// One a cell: 1 when solid.
	PackedByteArray solid;
	// How full each cell starts (0 to 1) and with what; both empty when the chunk starts dry.
	PackedFloat32Array mass;
	PackedByteArray kind;

	// A chunk of open, dry cells (the tests build their own).
	static Ref<LiquidSeed> make(const Vector3i &p_chunk_coordinate, int p_cells);
	// The chunk's cells from its field (samples below the iso level are solid), and the water
	// of the aquifers its density's caves give each column and of the lakes on its ground.
	static Ref<LiquidSeed> from_field(const Ref<SignedDensityField> &p_field, WorldDensity *p_density,
			const Vector3i &p_chunk_coordinate, int p_cells, const Vector3 &p_grid_world_origin, double p_step,
			double p_iso_level);
	static Ref<LiquidSeed> from_field_for(const Ref<SignedDensityField> &p_field, const Ref<WorldDensity> &p_density,
			const Vector3i &p_chunk_coordinate, int p_cells, const Vector3 &p_grid_world_origin, double p_step,
			double p_iso_level);
	// Builds the chunk's field as its mesh build does (loose rock cleared) and seeds from it.
	static Ref<LiquidSeed> build(const Vector3i &p_chunk_coordinate, const Ref<TerrainSettings> &p_settings);

	int index(int p_x, int p_y, int p_z) const { return p_x + (p_y + p_z * cells) * cells; }
	static void fill_cell(LocalVector<float> &r_mass, bool &r_any_water, int p_cells, int p_cell, double p_fill);
	bool is_dry() const { return mass.is_empty(); }

	// Script access (the tests).
	void set_solid_at(const Vector3i &p_cell, bool p_solid);
	bool is_solid_at(const Vector3i &p_cell) const;
	void set_liquid_at(const Vector3i &p_cell, double p_mass, int p_kind);
	double get_mass_at(const Vector3i &p_cell) const;
	Vector3i get_chunk_coordinate() const { return chunk_coordinate; }
	int get_cells() const { return cells; }
};

} // namespace godot
