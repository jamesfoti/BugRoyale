#include "cave_carver.h"

#include "terrain_settings.h"

namespace godot {

double CaveCarver::draw(const Ref<RandomNumberGenerator> &rng, const Dictionary &ranges, const String &field,
		double least, double most) {
	if (ranges.has(field)) {
		Vector2 range_value = ranges[field];
		return rng->randf_range(range_value.x, range_value.y);
	}
	return rng->randf_range(least, most);
}

Ref<CaveCarver> CaveCarver::from_seed(int value, double p_bedrock_y, const Dictionary &ranges) {
	Ref<CaveCarver> carver;
	carver.instantiate();
	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed((uint64_t)thash::of(value, 7919));
	carver->world_seed = value;
	carver->floor_y = p_bedrock_y;
	carver->tunnel_frequency = rng->randf_range(0.014, 0.024);
	carver->tunnel_threshold = rng->randf_range(0.25, 0.35);
	carver->tunnel_depth = draw(rng, ranges, "tunnel_depth", 6.0, 12.0);
	carver->cavern_frequency = rng->randf_range(0.009, 0.022);
	carver->cavern_cutoff = rng->randf_range(0.38, 0.6);
	carver->cavern_depth = rng->randf_range(16.0, 26.0);
	carver->sinkhole_threshold = rng->randf_range(0.36, 0.5);
	carver->warp_metres = rng->randf_range(4.0, 10.0);
	carver->warp_frequency = rng->randf_range(0.005, 0.01);
	if (rng->randf() < RAVINE_CHANCE) {
		carver->ravine_width = rng->randf_range(0.05, 0.08);
		carver->ravine_frequency = rng->randf_range(0.01, 0.02);
		carver->ravine_depth = rng->randf_range(8.0, 18.0);
		carver->ravine_lean = rng->randf_range(0.25, 0.6);
	}
	carver->cavern_squash = rng->randf_range(1.2, 2.2);
	carver->region_size = rng->randf_range(150.0, 400.0);
	// The condition is drawn before the value, as the script's conditional expression has it.
	if (rng->randf() < 0.5) {
		carver->region_lean = rng->randf_range(0.5, 0.8);
	} else {
		carver->region_lean = 0.0;
	}
	carver->region_rich = rng->randf_range(1.0, 1.25);
	carver->region_bias = rng->randf_range(-0.2, 0.2);
	carver->thickness_size = rng->randf_range(40.0, 80.0);
	carver->thickness_thin = rng->randf_range(0.5, 0.7);
	carver->thickness_thick = rng->randf_range(1.2, 1.5);
	carver->deep_depth = rng->randf_range(120.0, 260.0);
	carver->deep_tunnels = rng->randf_range(0.3, 0.7);
	carver->deep_rooms = rng->randf_range(1.2, 1.6);
	carver->seam_width = rng->randf_range(3.0, 8.0);
	carver->seam_strength = rng->randf_range(0.5, 1.0);
	carver->band_wave = rng->randf_range(5.0, 20.0);
	if (rng->randf() < FLOOR_CHANCE) {
		carver->floor_spacing = rng->randf_range(24.0, 48.0);
		carver->floor_thickness = rng->randf_range(2.0, 4.0);
	}
	carver->hall_size = rng->randf_range(120.0, 200.0);
	carver->hall_cutoff = rng->randf_range(0.55, 0.7);
	carver->shaft_frequency = rng->randf_range(0.009, 0.015);
	carver->shaft_width = rng->randf_range(0.12, 0.2);
	carver->shaft_lean = rng->randf_range(0.08, 0.2);
	carver->shaft_share = rng->randf_range(0.35, 0.55);
	carver->tunnel_ramp = draw(rng, ranges, "tunnel_ramp", 20.0, 40.0);
	carver->shallow_cutoff = draw(rng, ranges, "shallow_cutoff", 0.25, 0.45);
	carver->ceiling_jag = draw(rng, ranges, "ceiling_jag", 0.8, 2.0);
	carver->rubble = draw(rng, ranges, "rubble", 0.3, 0.8);
	carver->water_share = draw(rng, ranges, "water_share", 0.4, 0.8);
	carver->aquifer_size = draw(rng, ranges, "aquifer_size", 120.0, 220.0);
	carver->make_noises();
	return carver;
}

Ref<CaveCarver> CaveCarver::for_settings(const Ref<TerrainSettings> &settings) {
	Ref<CaveCarver> carver = from_seed(settings->noise_seed,
			bedrock_y(settings->world_origin.y, settings->chunks_y, settings->chunk_world_size),
			settings->open_terrain_cave_ranges);
	if (settings->open_terrain_cave_roll == 1) {
		carver->apply(settings->open_terrain_cave_values);
	} else {
		carver->apply(settings->open_terrain_cave_shape);
	}
	carver->water_top = (double)settings->bounds_center.y + settings->open_terrain_surface_offset - WATER_UNDER_SURFACE;
	return carver;
}

double CaveCarver::bedrock_y(double origin_y, int chunks_y, double chunk_world_size) {
	return origin_y - (double)chunks_y * chunk_world_size * 0.5 + FLOOR_MARGIN;
}

Ref<CaveCarver> CaveCarver::clone() const {
	Ref<CaveCarver> copy;
	copy.instantiate();
	CaveCarver *c = copy.ptr();
	c->world_seed = world_seed;
	c->tunnel_frequency = tunnel_frequency;
	c->tunnel_threshold = tunnel_threshold;
	c->tunnel_depth = tunnel_depth;
	c->tunnel_ramp = tunnel_ramp;
	c->shallow_cutoff = shallow_cutoff;
	c->fade = fade;
	c->shallow_size = shallow_size;
	c->cavern_frequency = cavern_frequency;
	c->cavern_cutoff = cavern_cutoff;
	c->cavern_depth = cavern_depth;
	c->cavern_squash = cavern_squash;
	c->sinkhole_threshold = sinkhole_threshold;
	c->ravine_frequency = ravine_frequency;
	c->ravine_width = ravine_width;
	c->ravine_depth = ravine_depth;
	c->ravine_lean = ravine_lean;
	c->warp_metres = warp_metres;
	c->warp_frequency = warp_frequency;
	c->region_size = region_size;
	c->region_lean = region_lean;
	c->region_rich = region_rich;
	c->region_bias = region_bias;
	c->thickness_size = thickness_size;
	c->thickness_thin = thickness_thin;
	c->thickness_thick = thickness_thick;
	c->deep_depth = deep_depth;
	c->deep_tunnels = deep_tunnels;
	c->deep_rooms = deep_rooms;
	c->seam_width = seam_width;
	c->seam_strength = seam_strength;
	c->band_wave = band_wave;
	c->floor_spacing = floor_spacing;
	c->floor_thickness = floor_thickness;
	c->hall_size = hall_size;
	c->hall_cutoff = hall_cutoff;
	c->shaft_frequency = shaft_frequency;
	c->shaft_width = shaft_width;
	c->shaft_lean = shaft_lean;
	c->ceiling_jag = ceiling_jag;
	c->rubble = rubble;
	c->biomes = biomes;
	c->biome_patch_size = biome_patch_size;
	c->biome_fixed = biome_fixed;
	c->water_share = water_share;
	c->aquifer_size = aquifer_size;
	c->water_top = water_top;
	c->shaft_share = shaft_share;
	c->floor_y = floor_y;
	if (systems.is_valid()) {
		c->systems = systems->clone();
	}
	c->tunnel_noise = tunnel_noise;
	c->tunnel_noise_b = tunnel_noise_b;
	c->cavern_noise = cavern_noise;
	c->sinkhole_noise = sinkhole_noise;
	c->ravine_noise = ravine_noise;
	c->warp_noise = warp_noise;
	c->region_noise = region_noise;
	c->thickness_noise = thickness_noise;
	c->wave_noise = wave_noise;
	c->hall_noise = hall_noise;
	c->shaft_noise = shaft_noise;
	c->shaft_noise_b = shaft_noise_b;
	c->shaft_map = shaft_map;
	c->shallow_map = shallow_map;
	c->ceiling_noise = ceiling_noise;
	c->rubble_noise = rubble_noise;
	c->pillar_noise = pillar_noise;
	c->biome_warp = biome_warp;
	return copy;
}

void CaveCarver::apply(const Dictionary &values) {
	Array keys = values.keys();
	for (int i = 0; i < keys.size(); i++) {
		set(keys[i], values[keys[i]]);
	}
	make_noises();
}

void CaveCarver::make_noises() {
	tunnel_noise = TNoise::make(world_seed + 404, TNoise::SIMPLEX, tunnel_frequency, 1);
	tunnel_noise_b = TNoise::make(world_seed + 405, TNoise::SIMPLEX, tunnel_frequency, 1);
	cavern_noise = TNoise::make(world_seed + 606, TNoise::SIMPLEX, cavern_frequency, 1);
	sinkhole_noise = TNoise::make(world_seed + 505, TNoise::SIMPLEX, 1.0 / 70.0, 1);
	ravine_noise = TNoise::make(world_seed + 707, TNoise::SIMPLEX, ravine_frequency, 2);
	warp_noise = TNoise::make(world_seed + 808, TNoise::SIMPLEX, warp_frequency, 1);
	region_noise = TNoise::make(world_seed + 909, TNoise::SIMPLEX, 1.0 / region_size, 1);
	thickness_noise = TNoise::make(world_seed + 910, TNoise::SIMPLEX, 1.0 / thickness_size, 1);
	wave_noise = TNoise::make(world_seed + 911, TNoise::SIMPLEX, 1.0 / 140.0, 1);
	hall_noise = TNoise::make(world_seed + 912, TNoise::SIMPLEX, 1.0 / hall_size, 1);
	shaft_noise = TNoise::make(world_seed + 913, TNoise::SIMPLEX, shaft_frequency, 1);
	shaft_noise_b = TNoise::make(world_seed + 914, TNoise::SIMPLEX, shaft_frequency, 1);
	shaft_map = TNoise::make(world_seed + 915, TNoise::SIMPLEX, 1.0 / 150.0, 1);
	shallow_map = TNoise::make(world_seed + 916, TNoise::SIMPLEX, 1.0 / shallow_size, 1);
	ceiling_noise = TNoise::make(world_seed + 917, TNoise::SIMPLEX, 1.0 / 4.0, 2);
	rubble_noise = TNoise::make(world_seed + 918, TNoise::SIMPLEX, 1.0 / 2.5, 1);
	pillar_noise = TNoise::make(world_seed + 920, TNoise::SIMPLEX, PILLAR_FREQUENCY, 1);
	refresh_biome_warp();
}

void CaveCarver::refresh_biome_warp() {
	biome_warp = patches::make_warp(world_seed + 919, biome_patch_size);
}

void CaveCarver::set_biomes(const Array &value) {
	biomes.set(value);
	refresh_biome_warp();
}

TypedArray<Dictionary> CaveCarver::get_biomes() const {
	TypedArray<Dictionary> out;
	for (int i = 0; i < biomes.source.size(); i++) {
		out.push_back(biomes.source[i]);
	}
	return out;
}

void CaveCarver::set_biome_patch_size(double value) {
	biome_patch_size = tmath::maxd(value, 1.0);
	refresh_biome_warp();
}

double CaveCarver::carve(double value, const Vector3 &world_pos, double surface_height, double slope) {
	double depth = surface_height - (double)world_pos.y;
	if (depth > 0.0 && (double)world_pos.y > floor_y + FLOOR_CLEARANCE) {
		value = tmath::maxd(value, air(world_pos, depth, slope));
	}
	return tmath::mind(value, (double)world_pos.y - floor_y);
}

double CaveCarver::air(const Vector3 &world_pos, double depth, double slope) {
	double widen = tmath::mind(1.0 + depth * WIDEN_PER_METRE, WIDEN_MAX);
	Vector3 read_pos = world_pos;
	if (warp_metres > 0.0 && warp_noise.valid) {
		read_pos.x = (real_t)((double)read_pos.x + warp_noise.get_3dv(world_pos) * warp_metres);
		read_pos.z = (real_t)((double)read_pos.z +
				warp_noise.get_3d((double)world_pos.x + 97.0, (double)world_pos.y + 41.0, (double)world_pos.z + 31.0) *
						warp_metres);
	}
	double bed = depth;
	if (band_wave > 0.0 && wave_noise.valid) {
		bed += wave_noise.get_2d(world_pos.x, world_pos.z) * band_wave;
	}
	double deep = tmath::smoothstep(deep_depth - BAND_FADE, deep_depth + BAND_FADE, bed);
	double richness = region_richness(world_pos) * seam(bed);
	double opening = tmath::smoothstep(sinkhole_threshold - 0.1, sinkhole_threshold + 0.1,
			sinkhole_noise.get_2d(world_pos.x, world_pos.z));
	double start = tmath::smoothstep(tunnel_depth - fade, tunnel_depth + fade, depth);
	if (start > 0.0 && tunnel_ramp > 0.0 && depth < tunnel_depth + tunnel_ramp) {
		double spread = tmath::smoothstep(tunnel_depth, tunnel_depth + tunnel_ramp, depth);
		double cut = tmath::lerpd(shallow_cutoff, -1.2, spread);
		start *= tmath::smoothstep(cut - 0.05, cut + 0.05, shallow_map.get_2d(world_pos.x, world_pos.z));
	}
	if (slope > STEEP_START) {
		start = tmath::maxd(start, tmath::smoothstep(STEEP_START, STEEP_END, slope));
	}
	double tunnel_mask = tmath::maxd(start, opening) * richness * tmath::lerpd(1.0, deep_tunnels, deep);
	double best = -tmath::INF_D;
	if (tunnel_mask > 0.0) {
		double tunnel = tunnel_threshold * widen * tunnel_mask * thickness(read_pos) -
				tmath::maxd(std::abs(tunnel_noise.get_3dv(read_pos)), std::abs(tunnel_noise_b.get_3dv(read_pos)));
		best = tunnel / (2.0 * tunnel_frequency);
	}
	double cavern_mask = tmath::smoothstep(cavern_depth - fade, cavern_depth + fade, bed) * richness;
	if (cavern_mask > 0.0) {
		double grow = widen * tmath::lerpd(1.0, deep_rooms, deep);
		double cutoff = tmath::lerpd(1.0, cavern_cutoff / grow, cavern_mask);
		double room_noise = cavern_noise.get_3d(read_pos.x, (double)read_pos.y * cavern_squash, read_pos.z);
		double cavern = (room_noise - cutoff) / (2.0 * cavern_frequency);
		if (std::abs(cavern) < WALL_BAND && (ceiling_jag > 0.0 || rubble > 0.0)) {
			const BiomeData &kind = biome_of(world_pos, depth);
			double above = cavern_noise.get_3d(read_pos.x, ((double)read_pos.y + 1.0) * cavern_squash, read_pos.z);
			if (above < room_noise) {
				double jag = ceiling_jag * kind.ceiling_jag;
				cavern += ceiling_noise.get_3dv(read_pos) * jag;
			} else {
				double scree = rubble * kind.rubble;
				cavern -= std::abs(rubble_noise.get_3dv(read_pos)) * scree;
			}
		}
		double pillar = (PILLAR_CUTOFF - pillar_noise.get_2d(read_pos.x, read_pos.z)) / (2.0 * PILLAR_FREQUENCY);
		if (pillar < cavern && biome_of(world_pos, depth).pillars) {
			cavern = pillar;
		}
		best = blend(best, tmath::mind(cavern, floor_slab(bed)));
	}
	if (hall_cutoff < 1.0 && deep > 0.0) {
		double hall_edge = tmath::lerpd(1.0, hall_cutoff, deep);
		double hall = hall_noise.get_3d(read_pos.x, (double)read_pos.y * cavern_squash, read_pos.z) - hall_edge;
		best = blend(best, hall * hall_size / 2.0);
	}
	if (shaft_width > 0.0) {
		double shaft_mask = tmath::smoothstep(tunnel_depth - fade, tunnel_depth + fade, depth) *
				tmath::smoothstep(shaft_share - 0.1, shaft_share + 0.1, shaft_map.get_2d(world_pos.x, world_pos.z));
		if (shaft_mask > 0.0) {
			double lean_y = (double)read_pos.y * shaft_lean;
			double shaft = shaft_width * shaft_mask -
					tmath::maxd(std::abs(shaft_noise.get_3d(read_pos.x, lean_y, read_pos.z)),
							std::abs(shaft_noise_b.get_3d(read_pos.x, lean_y, read_pos.z)));
			best = blend(best, shaft / (2.0 * shaft_frequency));
		}
	}
	if (ravine_width > 0.0 && depth < ravine_depth) {
		double pinch = std::sqrt(1.0 - tmath::maxd(depth, 0.0) / ravine_depth);
		double gash = ravine_width * pinch -
				std::abs(ravine_noise.get_3d(read_pos.x, (double)read_pos.y * ravine_lean, read_pos.z));
		best = blend(best, gash / (2.0 * ravine_frequency));
	}
	if (systems.is_valid()) {
		best = blend(best, systems->air(read_pos));
	}
	if (water_top > -tmath::INF_D) {
		best = tmath::mind(best, barrier(world_pos));
	}
	return best;
}

Vector3 CaveCarver::aquifer(double world_x, double world_z) {
	Vector2 key = Vector2((real_t)world_x, (real_t)world_z);
	auto found = aquifer_cache.find(key);
	if (found != aquifer_cache.end()) {
		return found->second;
	}
	Vector3 cells = aquifer_cells(world_x, world_z);
	if (aquifer_cache.size() < 16384) {
		aquifer_cache[key] = cells;
	}
	return cells;
}

Vector3 CaveCarver::aquifer_cells(double world_x, double world_z) const {
	int cell_x = tmath::floori(world_x / aquifer_size);
	int cell_z = tmath::floori(world_z / aquifer_size);
	double nearest = tmath::INF_D;
	double second = tmath::INF_D;
	double nearest_level = -tmath::INF_D;
	double second_level = -tmath::INF_D;
	Vector2 here = Vector2((real_t)world_x, (real_t)world_z);
	for (int dz = -1; dz < 2; dz++) {
		for (int dx = -1; dx < 2; dx++) {
			int cx = cell_x + dx;
			int cz = cell_z + dz;
			int64_t bits = thash::of(cx, cz, world_seed + 921) & 0x7FFFFFFF;
			Vector2 centre = Vector2(
					(real_t)(((double)cx + 0.2 + 0.6 * (double)(bits & 0xFF) / 255.0) * aquifer_size),
					(real_t)(((double)cz + 0.2 + 0.6 * (double)((bits >> 8) & 0xFF) / 255.0) * aquifer_size));
			double distance = centre.distance_to(here);
			double level = -tmath::INF_D;
			if ((double)((bits >> 16) & 0xFF) / 255.0 < water_share) {
				level = tmath::lerpd(floor_y + WATER_FLOOR, water_top, (double)((bits >> 24) & 0x7F) / 127.0);
			}
			if (distance < nearest) {
				second = nearest;
				second_level = nearest_level;
				nearest = distance;
				nearest_level = level;
			} else if (distance < second) {
				second = distance;
				second_level = level;
			}
		}
	}
	return v3(nearest_level, second_level, second - nearest);
}

double CaveCarver::water_level(double world_x, double world_z) {
	if (water_top == -tmath::INF_D) {
		return -tmath::INF_D;
	}
	return aquifer(world_x, world_z).x;
}

double CaveCarver::barrier(const Vector3 &world_pos) {
	if ((double)world_pos.y > water_top + 1.0) {
		return tmath::INF_D;
	}
	Vector3 cells = aquifer(world_pos.x, world_pos.z);
	if (tmath::approx(cells.x, cells.y) || (double)world_pos.y > tmath::maxd(cells.x, cells.y) + 1.0) {
		return tmath::INF_D;
	}
	return (double)cells.z * 0.5 - BARRIER;
}

double CaveCarver::region_richness(const Vector3 &world_pos) const {
	if (!region_noise.valid || tmath::approx(region_lean, region_rich)) {
		return region_rich;
	}
	double mask = tmath::smoothstep(-REGION_EDGE, REGION_EDGE, region_noise.get_3dv(world_pos) - region_bias);
	return tmath::lerpd(region_lean, region_rich, mask);
}

double CaveCarver::seam(double bed) const {
	if (seam_strength <= 0.0) {
		return 1.0;
	}
	double nearest = tmath::mind(std::abs(bed - cavern_depth), std::abs(bed - deep_depth));
	return 1.0 - seam_strength * (1.0 - tmath::smoothstep(0.0, seam_width, nearest));
}

double CaveCarver::thickness(const Vector3 &read_pos) const {
	if (!thickness_noise.valid || tmath::approx(thickness_thin, thickness_thick)) {
		return thickness_thick;
	}
	return tmath::lerpd(thickness_thin, thickness_thick, 0.5 + 0.5 * thickness_noise.get_3dv(read_pos));
}

double CaveCarver::floor_slab(double bed) const {
	if (floor_thickness <= 0.0) {
		return tmath::INF_D;
	}
	double into = tmath::fposmod(bed, floor_spacing);
	if (into < floor_thickness) {
		return -tmath::mind(into, floor_thickness - into);
	}
	return tmath::mind(into - floor_thickness, floor_spacing - into);
}

static const BiomeData &empty_biome() {
	static const BiomeData empty;
	return empty;
}

const BiomeData &CaveCarver::biome_of(const Vector3 &world_pos, double depth) const {
	if (!biome_fixed.empty) {
		return biome_fixed;
	}
	if (biomes.is_empty()) {
		return empty_biome();
	}
	int pick = patches::pick(world_pos.x, world_pos.z, world_seed + 919, biome_patch_size, &biome_warp, biomes.weights);
	if (pick >= 0 && biomes.kinds[pick].holds(depth)) {
		return biomes.kinds[pick];
	}
	for (const BiomeData &kind : biomes.kinds) {
		if (kind.weight > 0.0 && kind.holds(depth)) {
			return kind;
		}
	}
	return empty_biome();
}

bool CaveCarver::is_cave(const Vector3 &world_pos, double surface_height) {
	double depth = surface_height - (double)world_pos.y;
	return depth > 0.0 && (double)world_pos.y > floor_y + FLOOR_CLEARANCE && air(world_pos, depth) > 0.0;
}

static String fmt(const char *format, const Array &args) {
	return String(format) % args;
}

String CaveCarver::summary() const {
	String ravines = "no ravines";
	if (ravine_width > 0.0) {
		ravines = fmt("ravines %.2f to %d m down", Array::make(ravine_width, tmath::roundi(ravine_depth)));
	}
	String floors = "no floors";
	if (floor_thickness > 0.0) {
		floors = fmt("floors every %d m", Array::make(tmath::roundi(floor_spacing)));
	}
	String carved = systems.is_null() ? String("") : ", " + systems->summary();
	carved += fmt(", ceilings %.1f m, rubble %.1f m", Array::make(ceiling_jag, rubble));
	carved += ", caves " + patches::shares(biomes.names(), biomes.weights_packed());
	if (water_top > -tmath::INF_D) {
		carved += fmt(", water in %d%% of aquifers %d m across",
				Array::make(tmath::roundi(water_share * 100.0), tmath::roundi(aquifer_size)));
	}
	Array args;
	args.push_back(tunnel_threshold);
	args.push_back(tmath::roundi(tunnel_depth));
	args.push_back(tmath::roundi(tunnel_depth + tunnel_ramp));
	args.push_back(cavern_cutoff);
	args.push_back(tmath::roundi(cavern_depth));
	args.push_back(tmath::roundi(deep_depth));
	args.push_back(tmath::roundi(region_size));
	args.push_back(region_lean);
	args.push_back(region_rich);
	args.push_back(tmath::roundi(seam_width));
	args.push_back(floors);
	args.push_back(hall_cutoff);
	args.push_back(shaft_width);
	args.push_back(ravines);
	args.push_back(tmath::roundi(warp_metres));
	args.push_back(tmath::roundi(floor_y));
	return fmt("tunnels %.2f from %d m down, everywhere from %d m, caverns %.2f from %d m down, "
			   "deep from %d m, "
			   "regions %d m (%.1f to %.1f), seams %d m, %s, halls %.2f, shafts %.2f, %s, "
			   "warp %d m, bedrock at %d m",
				   args) +
			carved;
}

void CaveCarver::_bind_methods() {
	ClassDB::bind_static_method("CaveCarver", D_METHOD("from_seed", "value", "bedrock_y", "ranges"), &CaveCarver::from_seed, DEFVAL(Dictionary()));
	ClassDB::bind_static_method("CaveCarver", D_METHOD("for_settings", "settings"), &CaveCarver::for_settings);
	ClassDB::bind_static_method("CaveCarver", D_METHOD("bedrock_y", "origin_y", "chunks_y", "chunk_world_size"), &CaveCarver::bedrock_y);
	ClassDB::bind_static_method("CaveCarver", D_METHOD("floor_margin"), &CaveCarver::floor_margin);
	ClassDB::bind_static_method("CaveCarver", D_METHOD("fade_default"), &CaveCarver::fade_default);
	ClassDB::bind_static_method("CaveCarver", D_METHOD("water_floor"), &CaveCarver::water_floor);
	ClassDB::bind_method(D_METHOD("apply", "values"), &CaveCarver::apply);
	ClassDB::bind_method(D_METHOD("carve", "value", "world_pos", "surface_height", "slope"), &CaveCarver::carve, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("air", "world_pos", "depth", "slope"), &CaveCarver::air, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("aquifer", "world_x", "world_z"), &CaveCarver::aquifer);
	ClassDB::bind_method(D_METHOD("water_level", "world_x", "world_z"), &CaveCarver::water_level);
	ClassDB::bind_method(D_METHOD("barrier", "world_pos"), &CaveCarver::barrier);
	ClassDB::bind_method(D_METHOD("region_richness", "world_pos"), &CaveCarver::region_richness);
	ClassDB::bind_method(D_METHOD("seam", "bed"), &CaveCarver::seam);
	ClassDB::bind_method(D_METHOD("thickness", "read_pos"), &CaveCarver::thickness);
	ClassDB::bind_method(D_METHOD("floor_slab", "bed"), &CaveCarver::floor_slab);
	ClassDB::bind_method(D_METHOD("biome", "world_pos", "depth"), &CaveCarver::biome);
	ClassDB::bind_method(D_METHOD("is_cave", "world_pos", "surface_height"), &CaveCarver::is_cave);
	ClassDB::bind_method(D_METHOD("summary"), &CaveCarver::summary);
	ClassDB::bind_method(D_METHOD("make_noises"), &CaveCarver::make_noises);
	ClassDB::bind_static_method("CaveCarver", D_METHOD("_blend", "a", "b"), &CaveCarver::blend);
	ClassDB::bind_method(D_METHOD("tunnel_noise_frequency"), &CaveCarver::tunnel_noise_frequency);
	ClassDB::bind_integer_constant(get_class_static(), "", "FADE", 3);
	ClassDB::bind_integer_constant(get_class_static(), "", "WATER_FLOOR", 6);

#define CAVE_PROP(vtype, name) TBIND(CaveCarver, vtype, name)
	CAVE_PROP(INT, world_seed)
	CAVE_PROP(FLOAT, tunnel_frequency)
	CAVE_PROP(FLOAT, tunnel_threshold)
	CAVE_PROP(FLOAT, tunnel_depth)
	CAVE_PROP(FLOAT, tunnel_ramp)
	CAVE_PROP(FLOAT, shallow_cutoff)
	CAVE_PROP(FLOAT, fade)
	CAVE_PROP(FLOAT, shallow_size)
	CAVE_PROP(FLOAT, cavern_frequency)
	CAVE_PROP(FLOAT, cavern_cutoff)
	CAVE_PROP(FLOAT, cavern_depth)
	CAVE_PROP(FLOAT, cavern_squash)
	CAVE_PROP(FLOAT, sinkhole_threshold)
	CAVE_PROP(FLOAT, ravine_frequency)
	CAVE_PROP(FLOAT, ravine_width)
	CAVE_PROP(FLOAT, ravine_depth)
	CAVE_PROP(FLOAT, ravine_lean)
	CAVE_PROP(FLOAT, warp_metres)
	CAVE_PROP(FLOAT, warp_frequency)
	CAVE_PROP(FLOAT, region_size)
	CAVE_PROP(FLOAT, region_lean)
	CAVE_PROP(FLOAT, region_rich)
	CAVE_PROP(FLOAT, region_bias)
	CAVE_PROP(FLOAT, thickness_size)
	CAVE_PROP(FLOAT, thickness_thin)
	CAVE_PROP(FLOAT, thickness_thick)
	CAVE_PROP(FLOAT, deep_depth)
	CAVE_PROP(FLOAT, deep_tunnels)
	CAVE_PROP(FLOAT, deep_rooms)
	CAVE_PROP(FLOAT, seam_width)
	CAVE_PROP(FLOAT, seam_strength)
	CAVE_PROP(FLOAT, band_wave)
	CAVE_PROP(FLOAT, floor_spacing)
	CAVE_PROP(FLOAT, floor_thickness)
	CAVE_PROP(FLOAT, hall_size)
	CAVE_PROP(FLOAT, hall_cutoff)
	CAVE_PROP(FLOAT, shaft_frequency)
	CAVE_PROP(FLOAT, shaft_width)
	CAVE_PROP(FLOAT, shaft_lean)
	CAVE_PROP(FLOAT, ceiling_jag)
	CAVE_PROP(FLOAT, rubble)
	CAVE_PROP(FLOAT, water_share)
	CAVE_PROP(FLOAT, aquifer_size)
	CAVE_PROP(FLOAT, water_top)
	CAVE_PROP(FLOAT, shaft_share)
	CAVE_PROP(FLOAT, floor_y)
	CAVE_PROP(ARRAY, biomes)
	CAVE_PROP(FLOAT, biome_patch_size)
	CAVE_PROP(DICTIONARY, biome_fixed)
#undef CAVE_PROP
	ClassDB::bind_method(D_METHOD("set_systems", "value"), &CaveCarver::set_systems);
	ClassDB::bind_method(D_METHOD("get_systems"), &CaveCarver::get_systems);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "systems"), "set_systems", "get_systems");
}

} // namespace godot
