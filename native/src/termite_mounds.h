// Termite mounds: earth towers a land biome raises (its `mounds` share), each hollow inside.
// The map is cut into `CELL` squares with one jittered site each; a site in a patch of a kind
// with mounds grows one when its hash falls under that kind's share (and the ground under it
// is not too steep). A mound is a tall leaning spire or a low lumpy dome flared into the
// ground, with holes round its foot into it, a chimney up its middle (a spire) or a hollow
// heart (a dome), and a shaft down to a nest chamber under it whose honeycomb cells open
// into each other through round doorways. Pure numbers from the seed, read on the worker
// threads; `WorldDensity` unions the mounds into the ground and carves their hollows.
#pragma once

#include "common.h"

#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class WorldDensity;

struct TermiteMound {
	// The middle of its foot, on the lowest ground under it.
	Vector3 base;
	double height = 0.0;
	double radius = 0.0;
	bool spire = false;
	// Where the axis has drifted to at the top, from straight over the foot.
	double lean_x = 0.0;
	double lean_z = 0.0;
	double nest_depth = 0.0;
	double nest_radius = 0.0;
	int holes = 0;
	double hole_turn = 0.0;
	uint32_t hash = 0;
	AABB bounds;

	Vector3 nest_center() const;
	// The axis at a share of the height (0 the foot, 1 the top).
	Vector3 axis_at(double p_share) const;
	// Below 0 inside its earth, about the distance to its surface.
	double body(const Vector3 &p_point, const TNoise &p_lumps) const;
	// Below 0 inside its holes, chimney, shaft and nest.
	double hollow(const Vector3 &p_point) const;
	Dictionary to_dictionary() const;
};

class TermiteMounds {
public:
	static constexpr double CELL = 64.0;
	// How far a foot flares into the ground round it.
	static constexpr double BLEND = 3.0;
	// The farthest a mound reaches from its site, sideways.
	static constexpr double REACH = 40.0;
	// The honeycomb: cell spacing, wall half-thickness and doorway radius.
	static constexpr double COMB_CELL = 5.0;
	static constexpr double COMB_WALL = 0.6;
	static constexpr double COMB_DOOR = 1.2;
	// The tunnels: the holes, the chimney and the shaft down.
	static constexpr double HOLE_RADIUS = 1.4;
	static constexpr double CHIMNEY_RADIUS = 1.5;
	static constexpr double SHAFT_RADIUS = 1.5;

	// The mounds whose bounds meet an area.
	static LocalVector<TermiteMound> in(const AABB &p_area, const WorldDensity &p_density, int p_seed);
	// The mound at one site into `r_mound`; false when none grows there.
	static bool site(int p_cell_x, int p_cell_z, const WorldDensity &p_density, int p_seed, TermiteMound &r_mound);

	// The mounds of the region a chunk build samples (`prepare`), and the area they were looked
	// for over: a point outside it looks its mounds up on its own.
	LocalVector<TermiteMound> region;
	AABB region_area;
	bool region_ready = false;

	void prepare(const AABB &p_area, const WorldDensity &p_density, int p_seed);
	// The ground's value with the mounds near a point added and their hollows carved.
	double apply(double p_value, const Vector3 &p_point, const WorldDensity &p_density, int p_seed,
			const TNoise &p_lumps) const;
	// The mound whose earth or hollows lie within a margin of a point, into `r_mound`; false
	// when none does.
	bool near(const Vector3 &p_point, const WorldDensity &p_density, int p_seed, const TNoise &p_lumps,
			double p_margin, TermiteMound &r_mound) const;

private:
	const LocalVector<TermiteMound> &around(const Vector3 &p_point, const WorldDensity &p_density, int p_seed,
			LocalVector<TermiteMound> &r_scratch) const;
};

} // namespace godot
