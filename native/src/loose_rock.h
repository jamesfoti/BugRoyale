// Clears the floating rock out of a chunk's sampled field before it is meshed: a lump of
// solid samples with air on every side, up to a set number of voxels, is turned to air. A
// lump on a chunk face is judged the same from both sides (the pass reads up to HALO samples
// past the faces), so lumps across a seam thicker than that are kept. Anything built with the
// brush is never cleared.
#pragma once

#include "common.h"
#include "signed_density_field.h"
#include "world_density.h"

namespace godot {

class LooseRock : public RefCounted {
	GDCLASS(LooseRock, RefCounted)

protected:
	static void _bind_methods();

public:
	static constexpr int HALO = 2;

	static int clear(const Ref<SignedDensityField> &field, const Ref<WorldDensity> &density,
			const Vector3 &grid_world_origin, const Vector3i &grid_offset, double step, int cells_per_axis,
			double iso_level, int max_voxels);
};

} // namespace godot
