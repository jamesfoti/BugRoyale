// Biomes as the worker threads read them (Biome.to_data, a GDScript resource the inspector
// edits) and the patches that pick one per column: the map is cut into cells of a jittered
// grid, the lookup pushed about by a slow noise, and each cell draws its kind by weight with
// its own hash; a land list whose kinds have climates draws only among the kinds whose
// warmth and wetness hold the climate at the patch's middle (`WorldDensity::land_biome_of`).
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
	// Land only: the warmth and wetness (each from 0 to 1) the kind grows in, lowest to highest.
	Vector2 warmth = Vector2(0.0, 1.0);
	Vector2 wetness = Vector2(0.0, 1.0);
	bool empty = true;

	static BiomeData from(const Dictionary &p_data);
	// Whether a climate (warmth, wetness) lies in the kind's ranges.
	bool fits(const Vector2 &p_climate) const;
	// How far a climate lies outside the kind's ranges (0 inside).
	double climate_distance(const Vector2 &p_climate) const;
	// Whether the kind's ranges are narrower than the whole of either scale.
	bool has_climate() const;
	Dictionary to_dictionary() const;
	bool holds(double depth) const { return depth >= depth_min && depth < depth_max; }
};

struct BiomeList {
	std::vector<BiomeData> kinds;
	std::vector<float> weights;
	Array source; // as given, for scripts that read it back
	// Whether any kind has a climate, so patches draw by climate as well as weight.
	bool by_climate = false;

	void set(const Array &data);
	bool is_empty() const { return kinds.empty(); }
	PackedStringArray names() const;
	PackedFloat32Array weights_packed() const;
};

namespace patches {

constexpr double WARP = 0.35;

// The patch a column falls in: its jittered middle and its hash.
struct Patch {
	Vector2 middle;
	int64_t bits = 0;
};

TNoise make_warp(int seed_value, double patch_size);
Patch patch_at(double p_world_x, double p_world_z, int p_seed, double p_patch_size, const TNoise *p_warp);
// The share of the way through the weights a patch's hash draws, from 0 up to 1.
double draw_share(int64_t p_bits);
// The index into weights a patch's hash draws, or -1 when every weight is 0.
int draw(int64_t p_bits, const std::vector<float> &p_weights);
// The index into weights of the patch at a column, or -1 when every weight is 0.
int pick(double world_x, double world_z, int seed_value, double patch_size, const TNoise *warp,
		const std::vector<float> &weights);
String shares(const PackedStringArray &names, const PackedFloat32Array &weights);

} // namespace patches

} // namespace godot
