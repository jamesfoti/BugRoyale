extends GameMode
## Explore: any map with no enemies and no AI, for walking the levels and feeling out movement,
## climbing, flight, water and carving. Dying (drowning, falling off the map) just puts you back
## on the ground after a moment. The base mode already removes the battlefield's ambient hornet
## swarm, so nothing in the level hunts the player.

const RESPAWN_SECONDS: float = 2.0

var _map_name: String = ""
## Fighter -> seconds until it is back on its feet.
var _respawn_timers: Dictionary = {}


# --- Deciding ---------------------------------------------------------------------------------

func _start_match() -> void:
	_map_name = ModeCatalog.map_name(ModeCatalog.map_id_for_scene(LoadingScreen.current_scene_path))
	for human: Fighter in humans():
		human.respawn_at()
	announce("Explore: %s\nNo enemies. P pauses, Esc frees the mouse." % _map_name, 4.0)


func _update_match(delta: float) -> void:
	for fighter: Fighter in _respawn_timers.keys():
		var remaining: float = float(_respawn_timers[fighter]) - delta
		if remaining > 0.0:
			_respawn_timers[fighter] = remaining
			continue
		_respawn_timers.erase(fighter)
		fighter.respawn_at()


func _on_fighter_died(fighter: Fighter) -> void:
	fighter.kill()
	announce_to(fighter, "Back on your feet in a moment...", RESPAWN_SECONDS)
	_respawn_timers[fighter] = RESPAWN_SECONDS


# --- Showing ----------------------------------------------------------------------------------

func _status_text() -> String:
	return "Explore  ·  %s" % _map_name


func _snapshot_state() -> Dictionary:
	return {"map_name": _map_name}


func _apply_state(state: Dictionary) -> void:
	_map_name = str(state.get("map_name", _map_name))
