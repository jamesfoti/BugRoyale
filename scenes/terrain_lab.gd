@tool
extends Node3D
## Dev scene: a small open terrain for seeing how procedural the ground and its caves are,
## from the editor. Open scenes/terrain_lab.tscn, select TerrainWorld and press Build Terrain
## (the Terrain Editor plugin puts Build and Destroy at the top of its inspector), or change
## any of its settings: with Auto Rebuild In Editor on, every toggle (caves, solid underside,
## noise, seed, grid size, terraces) rebuilds the chunks on the spot, and the rebuild line in
## the Output panel says what the seed rolled. This root adds a New Seed button
## that rerolls the seed, and keeps the built chunks out of the saved scene: they are
## destroyed before a save and rebuilt after it.
##
## The grid is 4 by 4 chunks of 32 m (128 m a side, a quarter of the garden's width) and three
## chunks deep, the garden's own noise and voxel size, so a build takes about a second. Fly
## the editor camera below the surface to see the tunnels and caverns: the terrain's faces
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
