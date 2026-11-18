#include "biomes.h"

#include "materials.h"

namespace godot {

TermiteMoundShape TermiteMoundShape::from(const Dictionary &p_data) {
	TermiteMoundShape shape;
	shape.spire_share = (double)p_data.get("spire_share", shape.spire_share);
	shape.spire_height = p_data.get("spire_height", shape.spire_height);
	shape.spire_radius = p_data.get("spire_radius", shape.spire_radius);
	shape.dome_height = p_data.get("dome_height", shape.dome_height);
	shape.dome_radius = p_data.get("dome_radius", shape.dome_radius);
	shape.nest_depth = p_data.get("nest_depth", shape.nest_depth);
	shape.nest_radius = p_data.get("nest_radius", shape.nest_radius);
	return shape;
}

BiomeData BiomeData::from(const Dictionary &p_data) {
	BiomeData biome_data;
	if (p_data.is_empty()) {
		return biome_data;
	}
	biome_data.empty = false;
	biome_data.name = p_data.get("name", "");
	biome_data.weight = (double)p_data.get("weight", 0.0);
	biome_data.tint = p_data.get("tint", mat::natural_vertex_color());
	biome_data.depth_min = (double)p_data.get("depth_min", 0.0);
	biome_data.depth_max = (double)p_data.get("depth_max", tmath::INF_D);
	biome_data.pillars = (bool)p_data.get("pillars", false);
	biome_data.ceiling_jag = (double)p_data.get("ceiling_jag", 1.0);
	biome_data.rubble = (double)p_data.get("rubble", 1.0);
	biome_data.warmth = p_data.get("warmth", biome_data.warmth);
	biome_data.wetness = p_data.get("wetness", biome_data.wetness);
	biome_data.features = p_data.get("features", Array());
	for (int index = 0; index < biome_data.features.size(); index++) {
		Dictionary feature = biome_data.features[index];
		// The first termite mounds a kind lists are its own; a second is passed by.
		if (String(feature.get("type", "")) == "termite_mounds" && biome_data.termite_mounds <= 0.0) {
			biome_data.termite_mounds = (double)feature.get("density", 0.0);
			biome_data.termite_mound_shape = TermiteMoundShape::from(feature);
		}
	}
	return biome_data;
}

Dictionary BiomeData::to_dictionary() const {
	Dictionary data;
	if (empty) {
		return data;
	}
	data["name"] = name;
	data["weight"] = weight;
	data["tint"] = tint;
	data["depth_min"] = depth_min;
	data["depth_max"] = depth_max;
	data["pillars"] = pillars;
	data["ceiling_jag"] = ceiling_jag;
	data["rubble"] = rubble;
	data["warmth"] = warmth;
	data["wetness"] = wetness;
	data["features"] = features;
	return data;
}

bool BiomeData::fits(const Vector2 &p_climate) const {
	return p_climate.x >= warmth.x && p_climate.x <= warmth.y && p_climate.y >= wetness.x &&
			p_climate.y <= wetness.y;
}

double BiomeData::climate_distance(const Vector2 &p_climate) const {
	double across = tmath::maxd(0.0, tmath::maxd((double)warmth.x - p_climate.x, p_climate.x - (double)warmth.y));
	double along = tmath::maxd(0.0, tmath::maxd((double)wetness.x - p_climate.y, p_climate.y - (double)wetness.y));
	return Math::sqrt(across * across + along * along);
}

bool BiomeData::has_climate() const {
	return warmth.x > 0.0f || warmth.y < 1.0f || wetness.x > 0.0f || wetness.y < 1.0f;
}

void BiomeList::set(const Array &data) {
	source = data;
	kinds.clear();
	weights.clear();
	by_climate = false;
	for (int index = 0; index < data.size(); index++) {
		Dictionary entry = data[index];
		BiomeData biome_data = BiomeData::from(entry);
		by_climate = by_climate || biome_data.has_climate();
		kinds.push_back(biome_data);
		weights.push_back((float)(double)entry.get("weight", 0.0));
	}
}

PackedStringArray BiomeList::names() const {
	PackedStringArray out;
	for (const BiomeData &biome_data : kinds) {
		out.push_back(biome_data.name);
	}
	return out;
}

PackedFloat32Array BiomeList::weights_packed() const {
	PackedFloat32Array out;
	for (float weight : weights) {
		out.push_back(weight);
	}
	return out;
}

namespace patches {

TNoise make_warp(int seed_value, double patch_size) {
	return TNoise::make(seed_value, TNoise::SIMPLEX, 1.0 / tmath::maxd(patch_size, 1.0), 0);
}

int pick(double world_x, double world_z, int seed_value, double patch_size, const TNoise *warp,
		const std::vector<float> &weights) {
	return draw(patch_at(world_x, world_z, seed_value, patch_size, warp).bits, weights);
}

Patch patch_at(double p_world_x, double p_world_z, int p_seed, double p_patch_size, const TNoise *p_warp) {
	double size = tmath::maxd(p_patch_size, 1.0);
	double x = p_world_x;
	double z = p_world_z;
	if (p_warp != nullptr) {
		double reach = size * WARP;
		x += p_warp->get_2d(p_world_x, p_world_z) * reach;
		z += p_warp->get_2d(p_world_x + 1000.0, p_world_z - 1000.0) * reach;
	}
	int cell_x = tmath::floori(x / size);
	int cell_z = tmath::floori(z / size);
	double nearest = tmath::INF_D;
	int64_t nearest_bits = 0;
	Vector2 nearest_centre;
	for (int dz = -1; dz < 2; dz++) {
		for (int dx = -1; dx < 2; dx++) {
			int cx = cell_x + dx;
			int cz = cell_z + dz;
			int64_t bits = thash::of(cx, cz, p_seed) & 0x7FFFFFFF;
			Vector2 centre = Vector2(
					(real_t)(((double)cx + 0.2 + 0.6 * (double)(bits & 0xFF) / 255.0) * size),
					(real_t)(((double)cz + 0.2 + 0.6 * (double)((bits >> 8) & 0xFF) / 255.0) * size));
			double distance = centre.distance_squared_to(Vector2((real_t)x, (real_t)z));
			if (distance < nearest) {
				nearest = distance;
				nearest_bits = bits;
				nearest_centre = centre;
			}
		}
	}
	Patch patch;
	patch.middle = nearest_centre;
	patch.bits = nearest_bits;
	return patch;
}

double draw_share(int64_t p_bits) {
	return (double)((p_bits >> 16) & 0x7FFF) / 32768.0;
}

int draw(int64_t p_bits, const std::vector<float> &p_weights) {
	double total = 0.0;
	for (float weight : p_weights) {
		total += tmath::maxd((double)weight, 0.0);
	}
	if (total <= 0.0) {
		return -1;
	}
	double left = total * draw_share(p_bits);
	for (int index = 0; index < (int)p_weights.size(); index++) {
		left -= tmath::maxd((double)p_weights[index], 0.0);
		if (left < 0.0) {
			return index;
		}
	}
	return (int)p_weights.size() - 1;
}

String shares(const PackedStringArray &names, const PackedFloat32Array &weights) {
	double total = 0.0;
	for (int index = 0; index < weights.size(); index++) {
		total += tmath::maxd(weights[index], 0.0);
	}
	if (total <= 0.0) {
		return "none";
	}
	PackedStringArray parts;
	int count = MIN(names.size(), weights.size());
	for (int index = 0; index < count; index++) {
		if (weights[index] > 0.0) {
			parts.push_back(String(names[index]) + String(" ") + itos(tmath::roundi(100.0 * weights[index] / total)) + String("%"));
		}
	}
	return String(", ").join(parts);
}

} // namespace patches

} // namespace godot
