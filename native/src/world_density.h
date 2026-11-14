// Analytic density at any world position: the map's shape (an open terrain's layered surface
// over a sponge or solid ground with caves, a boxed-in noise volume, or plain noise), the
// solids a builder adds, and the edits on top; and what the ground is made of and coloured.
// DensitySampler.WorldDensity in the scripts.
#pragma once

#include "biomes.h"
#include "cave_carver.h"
#include "common.h"
#include "terrain_edits.h"
#include "termite_mounds.h"

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>

#include <vector>

namespace godot {

struct SolidShape {
	Vector3 center;
	double half_length = 0.0;
	double radius = 0.0;
	double height = 0.0;
	bool along_z = false;
	bool ground = false;
	bool has_tint = false;
	Color tint;
	AABB bounds;
	Dictionary source;

	static SolidShape from(const Dictionary &data);
	double sdf(const Vector3 &world_pos) const;
};

class WorldDensity : public RefCounted {
	GDCLASS(WorldDensity, RefCounted)

protected:
	static void _bind_methods();

public:
	static constexpr double TOPSOIL_DEPTH = 1.5;
	static constexpr double VEIN_THRESHOLD = 0.42;
	static constexpr double ORE_THRESHOLD = 0.4;
	static constexpr double ORE_POCKET_SIZE = 6.0;
	static constexpr double CURVE_FLOOR_SOFTNESS = 0.1;
	static constexpr double RELIEF_SLOPE_START = 0.5;
	static constexpr double RELIEF_SLOPE_END = 1.0;
	static constexpr double FLAT_SPOT_BLEND = 0.9;
	static constexpr double FLAT_SPOT_FADE = 10.0;
	static constexpr double SPONGE_NOISE_METRES = 4.0;
	static constexpr double OPEN_TERRAIN_NOISE_SKIP_HEIGHT = SPONGE_NOISE_METRES;

	bool noise_enabled = true;
	double noise_amplitude = 3.0;
	int noise_octaves = 3;
	double noise_lacunarity = 2.0;
	double noise_gain = 0.5;
	Vector3 bounds_center;
	Vector3 bounds_half;
	double bounds_clip_inset = 0.5;
	bool boxed_in_terrain_enabled = false;
	bool boxed_in_edges_enabled = true;
	bool open_terrain_enabled = false;
	bool open_terrain_edges_enabled = true;
	bool open_terrain_solid_fill = false;
	double surface_height_offset = 0.0;
	bool terrace_enabled = false;
	double terrace_step = 3.0;
	double terrace_strength = 1.0;
	double terrace_phase = 0.0;
	double terrace_coverage = 0.5;
	double surface_warp = 0.0;
	double surface_ridge = 0.0;
	double surface_power = 1.0;
	double region_strength = 0.0;
	double region_lowland = 0.2;
	double region_ridge = 0.0;
	double region_detail = 0.0;
	double curve_floor = 0.0;
	double curve_cliff = 0.0;
	double curve_cliff_at = 0.5;
	double curve_cliff_width = 0.15;
	double relief_amplitude = 0.0;
	double relief_band = 0.0;
	std::vector<Vector4> flat_spots;
	Ref<CaveCarver> caves;
	BiomeList land_biomes;
	double land_patch_size = 400.0;
	// Whether any land kind raises termite mounds, and the mounds near the region a chunk
	// build samples.
	bool mounds_enabled = false;
	TermiteMounds termites;
	std::vector<SolidShape> solids;
	Array solids_source;
	Ref<TerrainEdits> terrain_edits;
	int ore_seed = 0;

	// Creation (the scripts' DensitySampler and WorldDensity statics).
	static Ref<WorldDensity> create(bool p_noise_enabled, int noise_seed, double noise_frequency, double p_noise_amplitude,
			int p_noise_octaves, double p_noise_lacunarity, double p_noise_gain, const Vector3 &p_bounds_center,
			const Vector3 &p_bounds_half, double p_bounds_clip_inset = 0.5);
	static Ref<WorldDensity> create_open_terrain(int noise_seed, double noise_frequency, double p_noise_amplitude,
			int p_noise_octaves, double p_noise_lacunarity, double p_noise_gain, const Vector3 &p_bounds_center,
			const Vector3 &p_bounds_half, double p_bounds_clip_inset, bool open_edges_enabled,
			const Ref<Image> &heightmap_image, double p_surface_height_offset, bool solid_fill);
	static Ref<WorldDensity> create_boxed_in_terrain(int noise_seed, double noise_frequency, int p_noise_octaves,
			double p_noise_lacunarity, double p_noise_gain, const Vector3 &p_bounds_center, const Vector3 &p_bounds_half,
			double p_bounds_clip_inset, bool boxed_edges_enabled);

	// A copy for one chunk build: the same shape and noises, caches and regions of its own.
	Ref<WorldDensity> clone_for_build() const;

	// Solids.
	void set_solids(const Array &value);
	TypedArray<Dictionary> get_solids() const;
	static double stadium_sdf(const Vector3 &world_pos, const Dictionary &solid);
	static AABB solid_bounds(const Dictionary &solid);
	bool is_sky(double highest_surface, double bottom_y, const AABB &region) const;
	void prepare_for_region(const AABB &region);
	double solids_sdf(const Vector3 &world_pos) const;
	const SolidShape *solid_shape_at(const Vector3 &world_pos) const;
	Dictionary solid_at(const Vector3 &world_pos) const;

	// Materials and tints.
	int natural_material(const Vector3 &world_position, double density_value);
	int ground_material(const Vector3 &world_position, double density_value);
	double depth_below_surface(const Vector3 &world_position, double density_value) const;
	Color natural_tint(const Vector3 &world_position, double density_value);
	int ore_at(const Vector3 &world_position, double depth) const;
	const BiomeData &land_biome_of(double world_x, double world_z) const;
	Dictionary land_biome(double world_x, double world_z) const { return land_biome_of(world_x, world_z).to_dictionary(); }
	String land_summary() const;
	// The termite mounds whose bounds meet an area, as data (base, height, radius, spire,
	// lean, nest, nest_radius, holes, hole_turn).
	TypedArray<Dictionary> termite_mounds_in(const AABB &p_area) const;
	int get_land_seed() const { return land_seed; }
	void set_land_biomes(const Array &value);
	TypedArray<Dictionary> get_land_biomes() const;
	void set_land_patch_size(double value);
	double get_land_patch_size() const { return land_patch_size; }

	// The surface.
	double sample_open_terrain_height(double world_x, double world_z) const;
	double curve_height(double unit) const;
	double surface_slope(double world_x, double world_z, double height) const;
	double flat_spot_height(double height, double world_x, double world_z) const;
	void prepare_flat_spots();
	TypedArray<Vector3> flat_spot_points() const;
	double terrace_height(double height, double world_x, double world_z) const;
	void roll_terraces(int terrain_seed, double chance, const Vector2 &step_range, const Vector2 &strength_range,
			double coverage, bool force = false);
	void roll_surface(int terrain_seed, const Vector2 &power_range, double warp_chance, const Vector2 &warp_range,
			double ridge_chance, const Vector2 &ridge_range);
	void init_warp_noise(int terrain_seed);
	String surface_summary() const;
	String terrace_summary() const;
	void roll_regions(int terrain_seed, double chance, const Vector2 &size_range, const Vector2 &lowland_range,
			const Vector2 &ridge_range, const Vector2 &detail_range);
	void init_region_noise(int terrain_seed, double mask_frequency = 1.0 / 700.0);
	double highland_share() const;
	String region_summary() const;
	void roll_curve(int terrain_seed, double floor_chance, const Vector2 &floor_range, double cliff_chance,
			const Vector2 &cliff_range, const Vector2 &level_range, const Vector2 &width_range);
	String curve_summary() const;
	void roll_relief(int terrain_seed, double chance, const Vector2 &amplitude_range);
	void set_relief(double amplitude, int terrain_seed);
	// The region mask's raw noise at a column (0 without regions), for tests.
	double region_mask_noise(double world_x, double world_z) const {
		return region_noise.valid ? region_noise.get_2d(world_x, world_z) : 0.0;
	}
	static double topsoil_depth() { return TOPSOIL_DEPTH; }
	double relief_reach() const { return relief_amplitude > 0.0 ? relief_band : 0.0; }
	String relief_summary() const;
	void roll_flat_spots(int terrain_seed, const Vector2i &count_range, const Vector2 &radius_range);
	String flat_spot_summary() const;

	// The density.
	double evaluate_open_terrain_with_surface(const Vector3 &world_pos, double surface_height, bool with_edits = true,
			double slope = -1.0);
	double evaluate(const Vector3 &world_pos, bool with_edits = true);
	Vector3 gradient(const Vector3 &world_pos, double epsilon);

	// Script access to fields kept in C++ shapes.
	void set_flat_spots(const Array &value);
	TypedArray<Vector4> get_flat_spots() const;
	void set_caves(const Ref<CaveCarver> &value) { caves = value; }
	Ref<CaveCarver> get_caves() const { return caves; }
	void set_terrain_edits(const Ref<TerrainEdits> &value) { terrain_edits = value; }
	Ref<TerrainEdits> get_terrain_edits() const { return terrain_edits; }
	void set_heightmap_image(const Ref<Image> &image);

#define WD_ACCESSORS(T, name)                       \
	void set_##name(T p_value) { name = p_value; } \
	T get_##name() const { return name; }
	WD_ACCESSORS(bool, noise_enabled)
	WD_ACCESSORS(double, noise_amplitude)
	WD_ACCESSORS(int, noise_octaves)
	WD_ACCESSORS(double, noise_lacunarity)
	WD_ACCESSORS(double, noise_gain)
	WD_ACCESSORS(Vector3, bounds_center)
	WD_ACCESSORS(Vector3, bounds_half)
	WD_ACCESSORS(double, bounds_clip_inset)
	WD_ACCESSORS(bool, boxed_in_terrain_enabled)
	WD_ACCESSORS(bool, boxed_in_edges_enabled)
	WD_ACCESSORS(bool, open_terrain_enabled)
	WD_ACCESSORS(bool, open_terrain_edges_enabled)
	WD_ACCESSORS(bool, open_terrain_solid_fill)
	WD_ACCESSORS(double, surface_height_offset)
	WD_ACCESSORS(bool, terrace_enabled)
	WD_ACCESSORS(double, terrace_step)
	WD_ACCESSORS(double, terrace_strength)
	WD_ACCESSORS(double, terrace_phase)
	WD_ACCESSORS(double, terrace_coverage)
	WD_ACCESSORS(double, surface_warp)
	WD_ACCESSORS(double, surface_ridge)
	WD_ACCESSORS(double, surface_power)
	WD_ACCESSORS(double, region_strength)
	WD_ACCESSORS(double, region_lowland)
	WD_ACCESSORS(double, region_ridge)
	WD_ACCESSORS(double, region_detail)
	WD_ACCESSORS(double, curve_floor)
	WD_ACCESSORS(double, curve_cliff)
	WD_ACCESSORS(double, curve_cliff_at)
	WD_ACCESSORS(double, curve_cliff_width)
	WD_ACCESSORS(double, relief_amplitude)
	WD_ACCESSORS(double, relief_band)
	WD_ACCESSORS(int, ore_seed)
#undef WD_ACCESSORS

private:
	std::vector<double> flat_spot_heights;
	int flat_spot_count = 0;
	TNoise region_noise;
	TNoise detail_noise;
	TNoise relief_noise;
	TNoise land_warp;
	int land_seed = 0;
	// The lumps on a termite mound's skin.
	TNoise mound_noise;
	TNoise vein_noise;
	TNoise ore_noise;
	TNoise macro_noise;
	TNoise height_noise;
	TNoise terrace_noise;
	TNoise warp_noise_x;
	TNoise warp_noise_z;
	TNoise base_noise;
	// The heightmap as one height sample per pixel, read without the Image on worker threads.
	std::vector<double> heightmap;
	Vector2i heightmap_size;
	std::vector<int> region_solids;

	void init_ground_noises(int noise_seed);
	void init_boxed_in_terrain_noise(int terrain_seed, double surface_frequency, int octaves, double lacunarity,
			double gain);
	void init_open_terrain_height_noise(int terrain_seed, double surface_frequency, int octaves, double lacunarity,
			double gain);
	void refresh_land_warp();
	double sample_boxed_in_terrain_noise(const Vector3 &world_position) const;
	double evaluate_boxed_in_terrain(const Vector3 &world_pos, bool with_edits) const;
	double sample_heightmap(double world_x, double world_z) const;
	static double draw(const Ref<RandomNumberGenerator> &rng, const Vector2 &value_range);
	static Ref<RandomNumberGenerator> seeded_rng(int first, int second);

	friend class DensitySampler;
};

} // namespace godot
