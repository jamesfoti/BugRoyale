// The underground of a fixed map, drawn from its seed: worm tunnels where two 3D noises both
// run near zero, rounded caverns deeper down where a slower noise runs high, sinkholes that
// open tunnels to the sky, ravines on half the seeds, halls, shafts, bedding floors, seams,
// regions, aquifers with walls between them, cave biomes, and bedrock above the bottom of the
// grid. Every noise is read at a point pushed by a slow warp. Depth is metres below the
// surface of the column. See the README's caves section for what each number does.
#pragma once

#include "biomes.h"
#include "cave_systems.h"
#include "common.h"

#include <unordered_map>

namespace godot {

class TerrainSettings;

class CaveCarver : public RefCounted {
	GDCLASS(CaveCarver, RefCounted)

protected:
	static void _bind_methods();

public:
	static constexpr double FADE = 3.0;
	static constexpr double BAND_FADE = 10.0;
	static constexpr double FLOOR_MARGIN = 2.5;
	static constexpr double FLOOR_CLEARANCE = 1.5;
	static constexpr double WIDEN_PER_METRE = 0.006;
	static constexpr double WIDEN_MAX = 1.3;
	static constexpr double RAVINE_CHANCE = 0.5;
	static constexpr double BLEND = 2.0;
	static constexpr double FLOOR_CHANCE = 0.6;
	static constexpr double REGION_EDGE = 0.3;
	static constexpr double PILLAR_CUTOFF = 0.55;
	static constexpr double PILLAR_FREQUENCY = 0.2;
	static constexpr double WALL_BAND = 4.0;
	static constexpr double WATER_FLOOR = 6.0;
	static constexpr double BARRIER = 1.5;
	static constexpr double WATER_UNDER_SURFACE = 15.0;
	static constexpr double STEEP_START = 0.6;
	static constexpr double STEEP_END = 1.0;

	int world_seed = 0;
	double tunnel_frequency = 0.018;
	double tunnel_threshold = 0.3;
	double tunnel_depth = 8.0;
	double tunnel_ramp = 30.0;
	double shallow_cutoff = 0.35;
	double fade = FADE;
	double shallow_size = 180.0;
	double cavern_frequency = 0.016;
	double cavern_cutoff = 0.5;
	double cavern_depth = 22.0;
	double cavern_squash = 1.6;
	double sinkhole_threshold = 0.42;
	double ravine_frequency = 0.015;
	double ravine_width = 0.0;
	double ravine_depth = 12.0;
	double ravine_lean = 0.4;
	double warp_metres = 0.0;
	double warp_frequency = 0.007;
	double region_size = 250.0;
	double region_lean = 1.0;
	double region_rich = 1.0;
	double region_bias = 0.0;
	double thickness_size = 60.0;
	double thickness_thin = 1.0;
	double thickness_thick = 1.0;
	double deep_depth = 180.0;
	double deep_tunnels = 1.0;
	double deep_rooms = 1.0;
	double seam_width = 6.0;
	double seam_strength = 0.0;
	double band_wave = 0.0;
	double floor_spacing = 32.0;
	double floor_thickness = 0.0;
	double hall_size = 150.0;
	double hall_cutoff = 2.0;
	double shaft_frequency = 0.012;
	double shaft_width = 0.0;
	double shaft_lean = 0.12;
	double ceiling_jag = 1.4;
	double rubble = 0.5;
	BiomeList biomes;
	double biome_patch_size = 250.0;
	BiomeData biome_fixed;
	double water_share = 0.6;
	double aquifer_size = 160.0;
	double water_top = -tmath::INF_D;
	double shaft_share = 0.45;
	double floor_y = -tmath::INF_D;
	Ref<CaveSystems> systems;

	static Ref<CaveCarver> from_seed(int value, double bedrock_y, const Dictionary &ranges = Dictionary());
	static Ref<CaveCarver> for_settings(const Ref<TerrainSettings> &settings);
	static double bedrock_y(double origin_y, int chunks_y, double chunk_world_size);

	// A copy for one chunk build: the same numbers and noises, its own caches and region.
	Ref<CaveCarver> clone() const;

	void apply(const Dictionary &values);
	void make_noises();
	double carve(double value, const Vector3 &world_pos, double surface_height, double slope = 0.0);
	double air(const Vector3 &world_pos, double depth, double slope = 0.0);
	Vector3 aquifer(double world_x, double world_z);
	double water_level(double world_x, double world_z);
	double barrier(const Vector3 &world_pos);
	double region_richness(const Vector3 &world_pos) const;
	double seam(double bed) const;
	double thickness(const Vector3 &read_pos) const;
	double floor_slab(double bed) const;
	const BiomeData &biome_of(const Vector3 &world_pos, double depth) const;
	Dictionary biome(const Vector3 &world_pos, double depth) const { return biome_of(world_pos, depth).to_dictionary(); }
	bool is_cave(const Vector3 &world_pos, double surface_height);
	String summary() const;

	static double blend(double a, double b) {
		double overlap = tmath::maxd(BLEND - std::abs(a - b), 0.0) / BLEND;
		return tmath::maxd(a, b) + overlap * overlap * BLEND * 0.25;
	}

	// Script access to the constants that are not whole numbers.
	static double floor_margin() { return FLOOR_MARGIN; }
	double tunnel_noise_frequency() const { return tunnel_noise.frequency; }
	static double fade_default() { return FADE; }
	static double water_floor() { return WATER_FLOOR; }

	void set_biomes(const Array &value);
	TypedArray<Dictionary> get_biomes() const;
	void set_biome_patch_size(double value);
	double get_biome_patch_size() const { return biome_patch_size; }
	void set_biome_fixed(const Dictionary &value) { biome_fixed = BiomeData::from(value); }
	Dictionary get_biome_fixed() const { return biome_fixed.to_dictionary(); }
	void set_systems(const Ref<CaveSystems> &value) { systems = value; }
	Ref<CaveSystems> get_systems() const { return systems; }

#define CAVE_ACCESSORS(T, name)                     \
	void set_##name(T p_value) { name = p_value; } \
	T get_##name() const { return name; }
	CAVE_ACCESSORS(int, world_seed)
	CAVE_ACCESSORS(double, tunnel_frequency)
	CAVE_ACCESSORS(double, tunnel_threshold)
	CAVE_ACCESSORS(double, tunnel_depth)
	CAVE_ACCESSORS(double, tunnel_ramp)
	CAVE_ACCESSORS(double, shallow_cutoff)
	CAVE_ACCESSORS(double, fade)
	CAVE_ACCESSORS(double, shallow_size)
	CAVE_ACCESSORS(double, cavern_frequency)
	CAVE_ACCESSORS(double, cavern_cutoff)
	CAVE_ACCESSORS(double, cavern_depth)
	CAVE_ACCESSORS(double, cavern_squash)
	CAVE_ACCESSORS(double, sinkhole_threshold)
	CAVE_ACCESSORS(double, ravine_frequency)
	CAVE_ACCESSORS(double, ravine_width)
	CAVE_ACCESSORS(double, ravine_depth)
	CAVE_ACCESSORS(double, ravine_lean)
	CAVE_ACCESSORS(double, warp_metres)
	CAVE_ACCESSORS(double, warp_frequency)
	CAVE_ACCESSORS(double, region_size)
	CAVE_ACCESSORS(double, region_lean)
	CAVE_ACCESSORS(double, region_rich)
	CAVE_ACCESSORS(double, region_bias)
	CAVE_ACCESSORS(double, thickness_size)
	CAVE_ACCESSORS(double, thickness_thin)
	CAVE_ACCESSORS(double, thickness_thick)
	CAVE_ACCESSORS(double, deep_depth)
	CAVE_ACCESSORS(double, deep_tunnels)
	CAVE_ACCESSORS(double, deep_rooms)
	CAVE_ACCESSORS(double, seam_width)
	CAVE_ACCESSORS(double, seam_strength)
	CAVE_ACCESSORS(double, band_wave)
	CAVE_ACCESSORS(double, floor_spacing)
	CAVE_ACCESSORS(double, floor_thickness)
	CAVE_ACCESSORS(double, hall_size)
	CAVE_ACCESSORS(double, hall_cutoff)
	CAVE_ACCESSORS(double, shaft_frequency)
	CAVE_ACCESSORS(double, shaft_width)
	CAVE_ACCESSORS(double, shaft_lean)
	CAVE_ACCESSORS(double, ceiling_jag)
	CAVE_ACCESSORS(double, rubble)
	CAVE_ACCESSORS(double, water_share)
	CAVE_ACCESSORS(double, aquifer_size)
	CAVE_ACCESSORS(double, water_top)
	CAVE_ACCESSORS(double, shaft_share)
	CAVE_ACCESSORS(double, floor_y)
#undef CAVE_ACCESSORS

private:
	TNoise tunnel_noise;
	TNoise tunnel_noise_b;
	TNoise cavern_noise;
	TNoise sinkhole_noise;
	TNoise ravine_noise;
	TNoise warp_noise;
	TNoise region_noise;
	TNoise thickness_noise;
	TNoise wave_noise;
	TNoise hall_noise;
	TNoise shaft_noise;
	TNoise shaft_noise_b;
	TNoise shaft_map;
	TNoise shallow_map;
	TNoise ceiling_noise;
	TNoise rubble_noise;
	TNoise pillar_noise;
	TNoise biome_warp;
	std::unordered_map<Vector2, Vector3, Vector2Hash> aquifer_cache;

	void refresh_biome_warp();
	Vector3 aquifer_cells(double world_x, double world_z) const;
	static double draw(const Ref<RandomNumberGenerator> &rng, const Dictionary &ranges, const String &field,
			double least, double most);
};

} // namespace godot
