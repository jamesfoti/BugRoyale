// 3D grid of signed density samples. Negative = inside, positive = outside. Grid dimensions
// are sample counts (cells + 1 along each axis).
#pragma once

#include "common.h"

namespace godot {

class SignedDensityField : public RefCounted {
	GDCLASS(SignedDensityField, RefCounted)

protected:
	static void _bind_methods();

public:
	Vector3i size;
	PackedFloat32Array values;
	// Sample range, when known (build_chunk_field fills it): lets the mesher skip chunks that
	// are entirely solid or entirely air.
	double min_value = -tmath::INF_D;
	double max_value = tmath::INF_D;
	// The whole chunk is above the ground, filled with one clearance value.
	bool sky = false;
	// The samples that may differ from the field this one was resampled from (inclusive).
	Vector3i changed_first;
	Vector3i changed_last;

	static Ref<SignedDensityField> make(const Vector3i &sample_size);

	void resize(const Vector3i &sample_size);
	void mark_all_changed();
	void mark_changed(const Vector3i &at);
	bool is_valid() const { return size.x > 1 && size.y > 1 && size.z > 1; }
	Vector3i cell_counts() const { return size - Vector3i(1, 1, 1); }
	int index(int x, int y, int z) const { return x + y * size.x + z * size.x * size.y; }
	bool in_bounds(int x, int y, int z) const {
		return x >= 0 && y >= 0 && z >= 0 && x < size.x && y < size.y && z < size.z;
	}
	double get_sample(int x, int y, int z) const { return values[index(x, y, z)]; }
	void set_sample(int x, int y, int z, double value) { values.set(index(x, y, z), (float)value); }
	double sample_world(const Vector3 &world_pos, const Vector3 &origin, double voxel_size) const;

	// Script access.
	void set_size(const Vector3i &v) { size = v; }
	Vector3i get_size() const { return size; }
	void set_values(const PackedFloat32Array &v) { values = v; }
	PackedFloat32Array get_values() const { return values; }
	void set_min_value(double v) { min_value = v; }
	double get_min_value() const { return min_value; }
	void set_max_value(double v) { max_value = v; }
	double get_max_value() const { return max_value; }
	void set_sky(bool v) { sky = v; }
	bool get_sky() const { return sky; }
	void set_changed_first(const Vector3i &v) { changed_first = v; }
	Vector3i get_changed_first() const { return changed_first; }
	void set_changed_last(const Vector3i &v) { changed_last = v; }
	Vector3i get_changed_last() const { return changed_last; }
};

} // namespace godot
