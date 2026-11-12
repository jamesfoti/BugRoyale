// The kinds of world: an open terrain (a layered surface over a sponge of 3D noise, or over
// solid ground with a seeded underworld carved out of it), the same sized for a terrarium,
// and a boxed-in noise volume.
#pragma once

#include "chunked_terrain_world.h"

#include <godot_cpp/classes/texture2d.hpp>

namespace godot {

// The fields the Cave Roll sliders set (cave_ plus the CaveCarver field name) with their steps.
#define OPEN_TERRAIN_CAVE_FIELDS(X)                                  \
	X(tunnel_frequency, 0.018, 0.001, "0.01,0.05,0.001")             \
	X(tunnel_threshold, 0.3, 0.01, "0,0.5,0.01")                     \
	X(tunnel_depth, 8.0, 0.5, "0,30,0.5")                            \
	X(tunnel_ramp, 30.0, 1.0, "0,80,1")                              \
	X(shallow_cutoff, 0.35, 0.01, "-1,1,0.01")                       \
	X(fade, 3.0, 0.5, "0.5,15,0.5")                                  \
	X(shallow_size, 180.0, 10.0, "40,600,10")                        \
	X(water_share, 0.6, 0.05, "0,1,0.05")                            \
	X(aquifer_size, 160.0, 10.0, "60,400,10")                        \
	X(cavern_frequency, 0.016, 0.001, "0.005,0.04,0.001")            \
	X(cavern_cutoff, 0.49, 0.01, "0.2,1,0.01")                       \
	X(cavern_depth, 22.0, 1.0, "5,80,1")                             \
	X(cavern_squash, 1.6, 0.1, "1,3,0.1")                            \
	X(sinkhole_threshold, 0.42, 0.01, "0.2,1,0.01")                  \
	X(ravine_width, 0.0, 0.005, "0,0.15,0.005")                      \
	X(ravine_depth, 12.0, 0.5, "4,40,0.5")                           \
	X(warp_metres, 7.0, 0.5, "0,20,0.5")                             \
	X(region_size, 250.0, 10.0, "100,600,10")                        \
	X(region_lean, 0.0, 0.05, "0,1,0.05")                            \
	X(region_rich, 1.1, 0.05, "0.5,1.5,0.05")                        \
	X(region_bias, 0.0, 0.05, "-0.5,0.5,0.05")                       \
	X(thickness_thin, 0.6, 0.05, "0.2,1,0.05")                       \
	X(thickness_thick, 1.35, 0.05, "1,2,0.05")                       \
	X(deep_depth, 180.0, 5.0, "50,400,5")                            \
	X(deep_tunnels, 0.5, 0.05, "0,1,0.05")                           \
	X(deep_rooms, 1.4, 0.05, "1,2,0.05")                             \
	X(seam_width, 5.0, 0.5, "0,15,0.5")                              \
	X(seam_strength, 0.75, 0.05, "0,1,0.05")                         \
	X(band_wave, 12.0, 1.0, "0,30,1")                                \
	X(floor_spacing, 32.0, 1.0, "8,64,1")                            \
	X(floor_thickness, 3.0, 0.5, "0,6,0.5")                          \
	X(hall_cutoff, 0.62, 0.01, "0.3,1,0.01")                         \
	X(shaft_width, 0.16, 0.01, "0,0.3,0.01")                         \
	X(shaft_share, 0.45, 0.05, "0,1,0.05")                           \
	X(shaft_lean, 0.14, 0.01, "0.02,0.5,0.01")                       \
	X(ceiling_jag, 1.4, 0.1, "0,4,0.1")                              \
	X(rubble, 0.5, 0.1, "0,2,0.1")

class OpenTerrain : public ChunkedTerrainWorld {
	GDCLASS(OpenTerrain, ChunkedTerrainWorld)

protected:
	static void _bind_methods();

public:
	enum Terraces { TERRACES_SEEDED, TERRACES_ALWAYS, TERRACES_NEVER };
	enum Character { CHARACTER_SEEDED, CHARACTER_PLAIN };
	enum NoiseRoll { NOISE_ROLL_FIXED, NOISE_ROLL_SEEDED };
	enum Regions { REGIONS_SEEDED, REGIONS_PLAIN };
	enum Relief { RELIEF_SEEDED, RELIEF_NONE };
	enum CaveRoll { CAVE_ROLL_SEEDED, CAVE_ROLL_FIXED };

	OpenTerrain();

	int chunks_x = 5;
	int chunks_y = 3;
	int chunks_z = 5;
	Ref<Texture2D> heightmap;
	int surface_layer = 0;
	double surface_height_offset = 0.0;
	int terraces = TERRACES_SEEDED;
	double terrace_chance = 0.4;
	Vector2 terrace_step = Vector2(1.5, 5.0);
	Vector2 terrace_strength = Vector2(0.35, 1.0);
	double terrace_coverage = 0.5;
	int character = CHARACTER_SEEDED;
	Vector2 character_power = Vector2(0.7, 1.6);
	double character_warp_chance = 0.5;
	Vector2 character_warp = Vector2(10.0, 40.0);
	double character_ridge_chance = 0.35;
	Vector2 character_ridge = Vector2(0.2, 0.5);
	int noise_roll = NOISE_ROLL_FIXED;
	Vector2 roll_frequency = Vector2(0.004, 0.01);
	Vector2 roll_amplitude = Vector2(8.0, 40.0);
	Vector2i roll_octaves = Vector2i(2, 5);
	Vector2 roll_lacunarity = Vector2(1.8, 2.6);
	Vector2 roll_gain = Vector2(0.3, 0.65);
	int regions = REGIONS_SEEDED;
	double region_chance = 0.7;
	Vector2 region_size = Vector2(500.0, 900.0);
	Vector2 region_lowland = Vector2(0.1, 0.35);
	Vector2 region_ridge = Vector2(0.3, 0.8);
	Vector2 region_detail = Vector2(0.1, 0.3);
	double floor_chance = 0.6;
	Vector2 floor_level = Vector2(0.2, 0.45);
	double cliff_chance = 0.5;
	Vector2 cliff_strength = Vector2(0.4, 0.8);
	Vector2 cliff_level = Vector2(0.4, 0.6);
	Vector2 cliff_width = Vector2(0.08, 0.2);
	int relief = RELIEF_SEEDED;
	double relief_chance = 0.6;
	Vector2 relief_amplitude = Vector2(1.5, 3.5);
	Vector2i flat_spot_count = Vector2i(2, 4);
	Vector2 flat_spot_radius = Vector2(8.0, 14.0);
	double land_patch_size = 400.0;
	Array land_biomes;
	double cave_patch_size = 250.0;
	Array cave_biomes;
	int cave_roll = CAVE_ROLL_SEEDED;
	Vector2 cave_range_tunnel_depth = Vector2(6.0, 12.0);
	Vector2 cave_range_tunnel_ramp = Vector2(20.0, 40.0);
	Vector2 cave_range_shallow_cutoff = Vector2(0.25, 0.45);
#define OT_CAVE_DECLARE(name, def, step, range) double cave_##name = def;
	OPEN_TERRAIN_CAVE_FIELDS(OT_CAVE_DECLARE)
#undef OT_CAVE_DECLARE
	bool boxed_edges_enabled = true;
	bool solid_underside = false;

	void _register_playable_groups() override { add_to_group("open_terrain"); }
	Vector3i _get_grid_dimensions() const override { return Vector3i(chunks_x, chunks_y, chunks_z); }
	String _get_world_log_name() const override { return "OpenTerrain"; }
	double get_surface_datum_y() const override;
	void _apply_world_specific_settings(const Ref<TerrainSettings> &settings) override;
	Ref<WorldDensity> _build_world_density(const Ref<TerrainSettings> &settings) override;
	String _world_summary(const Ref<TerrainSettings> &settings) override;

	double surface_layer_offset(double half_height, double chunk_extent) const;
	virtual double get_surface_height_at(const Vector3 &world_position);
	static Dictionary rolled_noise(const Ref<TerrainSettings> &settings);
	static String noise_summary(const Dictionary &noise);
	TypedArray<Vector3> get_flat_spots();
	Dictionary cave_ranges() const;
	Dictionary cave_shape() const;
	static Dictionary cave_fields();

	// Accessors (each setter marks the settings changed).
#define OT_ACCESSORS(T, name)                     \
	void set_##name(T p_value) {                 \
		name = p_value;                          \
		settings_changed();                      \
	}                                            \
	T get_##name() const { return name; }
	OT_ACCESSORS(int, surface_layer)
	OT_ACCESSORS(double, surface_height_offset)
	OT_ACCESSORS(int, terraces)
	OT_ACCESSORS(double, terrace_chance)
	OT_ACCESSORS(Vector2, terrace_step)
	OT_ACCESSORS(Vector2, terrace_strength)
	OT_ACCESSORS(double, terrace_coverage)
	OT_ACCESSORS(int, character)
	OT_ACCESSORS(Vector2, character_power)
	OT_ACCESSORS(double, character_warp_chance)
	OT_ACCESSORS(Vector2, character_warp)
	OT_ACCESSORS(double, character_ridge_chance)
	OT_ACCESSORS(Vector2, character_ridge)
	OT_ACCESSORS(int, noise_roll)
	OT_ACCESSORS(Vector2, roll_frequency)
	OT_ACCESSORS(Vector2, roll_amplitude)
	OT_ACCESSORS(Vector2i, roll_octaves)
	OT_ACCESSORS(Vector2, roll_lacunarity)
	OT_ACCESSORS(Vector2, roll_gain)
	OT_ACCESSORS(int, regions)
	OT_ACCESSORS(double, region_chance)
	OT_ACCESSORS(Vector2, region_size)
	OT_ACCESSORS(Vector2, region_lowland)
	OT_ACCESSORS(Vector2, region_ridge)
	OT_ACCESSORS(Vector2, region_detail)
	OT_ACCESSORS(double, floor_chance)
	OT_ACCESSORS(Vector2, floor_level)
	OT_ACCESSORS(double, cliff_chance)
	OT_ACCESSORS(Vector2, cliff_strength)
	OT_ACCESSORS(Vector2, cliff_level)
	OT_ACCESSORS(Vector2, cliff_width)
	OT_ACCESSORS(int, relief)
	OT_ACCESSORS(double, relief_chance)
	OT_ACCESSORS(Vector2, relief_amplitude)
	OT_ACCESSORS(Vector2i, flat_spot_count)
	OT_ACCESSORS(Vector2, flat_spot_radius)
	OT_ACCESSORS(double, land_patch_size)
	OT_ACCESSORS(double, cave_patch_size)
	OT_ACCESSORS(int, cave_roll)
	OT_ACCESSORS(Vector2, cave_range_tunnel_depth)
	OT_ACCESSORS(Vector2, cave_range_tunnel_ramp)
	OT_ACCESSORS(Vector2, cave_range_shallow_cutoff)
	OT_ACCESSORS(bool, boxed_edges_enabled)
	OT_ACCESSORS(bool, solid_underside)
#define OT_CAVE_ACCESSORS(name, def, step, range) OT_ACCESSORS(double, cave_##name)
	OPEN_TERRAIN_CAVE_FIELDS(OT_CAVE_ACCESSORS)
#undef OT_CAVE_ACCESSORS
#undef OT_ACCESSORS

	void set_chunks_x(int v);
	int get_chunks_x() const { return chunks_x; }
	void set_chunks_y(int v);
	int get_chunks_y() const { return chunks_y; }
	void set_chunks_z(int v);
	int get_chunks_z() const { return chunks_z; }
	void set_heightmap(const Ref<Texture2D> &v);
	Ref<Texture2D> get_heightmap() const { return heightmap; }
	void set_land_biomes(const Array &v);
	Array get_land_biomes() const { return land_biomes; }
	void set_cave_biomes(const Array &v);
	Array get_cave_biomes() const { return cave_biomes; }

protected:
	Ref<Image> heightmap_image_cache;
	Ref<Image> duplicate_heightmap_image();
	static Array biome_data(const Array &biomes);
};

class TerrariumTerrain : public OpenTerrain {
	GDCLASS(TerrariumTerrain, OpenTerrain)

protected:
	static void _bind_methods();

public:
	void on_ready() override { apply_defaults_without_rebuild(); }
	void _request_rebuild() override {}
	void _ensure_world_defaults() override { apply_defaults_without_rebuild(); }
	void _register_playable_groups() override {}
	void rebuild_all() override;
	String _get_world_log_name() const override { return "TerrariumTerrain"; }
	double get_surface_height_at(const Vector3 &world_position) override;

	static TerrariumTerrain *create_configured(Object *grid_config, int noise_seed, const Ref<Material> &terrain_material,
			double noise_amplitude = 6.0, double noise_frequency = 0.02, int noise_octaves = 4,
			double noise_lacunarity = 2.0, double noise_gain = 0.5, double surface_height_offset = 0.0,
			const Ref<Texture2D> &heightmap = Ref<Texture2D>(), bool boxed_edges_enabled = true);

private:
	void apply_defaults_without_rebuild();
};

class BoxedInTerrain : public ChunkedTerrainWorld {
	GDCLASS(BoxedInTerrain, ChunkedTerrainWorld)

protected:
	static void _bind_methods();

public:
	int chunks_x = 5;
	int chunks_y = 3;
	int chunks_z = 5;
	bool boxed_edges_enabled = true;

	void _register_playable_groups() override { add_to_group("boxed_in_terrain"); }
	Vector3i _get_grid_dimensions() const override { return Vector3i(chunks_x, chunks_y, chunks_z); }
	String _get_world_log_name() const override { return "BoxedInTerrain"; }
	void _apply_world_specific_settings(const Ref<TerrainSettings> &settings) override;
	Ref<WorldDensity> _build_world_density(const Ref<TerrainSettings> &settings) override;
	double get_surface_height_at(const Vector3 &world_position) { return get_global_position().y; }

	void set_chunks_x(int v);
	int get_chunks_x() const { return chunks_x; }
	void set_chunks_y(int v);
	int get_chunks_y() const { return chunks_y; }
	void set_chunks_z(int v);
	int get_chunks_z() const { return chunks_z; }
	void set_boxed_edges_enabled(bool v);
	bool get_boxed_edges_enabled() const { return boxed_edges_enabled; }
};

} // namespace godot

VARIANT_ENUM_CAST(OpenTerrain::Terraces);
VARIANT_ENUM_CAST(OpenTerrain::Character);
VARIANT_ENUM_CAST(OpenTerrain::NoiseRoll);
VARIANT_ENUM_CAST(OpenTerrain::Regions);
VARIANT_ENUM_CAST(OpenTerrain::Relief);
VARIANT_ENUM_CAST(OpenTerrain::CaveRoll);
