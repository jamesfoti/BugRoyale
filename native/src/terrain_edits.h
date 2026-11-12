// Baked voxel density overrides. Negative density = solid. Voxels built from a placed
// material (TerrainMaterials) also remember which one, so the mesher can colour them.
#pragma once

#include "common.h"

#include <godot_cpp/variant/callable.hpp>

#include <functional>
#include <memory>
#include <unordered_map>

namespace godot {

class TerrainEdits : public RefCounted {
	GDCLASS(TerrainEdits, RefCounted)

protected:
	static void _bind_methods();

public:
	using DensityFn = std::function<double(const Vector3 &)>;
	using MaterialFn = std::function<int(const Vector3 &, double)>;
	using OverrideMap = std::unordered_map<Vector3i, double, Vector3iHash>;
	using MaterialMap = std::unordered_map<Vector3i, int, Vector3iHash>;

	// What the last stamp dug out (kind -> voxels) and how many voxels it turned solid.
	Dictionary last_removed;
	int last_added = 0;

	double voxel_size = 1.0;
	Vector3 grid_origin;
	OverrideMap overrides;
	MaterialMap materials;

	bool add_brush_native(const Vector3 &world_position, double radius, bool add_solid, const DensityFn &density,
			int material, const MaterialFn &natural_material);
	bool add_box_native(const Vector3 &center, const Vector3 &half_extents, bool add_solid, const DensityFn &density,
			int material, const MaterialFn &natural_material);

	// Script API.
	void set_voxel_size(double p_voxel_size);
	void set_grid_origin(const Vector3 &origin);
	bool add_brush(const Vector3 &world_position, double radius, bool add_solid, const Callable &procedural_density,
			int material = 0, const Callable &natural_material = Callable());
	bool add_box(const Vector3 &center, const Vector3 &half_extents, bool add_solid, const Callable &procedural_density,
			int material = 0, const Callable &natural_material = Callable());
	AABB get_last_changed_bounds() const { return last_changed_bounds; }
	double apply_to_density(double density, const Vector3 &world_position) const;
	bool is_overridden_at(const Vector3 &world_position) const;
	int material_at(const Vector3 &world_position) const;
	bool has_materials() const { return !materials.empty(); }
	int get_override_count() const { return (int)overrides.size(); }
	Dictionary export_state() const;
	void import_state(const Dictionary &state);
	AABB get_all_bounds();
	AABB get_all_bounds_const() const;
	Ref<TerrainEdits> duplicate_for_thread();

	static Vector3i position_to_key(const Vector3 &world_position, double p_voxel_size);
	static Vector3 key_to_position(const Vector3i &voxel_key, double p_voxel_size);

	Vector3i world_to_key(const Vector3 &world_position) const {
		return position_to_key(world_position - grid_origin, voxel_size);
	}
	Vector3 key_to_world(const Vector3i &voxel_key) const {
		return grid_origin + key_to_position(voxel_key, voxel_size);
	}

	Dictionary get_last_removed() const { return last_removed; }
	void set_last_removed(const Dictionary &v) { last_removed = v; }
	int get_last_added() const { return last_added; }
	void set_last_added(int v) { last_added = v; }

private:
	AABB last_changed_bounds;
	AABB all_bounds;
	bool all_bounds_known = false;
	Ref<TerrainEdits> thread_snapshot;

	bool stamp(const Vector3 &center, const Vector3 &half_extents, bool box, bool add_solid, const DensityFn &density,
			int material, const MaterialFn &natural_material);
	bool set_material(const Vector3i &voxel_key, int material);
	AABB measure_all_bounds() const;
	void changed();
};

} // namespace godot
