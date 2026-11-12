// The material numbers and colours the terrain needs from TerrainMaterials (a GDScript: the
// game's data on what the pickaxe digs, shared with the inventory and the HUD). Read once on
// the main thread (ensure), then plain tables the worker threads read.
#pragma once

#include "common.h"

#include <vector>

namespace godot {

namespace mat {

// TerrainMaterials.Kind values the terrain code names.
enum Kind {
	NATURAL = 0,
	DIRT = 1,
	STONE = 2,
	SAND = 3,
	CLAY = 4,
	GRAVEL = 5,
};

struct Table {
	bool loaded = false;
	Color natural_vertex_color = Color(1, 1, 1, 1);
	std::vector<Color> vertex_colors;
	std::vector<double> ore_depths;
	std::vector<int> ore_weights;
	std::vector<int> element_kinds;
};

// Loads the tables from the script, once; call on the main thread before any build.
void ensure();
const Table &table();

inline Color vertex_color(int kind) {
	const Table &t = table();
	if (kind >= 0 && kind < (int)t.vertex_colors.size()) {
		return t.vertex_colors[kind];
	}
	return t.natural_vertex_color;
}

inline Color natural_vertex_color() { return table().natural_vertex_color; }

} // namespace mat

} // namespace godot
