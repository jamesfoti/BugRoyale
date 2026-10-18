extends GameMode
## Battle Royale (terrarium): the player and 11 bots of mixed classes, every bug for itself, no
## respawns. The terrarium water rises in stages (like Fortnite's storm) and hurts anything under
## it, squeezing everyone onto the high ground. Last bug standing wins.

const FIGHTERS: int = 12
const WATER_DAMAGE_PER_SECOND: float = 12.0
## Nobody (bots) fires for this long after the drop, so everyone can scatter.
const GRACE_SECONDS: float = 10.0
## Stages: hold the water still, then raise it to `level` (fraction of the terrarium's height
## from its floor) over `rise` seconds. The last stage floods even the highest ground.
const WATER_STAGES: Array[Dictionary] = [
	{"hold": 30.0, "level": 0.3, "rise": 25.0},
	{"hold": 20.0, "level": 0.42, "rise": 25.0},
	{"hold": 20.0, "level": 0.52, "rise": 25.0},
	{"hold": 15.0, "level": 0.6, "rise": 20.0},
	{"hold": 15.0, "level": 0.7, "rise": 25.0},
]

var _stage: int = 0
var _stage_time: float = 0.0
var _rise_from_y: float = 0.0
var _water_floor_y: float = 0.0
var _water_height: float = 48.0


func _start_match() -> void:
	if map.water == null:
		push_warning("[BattleRoyale] This map has no terrarium water; playing without the flood.")
	else:
		_water_floor_y = map.water.global_position.y
		_water_height = map.water._world_size.y
		_rise_from_y = map.water_surface_y()
	player_health.team = 0
	var taken: Array[Vector3] = []
	respawn_player(_spread_spawn_point(taken))
	var classes: Array = LoadingScreen.PlayerCharacter.values()
	for index: int in FIGHTERS - 1:
		var character: LoadingScreen.PlayerCharacter = classes[randi() % classes.size()]
		var bot: BotFighter = spawn_bot(
			character, index + 1, _spread_spawn_point(taken)
		)
		bot.target_group = &"fighter"
		bot.avoid_water = true
		bot.detection_range = 45.0
		bot.hold_fire(GRACE_SECONDS)
	hud.show_message("Battle Royale\nScatter! Weapons free in %d seconds." % GRACE_SECONDS, 4.0)


func _update_match(delta: float) -> void:
	if match_over:
		return
	_update_water(delta)
	_apply_water_damage(delta)


func _status_text() -> String:
	var alive: String = "Alive %d" % _alive_count()
	if map.water == null:
		return alive
	if _stage >= WATER_STAGES.size():
		return alive + "  ·  The terrarium is flooded!"
	var stage: Dictionary = WATER_STAGES[_stage]
	if _stage_time < stage["hold"]:
		return alive + "  ·  Water rises in %ds" % ceili(stage["hold"] - _stage_time)
	return alive + "  ·  The water is rising!"


func _on_player_died() -> void:
	kill_player()
	# Everyone still standing finished ahead of the player.
	end_match("Eliminated", "You placed #%d of %d." % [_alive_count() + 1, FIGHTERS])


func _on_bot_died(bot: BotFighter) -> void:
	bot.deactivate()
	if is_player_alive() and _alive_count() == 1:
		end_match("Victory Royale!", "Last bug standing out of %d." % FIGHTERS)


func _update_water(delta: float) -> void:
	if map.water == null or _stage >= WATER_STAGES.size():
		return
	var stage: Dictionary = WATER_STAGES[_stage]
	var hold: float = stage["hold"]
	var rise: float = stage["rise"]
	_stage_time += delta
	if _stage_time < hold:
		return
	if _stage_time - delta < hold:
		hud.show_message("The water is rising!", 2.5)
	var target_y: float = _water_floor_y + _water_height * float(stage["level"])
	var progress: float = clampf((_stage_time - hold) / rise, 0.0, 1.0)
	map.water.set_water_surface_y(lerpf(_rise_from_y, target_y, progress))
	if progress >= 1.0:
		_stage += 1
		_stage_time = 0.0
		_rise_from_y = target_y


func _apply_water_damage(delta: float) -> void:
	if map.water == null:
		return
	if is_player_alive() and map.is_underwater(player.global_position + Vector3.UP * 0.6):
		player_health.apply_damage(WATER_DAMAGE_PER_SECOND * delta)
	for bot: BotFighter in bots:
		if bot.is_active() and map.is_underwater(bot.global_position + Vector3.UP * 0.6):
			bot.damageable.apply_damage(WATER_DAMAGE_PER_SECOND * delta)


func _alive_count() -> int:
	var alive: int = 1 if is_player_alive() else 0
	for bot: BotFighter in bots:
		if bot.is_active():
			alive += 1
	return alive


## Drop point far from everyone already placed: the best of several random high-ground spots.
func _spread_spawn_point(taken: Array[Vector3]) -> Vector3:
	var best: Vector3 = Vector3.ZERO
	var best_gap: float = -1.0
	for attempt: int in 10:
		var candidate: Vector3 = map.random_surface_point(1.2, 0.0, map.water_surface_y() + 2.0)
		var gap: float = INF
		for other: Vector3 in taken:
			gap = minf(gap, candidate.distance_to(other))
		if gap > best_gap:
			best_gap = gap
			best = candidate
	taken.append(best)
	return best
