#include "biomes.h"

#include "materials.h"

namespace godot {

BiomeData BiomeData::from(const Dictionary &data) {
	BiomeData biome_data;
	if (data.is_empty()) {
		return biome_data;
	}
	biome_data.empty = false;
	biome_data.name = data.get("name", "");
	biome_data.weight = (double)data.get("weight", 0.0);
	biome_data.tint = data.get("tint", mat::natural_vertex_color());
	biome_data.depth_min = (double)data.get("depth_min", 0.0);
	biome_data.depth_max = (double)data.get("depth_max", tmath::INF_D);
	biome_data.pillars = (bool)data.get("pillars", false);
	biome_data.ceiling_jag = (double)data.get("ceiling_jag", 1.0);
	biome_data.rubble = (double)data.get("rubble", 1.0);
	biome_data.mounds = (double)data.get("mounds", 0.0);
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
	data["mounds"] = mounds;
	return data;
}

void BiomeList::set(const Array &data) {
	source = data;
	kinds.clear();
	weights.clear();
	for (int index = 0; index < data.size(); index++) {
		Dictionary entry = data[index];
		BiomeData biome_data = BiomeData::from(entry);
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
	double total = 0.0;
	for (float weight : weights) {
		total += tmath::maxd((double)weight, 0.0);
	}
	if (total <= 0.0) {
		return -1;
	}
	double size = tmath::maxd(patch_size, 1.0);
	double x = world_x;
	double z = world_z;
	if (warp != nullptr) {
		double reach = size * WARP;
		x += warp->get_2d(world_x, world_z) * reach;
		z += warp->get_2d(world_x + 1000.0, world_z - 1000.0) * reach;
	}
	int cell_x = tmath::floori(x / size);
	int cell_z = tmath::floori(z / size);
	double nearest = tmath::INF_D;
	int64_t nearest_bits = 0;
	for (int dz = -1; dz < 2; dz++) {
		for (int dx = -1; dx < 2; dx++) {
			int cx = cell_x + dx;
			int cz = cell_z + dz;
			int64_t bits = thash::of(cx, cz, seed_value) & 0x7FFFFFFF;
			Vector2 centre = Vector2(
					(real_t)(((double)cx + 0.2 + 0.6 * (double)(bits & 0xFF) / 255.0) * size),
					(real_t)(((double)cz + 0.2 + 0.6 * (double)((bits >> 8) & 0xFF) / 255.0) * size));
			double distance = centre.distance_squared_to(Vector2((real_t)x, (real_t)z));
			if (distance < nearest) {
				nearest = distance;
				nearest_bits = bits;
			}
		}
	}
	double draw = total * (double)((nearest_bits >> 16) & 0x7FFF) / 32768.0;
	for (int index = 0; index < (int)weights.size(); index++) {
		draw -= tmath::maxd((double)weights[index], 0.0);
		if (draw < 0.0) {
			return index;
		}
	}
	return (int)weights.size() - 1;
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
