#include "termite_mounds.h"

#include "world_density.h"

#include <godot_cpp/core/math.hpp>

namespace godot {

namespace {

// A number in [0, 1) drawn from a site's hash, one per draw index.
double unit(uint32_t p_hash, uint32_t p_draw) {
	return (double)thash::fmix32(p_hash ^ (p_draw * 0x9E3779B9u)) / 4294967296.0;
}

// The smooth minimum of two distances, rounding their meeting over a width.
double smooth_min(double p_first, double p_second, double p_width) {
	double blend = tmath::clampd(0.5 + 0.5 * (p_second - p_first) / p_width, 0.0, 1.0);
	return tmath::lerpd(p_second, p_first, blend) - p_width * blend * (1.0 - blend);
}

double length3(double p_x, double p_y, double p_z) {
	return Math::sqrt(p_x * p_x + p_y * p_y + p_z * p_z);
}

double distance_between(const Vector3 &p_point, const Vector3 &p_other) {
	return length3((double)p_point.x - (double)p_other.x, (double)p_point.y - (double)p_other.y,
			(double)p_point.z - (double)p_other.z);
}

// The distance to the segment from start to end, less a radius: below 0 inside the capsule.
double capsule(const Vector3 &p_point, const Vector3 &p_start, const Vector3 &p_end, double p_radius) {
	double from_x = (double)p_point.x - (double)p_start.x;
	double from_y = (double)p_point.y - (double)p_start.y;
	double from_z = (double)p_point.z - (double)p_start.z;
	double along_x = (double)p_end.x - (double)p_start.x;
	double along_y = (double)p_end.y - (double)p_start.y;
	double along_z = (double)p_end.z - (double)p_start.z;
	double length_squared = along_x * along_x + along_y * along_y + along_z * along_z;
	double share = length_squared > 0.0
			? tmath::clampd((from_x * along_x + from_y * along_y + from_z * along_z) / length_squared, 0.0, 1.0)
			: 0.0;
	return length3(from_x - along_x * share, from_y - along_y * share, from_z - along_z * share) - p_radius;
}

// Below 0 inside an ellipsoid of these half-sizes, roughly the distance to its skin.
double ellipsoid(const Vector3 &p_point, const Vector3 &p_center, double p_half_x, double p_half_y, double p_half_z) {
	double x = ((double)p_point.x - (double)p_center.x) / p_half_x;
	double y = ((double)p_point.y - (double)p_center.y) / p_half_y;
	double z = ((double)p_point.z - (double)p_center.z) / p_half_z;
	return (length3(x, y, z) - 1.0) * tmath::mind(p_half_x, tmath::mind(p_half_y, p_half_z));
}

// The honeycomb's space at a point: below 0 inside a cell away from its walls, or in the
// round doorway in the middle of the wall between the two nearest cells.
double comb(const Vector3 &p_point, uint32_t p_seed_hash) {
	double spacing = TermiteMounds::COMB_CELL;
	int cell_x = tmath::floori((double)p_point.x / spacing);
	int cell_y = tmath::floori((double)p_point.y / spacing);
	int cell_z = tmath::floori((double)p_point.z / spacing);
	double nearest = tmath::INF_D;
	double next_nearest = tmath::INF_D;
	Vector3 nearest_site;
	Vector3 next_site;
	for (int offset_z = -1; offset_z <= 1; offset_z++) {
		for (int offset_y = -1; offset_y <= 1; offset_y++) {
			for (int offset_x = -1; offset_x <= 1; offset_x++) {
				int x = cell_x + offset_x;
				int y = cell_y + offset_y;
				int z = cell_z + offset_z;
				uint32_t hash = (uint32_t)thash::of(x, y, z, (int)p_seed_hash);
				Vector3 site = v3(((double)x + 0.15 + 0.7 * unit(hash, 1)) * spacing,
						((double)y + 0.15 + 0.7 * unit(hash, 2)) * spacing,
						((double)z + 0.15 + 0.7 * unit(hash, 3)) * spacing);
				double distance = distance_between(p_point, site);
				if (distance < nearest) {
					next_nearest = nearest;
					next_site = nearest_site;
					nearest = distance;
					nearest_site = site;
				} else if (distance < next_nearest) {
					next_nearest = distance;
					next_site = site;
				}
			}
		}
	}
	double off_wall = (next_nearest - nearest) * 0.5;
	double room = TermiteMounds::COMB_WALL - off_wall;
	Vector3 wall_middle = (nearest_site + next_site) * 0.5f;
	double doorway = distance_between(p_point, wall_middle) - TermiteMounds::COMB_DOOR;
	return tmath::mind(room, doorway);
}

} // namespace

Vector3 TermiteMound::nest_center() const {
	return v3((double)base.x, (double)base.y - nest_depth, (double)base.z);
}

Vector3 TermiteMound::axis_at(double p_share) const {
	double bend = p_share * p_share;
	return v3((double)base.x + lean_x * bend, (double)base.y + height * p_share, (double)base.z + lean_z * bend);
}

double TermiteMound::body(const Vector3 &p_point, const TNoise &p_lumps) const {
	double lump = p_lumps.valid ? p_lumps.get_3dv(p_point) : 0.0;
	if (!spire) {
		return ellipsoid(p_point, base, radius, height, radius) * 0.8 + lump * 1.4;
	}
	double share = ((double)p_point.y - (double)base.y) / height;
	double along = tmath::clampd(share, 0.0, 1.0);
	Vector3 axis = axis_at(along);
	double girth = radius * Math::pow(1.0 - along, 0.85) + 0.9;
	// The foot flares out over its first sixth.
	double flare = tmath::maxd(0.0, 1.0 - share / 0.16);
	girth += radius * 0.45 * flare * flare;
	double across_x = (double)p_point.x - (double)axis.x;
	double across_z = (double)p_point.z - (double)axis.z;
	double side = Math::sqrt(across_x * across_x + across_z * across_z) - girth;
	double top = (double)p_point.y - ((double)base.y + height);
	return tmath::maxd(side * 0.8, top) + lump * 0.9;
}

double TermiteMound::hollow(const Vector3 &p_point) const {
	Vector3 heart = spire ? axis_at(0.08) : v3((double)base.x, (double)base.y + height * 0.32, (double)base.z);
	double space = capsule(p_point, heart, nest_center(), TermiteMounds::SHAFT_RADIUS);
	if (spire) {
		space = tmath::mind(space, capsule(p_point, heart, axis_at(0.8), TermiteMounds::CHIMNEY_RADIUS));
	} else {
		space = tmath::mind(space, ellipsoid(p_point, heart, radius * 0.4, height * 0.28, radius * 0.4));
	}
	double reach = radius * (spire ? 1.45 : 1.1) + 3.0;
	for (int hole = 0; hole < holes; hole++) {
		double turn = hole_turn + Math::TAU * (double)hole / (double)holes;
		Vector3 mouth = v3((double)base.x + Math::cos(turn) * reach, (double)base.y + 1.6,
				(double)base.z + Math::sin(turn) * reach);
		space = tmath::mind(space, capsule(p_point, mouth, heart, TermiteMounds::HOLE_RADIUS));
	}
	double chamber = ellipsoid(p_point, nest_center(), nest_radius, nest_radius * 0.55, nest_radius);
	if (chamber < TermiteMounds::COMB_CELL) {
		space = tmath::mind(space, tmath::maxd(chamber, comb(p_point, hash)));
	}
	return space;
}

Dictionary TermiteMound::to_dictionary() const {
	Dictionary data;
	data["base"] = base;
	data["height"] = height;
	data["radius"] = radius;
	data["spire"] = spire;
	data["lean"] = Vector2((real_t)lean_x, (real_t)lean_z);
	data["nest"] = nest_center();
	data["nest_radius"] = nest_radius;
	data["holes"] = holes;
	data["hole_turn"] = hole_turn;
	return data;
}

bool TermiteMounds::site(int p_cell_x, int p_cell_z, const WorldDensity &p_density, int p_seed, TermiteMound &r_mound) {
	uint32_t hash = (uint32_t)thash::of(p_cell_x, p_cell_z, p_seed + 4111);
	double x = ((double)p_cell_x + 0.15 + 0.7 * unit(hash, 1)) * CELL;
	double z = ((double)p_cell_z + 0.15 + 0.7 * unit(hash, 2)) * CELL;
	const BiomeData &kind = p_density.land_biome_of(x, z);
	if (kind.empty || kind.termite_mounds <= 0.0 || unit(hash, 3) >= kind.termite_mounds) {
		return false;
	}
	TermiteMound mound;
	mound.hash = hash;
	mound.spire = unit(hash, 4) < 0.5;
	mound.height = mound.spire ? tmath::lerpd(20.0, 34.0, unit(hash, 5)) : tmath::lerpd(10.0, 18.0, unit(hash, 5));
	mound.radius = mound.spire ? tmath::lerpd(6.0, 9.0, unit(hash, 6)) : tmath::lerpd(9.0, 13.0, unit(hash, 6));
	// Inside the map, with room for its foot, whether or not the map has edge walls.
	double margin = mound.radius * 1.6 + 4.0;
	if (Math::abs(x - (double)p_density.bounds_center.x) > (double)p_density.bounds_half.x - margin ||
			Math::abs(z - (double)p_density.bounds_center.z) > (double)p_density.bounds_half.z - margin) {
		return false;
	}
	// The foot sits on the lowest ground under it; a site on ground too steep is passed by.
	double lowest = tmath::INF_D;
	double highest = -tmath::INF_D;
	for (int sample = 0; sample < 9; sample++) {
		double turn = Math::TAU * (double)sample / 8.0;
		double out_by = sample == 8 ? 0.0 : mound.radius * 0.8;
		double ground =
				p_density.sample_open_terrain_height(x + Math::cos(turn) * out_by, z + Math::sin(turn) * out_by);
		lowest = tmath::mind(lowest, ground);
		highest = tmath::maxd(highest, ground);
	}
	if (highest - lowest > mound.radius * 0.9) {
		return false;
	}
	mound.base = v3(x, lowest - 0.3, z);
	if (mound.spire) {
		double turn = Math::TAU * unit(hash, 7);
		double amount = mound.height * tmath::lerpd(0.05, 0.25, unit(hash, 8));
		mound.lean_x = Math::cos(turn) * amount;
		mound.lean_z = Math::sin(turn) * amount;
	}
	mound.nest_depth = tmath::lerpd(8.0, 12.0, unit(hash, 9));
	mound.nest_radius = tmath::lerpd(5.5, 8.0, unit(hash, 10));
	mound.holes = mound.spire ? 2 + (int)(unit(hash, 11) * 2.0) : 3 + (int)(unit(hash, 11) * 3.0);
	mound.hole_turn = Math::TAU * unit(hash, 12);
	double lean = Math::sqrt(mound.lean_x * mound.lean_x + mound.lean_z * mound.lean_z);
	double side = mound.radius * 1.6 + 4.0 + lean;
	double below = mound.nest_depth + mound.nest_radius * 0.55 + 2.0;
	mound.bounds = AABB(v3(x - side, (double)mound.base.y - below, z - side),
			v3(side * 2.0, below + mound.height + BLEND + 2.0, side * 2.0));
	r_mound = mound;
	return true;
}

LocalVector<TermiteMound> TermiteMounds::in(const AABB &p_area, const WorldDensity &p_density, int p_seed) {
	LocalVector<TermiteMound> found;
	Vector3 low = p_area.position;
	Vector3 high = p_area.get_end();
	int first_x = tmath::floori(((double)low.x - REACH) / CELL);
	int last_x = tmath::floori(((double)high.x + REACH) / CELL);
	int first_z = tmath::floori(((double)low.z - REACH) / CELL);
	int last_z = tmath::floori(((double)high.z + REACH) / CELL);
	for (int cell_z = first_z; cell_z <= last_z; cell_z++) {
		for (int cell_x = first_x; cell_x <= last_x; cell_x++) {
			TermiteMound mound;
			if (site(cell_x, cell_z, p_density, p_seed, mound) && mound.bounds.intersects(p_area)) {
				found.push_back(mound);
			}
		}
	}
	return found;
}

void TermiteMounds::prepare(const AABB &p_area, const WorldDensity &p_density, int p_seed) {
	region = in(p_area, p_density, p_seed);
	region_area = p_area;
	region_ready = true;
}

const LocalVector<TermiteMound> &TermiteMounds::around(const Vector3 &p_point, const WorldDensity &p_density,
		int p_seed, LocalVector<TermiteMound> &r_scratch) const {
	if (region_ready && region_area.has_point(p_point)) {
		return region;
	}
	r_scratch = in(AABB(p_point - Vector3(1, 1, 1), Vector3(2, 2, 2)), p_density, p_seed);
	return r_scratch;
}

double TermiteMounds::apply(double p_value, const Vector3 &p_point, const WorldDensity &p_density, int p_seed,
		const TNoise &p_lumps) const {
	LocalVector<TermiteMound> scratch;
	const LocalVector<TermiteMound> &mounds = around(p_point, p_density, p_seed, scratch);
	if (mounds.is_empty()) {
		return p_value;
	}
	double value = p_value;
	bool touched = false;
	for (const TermiteMound &mound : mounds) {
		if (mound.bounds.has_point(p_point)) {
			value = smooth_min(value, mound.body(p_point, p_lumps), BLEND);
			touched = true;
		}
	}
	if (!touched) {
		return value;
	}
	for (const TermiteMound &mound : mounds) {
		if (mound.bounds.has_point(p_point)) {
			value = tmath::maxd(value, -mound.hollow(p_point));
		}
	}
	return value;
}

bool TermiteMounds::near(const Vector3 &p_point, const WorldDensity &p_density, int p_seed, const TNoise &p_lumps,
		double p_margin, TermiteMound &r_mound) const {
	LocalVector<TermiteMound> scratch;
	const LocalVector<TermiteMound> &mounds = around(p_point, p_density, p_seed, scratch);
	for (const TermiteMound &mound : mounds) {
		if (!mound.bounds.has_point(p_point)) {
			continue;
		}
		if (mound.body(p_point, p_lumps) < p_margin || mound.hollow(p_point) < p_margin) {
			r_mound = mound;
			return true;
		}
	}
	return false;
}

} // namespace godot
