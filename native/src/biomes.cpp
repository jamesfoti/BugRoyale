#include "biomes.h"

#include "materials.h"

namespace godot {

BiomeData BiomeData::from(const Dictionary &d) {
	BiomeData b;
	if (d.is_empty()) {
		return b;
	}
	b.empty = false;
	b.name = d.get("name", "");
	b.weight = (double)d.get("weight", 0.0);
	b.tint = d.get("tint", mat::natural_vertex_color());
	b.depth_min = (double)d.get("depth_min", 0.0);
	b.depth_max = (double)d.get("depth_max", tmath::INF_D);
	b.pillars = (bool)d.get("pillars", false);
	b.ceiling_jag = (double)d.get("ceiling_jag", 1.0);
	b.rubble = (double)d.get("rubble", 1.0);
	return b;
}

Dictionary BiomeData::to_dictionary() const {
	Dictionary d;
	if (empty) {
		return d;
	}
	d["name"] = name;
	d["weight"] = weight;
	d["tint"] = tint;
	d["depth_min"] = depth_min;
	d["depth_max"] = depth_max;
	d["pillars"] = pillars;
	d["ceiling_jag"] = ceiling_jag;
	d["rubble"] = rubble;
	return d;
}

void BiomeList::set(const Array &data) {
	source = data;
	kinds.clear();
	weights.clear();
	for (int i = 0; i < data.size(); i++) {
		Dictionary d = data[i];
		BiomeData b = BiomeData::from(d);
		kinds.push_back(b);
		weights.push_back((float)(double)d.get("weight", 0.0));
	}
}

PackedStringArray BiomeList::names() const {
	PackedStringArray out;
	for (const BiomeData &b : kinds) {
		out.push_back(b.name);
	}
	return out;
}

PackedFloat32Array BiomeList::weights_packed() const {
	PackedFloat32Array out;
	for (float w : weights) {
		out.push_back(w);
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
	for (int i = 0; i < weights.size(); i++) {
		total += tmath::maxd(weights[i], 0.0);
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
