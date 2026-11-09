class_name ColonyMatch
extends GameMode
## Base for the competitive modes (Slayer today): two colonies (the Red soldier ants against the
## Black ants), or every bug for itself, by the match format (ModeCatalog.FORMATS: how many teams
## and how big). Keeps the scores, the clock, respawns, team spawns and nests, and ends the match
## at the score limit or when time runs out. A mode on top scores through the hooks under
## "Scoring".

## Which half of the map each colony holds.
const TEAM_SIDES: Array[float] = [-1.0, 1.0]

## Tuned from the editor on each competitive mode's scene (modes/slayer.tscn): the colonies'
## names and colours, the colours of a solo match's bugs (by fighter), the colour of nobody's
## side, the clock, and how long a squished bug waits to respawn. These are the defaults; a
## scene saves only what differs.
@export var team_names: Array[String] = ["Red", "Black"]
@export var team_colors: Array[Color] = [Color(0.9, 0.25, 0.2), Color(0.3, 0.35, 0.8)]
@export var solo_colors: Array[Color] = [
	Color(0.9, 0.3, 0.2),
	Color(0.3, 0.5, 0.95),
	Color(0.95, 0.8, 0.2),
	Color(0.3, 0.85, 0.4),
	Color(0.8, 0.4, 0.9),
	Color(0.2, 0.85, 0.85),
]
@export var neutral_color: Color = Color(0.75, 0.75, 0.7)
@export var time_limit: float = 600.0
@export var respawn_seconds: float = 5.0

## 0 teams means solo: every fighter is its own team, numbered by spawn order.
var teams: int = 2
var team_size: int = 4
var fighter_total: int = 10
## Team -> points.
var scores: Dictionary = {}
var score_limit: int = 40
var time_left: float = 0.0
## Each colony's home on its side of the map (none in a solo match).
var nests: Array[Vector3] = []

var _nest_beacons: Array[Beacon] = []

# --- Deciding ---------------------------------------------------------------------------------


func _start_match() -> void:
	_read_format()
	score_limit = _score_limit()
	time_left = _time_limit()
	if not is_solo():
		_place_nests()
	_spawn_everyone()
	for team: int in team_ids():
		scores[team] = 0
	announce(_intro_text(), 4.0)


func _update_match(delta: float) -> void:
	if match_over:
		return
	time_left = maxf(time_left - delta, 0.0)
	if time_left <= 0.0:
		_time_up()


func _on_fighter_died(fighter: Fighter) -> void:
	var killer: int = killer_team(fighter.health)
	_on_kill(fighter, killer)
	fighter.kill()
	if match_over:
		return
	announce_to(fighter, "You were squished! Respawning...", respawn_seconds - 0.5)
	get_tree().create_timer(respawn_seconds).timeout.connect(
		func() -> void:
			if not match_over and fighter.is_valid() and not fighter.is_alive():
				fighter.respawn_at(_spawn_point(fighter))
	)


# --- Scoring: what a mode on top fills in ---------------------------------------------------


## A kill (or an accident: killer is NO_TEAM). Nothing by default: a deathmatch scores kills
## (see score_kill).
func _on_kill(_victim: Fighter, _killer: int) -> void:
	pass


## A point to the killing team, unless the victim fell or was killed by its own side.
func score_kill(victim: Fighter, killer: int) -> void:
	if killer != Damageable.NO_TEAM and killer != victim.get_team():
		add_score(killer, 1)


func _intro_text() -> String:
	return "First to %d." % score_limit


func _score_limit() -> int:
	return 40


func _time_limit() -> float:
	return time_limit


# --- Teams and scores ------------------------------------------------------------------------


func is_solo() -> bool:
	return teams == 0


## The teams in the match: the colonies, or every fighter's own number in a solo match.
func team_ids() -> Array[int]:
	var ids: Array[int] = []
	if is_solo():
		for fighter: Fighter in fighters:
			ids.append(fighter.get_team())
	else:
		for team: int in teams:
			ids.append(team)
	return ids


func fighters_of(team: int) -> Array[Fighter]:
	var result: Array[Fighter] = []
	for fighter: Fighter in fighters:
		if fighter.get_team() == team:
			result.append(fighter)
	return result


func local_team() -> int:
	return local_fighter.get_team() if local_fighter != null else Damageable.NO_TEAM


func name_of_team(team: int) -> String:
	if is_solo():
		for fighter: Fighter in fighters:
			if fighter.get_team() == team:
				return fighter.display_name()
		return "Bug %d" % team
	return team_names[team] if team >= 0 and team < team_names.size() else "Team %d" % team


func color_of_team(team: int) -> Color:
	if team < 0:
		return neutral_color
	if is_solo():
		return solo_colors[team % solo_colors.size()]
	return team_colors[team % team_colors.size()]


func score_of(team: int) -> int:
	return int(scores.get(team, 0))


## The team with the most points (ties go to the lower number), or NO_TEAM with no scores.
func leading_team() -> int:
	var best: int = Damageable.NO_TEAM
	var best_score: int = -1
	for team: int in scores:
		if int(scores[team]) > best_score:
			best_score = int(scores[team])
			best = team
	return best


func add_score(team: int, points: int) -> void:
	if match_over or team == Damageable.NO_TEAM:
		return
	scores[team] = score_of(team) + points
	if score_of(team) >= score_limit:
		_finish(team)


## The match is decided for a team (NO_TEAM: a draw).
func _finish(team: int) -> void:
	if team == Damageable.NO_TEAM:
		end_match("Time's up", "A draw. " + _final_scores())
		return
	var local_won: bool = team == local_team()
	var title: String
	if is_solo():
		title = "You win!" if local_won else "%s wins!" % name_of_team(team)
	else:
		title = "%s colony wins!" % name_of_team(team)
	end_match(title, ("Victory! " if local_won else "Defeat. ") + _final_scores())


func _time_up() -> void:
	var leader: int = leading_team()
	if leader == Damageable.NO_TEAM:
		_finish(Damageable.NO_TEAM)
		return
	var tied: bool = false
	for team: int in scores:
		if team != leader and int(scores[team]) == score_of(leader):
			tied = true
	_finish(Damageable.NO_TEAM if tied else leader)


func _final_scores() -> String:
	if is_solo():
		return "You scored %d; the winner %d." % [score_of(local_team()), score_of(leading_team())]
	return "Final score: Red %d — %d Black" % [score_of(0), score_of(1)]


# --- Spawning ---------------------------------------------------------------------------------


func _read_format() -> void:
	teams = int(format.get("teams", 2))
	if is_solo():
		fighter_total = fighter_count(int(format.get("fighters", 10)))
	else:
		team_size = floori(fighter_count(int(format.get("team_size", 4)) * teams) / float(teams))
		fighter_total = team_size * teams


func _spawn_everyone() -> void:
	if is_solo():
		var taken: Array[Vector3] = []
		var team: int = 0
		for human: Fighter in humans():
			human.set_team(team)
			team += 1
			human.respawn_at(_solo_spawn(taken))
		var classes: Array = LoadingScreen.PlayerCharacter.values()
		for _index: int in fighter_total - humans().size():
			var character: LoadingScreen.PlayerCharacter = classes[randi() % classes.size()]
			var bot: Fighter = spawn_bot(character, team, _solo_spawn(taken))
			team += 1
			if bot != null:
				bot.brain.target_group = &"fighter"
				bot.brain.detection_range = 45.0
		return
	for human: Fighter in humans():
		human.set_team(0)
		human.respawn_at(_team_spawn(0))
	for _index: int in team_size - humans().size():
		_spawn_colony_bot(0)
	for team: int in range(1, teams):
		for _index: int in team_size:
			_spawn_colony_bot(team)


func _spawn_colony_bot(team: int) -> void:
	var skin: String = CharacterSkin.BLACK_ANT_BOT_SCENE_PATH if team == 1 else ""
	var bot: Fighter = spawn_bot(
		LoadingScreen.PlayerCharacter.ANT_WARRIOR, team, _team_spawn(team), skin
	)
	if bot != null:
		bot.brain.target_group = &"fighter"


func _place_nests() -> void:
	for team: int in teams:
		var nest: Vector3 = map.random_surface_point(0.0, TEAM_SIDES[team % TEAM_SIDES.size()])
		nests.append(nest)
		_nest_beacons.append(Beacon.build(get_parent(), map, nest, color_of_team(team), 1.5, 30.0))


func _spawn_point(fighter: Fighter) -> Vector3:
	if is_solo():
		return _solo_spawn([])
	return _team_spawn(fighter.get_team())


## On the colony's half of the map, near its nest when it has one.
func _team_spawn(team: int) -> Vector3:
	if team < nests.size():
		return map.ground_point_near(nests[team], 3.0, 9.0, 1.2)
	return map.random_surface_point(1.2, TEAM_SIDES[team % TEAM_SIDES.size()])


## A spot far from everyone placed so far (the best of several).
func _solo_spawn(taken: Array[Vector3]) -> Vector3:
	var best: Vector3 = map.random_surface_point(1.2)
	var best_gap: float = -1.0
	for _attempt: int in 8:
		var candidate: Vector3 = map.random_surface_point(1.2)
		var gap: float = INF
		for other: Vector3 in taken:
			gap = minf(gap, candidate.distance_to(other))
		for fighter: Fighter in alive_fighters():
			gap = minf(gap, candidate.distance_to(fighter.get_position()))
		if gap > best_gap:
			best_gap = gap
			best = candidate
	taken.append(best)
	return best


# --- Showing ----------------------------------------------------------------------------------


func _status_text() -> String:
	var parts: Array[String] = []
	if is_solo():
		parts.append("You %d" % score_of(local_team()))
		var leader: int = leading_team()
		if leader != Damageable.NO_TEAM and leader != local_team():
			parts.append("Lead: %s %d" % [name_of_team(leader), score_of(leader)])
	else:
		parts.append("Red %d  —  %d Black" % [score_of(0), score_of(1)])
	parts.append("First to %d" % score_limit)
	parts.append("%d:%02d" % [floori(time_left / 60.0), int(time_left) % 60])
	return "  ·  ".join(parts)


func _snapshot_state() -> Dictionary:
	var state: Dictionary = {}
	state["scores"] = scores.duplicate()
	state["time_left"] = time_left
	state["teams"] = teams
	state["score_limit"] = score_limit
	return state


func _apply_state(state: Dictionary) -> void:
	if state.has("scores"):
		scores = (state["scores"] as Dictionary).duplicate()
	time_left = float(state.get("time_left", time_left))
	teams = int(state.get("teams", teams))
	score_limit = int(state.get("score_limit", score_limit))
