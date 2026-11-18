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

// How a kind's termite mounds come out (a `TermiteMoundFeature`): each range is smallest to
// largest, in metres, and each mound draws from it with its own hash.
struct TermiteMoundShape {
	double spire_share = 0.5;
	Vector2 spire_height = Vector2(20.0, 34.0);
	Vector2 spire_radius = Vector2(6.0, 9.0);
	Vector2 dome_height = Vector2(10.0, 18.0);
	Vector2 dome_radius = Vector2(9.0, 13.0);
	Vector2 nest_depth = Vector2(8.0, 12.0);
	Vector2 nest_radius = Vector2(5.5, 8.0);

	static TermiteMoundShape from(const Dictionary &p_data);
};

struct BiomeData {
	String name;
	double weight = 0.0;
	Color tint = Color(1, 1, 1, 1);
	double depth_min = 0.0;
	double depth_max = tmath::INF_D;
	bool pillars = false;
	double ceiling_jag = 1.0;
	double rubble = 1.0;
	// Land only: its features as data (`Biome.features`, less those the map does not list), and
	// from them the share of termite mound sites in its patches where a mound stands, and how.
	Array features;
	double termite_mounds = 0.0;
	TermiteMoundShape termite_mound_shape;
	bool empty = true;

	static BiomeData from(const Dictionary &p_data);
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
