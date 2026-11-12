#include "density_sampler.h"

#include <vector>

namespace godot {

Ref<WorldDensity> DensitySampler::create_open_terrain_world_density(int noise_seed, double noise_frequency,
		double noise_amplitude, int noise_octaves, double noise_lacunarity, double noise_gain,
		const Vector3 &bounds_center, const Vector3 &bounds_half, double bounds_clip_inset, bool open_edges_enabled,
		const Ref<Image> &heightmap_image, double surface_height_offset, bool solid_fill) {
	return WorldDensity::create_open_terrain(noise_seed, noise_frequency, noise_amplitude, noise_octaves,
			noise_lacunarity, noise_gain, bounds_center, bounds_half, bounds_clip_inset, open_edges_enabled,
			heightmap_image, surface_height_offset, solid_fill);
}

Ref<WorldDensity> DensitySampler::create_boxed_in_terrain_world_density(int noise_seed, double noise_frequency,
		int noise_octaves, double noise_lacunarity, double noise_gain, const Vector3 &bounds_center,
		const Vector3 &bounds_half, double bounds_clip_inset, bool boxed_edges_enabled) {
	return WorldDensity::create_boxed_in_terrain(noise_seed, noise_frequency, noise_octaves, noise_lacunarity,
			noise_gain, bounds_center, bounds_half, bounds_clip_inset, boxed_edges_enabled);
}

double DensitySampler::fbm(const TNoise &noise, const Vector3 &world_pos, int octaves, double lacunarity, double gain) {
	double amplitude = 1.0;
	double frequency = 1.0;
	double total = 0.0;
	double normalizer = 0.0;
	for (int i = 0; i < octaves; i++) {
		total += noise.get_3d((double)world_pos.x * frequency, (double)world_pos.y * frequency,
						 (double)world_pos.z * frequency) *
				amplitude;
		normalizer += amplitude;
		amplitude *= gain;
		frequency *= lacunarity;
	}
	if (normalizer <= 0.0) {
		return 0.0;
	}
	return total / normalizer;
}

double DensitySampler::fbm_noise_3d(const Ref<FastNoiseLite> &noise, const Vector3 &world_pos, int octaves,
		double lacunarity, double gain) {
	double amplitude = 1.0;
	double frequency = 1.0;
	double total = 0.0;
	double normalizer = 0.0;
	for (int i = 0; i < octaves; i++) {
		total += (double)noise->get_noise_3d((double)world_pos.x * frequency, (double)world_pos.y * frequency,
						 (double)world_pos.z * frequency) *
				amplitude;
		normalizer += amplitude;
		amplitude *= gain;
		frequency *= lacunarity;
	}
	if (normalizer <= 0.0) {
		return 0.0;
	}
	return total / normalizer;
}

double DensitySampler::boxed_in_terrain_box_sdf(const Vector3 &world_pos, const Vector3 &bounds_center,
		const Vector3 &bounds_half, double clip_inset) {
	Vector3 relative = world_pos - bounds_center;
	double half_extent_x = tmath::maxd((double)bounds_half.x - clip_inset, 0.0);
	double half_extent_y = tmath::maxd((double)bounds_half.y - clip_inset, 0.0);
	double half_extent_z = tmath::maxd((double)bounds_half.z - clip_inset, 0.0);
	double outside_x = std::abs((double)relative.x) - half_extent_x;
	double outside_y = std::abs((double)relative.y) - half_extent_y;
	double outside_z = std::abs((double)relative.z) - half_extent_z;
	return tmath::maxd(outside_x, tmath::maxd(outside_y, outside_z));
}

double DensitySampler::open_terrain_box_sdf(const Vector3 &world_pos, const Vector3 &bounds_center,
		const Vector3 &bounds_half, double clip_inset) {
	Vector3 relative = world_pos - bounds_center;
	double half_extent_x = tmath::maxd((double)bounds_half.x - clip_inset, 0.0);
	double half_extent_y = tmath::maxd((double)bounds_half.y - clip_inset, 0.0);
	double half_extent_z = tmath::maxd((double)bounds_half.z - clip_inset, 0.0);
	double outside_x = std::abs((double)relative.x) - half_extent_x;
	double outside_z = std::abs((double)relative.z) - half_extent_z;
	double outside_bottom = -half_extent_y - (double)relative.y;
	return tmath::maxd(outside_x, tmath::maxd(outside_z, outside_bottom));
}

double DensitySampler::sample_heightmap_image(const Ref<Image> &heightmap_image, double world_x, double world_z,
		const Vector3 &bounds_center, const Vector3 &bounds_half, double height_scale) {
	if ((double)bounds_half.x <= 0.0 || (double)bounds_half.z <= 0.0) {
		return bounds_center.y;
	}
	double normalized_x = (world_x - (double)bounds_center.x) / (double)bounds_half.x;
	double normalized_z = (world_z - (double)bounds_center.z) / (double)bounds_half.z;
	if (std::abs(normalized_x) > 1.0 || std::abs(normalized_z) > 1.0) {
		return bounds_center.y;
	}
	Vector2i image_size = heightmap_image->get_size();
	int sample_x = tmath::clampi((int)std::floor((normalized_x * 0.5 + 0.5) * (double)(image_size.x - 1)), 0, image_size.x - 1);
	int sample_z = tmath::clampi((int)std::floor((normalized_z * 0.5 + 0.5) * (double)(image_size.y - 1)), 0, image_size.y - 1);
	Color pixel = heightmap_image->get_pixel(sample_x, sample_z);
	double height_sample = ((double)pixel.r + (double)pixel.g + (double)pixel.b) / 3.0;
	return (double)bounds_center.y + (height_sample - 0.5) * height_scale * 2.0;
}

Ref<SignedDensityField> DensitySampler::build_chunk_field(const Ref<WorldDensity> &density_ref,
		const Vector3i &sample_size, const Vector3 &grid_world_origin, const Vector3i &grid_offset, double step) {
	WorldDensity *density = density_ref.ptr();
	Ref<SignedDensityField> field = SignedDensityField::make(sample_size);
	PackedFloat32Array values = field->values;
	float *out = values.ptrw();
	int size_x = sample_size.x;
	int size_y = sample_size.y;
	int size_z = sample_size.z;
	if (!density->solids.empty() || (density->caves.is_valid() && density->caves->systems.is_valid())) {
		Vector3 halo = Vector3(1, 1, 1) * (real_t)(step * 2.0);
		Vector3 region_start = grid_world_origin + Vector3(grid_offset) * (real_t)step - halo;
		density->prepare_for_region(AABB(region_start, Vector3(sample_size) * (real_t)step + halo * 2.0f));
	}
	double min_value = tmath::INF_D;
	double max_value = -tmath::INF_D;
	bool use_column_heights = density->open_terrain_enabled;
	// The scripts kept these in PackedFloat32Arrays: the surface height of a column is a float.
	std::vector<float> column_heights;
	std::vector<float> column_slopes;
	if (use_column_heights) {
		column_heights.assign(size_x * size_z, 0.0f);
		column_slopes.assign(size_x * size_z, 0.0f);
		bool want_slopes = density->open_terrain_solid_fill &&
				(density->relief_amplitude > 0.0 || density->caves.is_valid());
		double highest = -tmath::INF_D;
		for (int z = 0; z < size_z; z++) {
			double world_z = (double)grid_world_origin.z + (double)(grid_offset.z + z) * step;
			for (int x = 0; x < size_x; x++) {
				double world_x = (double)grid_world_origin.x + (double)(grid_offset.x + x) * step;
				double height = density->sample_open_terrain_height(world_x, world_z);
				column_heights[x + z * size_x] = (float)height;
				if (want_slopes) {
					column_slopes[x + z * size_x] = (float)density->surface_slope(world_x, world_z, height);
				}
				highest = tmath::maxd(highest, height);
			}
		}
		double bottom_y = (double)grid_world_origin.y + (double)grid_offset.y * step;
		Vector3 halo = Vector3(1, 1, 1) * (real_t)step;
		AABB region = AABB(grid_world_origin + Vector3(grid_offset) * (real_t)step - halo,
				Vector3(sample_size - Vector3i(1, 1, 1)) * (real_t)step + halo * 2.0f);
		if (density->is_sky(highest + density->relief_reach(), bottom_y, region)) {
			double clearance = bottom_y - highest;
			values.fill((float)clearance);
			field->values = values;
			field->min_value = clearance;
			field->max_value = clearance;
			field->sky = true;
			return field;
		}
	}
	int index = 0;
	for (int z = 0; z < size_z; z++) {
		double world_z = (double)grid_world_origin.z + (double)(grid_offset.z + z) * step;
		for (int y = 0; y < size_y; y++) {
			double world_y = (double)grid_world_origin.y + (double)(grid_offset.y + y) * step;
			for (int x = 0; x < size_x; x++) {
				Vector3 world_pos = v3((double)grid_world_origin.x + (double)(grid_offset.x + x) * step, world_y, world_z);
				double value;
				if (use_column_heights) {
					value = density->evaluate_open_terrain_with_surface(world_pos, column_heights[x + z * size_x], true,
							column_slopes[x + z * size_x]);
				} else {
					value = density->evaluate(world_pos);
				}
				out[index] = (float)value;
				min_value = tmath::mind(min_value, value);
				max_value = tmath::maxd(max_value, value);
				index += 1;
			}
		}
	}
	field->values = values;
	field->min_value = min_value;
	field->max_value = max_value;
	return field;
}

Ref<SignedDensityField> DensitySampler::resample_chunk_field(const Ref<SignedDensityField> &cached,
		const Ref<WorldDensity> &density_ref, const Vector3 &grid_world_origin, const Vector3i &grid_offset, double step,
		const AABB &bounds) {
	WorldDensity *density = density_ref.ptr();
	Ref<SignedDensityField> field;
	field.instantiate();
	field->size = cached->size;
	field->values = cached->values.duplicate();
	field->sky = false;
	Vector3i size = field->size;
	Vector3 corner = grid_sample_position(grid_world_origin, grid_offset, step);
	Vector3 low_f = ((bounds.position - corner) / (real_t)step).floor();
	Vector3 high_f = ((bounds.get_end() - corner) / (real_t)step).ceil();
	Vector3i first = (Vector3i((int)low_f.x, (int)low_f.y, (int)low_f.z) - Vector3i(1, 1, 1)).max(Vector3i());
	Vector3i last = (Vector3i((int)high_f.x, (int)high_f.y, (int)high_f.z) + Vector3i(1, 1, 1)).min(size - Vector3i(1, 1, 1));
	field->changed_first = first;
	field->changed_last = last.max(first);
	if (first.x <= last.x && first.y <= last.y && first.z <= last.z) {
		if (!density->solids.empty() || (density->caves.is_valid() && density->caves->systems.is_valid())) {
			Vector3 halo = Vector3(1, 1, 1) * (real_t)(step * 2.0);
			density->prepare_for_region(AABB(corner - halo, Vector3(size) * (real_t)step + halo * 2.0f));
		}
		bool open = density->open_terrain_enabled;
		bool want_slopes = open && density->open_terrain_solid_fill &&
				(density->relief_amplitude > 0.0 || density->caves.is_valid());
		PackedFloat32Array values = field->values;
		float *out = values.ptrw();
		for (int z = first.z; z < last.z + 1; z++) {
			double world_z = (double)corner.z + (double)z * step;
			for (int x = first.x; x < last.x + 1; x++) {
				double world_x = (double)corner.x + (double)x * step;
				double height = 0.0;
				double slope = 0.0;
				if (open) {
					height = density->sample_open_terrain_height(world_x, world_z);
					if (want_slopes) {
						slope = density->surface_slope(world_x, world_z, height);
					}
				}
				for (int y = first.y; y < last.y + 1; y++) {
					Vector3 world_pos = v3(world_x, (double)corner.y + (double)y * step, world_z);
					double value;
					if (open) {
						value = density->evaluate_open_terrain_with_surface(world_pos, height, true, slope);
					} else {
						value = density->evaluate(world_pos);
					}
					out[x + y * size.x + z * size.x * size.y] = (float)value;
				}
			}
		}
		field->values = values;
	}
	double min_value = tmath::INF_D;
	double max_value = -tmath::INF_D;
	const float *read = field->values.ptr();
	int64_t count = field->values.size();
	for (int64_t i = 0; i < count; i++) {
		min_value = tmath::mind(min_value, read[i]);
		max_value = tmath::maxd(max_value, read[i]);
	}
	field->min_value = min_value;
	field->max_value = max_value;
	return field;
}

void DensitySampler::_bind_methods() {
	ClassDB::bind_static_method("DensitySampler",
			D_METHOD("create_open_terrain_world_density", "noise_seed", "noise_frequency", "noise_amplitude",
					"noise_octaves", "noise_lacunarity", "noise_gain", "bounds_center", "bounds_half",
					"bounds_clip_inset", "open_edges_enabled", "heightmap_image", "surface_height_offset", "solid_fill"),
			&DensitySampler::create_open_terrain_world_density, DEFVAL(0.5), DEFVAL(true), DEFVAL(Ref<Image>()),
			DEFVAL(0.0), DEFVAL(false));
	ClassDB::bind_static_method("DensitySampler",
			D_METHOD("create_boxed_in_terrain_world_density", "noise_seed", "noise_frequency", "noise_octaves",
					"noise_lacunarity", "noise_gain", "bounds_center", "bounds_half", "bounds_clip_inset",
					"boxed_edges_enabled"),
			&DensitySampler::create_boxed_in_terrain_world_density, DEFVAL(0.5), DEFVAL(true));
	ClassDB::bind_static_method("DensitySampler", D_METHOD("fbm_noise_3d", "noise", "world_pos", "octaves", "lacunarity", "gain"), &DensitySampler::fbm_noise_3d);
	ClassDB::bind_static_method("DensitySampler", D_METHOD("boxed_in_terrain_box_sdf", "world_pos", "bounds_center", "bounds_half", "clip_inset"), &DensitySampler::boxed_in_terrain_box_sdf);
	ClassDB::bind_static_method("DensitySampler", D_METHOD("open_terrain_box_sdf", "world_pos", "bounds_center", "bounds_half", "clip_inset"), &DensitySampler::open_terrain_box_sdf);
	ClassDB::bind_static_method("DensitySampler", D_METHOD("sample_heightmap_image", "heightmap_image", "world_x", "world_z", "bounds_center", "bounds_half", "height_scale"), &DensitySampler::sample_heightmap_image);
	ClassDB::bind_static_method("DensitySampler", D_METHOD("build_chunk_field", "density", "sample_size", "grid_world_origin", "grid_offset", "step"), &DensitySampler::build_chunk_field);
	ClassDB::bind_static_method("DensitySampler", D_METHOD("resample_chunk_field", "cached", "density", "grid_world_origin", "grid_offset", "step", "bounds"), &DensitySampler::resample_chunk_field);
	ClassDB::bind_static_method("DensitySampler", D_METHOD("grid_sample_position", "grid_world_origin", "global_sample", "step"), &DensitySampler::grid_sample_position);
	ClassDB::bind_static_method("DensitySampler", D_METHOD("sponge_noise_metres"), &DensitySampler::sponge_noise_metres);
}

} // namespace godot
