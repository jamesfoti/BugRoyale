#include "terrain_settings.h"

#include "chunk_mesh_blocks.h"
#include "signed_density_field.h"
#include "world_density.h"

namespace godot {

static TypedArray<Dictionary> typed_dictionaries(const Array &source) {
	TypedArray<Dictionary> out;
	for (int i = 0; i < source.size(); i++) {
		out.push_back(source[i]);
	}
	return out;
}

TypedArray<Dictionary> TerrainSettings::get_open_terrain_land_biomes() const {
	return typed_dictionaries(open_terrain_land_biomes);
}

TypedArray<Dictionary> TerrainSettings::get_open_terrain_cave_biomes() const {
	return typed_dictionaries(open_terrain_cave_biomes);
}

TypedArray<Dictionary> TerrainSettings::get_solids() const {
	return typed_dictionaries(solids);
}

Ref<SignedDensityField> TerrainSettings::get_cached_field() const { return cached_field; }
void TerrainSettings::set_cached_field(const Ref<SignedDensityField> &v) { cached_field = v; }
Ref<ChunkMeshBlocks> TerrainSettings::get_cached_blocks() const { return cached_blocks; }
void TerrainSettings::set_cached_blocks(const Ref<ChunkMeshBlocks> &v) { cached_blocks = v; }
Ref<WorldDensity> TerrainSettings::get_density_prototype() const { return density_prototype; }
void TerrainSettings::set_density_prototype(const Ref<WorldDensity> &v) { density_prototype = v; }

Ref<TerrainSettings> TerrainSettings::duplicate_settings() const {
	Ref<TerrainSettings> copy;
	copy.instantiate();
#define TS_COPY(T, name, def, vt) copy->name = name;
	TERRAIN_SETTINGS_FIELDS(TS_COPY)
#undef TS_COPY
	copy->material = material;
	copy->open_terrain_heightmap_image = open_terrain_heightmap_image;
	copy->open_terrain_land_biomes = open_terrain_land_biomes;
	copy->open_terrain_cave_biomes = open_terrain_cave_biomes;
	copy->terrain_edits = terrain_edits;
	copy->cached_field = cached_field;
	copy->cached_blocks = cached_blocks;
	copy->solids = solids;
	copy->density_prototype = density_prototype;
	copy->density_factory = density_factory;
	return copy;
}

void TerrainSettings::_bind_methods() {
#define TS_BIND(T, name, def, vt) TBIND(TerrainSettings, vt, name)
	TERRAIN_SETTINGS_FIELDS(TS_BIND)
#undef TS_BIND
	ClassDB::bind_method(D_METHOD("duplicate_settings"), &TerrainSettings::duplicate_settings);
	ClassDB::bind_method(D_METHOD("get_material"), &TerrainSettings::get_material);
	ClassDB::bind_method(D_METHOD("set_material", "value"), &TerrainSettings::set_material);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "material", PROPERTY_HINT_RESOURCE_TYPE, "Material"), "set_material", "get_material");
	ClassDB::bind_method(D_METHOD("get_open_terrain_heightmap_image"), &TerrainSettings::get_open_terrain_heightmap_image);
	ClassDB::bind_method(D_METHOD("set_open_terrain_heightmap_image", "value"), &TerrainSettings::set_open_terrain_heightmap_image);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "open_terrain_heightmap_image", PROPERTY_HINT_RESOURCE_TYPE, "Image"), "set_open_terrain_heightmap_image", "get_open_terrain_heightmap_image");
	ClassDB::bind_method(D_METHOD("get_open_terrain_land_biomes"), &TerrainSettings::get_open_terrain_land_biomes);
	ClassDB::bind_method(D_METHOD("set_open_terrain_land_biomes", "value"), &TerrainSettings::set_open_terrain_land_biomes);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "open_terrain_land_biomes"), "set_open_terrain_land_biomes", "get_open_terrain_land_biomes");
	ClassDB::bind_method(D_METHOD("get_open_terrain_cave_biomes"), &TerrainSettings::get_open_terrain_cave_biomes);
	ClassDB::bind_method(D_METHOD("set_open_terrain_cave_biomes", "value"), &TerrainSettings::set_open_terrain_cave_biomes);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "open_terrain_cave_biomes"), "set_open_terrain_cave_biomes", "get_open_terrain_cave_biomes");
	ClassDB::bind_method(D_METHOD("get_terrain_edits"), &TerrainSettings::get_terrain_edits);
	ClassDB::bind_method(D_METHOD("set_terrain_edits", "value"), &TerrainSettings::set_terrain_edits);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "terrain_edits"), "set_terrain_edits", "get_terrain_edits");
	ClassDB::bind_method(D_METHOD("get_cached_field"), &TerrainSettings::get_cached_field);
	ClassDB::bind_method(D_METHOD("set_cached_field", "value"), &TerrainSettings::set_cached_field);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "cached_field"), "set_cached_field", "get_cached_field");
	ClassDB::bind_method(D_METHOD("get_cached_blocks"), &TerrainSettings::get_cached_blocks);
	ClassDB::bind_method(D_METHOD("set_cached_blocks", "value"), &TerrainSettings::set_cached_blocks);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "cached_blocks"), "set_cached_blocks", "get_cached_blocks");
	ClassDB::bind_method(D_METHOD("get_solids"), &TerrainSettings::get_solids);
	ClassDB::bind_method(D_METHOD("set_solids", "value"), &TerrainSettings::set_solids);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "solids"), "set_solids", "get_solids");
	ClassDB::bind_method(D_METHOD("get_density_prototype"), &TerrainSettings::get_density_prototype);
	ClassDB::bind_method(D_METHOD("set_density_prototype", "value"), &TerrainSettings::set_density_prototype);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "density_prototype"), "set_density_prototype", "get_density_prototype");
	ClassDB::bind_method(D_METHOD("get_density_factory"), &TerrainSettings::get_density_factory);
	ClassDB::bind_method(D_METHOD("set_density_factory", "value"), &TerrainSettings::set_density_factory);
	ADD_PROPERTY(PropertyInfo(Variant::CALLABLE, "density_factory"), "set_density_factory", "get_density_factory");
}

} // namespace godot
