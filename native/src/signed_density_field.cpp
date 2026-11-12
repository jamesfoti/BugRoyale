#include "signed_density_field.h"

namespace godot {

Ref<SignedDensityField> SignedDensityField::make(const Vector3i &sample_size) {
	Ref<SignedDensityField> field;
	field.instantiate();
	if (sample_size != Vector3i()) {
		field->resize(sample_size);
	}
	return field;
}

void SignedDensityField::resize(const Vector3i &sample_size) {
	size = sample_size;
	int count = size.x * size.y * size.z;
	values.resize(count);
	values.fill(1.0f);
	mark_all_changed();
}

void SignedDensityField::mark_all_changed() {
	changed_first = Vector3i();
	changed_last = size - Vector3i(1, 1, 1);
}

void SignedDensityField::mark_changed(const Vector3i &at) {
	changed_first = changed_first.min(at);
	changed_last = changed_last.max(at);
}

double SignedDensityField::sample_world(const Vector3 &world_pos, const Vector3 &origin, double voxel_size) const {
	Vector3 local = (world_pos - origin) / (real_t)voxel_size;
	double fx = local.x;
	double fy = local.y;
	double fz = local.z;
	if (fx < 0.0 || fy < 0.0 || fz < 0.0) {
		return 1.0;
	}
	if (fx > (double)(size.x - 1) || fy > (double)(size.y - 1) || fz > (double)(size.z - 1)) {
		return 1.0;
	}
	int x0 = (int)std::floor(fx);
	int y0 = (int)std::floor(fy);
	int z0 = (int)std::floor(fz);
	int x1 = MIN(x0 + 1, size.x - 1);
	int y1 = MIN(y0 + 1, size.y - 1);
	int z1 = MIN(z0 + 1, size.z - 1);
	double tx = fx - (double)x0;
	double ty = fy - (double)y0;
	double tz = fz - (double)z0;
	double c000 = get_sample(x0, y0, z0);
	double c100 = get_sample(x1, y0, z0);
	double c010 = get_sample(x0, y1, z0);
	double c110 = get_sample(x1, y1, z0);
	double c001 = get_sample(x0, y0, z1);
	double c101 = get_sample(x1, y0, z1);
	double c011 = get_sample(x0, y1, z1);
	double c111 = get_sample(x1, y1, z1);
	double c00 = tmath::lerpd(c000, c100, tx);
	double c10 = tmath::lerpd(c010, c110, tx);
	double c01 = tmath::lerpd(c001, c101, tx);
	double c11 = tmath::lerpd(c011, c111, tx);
	double c0 = tmath::lerpd(c00, c10, ty);
	double c1 = tmath::lerpd(c01, c11, ty);
	return tmath::lerpd(c0, c1, tz);
}

void SignedDensityField::_bind_methods() {
	ClassDB::bind_static_method("SignedDensityField", D_METHOD("make", "sample_size"), &SignedDensityField::make);
	ClassDB::bind_method(D_METHOD("resize", "sample_size"), &SignedDensityField::resize);
	ClassDB::bind_method(D_METHOD("mark_all_changed"), &SignedDensityField::mark_all_changed);
	ClassDB::bind_method(D_METHOD("mark_changed", "at"), &SignedDensityField::mark_changed);
	ClassDB::bind_method(D_METHOD("is_valid"), &SignedDensityField::is_valid);
	ClassDB::bind_method(D_METHOD("cell_counts"), &SignedDensityField::cell_counts);
	ClassDB::bind_method(D_METHOD("in_bounds", "x", "y", "z"), &SignedDensityField::in_bounds);
	ClassDB::bind_method(D_METHOD("get_sample", "x", "y", "z"), &SignedDensityField::get_sample);
	ClassDB::bind_method(D_METHOD("set_sample", "x", "y", "z", "value"), &SignedDensityField::set_sample);
	ClassDB::bind_method(D_METHOD("sample_world", "world_pos", "origin", "voxel_size"), &SignedDensityField::sample_world);
	ClassDB::bind_method(D_METHOD("set_size", "value"), &SignedDensityField::set_size);
	ClassDB::bind_method(D_METHOD("get_size"), &SignedDensityField::get_size);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3I, "size"), "set_size", "get_size");
	ClassDB::bind_method(D_METHOD("set_values", "value"), &SignedDensityField::set_values);
	ClassDB::bind_method(D_METHOD("get_values"), &SignedDensityField::get_values);
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_FLOAT32_ARRAY, "values"), "set_values", "get_values");
	ClassDB::bind_method(D_METHOD("set_min_value", "value"), &SignedDensityField::set_min_value);
	ClassDB::bind_method(D_METHOD("get_min_value"), &SignedDensityField::get_min_value);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_value"), "set_min_value", "get_min_value");
	ClassDB::bind_method(D_METHOD("set_max_value", "value"), &SignedDensityField::set_max_value);
	ClassDB::bind_method(D_METHOD("get_max_value"), &SignedDensityField::get_max_value);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_value"), "set_max_value", "get_max_value");
	ClassDB::bind_method(D_METHOD("set_sky", "value"), &SignedDensityField::set_sky);
	ClassDB::bind_method(D_METHOD("get_sky"), &SignedDensityField::get_sky);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "sky"), "set_sky", "get_sky");
	ClassDB::bind_method(D_METHOD("set_changed_first", "value"), &SignedDensityField::set_changed_first);
	ClassDB::bind_method(D_METHOD("get_changed_first"), &SignedDensityField::get_changed_first);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3I, "changed_first"), "set_changed_first", "get_changed_first");
	ClassDB::bind_method(D_METHOD("set_changed_last", "value"), &SignedDensityField::set_changed_last);
	ClassDB::bind_method(D_METHOD("get_changed_last"), &SignedDensityField::get_changed_last);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3I, "changed_last"), "set_changed_last", "get_changed_last");
}

} // namespace godot
