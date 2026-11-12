// Everything a chunk build reads, copied from the terrain node on the main thread so the
// worker threads never touch the node (ChunkedTerrainWorld.SettingsSnapshot in the scripts).
#pragma once

#include "common.h"
#include "terrain_edits.h"

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/variant/callable.hpp>

namespace godot {

class SignedDensityField;
class ChunkMeshBlocks;
class WorldDensity;

// The plain fields: type, name, default, variant type for the binding.
#define TERRAIN_SETTINGS_FIELDS(X)                                               \
	X(int, chunks_x, 3, INT)                                                     \
	X(int, chunks_y, 3, INT)                                                     \
	X(int, chunks_z, 3, INT)                                                     \
	X(int, cells_per_axis, 12, INT)                                              \
	X(double, voxel_size, 1.0, FLOAT)                                            \
	X(double, iso_level, 0.0, FLOAT)                                             \
	X(Vector3, world_origin, Vector3(), VECTOR3)                                 \
	X(double, chunk_world_size, 12.0, FLOAT)                                     \
	X(int, chunk_resolution, 1, INT)                                             \
	X(bool, noise_enabled, true, BOOL)                                           \
	X(int, noise_seed, 42, INT)                                                  \
	X(double, noise_frequency, 0.08, FLOAT)                                      \
	X(double, noise_amplitude, 3.0, FLOAT)                                       \
	X(int, noise_octaves, 3, INT)                                                \
	X(double, noise_lacunarity, 2.0, FLOAT)                                      \
	X(double, noise_gain, 0.5, FLOAT)                                            \
	X(bool, generate_collision, true, BOOL)                                      \
	X(int, loose_rock_voxels, 8, INT)                                            \
	X(bool, caves_enabled, false, BOOL)                                          \
	X(Vector3, bounds_center, Vector3(), VECTOR3)                                \
	X(Vector3, bounds_half, Vector3(), VECTOR3)                                  \
	X(double, bounds_clip_inset, 0.5, FLOAT)                                     \
	X(bool, boxed_in_terrain_enabled, false, BOOL)                               \
	X(bool, boxed_in_edges_enabled, true, BOOL)                                  \
	X(bool, open_terrain_enabled, false, BOOL)                                   \
	X(bool, open_terrain_edges_enabled, true, BOOL)                              \
	X(bool, open_terrain_solid_fill, false, BOOL)                                \
	X(double, open_terrain_surface_offset, 0.0, FLOAT)                           \
	X(int, open_terrain_terraces, 0, INT)                                        \
	X(double, open_terrain_terrace_chance, 0.4, FLOAT)                           \
	X(Vector2, open_terrain_terrace_step, Vector2(1.5, 5.0), VECTOR2)            \
	X(Vector2, open_terrain_terrace_strength, Vector2(0.35, 1.0), VECTOR2)       \
	X(double, open_terrain_terrace_coverage, 0.5, FLOAT)                         \
	X(int, open_terrain_character, 0, INT)                                       \
	X(Vector2, open_terrain_character_power, Vector2(0.7, 1.6), VECTOR2)         \
	X(double, open_terrain_character_warp_chance, 0.5, FLOAT)                    \
	X(Vector2, open_terrain_character_warp, Vector2(10.0, 40.0), VECTOR2)        \
	X(double, open_terrain_character_ridge_chance, 0.35, FLOAT)                  \
	X(Vector2, open_terrain_character_ridge, Vector2(0.2, 0.5), VECTOR2)         \
	X(int, open_terrain_cave_roll, 0, INT)                                       \
	X(Dictionary, open_terrain_cave_values, Dictionary(), DICTIONARY)            \
	X(Dictionary, open_terrain_cave_ranges, Dictionary(), DICTIONARY)            \
	X(Dictionary, open_terrain_cave_shape, Dictionary(), DICTIONARY)             \
	X(double, open_terrain_land_patch, 400.0, FLOAT)                             \
	X(double, open_terrain_cave_patch, 250.0, FLOAT)                             \
	X(int, open_terrain_noise_roll, 0, INT)                                      \
	X(Vector2, open_terrain_roll_frequency, Vector2(0.004, 0.01), VECTOR2)       \
	X(Vector2, open_terrain_roll_amplitude, Vector2(8.0, 40.0), VECTOR2)         \
	X(Vector2i, open_terrain_roll_octaves, Vector2i(2, 5), VECTOR2I)             \
	X(Vector2, open_terrain_roll_lacunarity, Vector2(1.8, 2.6), VECTOR2)         \
	X(Vector2, open_terrain_roll_gain, Vector2(0.3, 0.65), VECTOR2)              \
	X(int, open_terrain_regions, 0, INT)                                         \
	X(double, open_terrain_region_chance, 0.7, FLOAT)                            \
	X(Vector2, open_terrain_region_size, Vector2(500.0, 900.0), VECTOR2)         \
	X(Vector2, open_terrain_region_lowland, Vector2(0.1, 0.35), VECTOR2)         \
	X(Vector2, open_terrain_region_ridge, Vector2(0.3, 0.8), VECTOR2)            \
	X(Vector2, open_terrain_region_detail, Vector2(0.1, 0.3), VECTOR2)           \
	X(double, open_terrain_floor_chance, 0.6, FLOAT)                             \
	X(Vector2, open_terrain_floor_level, Vector2(0.2, 0.45), VECTOR2)            \
	X(double, open_terrain_cliff_chance, 0.5, FLOAT)                             \
	X(Vector2, open_terrain_cliff_strength, Vector2(0.4, 0.8), VECTOR2)          \
	X(Vector2, open_terrain_cliff_level, Vector2(0.4, 0.6), VECTOR2)             \
	X(Vector2, open_terrain_cliff_width, Vector2(0.08, 0.2), VECTOR2)            \
	X(int, open_terrain_relief, 0, INT)                                          \
	X(double, open_terrain_relief_chance, 0.6, FLOAT)                            \
	X(Vector2, open_terrain_relief_amplitude, Vector2(1.5, 3.5), VECTOR2)        \
	X(Vector2i, open_terrain_flat_spot_count, Vector2i(2, 4), VECTOR2I)          \
	X(Vector2, open_terrain_flat_spot_radius, Vector2(8.0, 14.0), VECTOR2)       \
	X(AABB, resample_bounds, AABB(), AABB)                                       \
	X(bool, keep_field, false, BOOL)                                             \
	X(bool, rebuild_collision, true, BOOL)

class TerrainSettings : public RefCounted {
	GDCLASS(TerrainSettings, RefCounted)

protected:
	static void _bind_methods();

public:
#define TS_DECLARE(T, name, def, vt) TFIELD(T, name, def)
	TERRAIN_SETTINGS_FIELDS(TS_DECLARE)
#undef TS_DECLARE

	Ref<Material> material;
	Ref<Image> open_terrain_heightmap_image;
	Array open_terrain_land_biomes;
	Array open_terrain_cave_biomes;
	Ref<TerrainEdits> terrain_edits;
	Ref<SignedDensityField> cached_field;
	Ref<ChunkMeshBlocks> cached_blocks;
	Array solids;
	// The world's density without edits or solids, built once on the main thread and
	// copied per chunk (WorldDensity::clone_for_build).
	Ref<WorldDensity> density_prototype;
	// A world with a density of its own kind from a script (the scripts' density_factory).
	Callable density_factory;

	Ref<TerrainSettings> duplicate_settings() const;

	Ref<Material> get_material() const { return material; }
	void set_material(const Ref<Material> &v) { material = v; }
	Ref<Image> get_open_terrain_heightmap_image() const { return open_terrain_heightmap_image; }
	void set_open_terrain_heightmap_image(const Ref<Image> &v) { open_terrain_heightmap_image = v; }
	TypedArray<Dictionary> get_open_terrain_land_biomes() const;
	void set_open_terrain_land_biomes(const Array &v) { open_terrain_land_biomes = v; }
	TypedArray<Dictionary> get_open_terrain_cave_biomes() const;
	void set_open_terrain_cave_biomes(const Array &v) { open_terrain_cave_biomes = v; }
	Ref<TerrainEdits> get_terrain_edits() const { return terrain_edits; }
	void set_terrain_edits(const Ref<TerrainEdits> &v) { terrain_edits = v; }
	Ref<SignedDensityField> get_cached_field() const;
	void set_cached_field(const Ref<SignedDensityField> &v);
	Ref<ChunkMeshBlocks> get_cached_blocks() const;
	void set_cached_blocks(const Ref<ChunkMeshBlocks> &v);
	TypedArray<Dictionary> get_solids() const;
	void set_solids(const Array &v) { solids = v; }
	Ref<WorldDensity> get_density_prototype() const;
	void set_density_prototype(const Ref<WorldDensity> &v);
	Callable get_density_factory() const { return density_factory; }
	void set_density_factory(const Callable &v) { density_factory = v; }
};

} // namespace godot
