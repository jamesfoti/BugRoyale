// Carved cave systems: a seed's handful of passages that start at a mouth on the surface and
// worm their way down. Each system is a random walk of capsules: from the mouth it heads down
// at a pitch, turns a little each step with a persistent lean, swells and pinches, branches
// now and then, and ends in a chamber. The mouths are picked on the steepest ground among a
// few candidates. Rolled from the seed, the bounds and a surface height function, so every
// chunk builds the same systems; a chunk prepares the segments in its reach once.
#pragma once

#include "common.h"

#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/string.hpp>

#include <functional>
#include <vector>

namespace godot {

class CaveSystems : public RefCounted {
	GDCLASS(CaveSystems, RefCounted)

protected:
	static void _bind_methods();

public:
	static constexpr double STEP = 5.0;
	static constexpr int MOUTH_CANDIDATES = 6;
	static constexpr double MOUTH_SPACING = 80.0;
	static constexpr double REACH = 2.5;
	static constexpr double FLOOR_CLEARANCE = 6.0;
	static constexpr double PER_KM2_MIN = 10.0;
	static constexpr double PER_KM2_MAX = 24.0;
	static constexpr int STEPS_MIN = 24;
	static constexpr int STEPS_MAX = 60;
	static constexpr double RADIUS_MIN = 2.0;
	static constexpr double RADIUS_MAX = 3.4;
	static constexpr double CHAMBER = 2.2;

	using HeightFn = std::function<double(double, double)>;

	int count = 0;
	PackedVector3Array starts;
	PackedVector3Array ends;
	PackedFloat32Array start_radii;
	PackedFloat32Array end_radii;
	PackedVector3Array mouths;
	PackedVector3Array box_min;
	PackedVector3Array box_max;
	std::vector<int> region;

	static Ref<CaveSystems> roll_native(int seed_value, const AABB &bounds, const HeightFn &height, double floor_y);
	static Ref<CaveSystems> roll(int seed_value, const AABB &bounds, const Callable &height, double floor_y);

	// A copy sharing the segments, with a region of its own (one per chunk build).
	Ref<CaveSystems> clone() const;

	void prepare_region(const AABB &p_region);
	double air(const Vector3 &world_pos) const;
	String summary() const;

	int get_count() const { return count; }
	void set_count(int v) { count = v; }
	PackedVector3Array get_starts() const { return starts; }
	PackedVector3Array get_ends() const { return ends; }
	PackedFloat32Array get_start_radii() const { return start_radii; }
	PackedFloat32Array get_end_radii() const { return end_radii; }
	PackedVector3Array get_mouths() const { return mouths; }
	void set_starts(const PackedVector3Array &v) { starts = v; }
	void set_ends(const PackedVector3Array &v) { ends = v; }
	void set_start_radii(const PackedFloat32Array &v) { start_radii = v; }
	void set_end_radii(const PackedFloat32Array &v) { end_radii = v; }
	void set_mouths(const PackedVector3Array &v) { mouths = v; }

	static double mouth_spacing() { return MOUTH_SPACING; }
	static double floor_clearance() { return FLOOR_CLEARANCE; }
	static Vector2i steps_range() { return Vector2i(STEPS_MIN, STEPS_MAX); }
	static Vector2 per_km2_range() { return Vector2((real_t)PER_KM2_MIN, (real_t)PER_KM2_MAX); }

private:
	static Vector2 steepest_spot(const Ref<RandomNumberGenerator> &rng, const Vector2 &low, const Vector2 &high,
			const HeightFn &height, const PackedVector3Array &taken);
	void walk(const Ref<RandomNumberGenerator> &rng, const Vector3 &from, double yaw, double radius, int steps,
			const AABB &bounds, double lowest_y, bool trunk);
	void add_segment(const Vector3 &a, const Vector3 &b, double radius_a, double radius_b);
};

} // namespace godot
