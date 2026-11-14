#include "world_density.h"

#include "density_sampler.h"
#include "materials.h"

namespace godot {

// --- Solids -----------------------------------------------------------------------------------

SolidShape SolidShape::from(const Dictionary &data) {
	SolidShape shape;
	shape.source = data;
	shape.center = data.get("center", Vector3());
	shape.half_length = (double)data.get("half_length", 0.0);
	shape.radius = (double)data.get("radius", 0.0);
	shape.height = (double)data.get("height", 0.0);
	shape.along_z = (bool)data.get("along_z", false);
	shape.ground = (bool)data.get("ground", false);
	shape.has_tint = data.has("tint");
	if (shape.has_tint) {
		shape.tint = data["tint"];
	}
	shape.bounds = WorldDensity::solid_bounds(data);
	return shape;
}

double SolidShape::sdf(const Vector3 &world_pos) const {
	Vector3 local = world_pos - center;
	double along = along_z ? local.z : local.x;
	double across = along_z ? local.x : local.z;
	double straight = tmath::maxd(std::abs(along) - (half_length - radius), 0.0);
	double sideways = (double)Vector2((real_t)straight, (real_t)across).length() - radius;
	double vertical = std::abs((double)local.y - height * 0.5) - height * 0.5;
	return tmath::maxd(sideways, vertical);
}

double WorldDensity::stadium_sdf(const Vector3 &world_pos, const Dictionary &solid) {
	return SolidShape::from(solid).sdf(world_pos);
}

AABB WorldDensity::solid_bounds(const Dictionary &solid) {
	Vector3 center = solid.get("center", Vector3());
	double half_length = (double)solid.get("half_length", 0.0);
	double radius = (double)solid.get("radius", 0.0);
	Vector3 half = (bool)solid.get("along_z", false) ? v3(radius, 0.0, half_length) : v3(half_length, 0.0, radius);
	return AABB(center - half, v3((double)half.x * 2.0, (double)solid.get("height", 0.0), (double)half.z * 2.0));
}

void WorldDensity::set_solids(const Array &value) {
	solids_source = value;
	solids.clear();
	region_solids.clear();
	for (int index = 0; index < value.size(); index++) {
		solids.push_back(SolidShape::from(value[index]));
		region_solids.push_back(index);
	}
}

TypedArray<Dictionary> WorldDensity::get_solids() const {
	TypedArray<Dictionary> out;
	for (int index = 0; index < solids_source.size(); index++) {
		out.push_back(solids_source[index]);
	}
	return out;
}

bool WorldDensity::is_sky(double highest_surface, double bottom_y, const AABB &region) const {
	if (!open_terrain_enabled || highest_surface >= bottom_y || !region_solids.empty()) {
		return false;
	}
	// A mound standing up into the region (prepare_for_region found it) is ground up there.
	if (mounds_enabled && (!termites.region_ready || !termites.region.is_empty())) {
		return false;
	}
	if (terrain_edits.is_valid() && terrain_edits->get_override_count() > 0) {
		return !terrain_edits->get_all_bounds_const().intersects(region);
	}
	return true;
}

void WorldDensity::prepare_for_region(const AABB &region) {
	region_solids.clear();
	for (int index = 0; index < (int)solids.size(); index++) {
		if (region.intersects(solids[index].bounds)) {
			region_solids.push_back(index);
		}
	}
	if (caves.is_valid() && caves->systems.is_valid()) {
		caves->systems->prepare_region(region);
	}
	if (mounds_enabled) {
		termites.prepare(region, *this, land_seed);
	}
}

double WorldDensity::solids_sdf(const Vector3 &world_pos) const {
	double nearest = tmath::INF_D;
	for (int index : region_solids) {
		nearest = tmath::mind(nearest, solids[index].sdf(world_pos));
	}
	return nearest;
}

const SolidShape *WorldDensity::solid_shape_at(const Vector3 &world_pos) const {
	for (int index : region_solids) {
		if (solids[index].sdf(world_pos) <= 0.0) {
			return &solids[index];
		}
	}
	return nullptr;
}

Dictionary WorldDensity::solid_at(const Vector3 &world_pos) const {
	const SolidShape *shape = solid_shape_at(world_pos);
	return shape != nullptr ? shape->source : Dictionary();
}

// --- Creation ---------------------------------------------------------------------------------

Ref<WorldDensity> WorldDensity::create(bool p_noise_enabled, int noise_seed, double noise_frequency,
		double p_noise_amplitude, int p_noise_octaves, double p_noise_lacunarity, double p_noise_gain,
		const Vector3 &p_bounds_center, const Vector3 &p_bounds_half, double p_bounds_clip_inset) {
	mat::ensure();
	Ref<WorldDensity> density;
	density.instantiate();
	density->noise_enabled = p_noise_enabled;
	density->noise_amplitude = p_noise_amplitude;
	density->noise_octaves = p_noise_octaves;
	density->noise_lacunarity = p_noise_lacunarity;
	density->noise_gain = p_noise_gain;
	density->bounds_center = p_bounds_center;
	density->bounds_half = p_bounds_half;
	density->bounds_clip_inset = p_bounds_clip_inset;
	if (p_noise_enabled) {
		// Perlin with the engine's default fractal (five octaves of FBm), under the manual one.
		density->base_noise = TNoise::make(noise_seed, TNoise::PERLIN, noise_frequency, -1);
	}
	density->init_ground_noises(noise_seed);
	return density;
}

Ref<WorldDensity> WorldDensity::create_open_terrain(int noise_seed, double noise_frequency, double p_noise_amplitude,
		int p_noise_octaves, double p_noise_lacunarity, double p_noise_gain, const Vector3 &p_bounds_center,
		const Vector3 &p_bounds_half, double p_bounds_clip_inset, bool open_edges_enabled,
		const Ref<Image> &heightmap_image, double p_surface_height_offset, bool solid_fill) {
	mat::ensure();
	Ref<WorldDensity> density;
	density.instantiate();
	density->open_terrain_enabled = true;
	density->open_terrain_edges_enabled = open_edges_enabled;
	density->open_terrain_solid_fill = solid_fill;
	density->surface_height_offset = p_surface_height_offset;
	density->noise_enabled = true;
	density->noise_amplitude = p_noise_amplitude;
	density->noise_octaves = p_noise_octaves;
	density->noise_lacunarity = p_noise_lacunarity;
	density->noise_gain = p_noise_gain;
	density->bounds_center = p_bounds_center;
	density->bounds_half = p_bounds_half;
	density->bounds_clip_inset = p_bounds_clip_inset;
	if (heightmap_image.is_valid() && !heightmap_image->is_empty()) {
		density->set_heightmap_image(heightmap_image);
	}
	density->init_open_terrain_height_noise(noise_seed, noise_frequency, p_noise_octaves, p_noise_lacunarity, p_noise_gain);
	if (!solid_fill) {
		density->init_boxed_in_terrain_noise(noise_seed, noise_frequency, p_noise_octaves, p_noise_lacunarity, p_noise_gain);
	}
	density->init_ground_noises(noise_seed);
	return density;
}

Ref<WorldDensity> WorldDensity::create_boxed_in_terrain(int noise_seed, double noise_frequency, int p_noise_octaves,
		double p_noise_lacunarity, double p_noise_gain, const Vector3 &p_bounds_center, const Vector3 &p_bounds_half,
		double p_bounds_clip_inset, bool boxed_edges_enabled) {
	mat::ensure();
	Ref<WorldDensity> density;
	density.instantiate();
	density->boxed_in_terrain_enabled = true;
	density->boxed_in_edges_enabled = boxed_edges_enabled;
	density->noise_enabled = true;
	density->noise_octaves = p_noise_octaves;
	density->noise_lacunarity = p_noise_lacunarity;
	density->noise_gain = p_noise_gain;
	density->bounds_center = p_bounds_center;
	density->bounds_half = p_bounds_half;
	density->bounds_clip_inset = p_bounds_clip_inset;
	density->init_boxed_in_terrain_noise(noise_seed, noise_frequency, p_noise_octaves, p_noise_lacunarity, p_noise_gain);
	density->init_ground_noises(noise_seed);
	return density;
}

Ref<WorldDensity> WorldDensity::clone_for_build() const {
	Ref<WorldDensity> copy;
	copy.instantiate();
	WorldDensity *clone = copy.ptr();
	clone->noise_enabled = noise_enabled;
	clone->noise_amplitude = noise_amplitude;
	clone->noise_octaves = noise_octaves;
	clone->noise_lacunarity = noise_lacunarity;
	clone->noise_gain = noise_gain;
	clone->bounds_center = bounds_center;
	clone->bounds_half = bounds_half;
	clone->bounds_clip_inset = bounds_clip_inset;
	clone->boxed_in_terrain_enabled = boxed_in_terrain_enabled;
	clone->boxed_in_edges_enabled = boxed_in_edges_enabled;
	clone->open_terrain_enabled = open_terrain_enabled;
	clone->open_terrain_edges_enabled = open_terrain_edges_enabled;
	clone->open_terrain_solid_fill = open_terrain_solid_fill;
	clone->surface_height_offset = surface_height_offset;
	clone->terrace_enabled = terrace_enabled;
	clone->terrace_step = terrace_step;
	clone->terrace_strength = terrace_strength;
	clone->terrace_phase = terrace_phase;
	clone->terrace_coverage = terrace_coverage;
	clone->surface_warp = surface_warp;
	clone->surface_ridge = surface_ridge;
	clone->surface_power = surface_power;
	clone->region_strength = region_strength;
	clone->region_lowland = region_lowland;
	clone->region_ridge = region_ridge;
	clone->region_detail = region_detail;
	clone->curve_floor = curve_floor;
	clone->curve_cliff = curve_cliff;
	clone->curve_cliff_at = curve_cliff_at;
	clone->curve_cliff_width = curve_cliff_width;
	clone->relief_amplitude = relief_amplitude;
	clone->relief_band = relief_band;
	clone->flat_spots = flat_spots;
	if (caves.is_valid()) {
		clone->caves = caves->clone();
	}
	clone->land_biomes = land_biomes;
	clone->land_patch_size = land_patch_size;
	clone->mounds_enabled = mounds_enabled;
	clone->mound_noise = mound_noise;
	clone->solids = solids;
	clone->solids_source = solids_source;
	clone->region_solids.clear();
	for (int index = 0; index < (int)solids.size(); index++) {
		clone->region_solids.push_back(index);
	}
	clone->terrain_edits = terrain_edits;
	clone->ore_seed = ore_seed;
	clone->flat_spot_heights = flat_spot_heights;
	clone->flat_spot_count = flat_spot_count;
	clone->region_noise = region_noise;
	clone->detail_noise = detail_noise;
	clone->relief_noise = relief_noise;
	clone->land_warp = land_warp;
	clone->land_seed = land_seed;
	clone->vein_noise = vein_noise;
	clone->ore_noise = ore_noise;
	clone->macro_noise = macro_noise;
	clone->height_noise = height_noise;
	clone->terrace_noise = terrace_noise;
	clone->warp_noise_x = warp_noise_x;
	clone->warp_noise_z = warp_noise_z;
	clone->base_noise = base_noise;
	clone->heightmap = heightmap;
	clone->heightmap_size = heightmap_size;
	return copy;
}

void WorldDensity::set_heightmap_image(const Ref<Image> &image) {
	heightmap.clear();
	heightmap_size = Vector2i();
	if (image.is_null() || image->is_empty()) {
		return;
	}
	heightmap_size = image->get_size();
	heightmap.resize(heightmap_size.x * heightmap_size.y);
	for (int y = 0; y < heightmap_size.y; y++) {
		for (int x = 0; x < heightmap_size.x; x++) {
			Color pixel = image->get_pixel(x, y);
			heightmap[x + y * heightmap_size.x] = ((double)pixel.r + (double)pixel.g + (double)pixel.b) / 3.0;
		}
	}
}

// --- Materials --------------------------------------------------------------------------------

int WorldDensity::natural_material(const Vector3 &world_position, double density_value) {
	double depth = -density_value;
	if (depth < TOPSOIL_DEPTH || !vein_noise.valid) {
		return mat::NATURAL;
	}
	if (!region_solids.empty()) {
		const SolidShape *solid = solid_shape_at(world_position);
		if (solid != nullptr && !solid->ground) {
			return mat::NATURAL;
		}
	}
	double vein = vein_noise.get_3dv(world_position);
	if (vein < VEIN_THRESHOLD) {
		if (ore_noise.get_3dv(world_position) < ORE_THRESHOLD) {
			return mat::STONE;
		}
		return ore_at(world_position, depth);
	}
	double which = vein_noise.get_3dv(world_position + Vector3(131.0f, 71.0f, 17.0f));
	if (which < -0.15) {
		return mat::SAND;
	}
	if (which < 0.15) {
		return mat::CLAY;
	}
	return mat::GRAVEL;
}

int WorldDensity::ground_material(const Vector3 &world_position, double density_value) {
	return natural_material(world_position, -depth_below_surface(world_position, density_value));
}

double WorldDensity::depth_below_surface(const Vector3 &world_position, double density_value) const {
	if (open_terrain_enabled) {
		double surface = sample_open_terrain_height(world_position.x, world_position.z);
		return surface - (double)world_position.y;
	}
	return -density_value;
}

static Color tint_of(const BiomeData &kind) {
	if (kind.empty) {
		return mat::natural_vertex_color();
	}
	return kind.tint;
}

Color WorldDensity::natural_tint(const Vector3 &world_position, double density_value) {
	if (!region_solids.empty()) {
		const SolidShape *solid = solid_shape_at(world_position);
		if (solid != nullptr) {
			return solid->has_tint ? solid->tint : mat::natural_vertex_color();
		}
	}
	if (mounds_enabled && open_terrain_enabled) {
		// A mound and its hollows wear the clay of the kind it stands in, down to its nest.
		TermiteMound mound;
		if (termites.near(world_position, *this, land_seed, mound_noise, 1.5, mound)) {
			return tint_of(land_biome_of(mound.base.x, mound.base.z));
		}
	}
	if (open_terrain_enabled) {
		double depth = depth_below_surface(world_position, density_value);
		if (depth > 1.5) {
			if (caves.is_valid()) {
				return tint_of(caves->biome_of(world_position, depth));
			}
		} else {
			return tint_of(land_biome_of(world_position.x, world_position.z));
		}
	}
	return mat::natural_vertex_color();
}

int WorldDensity::ore_at(const Vector3 &world_position, double depth) const {
	const mat::Table &table = mat::table();
	int total = 0;
	for (int kind : table.element_kinds) {
		if (depth >= table.ore_depths[kind]) {
			total += table.ore_weights[kind];
		}
	}
	if (total <= 0) {
		return mat::STONE;
	}
	Vector3 cell_f = (world_position / (real_t)ORE_POCKET_SIZE).floor();
	Vector3i cell = Vector3i((int)cell_f.x, (int)cell_f.y, (int)cell_f.z);
	int64_t draw_value = (thash::of(cell.x, cell.y, cell.z, ore_seed) & 0x7FFFFFFF) % total;
	for (int kind : table.element_kinds) {
		if (depth < table.ore_depths[kind]) {
			continue;
		}
		draw_value -= table.ore_weights[kind];
		if (draw_value < 0) {
			return kind;
		}
	}
	return mat::STONE;
}

void WorldDensity::init_ground_noises(int noise_seed) {
	ore_seed = noise_seed;
	// The engine's default fractal (five octaves of FBm) is kept, as the scripts kept it.
	vein_noise = TNoise::make(noise_seed + 77, TNoise::SIMPLEX, 0.09, -1);
	ore_noise = TNoise::make(noise_seed + 88, TNoise::SIMPLEX, 0.14, -1);
	land_seed = noise_seed + 1313;
	mound_noise = TNoise::make(noise_seed + 2909, TNoise::SIMPLEX_SMOOTH, 0.11, 2);
	refresh_land_warp();
}

void WorldDensity::refresh_land_warp() {
	land_warp = patches::make_warp(land_seed, land_patch_size);
}

const BiomeData &WorldDensity::land_biome_of(double world_x, double world_z) const {
	static const BiomeData empty;
	if (land_biomes.is_empty()) {
		return empty;
	}
	int pick = patches::pick(world_x, world_z, land_seed, land_patch_size, &land_warp, land_biomes.weights);
	return pick < 0 ? empty : land_biomes.kinds[pick];
}

String WorldDensity::land_summary() const {
	String summary = "land " + patches::shares(land_biomes.names(), land_biomes.weights_packed());
	if (mounds_enabled) {
		AABB map(bounds_center - bounds_half, bounds_half * 2.0f);
		int64_t count = (int64_t)TermiteMounds::in(map, *this, land_seed).size();
		summary += ", " + itos(count) + (count == 1 ? " termite mound" : " termite mounds");
	}
	return summary;
}

TypedArray<Dictionary> WorldDensity::termite_mounds_in(const AABB &p_area) const {
	TypedArray<Dictionary> out;
	if (!mounds_enabled) {
		return out;
	}
	for (const TermiteMound &mound : TermiteMounds::in(p_area, *this, land_seed)) {
		out.push_back(mound.to_dictionary());
	}
	return out;
}

void WorldDensity::set_land_biomes(const Array &value) {
	land_biomes.set(value);
	mounds_enabled = false;
	for (const BiomeData &kind : land_biomes.kinds) {
		mounds_enabled = mounds_enabled || kind.mounds > 0.0;
	}
	refresh_land_warp();
}

TypedArray<Dictionary> WorldDensity::get_land_biomes() const {
	TypedArray<Dictionary> out;
	for (int index = 0; index < land_biomes.source.size(); index++) {
		out.push_back(land_biomes.source[index]);
	}
	return out;
}

void WorldDensity::set_land_patch_size(double value) {
	land_patch_size = tmath::maxd(value, 1.0);
	refresh_land_warp();
}

// --- Noises -----------------------------------------------------------------------------------

void WorldDensity::init_boxed_in_terrain_noise(int terrain_seed, double surface_frequency, int octaves,
		double lacunarity, double gain) {
	macro_noise = TNoise::make(terrain_seed, TNoise::SIMPLEX, tmath::maxd(surface_frequency, 0.001), -1);
	macro_noise.set_fbm(octaves);
	macro_noise.set_lacunarity(lacunarity);
	macro_noise.set_gain(gain);
}

double WorldDensity::sample_boxed_in_terrain_noise(const Vector3 &world_position) const {
	if (!noise_enabled || !macro_noise.valid) {
		return 1.0;
	}
	return macro_noise.get_3d(world_position.x, world_position.y, world_position.z);
}

double WorldDensity::evaluate_boxed_in_terrain(const Vector3 &world_pos, bool with_edits) const {
	double value = sample_boxed_in_terrain_noise(world_pos);
	if (boxed_in_edges_enabled) {
		value = tmath::maxd(value,
				DensitySampler::boxed_in_terrain_box_sdf(world_pos, bounds_center, bounds_half, bounds_clip_inset));
	}
	if (!region_solids.empty()) {
		value = tmath::mind(value, solids_sdf(world_pos));
	}
	if (with_edits && terrain_edits.is_valid()) {
		value = terrain_edits->apply_to_density(value, world_pos);
	}
	return value;
}

void WorldDensity::init_open_terrain_height_noise(int terrain_seed, double surface_frequency, int octaves,
		double lacunarity, double gain) {
	height_noise = TNoise::make(terrain_seed, TNoise::SIMPLEX, tmath::maxd(surface_frequency, 0.001), -1);
	height_noise.set_fbm(octaves);
	height_noise.set_lacunarity(lacunarity);
	height_noise.set_gain(gain);
}

double WorldDensity::sample_heightmap(double world_x, double world_z) const {
	if ((double)bounds_half.x <= 0.0 || (double)bounds_half.z <= 0.0) {
		return bounds_center.y;
	}
	double normalized_x = (world_x - (double)bounds_center.x) / (double)bounds_half.x;
	double normalized_z = (world_z - (double)bounds_center.z) / (double)bounds_half.z;
	if (std::abs(normalized_x) > 1.0 || std::abs(normalized_z) > 1.0) {
		return bounds_center.y;
	}
	int sample_x = tmath::clampi((int)std::floor((normalized_x * 0.5 + 0.5) * (double)(heightmap_size.x - 1)), 0,
			heightmap_size.x - 1);
	int sample_z = tmath::clampi((int)std::floor((normalized_z * 0.5 + 0.5) * (double)(heightmap_size.y - 1)), 0,
			heightmap_size.y - 1);
	double height_sample = heightmap[sample_x + sample_z * heightmap_size.x];
	return (double)bounds_center.y + (height_sample - 0.5) * noise_amplitude * 2.0;
}

double WorldDensity::sample_open_terrain_height(double world_x, double world_z) const {
	double height;
	if (!heightmap.empty()) {
		height = sample_heightmap(world_x, world_z) + surface_height_offset;
	} else if (!noise_enabled || !height_noise.valid) {
		height = (double)bounds_center.y + surface_height_offset;
	} else {
		double mask = 0.0;
		if (region_strength > 0.0 && region_noise.valid) {
			mask = tmath::smoothstep(-0.45, 0.45, region_noise.get_2d(world_x, world_z));
		}
		double sample_x = world_x;
		double sample_z = world_z;
		if (surface_warp > 0.0 && warp_noise_x.valid) {
			double warp = surface_warp;
			if (region_strength > 0.0) {
				warp *= tmath::lerpd(1.0, tmath::lerpd(0.5, 1.5, mask), region_strength);
			}
			sample_x += warp_noise_x.get_2d(world_x, world_z) * warp;
			sample_z += warp_noise_z.get_2d(world_x, world_z) * warp;
		}
		double noise_value = height_noise.get_2d(sample_x, sample_z);
		double ridge = surface_ridge;
		if (region_ridge > 0.0) {
			ridge = tmath::maxd(ridge, region_ridge * mask * region_strength);
		}
		if (ridge > 0.0) {
			noise_value = tmath::lerpd(noise_value, 1.0 - 2.0 * std::abs(noise_value), ridge);
		}
		if (region_detail > 0.0 && mask > 0.0 && detail_noise.valid) {
			noise_value += detail_noise.get_2d(world_x, world_z) * region_detail * mask * region_strength;
		}
		double unit = tmath::clampd((noise_value + 1.0) * 0.5, 0.0, 1.0);
		if (!tmath::approx(surface_power, 1.0)) {
			unit = std::pow(unit, surface_power);
		}
		unit = curve_height(unit);
		double amplitude = noise_amplitude;
		if (region_strength > 0.0) {
			amplitude *= tmath::lerpd(1.0, tmath::lerpd(region_lowland, 1.0, mask), region_strength);
		}
		height = (double)bounds_center.y + (unit * 2.0 - 1.0) * amplitude + surface_height_offset;
	}
	if (terrace_enabled) {
		height = terrace_height(height, world_x, world_z);
	}
	if (flat_spot_count > 0) {
		height = flat_spot_height(height, world_x, world_z);
	}
	return height;
}

double WorldDensity::curve_height(double unit) const {
	if (curve_floor > 0.0) {
		double blend = tmath::clampd(0.5 + 0.5 * (unit - curve_floor) / CURVE_FLOOR_SOFTNESS, 0.0, 1.0);
		unit = tmath::lerpd(curve_floor, unit, blend) + CURVE_FLOOR_SOFTNESS * blend * (1.0 - blend);
	}
	if (curve_cliff > 0.0) {
		double steep = tmath::smoothstep(curve_cliff_at - curve_cliff_width, curve_cliff_at + curve_cliff_width, unit);
		unit = tmath::lerpd(unit, steep, curve_cliff);
	}
	return unit;
}

double WorldDensity::surface_slope(double world_x, double world_z, double height) const {
	double along_x = sample_open_terrain_height(world_x + 1.0, world_z) - height;
	double along_z = sample_open_terrain_height(world_x, world_z + 1.0) - height;
	return std::sqrt(along_x * along_x + along_z * along_z);
}

double WorldDensity::flat_spot_height(double height, double world_x, double world_z) const {
	for (int index = 0; index < flat_spot_count; index++) {
		const Vector4 &spot = flat_spots[index];
		double distance = Vector2((real_t)(world_x - (double)spot.x), (real_t)(world_z - (double)spot.y)).length();
		if (distance >= (double)spot.w) {
			continue;
		}
		double weight = tmath::smoothstep(spot.w, spot.z, distance) * FLAT_SPOT_BLEND;
		height = tmath::lerpd(height, flat_spot_heights[index], weight);
	}
	return height;
}

void WorldDensity::prepare_flat_spots() {
	flat_spot_count = 0;
	flat_spot_heights.resize(flat_spots.size());
	for (int index = 0; index < (int)flat_spots.size(); index++) {
		const Vector4 &spot = flat_spots[index];
		// Stored as the scripts stored it: in a PackedFloat32Array.
		flat_spot_heights[index] = (double)(float)sample_open_terrain_height(spot.x, spot.y);
	}
	flat_spot_count = (int)flat_spots.size();
}

TypedArray<Vector3> WorldDensity::flat_spot_points() const {
	TypedArray<Vector3> points;
	for (int index = 0; index < flat_spot_count; index++) {
		const Vector4 &spot = flat_spots[index];
		points.push_back(v3(spot.x, flat_spot_heights[index], spot.y));
	}
	return points;
}

void WorldDensity::set_flat_spots(const Array &value) {
	flat_spots.clear();
	for (int index = 0; index < value.size(); index++) {
		flat_spots.push_back(value[index]);
	}
}

TypedArray<Vector4> WorldDensity::get_flat_spots() const {
	TypedArray<Vector4> out;
	for (const Vector4 &spot : flat_spots) {
		out.push_back(spot);
	}
	return out;
}

double WorldDensity::terrace_height(double height, double world_x, double world_z) const {
	if (terrace_step <= 0.0) {
		return height;
	}
	double level = (height - terrace_phase) / terrace_step;
	double tread = std::floor(level);
	double along = level - tread;
	double riser = tmath::lerpd(0.5, 0.06, tmath::clampd(terrace_strength, 0.0, 1.0));
	double stepped = tread + tmath::smoothstep(0.5 - riser, 0.5 + riser, along);
	double shelved = terrace_phase + stepped * terrace_step;
	double share = 1.0;
	if (terrace_noise.valid) {
		double threshold = tmath::lerpd(1.2, -1.2, tmath::clampd(terrace_coverage, 0.0, 1.0));
		share = tmath::smoothstep(threshold - 0.2, threshold + 0.2, terrace_noise.get_2d(world_x, world_z));
	}
	return tmath::lerpd(height, shelved, share);
}

Ref<RandomNumberGenerator> WorldDensity::seeded_rng(int first, int second) {
	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed((uint64_t)thash::of(first, second));
	return rng;
}

double WorldDensity::draw(const Ref<RandomNumberGenerator> &rng, const Vector2 &value_range) {
	return rng->randf_range(MIN(value_range.x, value_range.y), MAX(value_range.x, value_range.y));
}

void WorldDensity::roll_terraces(int terrain_seed, double chance, const Vector2 &step_range,
		const Vector2 &strength_range, double coverage, bool force) {
	Ref<RandomNumberGenerator> rng = seeded_rng(terrain_seed, 3301);
	double rolled = rng->randf();
	terrace_step = rng->randf_range(MIN(step_range.x, step_range.y), MAX(step_range.x, step_range.y));
	terrace_strength = rng->randf_range(MIN(strength_range.x, strength_range.y), MAX(strength_range.x, strength_range.y));
	terrace_phase = rng->randf_range(0.0, terrace_step);
	terrace_coverage = coverage;
	terrace_enabled = force || rolled < chance;
	terrace_noise = TNoise::make(terrain_seed + 909, TNoise::SIMPLEX, 1.0 / 90.0, 0);
}

void WorldDensity::roll_surface(int terrain_seed, const Vector2 &power_range, double warp_chance,
		const Vector2 &warp_range, double ridge_chance, const Vector2 &ridge_range) {
	Ref<RandomNumberGenerator> rng = seeded_rng(terrain_seed, 4409);
	surface_power = rng->randf_range(MIN(power_range.x, power_range.y), MAX(power_range.x, power_range.y));
	double warp_rolled = rng->randf();
	double warp = rng->randf_range(MIN(warp_range.x, warp_range.y), MAX(warp_range.x, warp_range.y));
	surface_warp = warp_rolled < warp_chance ? warp : 0.0;
	double ridge_rolled = rng->randf();
	double ridge = rng->randf_range(MIN(ridge_range.x, ridge_range.y), MAX(ridge_range.x, ridge_range.y));
	surface_ridge = ridge_rolled < ridge_chance ? ridge : 0.0;
	init_warp_noise(terrain_seed);
}

void WorldDensity::init_warp_noise(int terrain_seed) {
	double frequency = 0.004;
	if (height_noise.valid) {
		frequency = (double)height_noise.frequency * 0.5;
	}
	warp_noise_x = TNoise::make(terrain_seed + 808, TNoise::SIMPLEX, frequency, 2);
	warp_noise_z = TNoise::make(terrain_seed + 809, TNoise::SIMPLEX, frequency, 2);
}

static String fmt(const char *format, const Array &args) {
	return String(format) % args;
}

String WorldDensity::surface_summary() const {
	PackedStringArray traits;
	if (surface_warp > 0.0) {
		traits.push_back(fmt("warp %d m", Array::make(tmath::roundi(surface_warp))));
	}
	if (surface_ridge > 0.0) {
		traits.push_back(fmt("ridges %.2f", Array::make(surface_ridge)));
	}
	if (!tmath::approx(surface_power, 1.0)) {
		traits.push_back(fmt("power %.1f", Array::make(surface_power)));
	}
	if (traits.is_empty()) {
		return "plain surface";
	}
	return String(", ").join(traits);
}

String WorldDensity::terrace_summary() const {
	if (!terrace_enabled) {
		return "no terraces";
	}
	return fmt("terraces every %.1f m, strength %.2f, over %d%% of the ground",
			Array::make(terrace_step, terrace_strength, tmath::roundi(terrace_coverage * 100.0)));
}

void WorldDensity::roll_regions(int terrain_seed, double chance, const Vector2 &size_range,
		const Vector2 &lowland_range, const Vector2 &ridge_range, const Vector2 &detail_range) {
	Ref<RandomNumberGenerator> rng = seeded_rng(terrain_seed, 5501);
	double rolled = rng->randf();
	double size = tmath::maxd(draw(rng, size_range), 1.0);
	region_lowland = tmath::clampd(draw(rng, lowland_range), 0.0, 1.0);
	region_ridge = tmath::clampd(draw(rng, ridge_range), 0.0, 1.0);
	region_detail = tmath::maxd(draw(rng, detail_range), 0.0);
	region_strength = rolled < chance ? 1.0 : 0.0;
	init_region_noise(terrain_seed, 1.0 / size);
}

void WorldDensity::init_region_noise(int terrain_seed, double mask_frequency) {
	region_noise = TNoise::make(terrain_seed + 1010, TNoise::SIMPLEX, mask_frequency, 0);
	double detail_frequency = height_noise.valid ? (double)height_noise.frequency * 4.0 : 0.032;
	detail_noise = TNoise::make(terrain_seed + 1011, TNoise::SIMPLEX, detail_frequency, 2);
}

double WorldDensity::highland_share() const {
	if (region_strength <= 0.0 || !region_noise.valid) {
		return 0.0;
	}
	int highland = 0;
	int steps = 16;
	for (int step_x = 0; step_x < steps; step_x++) {
		for (int step_z = 0; step_z < steps; step_z++) {
			double world_x = (double)bounds_center.x +
					(((double)step_x + 0.5) / (double)steps - 0.5) * 2.0 * (double)bounds_half.x;
			double world_z = (double)bounds_center.z +
					(((double)step_z + 0.5) / (double)steps - 0.5) * 2.0 * (double)bounds_half.z;
			if (region_noise.get_2d(world_x, world_z) > 0.0) {
				highland += 1;
			}
		}
	}
	return (double)highland / (double)(steps * steps);
}

String WorldDensity::region_summary() const {
	if (region_strength <= 0.0) {
		return "no regions";
	}
	return fmt("highland over %d%% (lowlands at %.2f of the height, ridges %.2f, detail %.2f)",
			Array::make(tmath::roundi(highland_share() * 100.0), region_lowland, region_ridge, region_detail));
}

void WorldDensity::roll_curve(int terrain_seed, double floor_chance, const Vector2 &floor_range, double cliff_chance,
		const Vector2 &cliff_range, const Vector2 &level_range, const Vector2 &width_range) {
	Ref<RandomNumberGenerator> rng = seeded_rng(terrain_seed, 5502);
	double floor_rolled = rng->randf();
	double floor_level = tmath::clampd(draw(rng, floor_range), 0.0, 1.0);
	curve_floor = floor_rolled < floor_chance ? floor_level : 0.0;
	double cliff_rolled = rng->randf();
	double cliff = tmath::clampd(draw(rng, cliff_range), 0.0, 1.0);
	curve_cliff_at = tmath::clampd(draw(rng, level_range), 0.0, 1.0);
	curve_cliff_width = tmath::maxd(draw(rng, width_range), 0.01);
	curve_cliff = cliff_rolled < cliff_chance ? cliff : 0.0;
}

String WorldDensity::curve_summary() const {
	PackedStringArray parts;
	if (curve_floor > 0.0) {
		parts.push_back(fmt("floor at %.2f", Array::make(curve_floor)));
	}
	if (curve_cliff > 0.0) {
		parts.push_back(fmt("cliffs %.1f at %.2f", Array::make(curve_cliff, curve_cliff_at)));
	}
	if (parts.is_empty()) {
		return "no height curve";
	}
	return String(", ").join(parts);
}

void WorldDensity::roll_relief(int terrain_seed, double chance, const Vector2 &amplitude_range) {
	Ref<RandomNumberGenerator> rng = seeded_rng(terrain_seed, 5504);
	double rolled = rng->randf();
	double amplitude = tmath::maxd(draw(rng, amplitude_range), 0.0);
	set_relief(rolled < chance ? amplitude : 0.0, terrain_seed);
}

void WorldDensity::set_relief(double amplitude, int terrain_seed) {
	relief_amplitude = amplitude;
	relief_band = amplitude * 2.0;
	if (amplitude <= 0.0) {
		relief_noise = TNoise();
		return;
	}
	relief_noise = TNoise::make(terrain_seed + 1212, TNoise::SIMPLEX, 1.0 / 6.0, 2);
}

String WorldDensity::relief_summary() const {
	if (relief_amplitude <= 0.0) {
		return "no relief";
	}
	return fmt("relief %.1f m", Array::make(relief_amplitude));
}

void WorldDensity::roll_flat_spots(int terrain_seed, const Vector2i &count_range, const Vector2 &radius_range) {
	Ref<RandomNumberGenerator> rng = seeded_rng(terrain_seed, 5505);
	int count = (int)rng->randi_range(MIN(count_range.x, count_range.y), MAX(count_range.x, count_range.y));
	flat_spots.clear();
	for (int index = 0; index < MAX(count, 0); index++) {
		double inner = tmath::maxd(draw(rng, radius_range), 1.0);
		double outer = inner + FLAT_SPOT_FADE;
		double reach_x = tmath::maxd((double)bounds_half.x - outer, 0.0);
		double reach_z = tmath::maxd((double)bounds_half.z - outer, 0.0);
		Vector4 spot = Vector4(bounds_center.x, bounds_center.z, (real_t)inner, (real_t)outer);
		for (int attempt = 0; attempt < 8; attempt++) {
			spot.x = (real_t)((double)bounds_center.x + (double)rng->randf_range(-reach_x, reach_x));
			spot.y = (real_t)((double)bounds_center.z + (double)rng->randf_range(-reach_z, reach_z));
			bool apart = true;
			for (const Vector4 &other : flat_spots) {
				if ((double)Vector2(spot.x - other.x, spot.y - other.y).length() < outer + (double)other.w) {
					apart = false;
					break;
				}
			}
			if (apart) {
				break;
			}
		}
		flat_spots.push_back(spot);
	}
	prepare_flat_spots();
}

String WorldDensity::flat_spot_summary() const {
	if (flat_spot_count == 0) {
		return "no flat spots";
	}
	if (flat_spot_count == 1) {
		return "1 flat spot";
	}
	return itos(flat_spot_count) + " flat spots";
}

// --- The density ------------------------------------------------------------------------------

double WorldDensity::evaluate_open_terrain_with_surface(const Vector3 &world_pos, double surface_height,
		bool with_edits, double slope) {
	double above_surface = (double)world_pos.y - surface_height;
	double value;
	if (open_terrain_solid_fill) {
		value = above_surface;
		if (relief_amplitude > 0.0 && std::abs(above_surface) < relief_band) {
			if (slope < 0.0) {
				slope = surface_slope(world_pos.x, world_pos.z, surface_height);
			}
			double steep = tmath::smoothstep(RELIEF_SLOPE_START, RELIEF_SLOPE_END, slope);
			if (steep > 0.0) {
				value += relief_noise.get_3dv(world_pos) * relief_amplitude * steep *
						(1.0 - std::abs(above_surface) / relief_band);
			}
		}
		if (caves.is_valid()) {
			if (slope < 0.0 && above_surface > -(caves->tunnel_depth + caves->fade)) {
				slope = surface_slope(world_pos.x, world_pos.z, surface_height);
			}
			value = caves->carve(value, world_pos, surface_height, tmath::maxd(slope, 0.0));
		}
	} else if (above_surface >= OPEN_TERRAIN_NOISE_SKIP_HEIGHT) {
		value = above_surface;
	} else {
		value = tmath::maxd(sample_boxed_in_terrain_noise(world_pos) * SPONGE_NOISE_METRES, above_surface);
	}
	if (mounds_enabled) {
		value = termites.apply(value, world_pos, *this, land_seed, mound_noise);
	}
	if (open_terrain_edges_enabled) {
		value = tmath::maxd(value,
				DensitySampler::open_terrain_box_sdf(world_pos, bounds_center, bounds_half, bounds_clip_inset));
	}
	if (!region_solids.empty()) {
		value = tmath::mind(value, solids_sdf(world_pos));
	}
	if (with_edits && terrain_edits.is_valid()) {
		value = terrain_edits->apply_to_density(value, world_pos);
	}
	return value;
}

double WorldDensity::evaluate(const Vector3 &world_pos, bool with_edits) {
	if (open_terrain_enabled) {
		double surface_height = sample_open_terrain_height(world_pos.x, world_pos.z);
		return evaluate_open_terrain_with_surface(world_pos, surface_height, with_edits);
	}
	if (boxed_in_terrain_enabled) {
		return evaluate_boxed_in_terrain(world_pos, with_edits);
	}
	double value = 1.0;
	if (noise_enabled) {
		value -= DensitySampler::fbm(base_noise, world_pos, noise_octaves, noise_lacunarity, noise_gain) * noise_amplitude;
	}
	if (!region_solids.empty()) {
		value = tmath::mind(value, solids_sdf(world_pos));
	}
	if (with_edits && terrain_edits.is_valid()) {
		value = terrain_edits->apply_to_density(value, world_pos);
	}
	return value;
}

Vector3 WorldDensity::gradient(const Vector3 &world_pos, double epsilon) {
	real_t offset = (real_t)epsilon;
	double dx = (evaluate(world_pos + Vector3(offset, 0, 0)) - evaluate(world_pos - Vector3(offset, 0, 0))) / (2.0 * epsilon);
	double dy = (evaluate(world_pos + Vector3(0, offset, 0)) - evaluate(world_pos - Vector3(0, offset, 0))) / (2.0 * epsilon);
	double dz = (evaluate(world_pos + Vector3(0, 0, offset)) - evaluate(world_pos - Vector3(0, 0, offset))) / (2.0 * epsilon);
	return v3(dx, dy, dz);
}

// --- Binding ----------------------------------------------------------------------------------

void WorldDensity::_bind_methods() {
	ClassDB::bind_static_method("WorldDensity",
			D_METHOD("create", "noise_enabled", "noise_seed", "noise_frequency", "noise_amplitude", "noise_octaves",
					"noise_lacunarity", "noise_gain", "bounds_center", "bounds_half", "bounds_clip_inset"),
			&WorldDensity::create, DEFVAL(0.5));
	ClassDB::bind_method(D_METHOD("clone_for_build"), &WorldDensity::clone_for_build);
	ClassDB::bind_static_method("WorldDensity", D_METHOD("stadium_sdf", "world_pos", "solid"), &WorldDensity::stadium_sdf);
	ClassDB::bind_static_method("WorldDensity", D_METHOD("solid_bounds", "solid"), &WorldDensity::solid_bounds);
	ClassDB::bind_method(D_METHOD("is_sky", "highest_surface", "bottom_y", "region"), &WorldDensity::is_sky);
	ClassDB::bind_method(D_METHOD("prepare_for_region", "region"), &WorldDensity::prepare_for_region);
	ClassDB::bind_method(D_METHOD("solid_at", "world_pos"), &WorldDensity::solid_at);
	ClassDB::bind_method(D_METHOD("natural_material", "world_position", "density_value"), &WorldDensity::natural_material);
	ClassDB::bind_method(D_METHOD("ground_material", "world_position", "density_value"), &WorldDensity::ground_material);
	ClassDB::bind_method(D_METHOD("depth_below_surface", "world_position", "density_value"), &WorldDensity::depth_below_surface);
	ClassDB::bind_method(D_METHOD("natural_tint", "world_position", "density_value"), &WorldDensity::natural_tint);
	ClassDB::bind_method(D_METHOD("ore_at", "world_position", "depth"), &WorldDensity::ore_at);
	ClassDB::bind_method(D_METHOD("land_biome", "world_x", "world_z"), &WorldDensity::land_biome);
	ClassDB::bind_method(D_METHOD("land_summary"), &WorldDensity::land_summary);
	ClassDB::bind_method(D_METHOD("termite_mounds_in", "area"), &WorldDensity::termite_mounds_in);
	ClassDB::bind_method(D_METHOD("sample_open_terrain_height", "world_x", "world_z"), &WorldDensity::sample_open_terrain_height);
	ClassDB::bind_method(D_METHOD("curve_height", "unit"), &WorldDensity::curve_height);
	ClassDB::bind_method(D_METHOD("surface_slope", "world_x", "world_z", "height"), &WorldDensity::surface_slope);
	ClassDB::bind_method(D_METHOD("flat_spot_height", "height", "world_x", "world_z"), &WorldDensity::flat_spot_height);
	ClassDB::bind_method(D_METHOD("prepare_flat_spots"), &WorldDensity::prepare_flat_spots);
	ClassDB::bind_method(D_METHOD("flat_spot_points"), &WorldDensity::flat_spot_points);
	ClassDB::bind_method(D_METHOD("terrace_height", "height", "world_x", "world_z"), &WorldDensity::terrace_height);
	ClassDB::bind_method(D_METHOD("roll_terraces", "terrain_seed", "chance", "step_range", "strength_range", "coverage", "force"), &WorldDensity::roll_terraces, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("roll_surface", "terrain_seed", "power_range", "warp_chance", "warp_range", "ridge_chance", "ridge_range"), &WorldDensity::roll_surface);
	ClassDB::bind_method(D_METHOD("init_warp_noise", "terrain_seed"), &WorldDensity::init_warp_noise);
	ClassDB::bind_method(D_METHOD("surface_summary"), &WorldDensity::surface_summary);
	ClassDB::bind_method(D_METHOD("terrace_summary"), &WorldDensity::terrace_summary);
	ClassDB::bind_method(D_METHOD("roll_regions", "terrain_seed", "chance", "size_range", "lowland_range", "ridge_range", "detail_range"), &WorldDensity::roll_regions);
	ClassDB::bind_method(D_METHOD("init_region_noise", "terrain_seed", "mask_frequency"), &WorldDensity::init_region_noise, DEFVAL(1.0 / 700.0));
	ClassDB::bind_method(D_METHOD("highland_share"), &WorldDensity::highland_share);
	ClassDB::bind_method(D_METHOD("region_summary"), &WorldDensity::region_summary);
	ClassDB::bind_method(D_METHOD("roll_curve", "terrain_seed", "floor_chance", "floor_range", "cliff_chance", "cliff_range", "level_range", "width_range"), &WorldDensity::roll_curve);
	ClassDB::bind_method(D_METHOD("curve_summary"), &WorldDensity::curve_summary);
	ClassDB::bind_method(D_METHOD("roll_relief", "terrain_seed", "chance", "amplitude_range"), &WorldDensity::roll_relief);
	ClassDB::bind_method(D_METHOD("set_relief", "amplitude", "terrain_seed"), &WorldDensity::set_relief);
	ClassDB::bind_method(D_METHOD("relief_reach"), &WorldDensity::relief_reach);
	ClassDB::bind_method(D_METHOD("region_mask_noise", "world_x", "world_z"), &WorldDensity::region_mask_noise);
	ClassDB::bind_static_method("WorldDensity", D_METHOD("topsoil_depth"), &WorldDensity::topsoil_depth);
	ClassDB::bind_method(D_METHOD("relief_summary"), &WorldDensity::relief_summary);
	ClassDB::bind_method(D_METHOD("roll_flat_spots", "terrain_seed", "count_range", "radius_range"), &WorldDensity::roll_flat_spots);
	ClassDB::bind_method(D_METHOD("flat_spot_summary"), &WorldDensity::flat_spot_summary);
	ClassDB::bind_method(D_METHOD("evaluate_open_terrain_with_surface", "world_pos", "surface_height", "with_edits", "slope"), &WorldDensity::evaluate_open_terrain_with_surface, DEFVAL(true), DEFVAL(-1.0));
	ClassDB::bind_method(D_METHOD("evaluate", "world_pos", "with_edits"), &WorldDensity::evaluate, DEFVAL(true));
	ClassDB::bind_method(D_METHOD("gradient", "world_pos", "epsilon"), &WorldDensity::gradient);
	ClassDB::bind_method(D_METHOD("set_heightmap_image", "image"), &WorldDensity::set_heightmap_image);

#define WD_PROP(vtype, name) TBIND(WorldDensity, vtype, name)
	WD_PROP(BOOL, noise_enabled)
	WD_PROP(FLOAT, noise_amplitude)
	WD_PROP(INT, noise_octaves)
	WD_PROP(FLOAT, noise_lacunarity)
	WD_PROP(FLOAT, noise_gain)
	WD_PROP(VECTOR3, bounds_center)
	WD_PROP(VECTOR3, bounds_half)
	WD_PROP(FLOAT, bounds_clip_inset)
	WD_PROP(BOOL, boxed_in_terrain_enabled)
	WD_PROP(BOOL, boxed_in_edges_enabled)
	WD_PROP(BOOL, open_terrain_enabled)
	WD_PROP(BOOL, open_terrain_edges_enabled)
	WD_PROP(BOOL, open_terrain_solid_fill)
	WD_PROP(FLOAT, surface_height_offset)
	WD_PROP(BOOL, terrace_enabled)
	WD_PROP(FLOAT, terrace_step)
	WD_PROP(FLOAT, terrace_strength)
	WD_PROP(FLOAT, terrace_phase)
	WD_PROP(FLOAT, terrace_coverage)
	WD_PROP(FLOAT, surface_warp)
	WD_PROP(FLOAT, surface_ridge)
	WD_PROP(FLOAT, surface_power)
	WD_PROP(FLOAT, region_strength)
	WD_PROP(FLOAT, region_lowland)
	WD_PROP(FLOAT, region_ridge)
	WD_PROP(FLOAT, region_detail)
	WD_PROP(FLOAT, curve_floor)
	WD_PROP(FLOAT, curve_cliff)
	WD_PROP(FLOAT, curve_cliff_at)
	WD_PROP(FLOAT, curve_cliff_width)
	WD_PROP(FLOAT, relief_amplitude)
	WD_PROP(FLOAT, relief_band)
	WD_PROP(INT, ore_seed)
	WD_PROP(ARRAY, flat_spots)
	WD_PROP(ARRAY, land_biomes)
	WD_PROP(FLOAT, land_patch_size)
	WD_PROP(ARRAY, solids)
	WD_PROP(OBJECT, caves)
	WD_PROP(OBJECT, terrain_edits)
#undef WD_PROP
}

} // namespace godot
