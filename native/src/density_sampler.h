// Builds signed density fields: a chunk's samples on the shared world grid (so neighbouring
// chunks get bit-identical values on their shared faces), and a brush stroke's resample of
// only the samples it changed.
#pragma once

#include "common.h"
#include "signed_density_field.h"
#include "world_density.h"

#include <godot_cpp/classes/fast_noise_lite.hpp>

namespace godot {

class DensitySampler : public RefCounted {
	GDCLASS(DensitySampler, RefCounted)

protected:
	static void _bind_methods();

public:
	static constexpr double SPONGE_NOISE_METRES = WorldDensity::SPONGE_NOISE_METRES;

	static Ref<WorldDensity> create_open_terrain_world_density(int noise_seed, double noise_frequency,
			double noise_amplitude, int noise_octaves, double noise_lacunarity, double noise_gain,
			const Vector3 &bounds_center, const Vector3 &bounds_half, double bounds_clip_inset = 0.5,
			bool open_edges_enabled = true, const Ref<Image> &heightmap_image = Ref<Image>(),
			double surface_height_offset = 0.0, bool solid_fill = false);
	static Ref<WorldDensity> create_boxed_in_terrain_world_density(int noise_seed, double noise_frequency,
			int noise_octaves, double noise_lacunarity, double noise_gain, const Vector3 &bounds_center,
			const Vector3 &bounds_half, double bounds_clip_inset = 0.5, bool boxed_edges_enabled = true);

	// FBm by hand over a noise (each octave a read of the noise as it is set up).
	static double fbm(const TNoise &noise, const Vector3 &world_pos, int octaves, double lacunarity, double gain);
	static double fbm_noise_3d(const Ref<FastNoiseLite> &noise, const Vector3 &world_pos, int octaves,
			double lacunarity, double gain);
	static double boxed_in_terrain_box_sdf(const Vector3 &world_pos, const Vector3 &bounds_center,
			const Vector3 &bounds_half, double clip_inset);
	static double open_terrain_box_sdf(const Vector3 &world_pos, const Vector3 &bounds_center,
			const Vector3 &bounds_half, double clip_inset);
	static double sample_heightmap_image(const Ref<Image> &heightmap_image, double world_x, double world_z,
			const Vector3 &bounds_center, const Vector3 &bounds_half, double height_scale);

	static Ref<SignedDensityField> build_chunk_field(const Ref<WorldDensity> &density, const Vector3i &sample_size,
			const Vector3 &grid_world_origin, const Vector3i &grid_offset, double step);
	static Ref<SignedDensityField> resample_chunk_field(const Ref<SignedDensityField> &cached,
			const Ref<WorldDensity> &density, const Vector3 &grid_world_origin, const Vector3i &grid_offset, double step,
			const AABB &bounds);
	static Vector3 grid_sample_position(const Vector3 &grid_world_origin, const Vector3i &global_sample, double step) {
		return v3((double)grid_world_origin.x + (double)global_sample.x * step,
				(double)grid_world_origin.y + (double)global_sample.y * step,
				(double)grid_world_origin.z + (double)global_sample.z * step);
	}
	static double sponge_noise_metres() { return SPONGE_NOISE_METRES; }
};

} // namespace godot
