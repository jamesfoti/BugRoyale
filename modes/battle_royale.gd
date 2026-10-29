extends GameMode
## Battle Royale: 12 bugs of mixed classes (humans plus bots), every bug for itself, no respawns.
## The map's water rises in stages (like Fortnite's storm) and hurts anything under it,
## squeezing everyone onto the high ground. In the terrariums that is the pool; in the crawlspace
## a storm floods the foundation, and once the water is well up the drains back up with sewage.
## Last bug standing wins.

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
## Stage at which a crawlspace's drains start backing up sewage onto the flood.
const SEWAGE_STAGE: int = 2

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
	var taken: Array[Vector3] = []
	var team: int = 0
	for human: Fighter in humans():
		human.set_team(team)
		team += 1
		human.respawn_at(_spread_spawn_point(taken))
	var classes: Array = LoadingScreen.PlayerCharacter.values()
	for index: int in FIGHTERS - humans().size():
		var character: LoadingScreen.PlayerCharacter = classes[randi() % classes.size()]
		var bot: Fighter = spawn_bot(character, team, _spread_spawn_point(taken))
		team += 1
		if bot == null:
			continue
		bot.brain.target_group = &"fighter"
		bot.brain.avoid_water = true
		bot.brain.detection_range = 45.0
		bot.hold_fire(GRACE_SECONDS)
	hud.show_message("Battle Royale\nScatter! Weapons free in %d seconds." % GRACE_SECONDS, 4.0)


func _update_match(delta: float) -> void:
	if match_over:
		return
	_update_water(delta)
	_apply_water_damage(delta)


func _status_text() -> String:
	var alive: String = "Alive %d" % alive_count()
	if map.water == null:
		return alive
	if _stage >= WATER_STAGES.size():
		return alive + "  ·  Flooded!"
	var stage: Dictionary = WATER_STAGES[_stage]
	if _stage_time < stage["hold"]:
		return alive + "  ·  Water rises in %ds" % ceili(stage["hold"] - _stage_time)
	return alive + "  ·  The water is rising!"


func _on_fighter_died(fighter: Fighter) -> void:
	fighter.kill()
	if match_over:
		return
	if fighter.is_human and humans_alive() == 0:
		# Everyone still standing finished ahead of the last human.
		end_match("Eliminated", "You placed #%d of %d." % [alive_count() + 1, FIGHTERS])
		return
	if alive_count() == 1:
		var winner: Fighter = alive_fighters()[0]
		if winner.is_local:
			end_match("Victory Royale!", "Last bug standing out of %d." % FIGHTERS)
		else:
			end_match("%s wins" % winner.display_name(), "Last bug standing out of %d." % FIGHTERS)


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
		if _stage == SEWAGE_STAGE:
			for crawlspace: Node in get_tree().get_nodes_in_group("crawlspace"):
				crawlspace.start_sewage_backup()
				hud.show_message("The drains are backing up!", 3.0)


func _apply_water_damage(delta: float) -> void:
	if map.water == null:
		return
	for fighter: Fighter in alive_fighters():
		if map.is_underwater(fighter.get_position() + Vector3.UP * 0.6):
			fighter.health.apply_damage(WATER_DAMAGE_PER_SECOND * delta)


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
