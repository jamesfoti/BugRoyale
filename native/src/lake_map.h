// Lakes on a map's ground. Every hollow of the surface (as the open terrain's height function
// gives it, on a `CELL` grid over the map) is found by a priority flood from the map's edges,
// which raises each point to the level water there would spill out at. Each hollow fills part
// way to that level by the climate's wetness at its deepest point: brimming in the wettest land,
// dry in the driest, the share scaled by the map's lake amount. A lake is flat; the liquids
// (`LiquidSeed`) fill the open cells of its columns from its level down to the ground. Built once
// a map on the main thread and shared by every chunk build.
#pragma once

#include "common.h"

#include <godot_cpp/templates/local_vector.hpp>

namespace godot {

class WorldDensity;

class LakeMap : public RefCounted {
	GDCLASS(LakeMap, RefCounted)

protected:
	static void _bind_methods();

public:
	static constexpr double CELL = 2.0;
	// A lake sits this far under the rim the grid found, so a notch in the rim between its points
	// does not let it out.
	static constexpr double RIM_MARGIN = 0.3;
	// A hollow holds no lake shallower than this, or smaller than this many square metres.
	static constexpr double MIN_DEPTH = 0.75;
	static constexpr double MIN_AREA = 64.0;
	// The wetness a hollow starts holding water at, and the wetness it brims at.
	static constexpr double WET_START = 0.35;
	static constexpr double WET_FULL = 0.75;

	// The map's lakes; `p_amount` scales how full every hollow is (0: none).
	static Ref<LakeMap> build(const WorldDensity &p_density, double p_amount);
	static Ref<LakeMap> build_for(const Ref<WorldDensity> &p_density, double p_amount);

	// The surface of the lake over a point, or -INF where there is none.
	double level_at(double p_world_x, double p_world_z) const;
	int get_lake_count() const { return lake_count; }
	double get_area() const { return area; }
	String summary() const;

private:
	double origin_x = 0.0;
	double origin_z = 0.0;
	int width = 0;
	int depth = 0;
	LocalVector<float> levels;
	int lake_count = 0;
	double area = 0.0;
};

} // namespace godot
