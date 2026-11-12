#include "materials.h"

#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/core/error_macros.hpp>

namespace godot {
namespace mat {

static Table g_table;

static const char *SCRIPT_PATH = "res://terrain/terrain_materials.gd";

void ensure() {
	if (g_table.loaded) {
		return;
	}
	Ref<Script> script = ResourceLoader::get_singleton()->load(SCRIPT_PATH);
	ERR_FAIL_COND_MSG(script.is_null(), "Terrain: could not load TerrainMaterials.");
	Dictionary constants = script->get_script_constant_map();
	Dictionary kinds = constants.get("Kind", Dictionary());
	int count = 0;
	Array values = kinds.values();
	for (int i = 0; i < values.size(); i++) {
		count = MAX(count, (int)values[i] + 1);
	}
	g_table.natural_vertex_color = constants.get("NATURAL_VERTEX_COLOR", Color(1, 1, 1, 1));
	g_table.vertex_colors.resize(count);
	g_table.ore_depths.resize(count);
	g_table.ore_weights.resize(count);
	for (int kind = 0; kind < count; kind++) {
		g_table.vertex_colors[kind] = script->call("vertex_color", kind);
		g_table.ore_depths[kind] = (double)script->call("ore_depth", kind);
		g_table.ore_weights[kind] = (int)script->call("ore_weight", kind);
	}
	Array elements = constants.get("ELEMENT_KINDS", Array());
	g_table.element_kinds.clear();
	for (int i = 0; i < elements.size(); i++) {
		g_table.element_kinds.push_back((int)elements[i]);
	}
	g_table.loaded = true;
}

const Table &table() {
	return g_table;
}

} // namespace mat
} // namespace godot
