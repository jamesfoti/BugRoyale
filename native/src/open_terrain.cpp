#include "open_terrain.h"

#include "cave_carver.h"
#include "cave_systems.h"

#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/script.hpp>

namespace godot {

static const char *LAND_BIOMES[] = {
	"res://biomes/land_meadow.tres",
	"res://biomes/land_dryland.tres",
	"res://biomes/land_marsh.tres",
	"res://biomes/land_barrens.tres",
};
static const char *CAVE_BIOMES[] = {
	"res://biomes/cave_plain.tres",
	"res://biomes/cave_mossy.tres",
	"res://biomes/cave_dripstone.tres",
	"res://biomes/cave_fungal.tres",
	"res://biomes/cave_crystal.tres",
};

OpenTerrain::OpenTerrain() {
	ResourceLoader *loader = ResourceLoader::get_singleton();
	for (const char *path : LAND_BIOMES) {
		if (loader->exists(path)) {
			land_biomes.push_back(loader->load(path));
		}
	}
	for (const char *path : CAVE_BIOMES) {
		if (loader->exists(path)) {
			cave_biomes.push_back(loader->load(path));
		}
	}
}

void OpenTerrain::set_chunks_x(int v) {
	chunks_x = MAX(v, 1);
	settings_changed();
}
void OpenTerrain::set_chunks_y(int v) {
	chunks_y = MAX(v, 1);
	settings_changed();
}
void OpenTerrain::set_chunks_z(int v) {
	chunks_z = MAX(v, 1);
	settings_changed();
}
void OpenTerrain::set_heightmap(const Ref<Texture2D> &v) {
	heightmap = v;
	heightmap_image_cache.unref();
	settings_changed();
}
void OpenTerrain::set_land_biomes(const Array &v) {
	land_biomes = v;
	settings_changed();
}
void OpenTerrain::set_cave_biomes(const Array &v) {
	cave_biomes = v;
	settings_changed();
}

double OpenTerrain::get_surface_datum_y() const {
	return (double)get_global_position().y + surface_height_offset +
			surface_layer_offset((double)get_world_extents().y * 0.5, chunk_size);
}

double OpenTerrain::surface_layer_offset(double half_height, double chunk_extent) const {
	if (surface_layer <= 0) {
		return 0.0;
	}
	return half_height - ((double)surface_layer - 0.5) * chunk_extent;
}

double OpenTerrain::get_surface_height_at(const Vector3 &world_position) {
	Ref<WorldDensity> density = _get_bake_density();
	if (density->open_terrain_enabled) {
		return density->sample_open_terrain_height(world_position.x, world_position.z);
	}
	return get_global_position().y;
}

Array OpenTerrain::biome_data(const Array &biomes) {
	Array out;
	for (int i = 0; i < biomes.size(); i++) {
		Object *biome = biomes[i];
		if (biome != nullptr && biome->has_method("to_data")) {
			out.push_back(biome->call("to_data"));
		}
	}
	return out;
}

void OpenTerrain::_apply_world_specific_settings(const Ref<TerrainSettings> &settings) {
	settings->boxed_in_terrain_enabled = false;
	settings->open_terrain_enabled = true;
	settings->open_terrain_edges_enabled = boxed_edges_enabled;
	settings->open_terrain_solid_fill = solid_underside;
	settings->open_terrain_heightmap_image = duplicate_heightmap_image();
	settings->open_terrain_surface_offset =
			surface_height_offset + surface_layer_offset(settings->bounds_half.y, settings->chunk_world_size);
	settings->open_terrain_terraces = terraces;
	settings->open_terrain_terrace_chance = terrace_chance;
	settings->open_terrain_terrace_step = terrace_step;
	settings->open_terrain_terrace_strength = terrace_strength;
	settings->open_terrain_terrace_coverage = terrace_coverage;
	settings->open_terrain_character = character;
	settings->open_terrain_character_power = character_power;
	settings->open_terrain_character_warp_chance = character_warp_chance;
	settings->open_terrain_character_warp = character_warp;
	settings->open_terrain_character_ridge_chance = character_ridge_chance;
	settings->open_terrain_character_ridge = character_ridge;
	settings->open_terrain_cave_roll = cave_roll;
	settings->open_terrain_cave_ranges = cave_ranges();
	settings->open_terrain_cave_shape = cave_shape();
	settings->open_terrain_land_biomes = biome_data(land_biomes);
	settings->open_terrain_land_patch = land_patch_size;
	settings->open_terrain_cave_biomes = biome_data(cave_biomes);
	settings->open_terrain_cave_patch = cave_patch_size;
	Dictionary values;
#define OT_CAVE_VALUE(name, def, step, range) values[#name] = cave_##name;
	OPEN_TERRAIN_CAVE_FIELDS(OT_CAVE_VALUE)
#undef OT_CAVE_VALUE
	settings->open_terrain_cave_values = values;
	settings->open_terrain_noise_roll = noise_roll;
	settings->open_terrain_roll_frequency = roll_frequency;
	settings->open_terrain_roll_amplitude = roll_amplitude;
	settings->open_terrain_roll_octaves = roll_octaves;
	settings->open_terrain_roll_lacunarity = roll_lacunarity;
	settings->open_terrain_roll_gain = roll_gain;
	settings->open_terrain_regions = regions;
	settings->open_terrain_region_chance = region_chance;
	settings->open_terrain_region_size = region_size;
	settings->open_terrain_region_lowland = region_lowland;
	settings->open_terrain_region_ridge = region_ridge;
	settings->open_terrain_region_detail = region_detail;
	settings->open_terrain_floor_chance = floor_chance;
	settings->open_terrain_floor_level = floor_level;
	settings->open_terrain_cliff_chance = cliff_chance;
	settings->open_terrain_cliff_strength = cliff_strength;
	settings->open_terrain_cliff_level = cliff_level;
	settings->open_terrain_cliff_width = cliff_width;
	settings->open_terrain_relief = relief;
	settings->open_terrain_relief_chance = relief_chance;
	settings->open_terrain_relief_amplitude = relief_amplitude;
	settings->open_terrain_flat_spot_count = flat_spot_count;
	settings->open_terrain_flat_spot_radius = flat_spot_radius;
}

Dictionary OpenTerrain::rolled_noise(const Ref<TerrainSettings> &settings) {
	Dictionary out;
	if (settings->open_terrain_noise_roll != NOISE_ROLL_SEEDED) {
		out["frequency"] = settings->noise_frequency;
		out["amplitude"] = settings->noise_amplitude;
		out["octaves"] = settings->noise_octaves;
		out["lacunarity"] = settings->noise_lacunarity;
		out["gain"] = settings->noise_gain;
		return out;
	}
	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed((uint64_t)thash::of(settings->noise_seed, 5503));
	Vector2 frequency = settings->open_terrain_roll_frequency;
	Vector2 amplitude = settings->open_terrain_roll_amplitude;
	Vector2i octaves = settings->open_terrain_roll_octaves;
	Vector2 lacunarity = settings->open_terrain_roll_lacunarity;
	Vector2 gain = settings->open_terrain_roll_gain;
	out["frequency"] = tmath::maxd(rng->randf_range(MIN(frequency.x, frequency.y), MAX(frequency.x, frequency.y)), 0.001);
	out["amplitude"] = tmath::maxd(rng->randf_range(MIN(amplitude.x, amplitude.y), MAX(amplitude.x, amplitude.y)), 0.0);
	out["octaves"] = rng->randi_range(MIN(octaves.x, octaves.y), MAX(octaves.x, octaves.y));
	out["lacunarity"] = rng->randf_range(MIN(lacunarity.x, lacunarity.y), MAX(lacunarity.x, lacunarity.y));
	out["gain"] = rng->randf_range(MIN(gain.x, gain.y), MAX(gain.x, gain.y));
	return out;
}

String OpenTerrain::noise_summary(const Dictionary &noise) {
	Array args;
	args.push_back(tmath::roundi(1.0 / tmath::maxd((double)noise["frequency"], 0.001)));
	args.push_back(tmath::roundi((double)noise["amplitude"]));
	args.push_back((int)noise["octaves"]);
	args.push_back((double)noise["lacunarity"]);
	args.push_back((double)noise["gain"]);
	return String("hills %d m across, %d m tall, %d octaves, lacunarity %.1f, gain %.2f") % args;
}

Ref<WorldDensity> OpenTerrain::_build_world_density(const Ref<TerrainSettings> &settings) {
	Dictionary noise = rolled_noise(settings);
	Ref<WorldDensity> density = WorldDensity::create_open_terrain(settings->noise_seed, (double)noise["frequency"],
			(double)noise["amplitude"], (int)noise["octaves"], (double)noise["lacunarity"], (double)noise["gain"],
			settings->bounds_center, settings->bounds_half, settings->bounds_clip_inset,
			settings->open_terrain_edges_enabled, settings->open_terrain_heightmap_image,
			settings->open_terrain_surface_offset, settings->open_terrain_solid_fill);
	if (settings->caves_enabled && settings->open_terrain_solid_fill) {
		density->caves = CaveCarver::for_settings(settings);
		density->caves->set_biomes(settings->open_terrain_cave_biomes);
		density->caves->set_biome_patch_size(settings->open_terrain_cave_patch);
	}
	if (settings->open_terrain_character == CHARACTER_SEEDED) {
		density->roll_surface(settings->noise_seed, settings->open_terrain_character_power,
				settings->open_terrain_character_warp_chance, settings->open_terrain_character_warp,
				settings->open_terrain_character_ridge_chance, settings->open_terrain_character_ridge);
	}
	if (settings->open_terrain_regions == REGIONS_SEEDED) {
		density->roll_regions(settings->noise_seed, settings->open_terrain_region_chance,
				settings->open_terrain_region_size, settings->open_terrain_region_lowland,
				settings->open_terrain_region_ridge, settings->open_terrain_region_detail);
		density->roll_curve(settings->noise_seed, settings->open_terrain_floor_chance, settings->open_terrain_floor_level,
				settings->open_terrain_cliff_chance, settings->open_terrain_cliff_strength,
				settings->open_terrain_cliff_level, settings->open_terrain_cliff_width);
	}
	if (settings->open_terrain_relief == RELIEF_SEEDED && settings->open_terrain_solid_fill) {
		density->roll_relief(settings->noise_seed, settings->open_terrain_relief_chance,
				settings->open_terrain_relief_amplitude);
	}
	if (settings->open_terrain_terraces != TERRACES_NEVER) {
		density->roll_terraces(settings->noise_seed, settings->open_terrain_terrace_chance,
				settings->open_terrain_terrace_step, settings->open_terrain_terrace_strength,
				settings->open_terrain_terrace_coverage, settings->open_terrain_terraces == TERRACES_ALWAYS);
	}
	// Last, so a landing is level whatever the terraces and the character did there.
	if (settings->open_terrain_relief == RELIEF_SEEDED) {
		density->roll_flat_spots(settings->noise_seed, settings->open_terrain_flat_spot_count,
				settings->open_terrain_flat_spot_radius);
	}
	density->set_land_biomes(settings->open_terrain_land_biomes);
	density->set_land_patch_size(settings->open_terrain_land_patch);
	// After every layer of the surface, so the cave mouths sit on the ground as built.
	if (density->caves.is_valid()) {
		WorldDensity *d = density.ptr();
		density->caves->systems = CaveSystems::roll_native(settings->noise_seed,
				AABB(settings->bounds_center - settings->bounds_half, settings->bounds_half * 2.0f),
				[d](double x, double z) -> double { return d->sample_open_terrain_height(x, z); }, density->caves->floor_y);
	}
	return density;
}

TypedArray<Vector3> OpenTerrain::get_flat_spots() {
	Ref<WorldDensity> density = _get_bake_density();
	if (density.is_null()) {
		return TypedArray<Vector3>();
	}
	return density->flat_spot_points();
}

String OpenTerrain::_world_summary(const Ref<TerrainSettings> &settings) {
	Ref<WorldDensity> density = _build_world_density(settings);
	String summary = ", seed " + itos(settings->noise_seed) + ": ";
	if (settings->open_terrain_noise_roll == NOISE_ROLL_SEEDED) {
		summary += noise_summary(rolled_noise(settings)) + ", ";
	}
	PackedStringArray parts;
	parts.push_back(density->surface_summary());
	parts.push_back(density->region_summary());
	parts.push_back(density->land_summary());
	parts.push_back(density->curve_summary());
	parts.push_back(density->relief_summary());
	parts.push_back(density->flat_spot_summary());
	parts.push_back(density->terrace_summary());
	summary += String(", ").join(parts);
	if (density->caves.is_valid()) {
		summary += ", " + density->caves->summary();
	}
	return summary;
}

Ref<Image> OpenTerrain::duplicate_heightmap_image() {
	if (heightmap.is_null()) {
		return Ref<Image>();
	}
	if (heightmap_image_cache.is_valid()) {
		return heightmap_image_cache;
	}
	Ref<Image> image = heightmap->get_image();
	if (image.is_null() || image->is_empty()) {
		return Ref<Image>();
	}
	heightmap_image_cache = image->duplicate();
	return heightmap_image_cache;
}

Dictionary OpenTerrain::cave_ranges() const {
	Dictionary out;
	out["tunnel_depth"] = cave_range_tunnel_depth;
	out["tunnel_ramp"] = cave_range_tunnel_ramp;
	out["shallow_cutoff"] = cave_range_shallow_cutoff;
	return out;
}

Dictionary OpenTerrain::cave_shape() const {
	Dictionary out;
	out["fade"] = cave_fade;
	out["shallow_size"] = cave_shallow_size;
	return out;
}

Dictionary OpenTerrain::cave_fields() {
	Dictionary out;
#define OT_CAVE_FIELD(name, def, step, range) out[#name] = step;
	OPEN_TERRAIN_CAVE_FIELDS(OT_CAVE_FIELD)
#undef OT_CAVE_FIELD
	return out;
}

void OpenTerrain::_bind_methods() {
	BIND_ENUM_CONSTANT(TERRACES_SEEDED);
	BIND_ENUM_CONSTANT(TERRACES_ALWAYS);
	BIND_ENUM_CONSTANT(TERRACES_NEVER);
	BIND_ENUM_CONSTANT(CHARACTER_SEEDED);
	BIND_ENUM_CONSTANT(CHARACTER_PLAIN);
	BIND_ENUM_CONSTANT(NOISE_ROLL_FIXED);
	BIND_ENUM_CONSTANT(NOISE_ROLL_SEEDED);
	BIND_ENUM_CONSTANT(REGIONS_SEEDED);
	BIND_ENUM_CONSTANT(REGIONS_PLAIN);
	BIND_ENUM_CONSTANT(RELIEF_SEEDED);
	BIND_ENUM_CONSTANT(RELIEF_NONE);
	BIND_ENUM_CONSTANT(CAVE_ROLL_SEEDED);
	BIND_ENUM_CONSTANT(CAVE_ROLL_FIXED);

	ClassDB::bind_method(D_METHOD("surface_layer_offset", "half_height", "chunk_extent"), &OpenTerrain::surface_layer_offset);
	ClassDB::bind_method(D_METHOD("get_surface_height_at", "world_position"), &OpenTerrain::get_surface_height_at);
	ClassDB::bind_static_method("OpenTerrain", D_METHOD("rolled_noise", "settings"), &OpenTerrain::rolled_noise);
	ClassDB::bind_static_method("OpenTerrain", D_METHOD("noise_summary", "noise"), &OpenTerrain::noise_summary);
	ClassDB::bind_static_method("OpenTerrain", D_METHOD("cave_fields"), &OpenTerrain::cave_fields);
	ClassDB::bind_method(D_METHOD("get_flat_spots"), &OpenTerrain::get_flat_spots);
	ClassDB::bind_method(D_METHOD("cave_ranges"), &OpenTerrain::cave_ranges);
	ClassDB::bind_method(D_METHOD("cave_shape"), &OpenTerrain::cave_shape);

#define OT_BIND(name, vtype, hint, hint_string)                                                \
	ClassDB::bind_method(D_METHOD("set_" #name, "value"), &OpenTerrain::set_##name);           \
	ClassDB::bind_method(D_METHOD("get_" #name), &OpenTerrain::get_##name);                    \
	ADD_PROPERTY(PropertyInfo(Variant::vtype, #name, hint, hint_string), "set_" #name, "get_" #name);
#define OT_ENUM(name, hint_string) OT_BIND(name, INT, PROPERTY_HINT_ENUM, hint_string)
#define OT_PLAIN(name, vtype) OT_BIND(name, vtype, PROPERTY_HINT_NONE, "")
#define OT_RANGE(name, range) OT_BIND(name, FLOAT, PROPERTY_HINT_RANGE, range)

	ADD_GROUP("Open Terrain Grid", "");
	OT_BIND(chunks_x, INT, PROPERTY_HINT_RANGE, "1,64,1")
	OT_BIND(chunks_y, INT, PROPERTY_HINT_RANGE, "1,128,1")
	OT_BIND(chunks_z, INT, PROPERTY_HINT_RANGE, "1,64,1")
	ADD_GROUP("Heightmap", "");
	OT_BIND(heightmap, OBJECT, PROPERTY_HINT_RESOURCE_TYPE, "Texture2D")
	OT_BIND(surface_layer, INT, PROPERTY_HINT_RANGE, "0,32,1")
	OT_RANGE(surface_height_offset, "-8,8,0.5")
	ADD_GROUP("Terraces", "");
	OT_ENUM(terraces, "Seeded,Always,Never")
	OT_RANGE(terrace_chance, "0,1,0.05")
	OT_PLAIN(terrace_step, VECTOR2)
	OT_PLAIN(terrace_strength, VECTOR2)
	OT_RANGE(terrace_coverage, "0,1,0.05")
	ADD_GROUP("Character", "");
	OT_ENUM(character, "Seeded,Plain")
	OT_PLAIN(character_power, VECTOR2)
	OT_RANGE(character_warp_chance, "0,1,0.05")
	OT_PLAIN(character_warp, VECTOR2)
	OT_RANGE(character_ridge_chance, "0,1,0.05")
	OT_PLAIN(character_ridge, VECTOR2)
	ADD_GROUP("Noise Roll", "");
	OT_ENUM(noise_roll, "Fixed,Seeded")
	OT_PLAIN(roll_frequency, VECTOR2)
	OT_PLAIN(roll_amplitude, VECTOR2)
	OT_PLAIN(roll_octaves, VECTOR2I)
	OT_PLAIN(roll_lacunarity, VECTOR2)
	OT_PLAIN(roll_gain, VECTOR2)
	ADD_GROUP("Regions", "");
	OT_ENUM(regions, "Seeded,Plain")
	OT_RANGE(region_chance, "0,1,0.05")
	OT_PLAIN(region_size, VECTOR2)
	OT_PLAIN(region_lowland, VECTOR2)
	OT_PLAIN(region_ridge, VECTOR2)
	OT_PLAIN(region_detail, VECTOR2)
	OT_RANGE(floor_chance, "0,1,0.05")
	OT_PLAIN(floor_level, VECTOR2)
	OT_RANGE(cliff_chance, "0,1,0.05")
	OT_PLAIN(cliff_strength, VECTOR2)
	OT_PLAIN(cliff_level, VECTOR2)
	OT_PLAIN(cliff_width, VECTOR2)
	ADD_GROUP("Relief", "");
	OT_ENUM(relief, "Seeded,None")
	OT_RANGE(relief_chance, "0,1,0.05")
	OT_PLAIN(relief_amplitude, VECTOR2)
	OT_PLAIN(flat_spot_count, VECTOR2I)
	OT_PLAIN(flat_spot_radius, VECTOR2)
	ADD_GROUP("Biomes", "");
	OT_RANGE(land_patch_size, "50,2000,10")
	OT_BIND(land_biomes, ARRAY, PROPERTY_HINT_TYPE_STRING, "24/17:Biome")
	OT_RANGE(cave_patch_size, "50,2000,10")
	OT_BIND(cave_biomes, ARRAY, PROPERTY_HINT_TYPE_STRING, "24/17:Biome")
	ADD_GROUP("Cave Roll", "");
	OT_ENUM(cave_roll, "Seeded,Fixed")
	OT_PLAIN(cave_range_tunnel_depth, VECTOR2)
	OT_PLAIN(cave_range_tunnel_ramp, VECTOR2)
	OT_PLAIN(cave_range_shallow_cutoff, VECTOR2)
#define OT_CAVE_BIND(name, def, step, range) OT_RANGE(cave_##name, range)
	OPEN_TERRAIN_CAVE_FIELDS(OT_CAVE_BIND)
#undef OT_CAVE_BIND
	ADD_GROUP("Edges", "");
	OT_PLAIN(boxed_edges_enabled, BOOL)
	OT_PLAIN(solid_underside, BOOL)
	ADD_GROUP("", "");
#undef OT_RANGE
#undef OT_PLAIN
#undef OT_ENUM
#undef OT_BIND
}

// --- The terrarium's terrain ------------------------------------------------------------------

static Dictionary terrarium_budget() {
	static Dictionary constants;
	if (constants.is_empty()) {
		Ref<Script> script = ResourceLoader::get_singleton()->load("res://generation/terrarium_budget.gd");
		if (script.is_valid()) {
			constants = script->get_script_constant_map();
		}
	}
	return constants;
}

void TerrariumTerrain::apply_defaults_without_rebuild() {
	Dictionary budget = terrarium_budget();
	int max_chunks = (int)budget.get("MAX_CHUNKS_PER_AXIS", 128);
	double min_chunk = (double)budget.get("MIN_CHUNK_SIZE", 1.0);
	double max_chunk = (double)budget.get("MAX_CHUNK_SIZE", 64.0);
	is_playable_world = false;
	boxed_edges_enabled = true;
	chunk_resolution = 1;
	use_threaded_rebuild = true;
	chunks_x = MIN(MAX(chunks_x, 1), max_chunks);
	chunks_y = MIN(MAX(chunks_y, 1), max_chunks);
	chunks_z = MIN(MAX(chunks_z, 1), max_chunks);
	chunk_size = tmath::clampd(chunk_size, min_chunk, max_chunk);
	// Rebuilt by the room, not by the setters: drop what was built from the old settings.
	_invalidate_bake_density();
}

void TerrariumTerrain::rebuild_all() {
	apply_defaults_without_rebuild();
	OpenTerrain::rebuild_all();
}

double TerrariumTerrain::get_surface_height_at(const Vector3 &world_position) {
	Vector3 local_position = to_local(world_position);
	Vector3 half_extents = get_world_extents() * 0.5f;
	if (std::abs(local_position.x) > half_extents.x || std::abs(local_position.z) > half_extents.z) {
		return get_global_position().y;
	}
	Ref<WorldDensity> density = _get_bake_density();
	if (density->open_terrain_enabled) {
		return density->sample_open_terrain_height(world_position.x, world_position.z);
	}
	return (double)get_global_position().y - (double)half_extents.y;
}

TerrariumTerrain *TerrariumTerrain::create_configured(Object *grid_config, int noise_seed,
		const Ref<Material> &terrain_material, double noise_amplitude, double noise_frequency, int noise_octaves,
		double noise_lacunarity, double noise_gain, double surface_height_offset, const Ref<Texture2D> &heightmap,
		bool boxed_edges_enabled) {
	TerrariumTerrain *terrain = memnew(TerrariumTerrain);
	terrain->set_name("TerrariumTerrain");
	terrain->rebuild_on_ready = false;
	terrain->auto_rebuild_in_editor = false;
	terrain->is_playable_world = false;
	Vector3i chunks = grid_config->get("chunks");
	terrain->chunks_x = chunks.x;
	terrain->chunks_y = chunks.y;
	terrain->chunks_z = chunks.z;
	terrain->chunk_size = (double)grid_config->get("chunk_size");
	terrain->voxel_size = (double)grid_config->get("voxel_size");
	terrain->chunk_resolution = 1;
	terrain->boxed_edges_enabled = boxed_edges_enabled;
	terrain->heightmap = heightmap;
	terrain->surface_height_offset = surface_height_offset;
	terrain->noise_seed = noise_seed;
	terrain->noise_amplitude = noise_amplitude;
	terrain->noise_frequency = noise_frequency;
	terrain->noise_octaves = noise_octaves;
	terrain->noise_lacunarity = noise_lacunarity;
	terrain->noise_gain = noise_gain;
	terrain->use_threaded_rebuild = true;
	if (terrain_material.is_valid()) {
		terrain->terrain_material = terrain_material;
	}
	return terrain;
}

void TerrariumTerrain::_bind_methods() {
	ClassDB::bind_static_method("TerrariumTerrain",
			D_METHOD("create_configured", "grid_config", "noise_seed", "terrain_material", "noise_amplitude",
					"noise_frequency", "noise_octaves", "noise_lacunarity", "noise_gain", "surface_height_offset",
					"heightmap", "boxed_edges_enabled"),
			&TerrariumTerrain::create_configured, DEFVAL(6.0), DEFVAL(0.02), DEFVAL(4), DEFVAL(2.0), DEFVAL(0.5),
			DEFVAL(0.0), DEFVAL(Ref<Texture2D>()), DEFVAL(true));
}

// --- The boxed-in terrain --------------------------------------------------------------------

void BoxedInTerrain::set_chunks_x(int v) {
	chunks_x = MAX(v, 1);
	settings_changed();
}
void BoxedInTerrain::set_chunks_y(int v) {
	chunks_y = MAX(v, 1);
	settings_changed();
}
void BoxedInTerrain::set_chunks_z(int v) {
	chunks_z = MAX(v, 1);
	settings_changed();
}
void BoxedInTerrain::set_boxed_edges_enabled(bool v) {
	boxed_edges_enabled = v;
	settings_changed();
}

void BoxedInTerrain::_apply_world_specific_settings(const Ref<TerrainSettings> &settings) {
	settings->boxed_in_terrain_enabled = true;
	settings->open_terrain_enabled = false;
	settings->boxed_in_edges_enabled = boxed_edges_enabled;
}

Ref<WorldDensity> BoxedInTerrain::_build_world_density(const Ref<TerrainSettings> &settings) {
	return WorldDensity::create_boxed_in_terrain(settings->noise_seed, settings->noise_frequency,
			settings->noise_octaves, settings->noise_lacunarity, settings->noise_gain, settings->bounds_center,
			settings->bounds_half, settings->bounds_clip_inset, settings->boxed_in_edges_enabled);
}

void BoxedInTerrain::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_surface_height_at", "world_position"), &BoxedInTerrain::get_surface_height_at);
	ADD_GROUP("Boxed-In Terrain Grid", "");
	ClassDB::bind_method(D_METHOD("set_chunks_x", "value"), &BoxedInTerrain::set_chunks_x);
	ClassDB::bind_method(D_METHOD("get_chunks_x"), &BoxedInTerrain::get_chunks_x);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "chunks_x", PROPERTY_HINT_RANGE, "1,64,1"), "set_chunks_x", "get_chunks_x");
	ClassDB::bind_method(D_METHOD("set_chunks_y", "value"), &BoxedInTerrain::set_chunks_y);
	ClassDB::bind_method(D_METHOD("get_chunks_y"), &BoxedInTerrain::get_chunks_y);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "chunks_y", PROPERTY_HINT_RANGE, "1,32,1"), "set_chunks_y", "get_chunks_y");
	ClassDB::bind_method(D_METHOD("set_chunks_z", "value"), &BoxedInTerrain::set_chunks_z);
	ClassDB::bind_method(D_METHOD("get_chunks_z"), &BoxedInTerrain::get_chunks_z);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "chunks_z", PROPERTY_HINT_RANGE, "1,64,1"), "set_chunks_z", "get_chunks_z");
	ADD_GROUP("Edges", "");
	ClassDB::bind_method(D_METHOD("set_boxed_edges_enabled", "value"), &BoxedInTerrain::set_boxed_edges_enabled);
	ClassDB::bind_method(D_METHOD("get_boxed_edges_enabled"), &BoxedInTerrain::get_boxed_edges_enabled);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "boxed_edges_enabled"), "set_boxed_edges_enabled", "get_boxed_edges_enabled");
	ADD_GROUP("", "");
}

} // namespace godot
