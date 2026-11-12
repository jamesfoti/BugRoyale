#include "terrain_chunk.h"

#include <godot_cpp/classes/collision_shape3d.hpp>
#include <godot_cpp/classes/concave_polygon_shape3d.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/static_body3d.hpp>

namespace godot {

static const char *WATER_MATERIAL_PATH = "res://materials/terrarium_water.tres";

void TerrainChunk::rebuild(const Ref<TerrainSettings> &settings) {
	Ref<ChunkBuildResult> result = ChunkMeshBuilder::build_chunk(chunk_coordinate, settings);
	apply_build_result(result, settings->rebuild_collision);
}

void TerrainChunk::apply_build_result(const Ref<ChunkBuildResult> &result, bool rebuild_collision) {
	set_mesh(FlyingEdgesMesher::to_array_mesh(result->mesh_result));
	set_position(result->local_position);
	apply_water(result->water_mesh_result);
	if (rebuild_collision && wants_collision()) {
		create_trimesh_collision(result->collision_faces);
	}
}

void TerrainChunk::apply_water(const Ref<TerrainMeshResult> &water_mesh_result) {
	MeshInstance3D *water = Object::cast_to<MeshInstance3D>(get_node_or_null(NodePath("Water")));
	if (water_mesh_result.is_null() || water_mesh_result->indices.is_empty()) {
		if (water != nullptr) {
			water->queue_free();
		}
		return;
	}
	if (water == nullptr) {
		water = memnew(MeshInstance3D);
		water->set_name("Water");
		water->set_material_override(ResourceLoader::get_singleton()->load(WATER_MATERIAL_PATH));
		water->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
		add_child(water);
	}
	water->set_mesh(FlyingEdgesMesher::to_array_mesh(water_mesh_result));
}

void TerrainChunk::update_collision() {
	if (wants_collision()) {
		create_trimesh_collision(PackedVector3Array());
	}
}

bool TerrainChunk::wants_collision() const {
	Ref<Mesh> current = get_mesh();
	return !Engine::get_singleton()->is_editor_hint() && current.is_valid() && current->get_surface_count() > 0;
}

void TerrainChunk::create_trimesh_collision(const PackedVector3Array &faces) {
	TypedArray<Node> children = get_children();
	for (int i = 0; i < children.size(); i++) {
		StaticBody3D *body = Object::cast_to<StaticBody3D>(children[i]);
		if (body != nullptr) {
			body->queue_free();
		}
	}
	StaticBody3D *static_body = memnew(StaticBody3D);
	CollisionShape3D *collision_shape = memnew(CollisionShape3D);
	if (faces.is_empty()) {
		collision_shape->set_shape(get_mesh()->create_trimesh_shape());
	} else {
		Ref<ConcavePolygonShape3D> shape;
		shape.instantiate();
		shape->set_faces(faces);
		collision_shape->set_shape(shape);
	}
	static_body->add_child(collision_shape);
	add_child(static_body);
}

void TerrainChunk::_bind_methods() {
	ClassDB::bind_method(D_METHOD("rebuild", "settings"), &TerrainChunk::rebuild);
	ClassDB::bind_method(D_METHOD("apply_build_result", "result", "rebuild_collision"), &TerrainChunk::apply_build_result);
	ClassDB::bind_method(D_METHOD("update_collision"), &TerrainChunk::update_collision);
	ClassDB::bind_method(D_METHOD("set_chunk_coordinate", "value"), &TerrainChunk::set_chunk_coordinate);
	ClassDB::bind_method(D_METHOD("get_chunk_coordinate"), &TerrainChunk::get_chunk_coordinate);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3I, "chunk_coordinate"), "set_chunk_coordinate", "get_chunk_coordinate");
}

} // namespace godot
