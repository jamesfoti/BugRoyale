@tool
extends Node3D
## Dev scene: a small open terrain for seeing how procedural the ground and its caves are,
## from the editor. Open scenes/terrain_lab.tscn, select TerrainWorld and press Build Terrain
## (the Terrain Editor plugin puts Build and Destroy at the top of its inspector), or change
## any of its settings: with Auto Rebuild In Editor on, every toggle (caves, solid underside,
## noise, seed, grid size, terraces, character) rebuilds the chunks on the spot, and the
## rebuild line in the Output panel says what the seed rolled; New Seed beside Build rolls a
## new one, and Randomize draws the Noise sliders and the Cave Roll sliders too and writes
## them into the inspector.
## This root keeps a New Seed button of its own and keeps the built chunks out of
## the saved scene: they are destroyed before a save and rebuilt after it.
##
## The grid is the maps' own, 16 by 16 chunks of 32 m and three deep, at 4 m voxels so a
## seed builds in a few seconds, with the noise rolled from the seed (Noise Roll) so seeds
## differ in hill size and height as well as in their regions, curve, relief and caves.
## Drop the voxel size to 2 m to see the terraces and ravines, 1 m for play quality. For
## the underground in cross-section: Chunks 16, 16, 3, Surface Layer 2, Boxed Edges off,
## and the camera off to one side of the slab, at 2 m so the tunnels resolve (at 4 m only
## the caverns show); tools/cave_slice.gd paints the raw cave field of a seed in a second.
## Or fly below the surface: the terrain's faces
## only draw from the air side, so rock is see-through from inside. Run as a scene (F6) it
## builds on ready and the camera looks down on it.

@export_tool_button("New seed", "RandomNumberGenerator") var new_seed_action: Callable = new_seed

var _built_before_save: bool = false


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			var terrain: ChunkedTerrainWorld = _terrain()
			_built_before_save = terrain != null and terrain.get_chunk_count() > 0
			if _built_before_save:
				terrain.destroy_all()
		NOTIFICATION_EDITOR_POST_SAVE:
			if _built_before_save:
				_built_before_save = false
				var terrain: ChunkedTerrainWorld = _terrain()
				if terrain != null:
					terrain.rebuild_all_editor()


## Rerolls the terrain's seed. With auto rebuild on the terrain rebuilds itself; otherwise
## this builds it.
func new_seed() -> void:
	var terrain: ChunkedTerrainWorld = _terrain()
	if terrain == null:
		push_error("[TerrainLab] No TerrainWorld child.")
		return
	terrain.noise_seed = randi() % 1000000
	print("[TerrainLab] Seed %d." % terrain.noise_seed)
	if not terrain.auto_rebuild_in_editor:
		terrain.rebuild_all_editor()


func _terrain() -> ChunkedTerrainWorld:
	return get_node_or_null("TerrainWorld") as ChunkedTerrainWorld
