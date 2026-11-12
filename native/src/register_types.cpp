// The terrain extension: every class of the terrain's generation, meshing and orchestration.
#include <gdextension_interface.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "cave_carver.h"
#include "cave_systems.h"
#include "chunk_mesh_blocks.h"
#include "chunk_mesh_builder.h"
#include "chunked_terrain_world.h"
#include "density_sampler.h"
#include "flying_edges_mesher.h"
#include "loose_rock.h"
#include "open_terrain.h"
#include "signed_density_field.h"
#include "terrain_chunk.h"
#include "terrain_edits.h"
#include "terrain_settings.h"
#include "world_density.h"

using namespace godot;

static void initialize_terrain_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(SignedDensityField);
	GDREGISTER_CLASS(TerrainEdits);
	GDREGISTER_CLASS(CaveSystems);
	GDREGISTER_CLASS(CaveCarver);
	GDREGISTER_CLASS(WorldDensity);
	GDREGISTER_CLASS(DensitySampler);
	GDREGISTER_CLASS(LooseRock);
	GDREGISTER_CLASS(TerrainMeshResult);
	GDREGISTER_CLASS(FlyingEdgesMesher);
	GDREGISTER_CLASS(ChunkMeshBlocks);
	GDREGISTER_CLASS(CaveWaterMesher);
	GDREGISTER_CLASS(TerrainSettings);
	GDREGISTER_CLASS(ChunkBuildResult);
	GDREGISTER_CLASS(ChunkMeshBuilder);
	GDREGISTER_CLASS(TerrainChunk);
	GDREGISTER_CLASS(ChunkedTerrainWorld);
	GDREGISTER_CLASS(OpenTerrain);
	GDREGISTER_CLASS(TerrariumTerrain);
	GDREGISTER_CLASS(BoxedInTerrain);
}

static void uninitialize_terrain_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT bugroyale_terrain_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_terrain_module);
	init_obj.register_terminator(uninitialize_terrain_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
