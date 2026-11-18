#include "lake_map.h"

#include "world_density.h"

namespace godot {

namespace {

// A grid point waiting in the flood, lowest first.
struct FloodPoint {
	float level = 0.0f;
	int index = 0;
};

// A binary heap on the lowest level.
class FloodQueue {
public:
	bool is_empty() const { return points.is_empty(); }

	void push(float p_level, int p_index) {
		FloodPoint point;
		point.level = p_level;
		point.index = p_index;
		points.push_back(point);
		uint32_t child = points.size() - 1;
		while (child > 0) {
			uint32_t parent = (child - 1) / 2;
			if (points[parent].level <= points[child].level) {
				break;
			}
			swap(parent, child);
			child = parent;
		}
	}

	FloodPoint pop() {
		FloodPoint lowest = points[0];
		points[0] = points[points.size() - 1];
		points.resize(points.size() - 1);
		uint32_t parent = 0;
		while (true) {
			uint32_t first = parent * 2 + 1;
			uint32_t second = first + 1;
			uint32_t smallest = parent;
			if (first < points.size() && points[first].level < points[smallest].level) {
				smallest = first;
			}
			if (second < points.size() && points[second].level < points[smallest].level) {
				smallest = second;
			}
			if (smallest == parent) {
				break;
			}
			swap(parent, smallest);
			parent = smallest;
		}
		return lowest;
	}

private:
	LocalVector<FloodPoint> points;

	void swap(uint32_t p_first, uint32_t p_second) {
		FloodPoint held = points[p_first];
		points[p_first] = points[p_second];
		points[p_second] = held;
	}
};

const int NEIGHBOUR_X[8] = { 1, -1, 0, 0, 1, 1, -1, -1 };
const int NEIGHBOUR_Z[8] = { 0, 0, 1, -1, 1, -1, 1, -1 };

} // namespace

Ref<LakeMap> LakeMap::build(const WorldDensity &p_density, double p_amount) {
	Ref<LakeMap> lakes;
	lakes.instantiate();
	LakeMap *map = lakes.ptr();
	if (!p_density.open_terrain_enabled || p_amount <= 0.0) {
		return lakes;
	}
	Vector3 low = p_density.bounds_center - p_density.bounds_half;
	map->origin_x = (double)low.x;
	map->origin_z = (double)low.z;
	map->width = MAX(tmath::ceili((double)p_density.bounds_half.x * 2.0 / CELL), 1);
	map->depth = MAX(tmath::ceili((double)p_density.bounds_half.z * 2.0 / CELL), 1);
	int count = map->width * map->depth;
	LocalVector<float> heights;
	LocalVector<float> filled;
	LocalVector<uint8_t> closed;
	heights.resize(count);
	filled.resize(count);
	closed.resize(count);
	map->levels.resize(count);
	for (int z = 0; z < map->depth; z++) {
		for (int x = 0; x < map->width; x++) {
			int index = x + z * map->width;
			double world_x = map->origin_x + ((double)x + 0.5) * CELL;
			double world_z = map->origin_z + ((double)z + 0.5) * CELL;
			heights[index] = (float)p_density.sample_open_terrain_height(world_x, world_z);
			filled[index] = heights[index];
			closed[index] = 0;
			map->levels[index] = -std::numeric_limits<float>::infinity();
		}
	}
	// The flood: from the edges inwards, lowest first, each point raised to the level of the
	// point it was reached from when that is higher (water there spills out at that level).
	FloodQueue queue;
	for (int z = 0; z < map->depth; z++) {
		for (int x = 0; x < map->width; x++) {
			if (x == 0 || z == 0 || x == map->width - 1 || z == map->depth - 1) {
				int index = x + z * map->width;
				closed[index] = 1;
				queue.push(filled[index], index);
			}
		}
	}
	while (!queue.is_empty()) {
		FloodPoint point = queue.pop();
		int x = point.index % map->width;
		int z = point.index / map->width;
		for (int neighbour = 0; neighbour < 8; neighbour++) {
			int next_x = x + NEIGHBOUR_X[neighbour];
			int next_z = z + NEIGHBOUR_Z[neighbour];
			if (next_x < 0 || next_z < 0 || next_x >= map->width || next_z >= map->depth) {
				continue;
			}
			int next = next_x + next_z * map->width;
			if (closed[next] != 0) {
				continue;
			}
			closed[next] = 1;
			filled[next] = MAX(heights[next], point.level);
			queue.push(filled[next], next);
		}
	}
	// Each hollow (points under their spill level that share it), filled by its wetness.
	LocalVector<int> label;
	label.resize(count);
	for (int index = 0; index < count; index++) {
		label[index] = -1;
	}
	LocalVector<int> members;
	LocalVector<int> frontier;
	double cell_area = CELL * CELL;
	for (int start = 0; start < count; start++) {
		if (label[start] >= 0 || filled[start] <= heights[start] + 0.01f) {
			continue;
		}
		members.clear();
		frontier.clear();
		frontier.push_back(start);
		label[start] = start;
		int lowest = start;
		while (!frontier.is_empty()) {
			int index = frontier[frontier.size() - 1];
			frontier.resize(frontier.size() - 1);
			members.push_back(index);
			if (heights[index] < heights[lowest]) {
				lowest = index;
			}
			int x = index % map->width;
			int z = index / map->width;
			for (int neighbour = 0; neighbour < 4; neighbour++) {
				int next_x = x + NEIGHBOUR_X[neighbour];
				int next_z = z + NEIGHBOUR_Z[neighbour];
				if (next_x < 0 || next_z < 0 || next_x >= map->width || next_z >= map->depth) {
					continue;
				}
				int next = next_x + next_z * map->width;
				if (label[next] >= 0 || filled[next] <= heights[next] + 0.01f ||
						Math::abs(filled[next] - filled[start]) > 0.001f) {
					continue;
				}
				label[next] = start;
				frontier.push_back(next);
			}
		}
		double bottom = heights[lowest];
		double spill = filled[start];
		double lowest_x = map->origin_x + ((double)(lowest % map->width) + 0.5) * CELL;
		double lowest_z = map->origin_z + ((double)(lowest / map->width) + 0.5) * CELL;
		double wetness = (double)p_density.climate_at(lowest_x, lowest_z).y;
		double share = tmath::smoothstep(WET_START, WET_FULL, wetness) * tmath::clampd(p_amount, 0.0, 1.0);
		double level = MIN(bottom + (spill - bottom) * share, spill - RIM_MARGIN);
		if (level - bottom < MIN_DEPTH) {
			continue;
		}
		int under = 0;
		for (int index : members) {
			if (heights[index] < level) {
				under += 1;
			}
		}
		if ((double)under * cell_area < MIN_AREA) {
			continue;
		}
		// The shore's points too (a little over the level): a column's own ground decides how
		// much of it is under water.
		for (int index : members) {
			if (heights[index] < level + 1.0) {
				map->levels[index] = (float)level;
			}
		}
		map->lake_count += 1;
		map->area += (double)under * cell_area;
	}
	return lakes;
}

Ref<LakeMap> LakeMap::build_for(const Ref<WorldDensity> &p_density, double p_amount) {
	if (p_density.is_null()) {
		Ref<LakeMap> none;
		none.instantiate();
		return none;
	}
	return build(**p_density, p_amount);
}

double LakeMap::level_at(double p_world_x, double p_world_z) const {
	if (width <= 0 || lake_count == 0) {
		return -tmath::INF_D;
	}
	int x = tmath::floori((p_world_x - origin_x) / CELL);
	int z = tmath::floori((p_world_z - origin_z) / CELL);
	if (x < 0 || z < 0 || x >= width || z >= depth) {
		return -tmath::INF_D;
	}
	float level = levels[x + z * width];
	return Math::is_inf(level) ? -tmath::INF_D : (double)level;
}

String LakeMap::summary() const {
	if (lake_count == 0) {
		return "no lakes";
	}
	return itos(lake_count) + (lake_count == 1 ? " lake" : " lakes") + " (" + itos(tmath::roundi(area)) + String::utf8(" m²)");
}

void LakeMap::_bind_methods() {
	ClassDB::bind_static_method("LakeMap", D_METHOD("build", "density", "amount"), &LakeMap::build_for);
	ClassDB::bind_method(D_METHOD("level_at", "world_x", "world_z"), &LakeMap::level_at);
	ClassDB::bind_method(D_METHOD("get_lake_count"), &LakeMap::get_lake_count);
	ClassDB::bind_method(D_METHOD("get_area"), &LakeMap::get_area);
	ClassDB::bind_method(D_METHOD("summary"), &LakeMap::summary);
}

} // namespace godot
