extends GameMode
## Explore: any map with no enemies and no AI, for walking the levels and feeling out movement,
## climbing, flight, water and carving. Dying (drowning, falling off the map) just puts you back
## on the ground after a moment. The base mode already removes the battlefield's ambient hornet
## swarm, so nothing in the level hunts the player.

const RESPAWN_SECONDS: float = 2.0

var _respawn_timer: float = -1.0
var _map_name: String = ""


func _start_match() -> void:
	_map_name = ModeCatalog.map_name(ModeCatalog.map_id_for_scene(LoadingScreen.current_scene_path))
	hud.show_message("Explore: %s\nNo enemies. P pauses, Esc frees the mouse." % _map_name, 4.0)


func _update_match(delta: float) -> void:
	if _respawn_timer < 0.0:
		return
	_respawn_timer -= delta
	if _respawn_timer < 0.0:
		respawn_player()


func _status_text() -> String:
	return "Explore  ·  %s" % _map_name


func _on_player_died() -> void:
	kill_player()
	hud.show_message("Back on your feet in a moment...", RESPAWN_SECONDS)
	_respawn_timer = RESPAWN_SECONDS
