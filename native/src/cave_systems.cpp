#include "cave_systems.h"

namespace godot {

Ref<CaveSystems> CaveSystems::roll(int seed_value, const AABB &bounds, const Callable &height, double floor_y) {
	return roll_native(seed_value, bounds, [height](double x, double z) -> double { return (double)height.call(x, z); },
			floor_y);
}

Ref<CaveSystems> CaveSystems::roll_native(int seed_value, const AABB &bounds, const HeightFn &height, double floor_y) {
	Ref<CaveSystems> systems;
	systems.instantiate();
	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed((uint64_t)thash::of(seed_value, 1301));
	double km2 = (double)bounds.size.x * (double)bounds.size.z / 1000000.0;
	systems->count = MAX(tmath::roundi((double)rng->randf_range(PER_KM2_MIN, PER_KM2_MAX) * km2), 1);
	double inset = 30.0;
	Vector2 low = Vector2((real_t)(bounds.position.x + inset), (real_t)(bounds.position.z + inset));
	Vector2 high = Vector2((real_t)((double)bounds.get_end().x - inset), (real_t)((double)bounds.get_end().z - inset));
	if (high.x <= low.x || high.y <= low.y) {
		low = Vector2(bounds.position.x, bounds.position.z);
		high = Vector2(bounds.get_end().x, bounds.get_end().z);
	}
	for (int system = 0; system < systems->count; system++) {
		Vector2 mouth = steepest_spot(rng, low, high, height, systems->mouths);
		double top = height(mouth.x, mouth.y);
		systems->mouths.push_back(v3(mouth.x, top, mouth.y));
		double radius = rng->randf_range(RADIUS_MIN, RADIUS_MAX);
		Vector3 from = v3(mouth.x, top + 0.5, mouth.y);
		double yaw = rng->randf_range(0.0, 6.283185307179586);
		int steps = (int)rng->randi_range(STEPS_MIN, STEPS_MAX);
		systems->walk(rng, from, yaw, radius, steps, bounds, floor_y + FLOOR_CLEARANCE, true);
	}
	systems->region.resize(systems->starts.size());
	for (int index = 0; index < systems->starts.size(); index++) {
		systems->region[index] = index;
	}
	return systems;
}

Vector2 CaveSystems::steepest_spot(const Ref<RandomNumberGenerator> &rng, const Vector2 &low, const Vector2 &high,
		const HeightFn &height, const PackedVector3Array &taken) {
	Vector2 best;
	double best_slope = -1.0;
	for (int candidate = 0; candidate < MOUTH_CANDIDATES; candidate++) {
		double sx = rng->randf_range(low.x, high.x);
		double sy = rng->randf_range(low.y, high.y);
		Vector2 spot = Vector2((real_t)sx, (real_t)sy);
		double here = height(spot.x, spot.y);
		double along_x = height((double)spot.x + 2.0, spot.y) - here;
		double along_z = height(spot.x, (double)spot.y + 2.0) - here;
		double slope = along_x * along_x + along_z * along_z;
		for (int i = 0; i < taken.size(); i++) {
			Vector3 mouth = taken[i];
			if ((double)Vector2(mouth.x, mouth.z).distance_to(spot) < MOUTH_SPACING) {
				slope = 0.0;
				break;
			}
		}
		if (slope > best_slope) {
			best_slope = slope;
			best = spot;
		}
	}
	return best;
}

void CaveSystems::walk(const Ref<RandomNumberGenerator> &rng, const Vector3 &from, double yaw, double radius, int steps,
		const AABB &bounds, double lowest_y, bool trunk) {
	Vector3 at = from;
	double pitch = -(double)rng->randf_range(0.6, 0.9);
	double lean = rng->randf_range(-0.07, 0.07);
	double phase = rng->randf_range(0.0, 6.283185307179586);
	double last_radius = radius;
	for (int step = 0; step < steps; step++) {
		yaw += lean + (double)rng->randf_range(-0.3, 0.3);
		double target_pitch = step < steps / 3 ? -0.4 : (double)rng->randf_range(-0.3, 0.15);
		if (step < 3) {
			target_pitch = -0.75;
		}
		pitch = tmath::lerpd(pitch, target_pitch, 0.3) + (double)rng->randf_range(-0.1, 0.1);
		pitch = tmath::clampd(pitch, -1.0, 0.3);
		Vector3 direction = v3(std::cos(yaw) * std::cos(pitch), std::sin(pitch), std::sin(yaw) * std::cos(pitch));
		Vector3 next = at + direction * (real_t)STEP;
		if ((double)next.y < lowest_y || !bounds.has_point(v3(next.x, (double)bounds.position.y + 1.0, next.z))) {
			break;
		}
		double swell = 0.8 + 0.35 * std::sin((double)step * 0.45 + phase);
		double next_radius = radius * swell;
		add_segment(at, next, last_radius, next_radius);
		at = next;
		last_radius = next_radius;
		if (trunk && step > 6 && step < steps - 6 && rng->randf() < 0.05) {
			// Drawn in the script's order (C++ leaves a product's operands unordered).
			double side = rng->randf_range(0.7, 1.4);
			side *= rng->randf() < 0.5 ? 1.0 : -1.0;
			walk(rng, at, yaw + side, radius * 0.75, (steps - step) / 2, bounds, lowest_y, false);
		}
	}
	if ((double)at.y < (double)from.y - 15.0) {
		double chamber = radius * CHAMBER;
		add_segment(at, at + Vector3(0.0f, 0.01f, 0.0f), chamber, chamber);
	}
}

void CaveSystems::add_segment(const Vector3 &a, const Vector3 &b, double radius_a, double radius_b) {
	starts.push_back(a);
	ends.push_back(b);
	start_radii.push_back((float)radius_a);
	end_radii.push_back((float)radius_b);
	Vector3 grow = Vector3(1, 1, 1) * (real_t)(tmath::maxd(radius_a, radius_b) + REACH);
	box_min.push_back(a.min(b) - grow);
	box_max.push_back(a.max(b) + grow);
}

Ref<CaveSystems> CaveSystems::clone() const {
	Ref<CaveSystems> copy;
	copy.instantiate();
	copy->count = count;
	copy->starts = starts;
	copy->ends = ends;
	copy->start_radii = start_radii;
	copy->end_radii = end_radii;
	copy->mouths = mouths;
	copy->box_min = box_min;
	copy->box_max = box_max;
	copy->region = region;
	return copy;
}

void CaveSystems::prepare_region(const AABB &p_region) {
	region.clear();
	const Vector3 *lows = box_min.ptr();
	const Vector3 *highs = box_max.ptr();
	for (int index = 0; index < starts.size(); index++) {
		AABB box = AABB(lows[index], highs[index] - lows[index]);
		if (p_region.intersects(box)) {
			region.push_back(index);
		}
	}
}

double CaveSystems::air(const Vector3 &world_pos) const {
	double best = -tmath::INF_D;
	const Vector3 *lows = box_min.ptr();
	const Vector3 *highs = box_max.ptr();
	const Vector3 *a_ptr = starts.ptr();
	const Vector3 *b_ptr = ends.ptr();
	const float *ra = start_radii.ptr();
	const float *rb = end_radii.ptr();
	for (int index : region) {
		const Vector3 &low = lows[index];
		if (world_pos.x < low.x || world_pos.y < low.y || world_pos.z < low.z) {
			continue;
		}
		const Vector3 &high = highs[index];
		if (world_pos.x > high.x || world_pos.y > high.y || world_pos.z > high.z) {
			continue;
		}
		Vector3 a = a_ptr[index];
		Vector3 along = b_ptr[index] - a;
		double length_squared = along.length_squared();
		double t = 0.0;
		if (length_squared > 0.000001) {
			t = tmath::clampd((double)(world_pos - a).dot(along) / length_squared, 0.0, 1.0);
		}
		double distance = world_pos.distance_to(a + along * (real_t)t);
		best = tmath::maxd(best, tmath::lerpd(ra[index], rb[index], t) - distance);
	}
	return best;
}

String CaveSystems::summary() const {
	return itos(count) + " cave systems of " + itos(starts.size()) + " passages";
}

void CaveSystems::_bind_methods() {
	ClassDB::bind_static_method("CaveSystems", D_METHOD("roll", "seed_value", "bounds", "height", "floor_y"), &CaveSystems::roll);
	ClassDB::bind_method(D_METHOD("prepare_region", "region"), &CaveSystems::prepare_region);
	ClassDB::bind_method(D_METHOD("air", "world_pos"), &CaveSystems::air);
	ClassDB::bind_method(D_METHOD("summary"), &CaveSystems::summary);
	ClassDB::bind_static_method("CaveSystems", D_METHOD("mouth_spacing"), &CaveSystems::mouth_spacing);
	ClassDB::bind_static_method("CaveSystems", D_METHOD("floor_clearance"), &CaveSystems::floor_clearance);
	ClassDB::bind_static_method("CaveSystems", D_METHOD("steps_range"), &CaveSystems::steps_range);
	ClassDB::bind_static_method("CaveSystems", D_METHOD("per_km2_range"), &CaveSystems::per_km2_range);
	ClassDB::bind_method(D_METHOD("get_count"), &CaveSystems::get_count);
	ClassDB::bind_method(D_METHOD("set_count", "value"), &CaveSystems::set_count);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "count"), "set_count", "get_count");
	ClassDB::bind_method(D_METHOD("get_starts"), &CaveSystems::get_starts);
	ClassDB::bind_method(D_METHOD("set_starts", "value"), &CaveSystems::set_starts);
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_VECTOR3_ARRAY, "starts"), "set_starts", "get_starts");
	ClassDB::bind_method(D_METHOD("get_ends"), &CaveSystems::get_ends);
	ClassDB::bind_method(D_METHOD("set_ends", "value"), &CaveSystems::set_ends);
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_VECTOR3_ARRAY, "ends"), "set_ends", "get_ends");
	ClassDB::bind_method(D_METHOD("get_start_radii"), &CaveSystems::get_start_radii);
	ClassDB::bind_method(D_METHOD("set_start_radii", "value"), &CaveSystems::set_start_radii);
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_FLOAT32_ARRAY, "start_radii"), "set_start_radii", "get_start_radii");
	ClassDB::bind_method(D_METHOD("get_end_radii"), &CaveSystems::get_end_radii);
	ClassDB::bind_method(D_METHOD("set_end_radii", "value"), &CaveSystems::set_end_radii);
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_FLOAT32_ARRAY, "end_radii"), "set_end_radii", "get_end_radii");
	ClassDB::bind_method(D_METHOD("get_mouths"), &CaveSystems::get_mouths);
	ClassDB::bind_method(D_METHOD("set_mouths", "value"), &CaveSystems::set_mouths);
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_VECTOR3_ARRAY, "mouths"), "set_mouths", "get_mouths");
}

} // namespace godot
