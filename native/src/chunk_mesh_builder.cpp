#include "chunk_mesh_builder.h"

#include "density_sampler.h"
#include "loose_rock.h"

namespace godot {

ChunkBuildResult::ChunkBuildResult() {
}

void BuildJob::run(void *userdata) {
	BuildJob *job = static_cast<BuildJob *>(userdata);
	job->results.resize(job->chunk_coordinates.size());
	for (size_t i = 0; i < job->chunk_coordinates.size(); i++) {
		job->results[i] = ChunkMeshBuilder::build_chunk(job->chunk_coordinates[i], job->settings);
	}
}

Ref<WorldDensity> ChunkMeshBuilder::density_for(const Ref<TerrainSettings> &settings) {
	Ref<WorldDensity> density;
	if (settings->density_prototype.is_valid()) {
		density = settings->density_prototype->clone_for_build();
	} else if (settings->density_factory.is_valid()) {
		density = settings->density_factory.call(settings);
	} else if (settings->open_terrain_enabled) {
		density = WorldDensity::create_open_terrain(settings->noise_seed, settings->noise_frequency,
				settings->noise_amplitude, settings->noise_octaves, settings->noise_lacunarity, settings->noise_gain,
				settings->bounds_center, settings->bounds_half, settings->bounds_clip_inset,
				settings->open_terrain_edges_enabled, settings->open_terrain_heightmap_image,
				settings->open_terrain_surface_offset, settings->open_terrain_solid_fill);
	} else if (settings->boxed_in_terrain_enabled) {
		density = WorldDensity::create_boxed_in_terrain(settings->noise_seed, settings->noise_frequency,
				settings->noise_octaves, settings->noise_lacunarity, settings->noise_gain, settings->bounds_center,
				settings->bounds_half, settings->bounds_clip_inset, settings->boxed_in_edges_enabled);
	} else {
		density = WorldDensity::create(settings->noise_enabled, settings->noise_seed, settings->noise_frequency,
				settings->noise_amplitude, settings->noise_octaves, settings->noise_lacunarity, settings->noise_gain,
				settings->bounds_center, settings->bounds_half, settings->bounds_clip_inset);
	}
	if (settings->terrain_edits.is_valid()) {
		density->terrain_edits = settings->terrain_edits;
	}
	if (!settings->solids.is_empty()) {
		density->set_solids(settings->solids);
	}
	return density;
}

Ref<ChunkBuildResult> ChunkMeshBuilder::build_chunk(const Vector3i &chunk_coordinate,
		const Ref<TerrainSettings> &settings) {
	Ref<ChunkBuildResult> result;
	result.instantiate();
	build_chunk_into(result, chunk_coordinate, settings);
	return result;
}

void ChunkMeshBuilder::build_chunk_into(const Ref<ChunkBuildResult> &result, const Vector3i &chunk_coordinate,
		const Ref<TerrainSettings> &settings) {
	int cells_per_axis = settings->cells_per_axis;
	double extent = settings->chunk_world_size;
	Vector3i sample_size = Vector3i(1, 1, 1) * (cells_per_axis + 1);
	Vector3 corner_local = chunk_corner_local(chunk_coordinate, settings);
	Vector3 half_extent = Vector3(1, 1, 1) * (real_t)(extent * 0.5);
	Vector3 world_corner = settings->world_origin + corner_local;
	Vector3 world_center = world_corner + half_extent;
	Vector3 grid_world_origin = settings->world_origin + chunk_corner_local(Vector3i(), settings);
	double world_step = extent / (double)cells_per_axis;
	Vector3i grid_offset = chunk_coordinate * cells_per_axis;
	Ref<WorldDensity> density = density_for(settings);
	result->water_mesh_result.instantiate();
	Ref<SignedDensityField> field;
	if (settings->cached_field.is_valid() && settings->resample_bounds.has_volume()) {
		field = DensitySampler::resample_chunk_field(settings->cached_field, density, grid_world_origin, grid_offset,
				world_step, settings->resample_bounds);
	} else {
		field = DensitySampler::build_chunk_field(density, sample_size, grid_world_origin, grid_offset, world_step);
	}
	if (settings->keep_field) {
		result->field = field;
	}
	if (settings->loose_rock_voxels > 0 && !field->sky && field->min_value < settings->iso_level &&
			field->max_value >= settings->iso_level) {
		LooseRock::clear(field, density, grid_world_origin, grid_offset, world_step, cells_per_axis,
				settings->iso_level, settings->loose_rock_voxels);
	}
	if (settings->keep_field) {
		Ref<ChunkMeshBlocks> previous = settings->cached_field.is_valid() ? settings->cached_blocks : Ref<ChunkMeshBlocks>();
		Ref<ChunkMeshBlocks> blocks = ChunkMeshBlocks::build_native(field, extent, settings->iso_level, grid_offset,
				grid_world_origin, world_center, density.ptr(), previous);
		result->mesh_result = blocks->merge();
		result->blocks = blocks;
	} else {
		result->mesh_result = FlyingEdgesMesher::build(field, extent, settings->iso_level, grid_offset, grid_world_origin,
				world_center, density.ptr(), Vector3i(), Vector3i(-1, -1, -1), nullptr);
	}
	result->collision_faces = collision_faces(result->mesh_result);
	if (density->caves.is_valid() && density->caves->water_top > -tmath::INF_D && !field->sky) {
		result->water_mesh_result = CaveWaterMesher::build_native(field, density.ptr(), grid_world_origin, grid_offset,
				world_step, extent, world_center);
	}
	result->local_position = corner_local + half_extent;
}

PackedVector3Array ChunkMeshBuilder::collision_faces(const Ref<TerrainMeshResult> &mesh_result) {
	PackedVector3Array faces;
	const PackedInt32Array &indices = mesh_result->indices;
	const Vector3 *vertices = mesh_result->vertices.ptr();
	faces.resize(indices.size());
	Vector3 *out = faces.ptrw();
	const int32_t *index = indices.ptr();
	for (int64_t i = 0; i < indices.size(); i++) {
		out[i] = vertices[index[i]];
	}
	return faces;
}

Vector3 ChunkMeshBuilder::chunk_corner_local(const Vector3i &chunk_coordinate, const Ref<TerrainSettings> &settings) {
	real_t extent = (real_t)settings->chunk_world_size;
	Vector3 grid_origin = -Vector3((real_t)settings->chunks_x, (real_t)settings->chunks_y, (real_t)settings->chunks_z) *
			extent * 0.5f;
	return grid_origin + Vector3(chunk_coordinate) * extent;
}

void ChunkBuildResult::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_mesh_result"), &ChunkBuildResult::get_mesh_result);
	ClassDB::bind_method(D_METHOD("get_field"), &ChunkBuildResult::get_field);
	ClassDB::bind_method(D_METHOD("get_blocks"), &ChunkBuildResult::get_blocks);
	ClassDB::bind_method(D_METHOD("get_water_mesh_result"), &ChunkBuildResult::get_water_mesh_result);
	ClassDB::bind_method(D_METHOD("get_local_position"), &ChunkBuildResult::get_local_position);
	ClassDB::bind_method(D_METHOD("get_collision_faces"), &ChunkBuildResult::get_collision_faces);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "mesh_result"), "", "get_mesh_result");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "field"), "", "get_field");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "blocks"), "", "get_blocks");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "water_mesh_result"), "", "get_water_mesh_result");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "local_position"), "", "get_local_position");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_VECTOR3_ARRAY, "collision_faces"), "", "get_collision_faces");
}

void ChunkMeshBuilder::_bind_methods() {
	ClassDB::bind_static_method("ChunkMeshBuilder", D_METHOD("build_chunk", "chunk_coordinate", "settings"), &ChunkMeshBuilder::build_chunk);
	ClassDB::bind_static_method("ChunkMeshBuilder", D_METHOD("collision_faces", "mesh_result"), &ChunkMeshBuilder::collision_faces);
	ClassDB::bind_static_method("ChunkMeshBuilder", D_METHOD("chunk_corner_local", "chunk_coordinate", "settings"), &ChunkMeshBuilder::chunk_corner_local);
}

} // namespace godot
