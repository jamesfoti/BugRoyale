// Biomes as the worker threads read them (Biome.to_data, a GDScript resource the inspector
// edits) and the patches that pick one per column (BiomePatches): the map is cut into cells
// of a jittered grid, the lookup pushed about by a slow noise, and each cell draws its kind
// by weight with its own hash.
#pragma once

#include "common.h"

#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <vector>

namespace godot {

struct BiomeData {
	String name;
	double weight = 0.0;
	Color tint = Color(1, 1, 1, 1);
	double depth_min = 0.0;
	double depth_max = tmath::INF_D;
	bool pillars = false;
	double ceiling_jag = 1.0;
	double rubble = 1.0;
	// Land only: the share of mound sites in its patches where a termite mound stands.
	double termite_mounds = 0.0;
	bool empty = true;

	static BiomeData from(const Dictionary &data);
	Dictionary to_dictionary() const;
	bool holds(double depth) const { return depth >= depth_min && depth < depth_max; }
};

struct BiomeList {
	std::vector<BiomeData> kinds;
	std::vector<float> weights;
	Array source; // as given, for scripts that read it back

	void set(const Array &data);
	bool is_empty() const { return kinds.empty(); }
	PackedStringArray names() const;
	PackedFloat32Array weights_packed() const;
};

namespace patches {

constexpr double WARP = 0.35;

TNoise make_warp(int seed_value, double patch_size);
// The index into weights of the patch at a column, or -1 when every weight is 0.
int pick(double world_x, double world_z, int seed_value, double patch_size, const TNoise *warp,
		const std::vector<float> &weights);
String shares(const PackedStringArray &names, const PackedFloat32Array &weights);

} // namespace patches

} // namespace godot
