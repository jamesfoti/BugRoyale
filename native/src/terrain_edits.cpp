#include "terrain_edits.h"

#include "materials.h"

namespace godot {

void TerrainEdits::changed() {
	thread_snapshot.unref();
	all_bounds_known = false;
}

void TerrainEdits::set_voxel_size(double p_voxel_size) {
	voxel_size = tmath::maxd(p_voxel_size, 0.001);
}

void TerrainEdits::set_grid_origin(const Vector3 &origin) {
	if (origin.is_equal_approx(grid_origin)) {
		return;
	}
	grid_origin = origin;
	changed();
}

bool TerrainEdits::add_brush_native(const Vector3 &world_position, double radius, bool add_solid,
		const DensityFn &density, int material, const MaterialFn &natural_material) {
	double brush_radius = tmath::maxd(radius, 0.1);
	return stamp(world_position, Vector3(1, 1, 1) * (real_t)brush_radius, false, add_solid, density, material,
			natural_material);
}

bool TerrainEdits::add_box_native(const Vector3 &center, const Vector3 &half_extents, bool add_solid,
		const DensityFn &density, int material, const MaterialFn &natural_material) {
	return stamp(center, half_extents.abs().max(Vector3(0.1f, 0.1f, 0.1f)), true, add_solid, density, material,
			natural_material);
}

static TerrainEdits::DensityFn density_of(const Callable &callable) {
	return [callable](const Vector3 &p) -> double { return (double)callable.call(p); };
}

static TerrainEdits::MaterialFn material_of(const Callable &callable) {
	if (!callable.is_valid()) {
		return nullptr;
	}
	return [callable](const Vector3 &p, double d) -> int { return (int)callable.call(p, d); };
}

bool TerrainEdits::add_brush(const Vector3 &world_position, double radius, bool add_solid,
		const Callable &procedural_density, int material, const Callable &natural_material) {
	return add_brush_native(world_position, radius, add_solid, density_of(procedural_density), material,
			material_of(natural_material));
}

bool TerrainEdits::add_box(const Vector3 &center, const Vector3 &half_extents, bool add_solid,
		const Callable &procedural_density, int material, const Callable &natural_material) {
	return add_box_native(center, half_extents, add_solid, density_of(procedural_density), material,
			material_of(natural_material));
}

bool TerrainEdits::stamp(const Vector3 &center, const Vector3 &half_extents, bool box, bool add_solid,
		const DensityFn &density, int material, const MaterialFn &natural_material) {
	last_removed = Dictionary();
	last_added = 0;
	Vector3 reach = half_extents + Vector3(1, 1, 1) * (real_t)voxel_size;
	Vector3 ceiled = (reach / (real_t)voxel_size).ceil();
	Vector3i extent_voxels = Vector3i((int)ceiled.x, (int)ceiled.y, (int)ceiled.z) + Vector3i(1, 1, 1);
	Vector3i center_key = world_to_key(center);
	bool any_changed = false;
	Vector3i changed_min;
	Vector3i changed_max;
	for (int offset_z = -extent_voxels.z; offset_z < extent_voxels.z + 1; offset_z++) {
		for (int offset_y = -extent_voxels.y; offset_y < extent_voxels.y + 1; offset_y++) {
			for (int offset_x = -extent_voxels.x; offset_x < extent_voxels.x + 1; offset_x++) {
				Vector3i voxel_key = center_key + Vector3i(offset_x, offset_y, offset_z);
				Vector3 sample_position = key_to_world(voxel_key);
				double sphere_sdf;
				if (box) {
					Vector3 q = (sample_position - center).abs() - half_extents;
					sphere_sdf = (double)q.max(Vector3()).length() +
							tmath::mind(tmath::maxd(q.x, tmath::maxd(q.y, q.z)), 0.0);
				} else {
					sphere_sdf = (double)sample_position.distance_to(center) - (double)half_extents.x;
				}
				if (sphere_sdf > voxel_size) {
					continue;
				}
				double density_value;
				auto found = overrides.find(voxel_key);
				if (found != overrides.end()) {
					density_value = found->second;
				} else {
					density_value = density(sample_position);
				}
				double new_density_value;
				if (add_solid) {
					new_density_value = tmath::mind(density_value, sphere_sdf);
				} else {
					new_density_value = tmath::maxd(density_value, -sphere_sdf);
				}
				bool voxel_changed = !tmath::approx(new_density_value, density_value);
				if (voxel_changed) {
					overrides[voxel_key] = new_density_value;
					if (density_value < 0.0 && new_density_value >= 0.0) {
						int dug = mat::NATURAL;
						auto m = materials.find(voxel_key);
						if (m != materials.end()) {
							dug = m->second;
						}
						if (dug == mat::NATURAL && natural_material) {
							dug = natural_material(sample_position, density_value);
						}
						if (dug == mat::NATURAL) {
							dug = mat::DIRT;
						}
						last_removed[dug] = (int)last_removed.get(dug, 0) + 1;
					} else if (density_value >= 0.0 && new_density_value < 0.0) {
						last_added += 1;
					}
				}
				if (new_density_value < 0.0) {
					if (add_solid && sphere_sdf <= 0.0) {
						voxel_changed = set_material(voxel_key, material) || voxel_changed;
					}
				} else if (materials.erase(voxel_key) > 0) {
					voxel_changed = true;
				}
				if (!voxel_changed) {
					continue;
				}
				changed();
				if (any_changed) {
					changed_min = changed_min.min(voxel_key);
					changed_max = changed_max.max(voxel_key);
				} else {
					any_changed = true;
					changed_min = voxel_key;
					changed_max = voxel_key;
				}
			}
		}
	}
	if (any_changed) {
		Vector3i padding(1, 1, 1);
		Vector3 bounds_min = key_to_world(changed_min - padding);
		Vector3 bounds_max = key_to_world(changed_max + padding);
		last_changed_bounds = AABB(bounds_min, bounds_max - bounds_min);
	} else {
		last_changed_bounds = AABB();
	}
	return any_changed;
}

bool TerrainEdits::set_material(const Vector3i &voxel_key, int material) {
	if (material == mat::NATURAL) {
		return materials.erase(voxel_key) > 0;
	}
	auto found = materials.find(voxel_key);
	if (found != materials.end() && found->second == material) {
		return false;
	}
	materials[voxel_key] = material;
	return true;
}

double TerrainEdits::apply_to_density(double density, const Vector3 &world_position) const {
	if (overrides.empty()) {
		return density;
	}
	auto found = overrides.find(world_to_key(world_position));
	if (found != overrides.end()) {
		return found->second;
	}
	return density;
}

bool TerrainEdits::is_overridden_at(const Vector3 &world_position) const {
	return !overrides.empty() && overrides.count(world_to_key(world_position)) > 0;
}

int TerrainEdits::material_at(const Vector3 &world_position) const {
	if (materials.empty()) {
		return mat::NATURAL;
	}
	auto found = materials.find(world_to_key(world_position));
	return found != materials.end() ? found->second : (int)mat::NATURAL;
}

Dictionary TerrainEdits::export_state() const {
	Dictionary out_overrides;
	for (const auto &entry : overrides) {
		out_overrides[entry.first] = entry.second;
	}
	Dictionary out_materials;
	for (const auto &entry : materials) {
		out_materials[entry.first] = entry.second;
	}
	Dictionary state;
	state["overrides"] = out_overrides;
	state["materials"] = out_materials;
	return state;
}

void TerrainEdits::import_state(const Dictionary &state) {
	overrides.clear();
	materials.clear();
	Dictionary in_overrides = state.get("overrides", Dictionary());
	Array keys = in_overrides.keys();
	for (int i = 0; i < keys.size(); i++) {
		Variant key = keys[i];
		if (key.get_type() == Variant::VECTOR3I) {
			overrides[(Vector3i)key] = (double)in_overrides[key];
		}
	}
	Dictionary in_materials = state.get("materials", Dictionary());
	keys = in_materials.keys();
	for (int i = 0; i < keys.size(); i++) {
		Variant key = keys[i];
		if (key.get_type() == Variant::VECTOR3I) {
			materials[(Vector3i)key] = (int)in_materials[key];
		}
	}
	changed();
	last_changed_bounds = get_all_bounds();
}

AABB TerrainEdits::get_all_bounds() {
	if (all_bounds_known) {
		return all_bounds;
	}
	all_bounds = measure_all_bounds();
	all_bounds_known = true;
	return all_bounds;
}

AABB TerrainEdits::get_all_bounds_const() const {
	if (all_bounds_known) {
		return all_bounds;
	}
	return measure_all_bounds();
}

AABB TerrainEdits::measure_all_bounds() const {
	if (overrides.empty()) {
		return AABB();
	}
	Vector3i key_min;
	Vector3i key_max;
	bool first = true;
	for (const auto &entry : overrides) {
		if (first) {
			key_min = entry.first;
			key_max = entry.first;
			first = false;
		} else {
			key_min = key_min.min(entry.first);
			key_max = key_max.max(entry.first);
		}
	}
	Vector3i padding(1, 1, 1);
	Vector3 bounds_min = key_to_world(key_min - padding);
	Vector3 bounds_max = key_to_world(key_max + padding);
	return AABB(bounds_min, bounds_max - bounds_min);
}

Ref<TerrainEdits> TerrainEdits::duplicate_for_thread() {
	if (thread_snapshot.is_valid() && tmath::approx(thread_snapshot->voxel_size, voxel_size)) {
		return thread_snapshot;
	}
	Ref<TerrainEdits> copy;
	copy.instantiate();
	copy->voxel_size = voxel_size;
	copy->grid_origin = grid_origin;
	copy->overrides = overrides;
	copy->materials = materials;
	// Measured now, so the worker threads only read it.
	copy->all_bounds = copy->measure_all_bounds();
	copy->all_bounds_known = true;
	thread_snapshot = copy;
	return copy;
}

Vector3i TerrainEdits::position_to_key(const Vector3 &world_position, double p_voxel_size) {
	double inverse_voxel_size = 1.0 / tmath::maxd(p_voxel_size, 0.001);
	return Vector3i(
			(int)std::round((double)world_position.x * inverse_voxel_size),
			(int)std::round((double)world_position.y * inverse_voxel_size),
			(int)std::round((double)world_position.z * inverse_voxel_size));
}

Vector3 TerrainEdits::key_to_position(const Vector3i &voxel_key, double p_voxel_size) {
	return Vector3((real_t)voxel_key.x, (real_t)voxel_key.y, (real_t)voxel_key.z) * (real_t)p_voxel_size;
}

void TerrainEdits::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_voxel_size", "voxel_size"), &TerrainEdits::set_voxel_size);
	ClassDB::bind_method(D_METHOD("set_grid_origin", "origin"), &TerrainEdits::set_grid_origin);
	ClassDB::bind_method(D_METHOD("add_brush", "world_position", "radius", "add_solid", "procedural_density", "material", "natural_material"),
			&TerrainEdits::add_brush, DEFVAL(0), DEFVAL(Callable()));
	ClassDB::bind_method(D_METHOD("add_box", "center", "half_extents", "add_solid", "procedural_density", "material", "natural_material"),
			&TerrainEdits::add_box, DEFVAL(0), DEFVAL(Callable()));
	ClassDB::bind_method(D_METHOD("get_last_changed_bounds"), &TerrainEdits::get_last_changed_bounds);
	ClassDB::bind_method(D_METHOD("apply_to_density", "density", "world_position"), &TerrainEdits::apply_to_density);
	ClassDB::bind_method(D_METHOD("is_overridden_at", "world_position"), &TerrainEdits::is_overridden_at);
	ClassDB::bind_method(D_METHOD("material_at", "world_position"), &TerrainEdits::material_at);
	ClassDB::bind_method(D_METHOD("has_materials"), &TerrainEdits::has_materials);
	ClassDB::bind_method(D_METHOD("get_override_count"), &TerrainEdits::get_override_count);
	ClassDB::bind_method(D_METHOD("export_state"), &TerrainEdits::export_state);
	ClassDB::bind_method(D_METHOD("import_state", "state"), &TerrainEdits::import_state);
	ClassDB::bind_method(D_METHOD("get_all_bounds"), &TerrainEdits::get_all_bounds);
	ClassDB::bind_method(D_METHOD("duplicate_for_thread"), &TerrainEdits::duplicate_for_thread);
	ClassDB::bind_static_method("TerrainEdits", D_METHOD("position_to_key", "world_position", "voxel_size"), &TerrainEdits::position_to_key);
	ClassDB::bind_static_method("TerrainEdits", D_METHOD("key_to_position", "voxel_key", "voxel_size"), &TerrainEdits::key_to_position);
	ClassDB::bind_method(D_METHOD("get_last_removed"), &TerrainEdits::get_last_removed);
	ClassDB::bind_method(D_METHOD("set_last_removed", "value"), &TerrainEdits::set_last_removed);
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "last_removed"), "set_last_removed", "get_last_removed");
	ClassDB::bind_method(D_METHOD("get_last_added"), &TerrainEdits::get_last_added);
	ClassDB::bind_method(D_METHOD("set_last_added", "value"), &TerrainEdits::set_last_added);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "last_added"), "set_last_added", "get_last_added");
}

} // namespace godot
