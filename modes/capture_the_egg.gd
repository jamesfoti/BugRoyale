extends ColonyMatch
## Capture the Egg: each colony's egg sits on its nest. Carry the enemy egg home while your own
## is on its nest to score. A carrier who falls drops the egg where it lies; its colony can touch
## it to send it home, and it goes home on its own after a while. First to three.

const RETURN_SECONDS: float = 20.0
const SCORE_RADIUS: float = 4.0

var eggs: Array[CarryItem] = []
## Per team, whether its egg is off the nest (for the status line and a client).
var eggs_taken: Array[bool] = [false, false]


func _score_limit() -> int:
	return 3


func _intro_text() -> String:
	return "Capture the Egg\nBring the enemy egg home while yours is on the nest. First to 3."


func _place_objectives() -> void:
	for team: int in teams:
		var egg: CarryItem = CarryItem.spawn(
			get_parent(),
			nests[team],
			CarryItem.Kind.EGG,
			team,
			color_of_team(team),
			map.up_at(nests[team])
		)
		egg.touched.connect(_on_egg_touched)
		eggs.append(egg)


func _on_egg_touched(egg: CarryItem, body: FighterBody) -> void:
	var fighter: Fighter = fighter_for_body(body)
	if fighter == null or match_over:
		return
	if fighter.get_team() == egg.team:
		if not egg.is_at_home():
			egg.return_home()
			announce("%s egg returned." % name_of_team(egg.team), 2.0)
		return
	egg.pick_up(fighter)
	announce("%s has the %s egg!" % [fighter.display_name(), name_of_team(egg.team)], 2.0)
	announce_to(fighter, "Take it home!", 2.0)


func _objective_tick(_delta: float) -> void:
	for egg: CarryItem in eggs:
		eggs_taken[egg.team] = not egg.is_at_home()
		if egg.is_carried():
			var carrier: Fighter = egg.carrier
			if not carrier.is_alive():
				egg.drop(carrier.get_position())
			elif _at_nest(carrier) and eggs[carrier.get_team()].is_at_home():
				add_score(carrier.get_team(), 1)
				announce("%s colony scores!" % name_of_team(carrier.get_team()), 2.5)
				egg.return_home()
		elif not egg.is_at_home() and egg.on_ground_seconds > RETURN_SECONDS:
			egg.return_home()
			announce("%s egg returned." % name_of_team(egg.team), 2.0)


func _at_nest(fighter: Fighter) -> bool:
	return fighter.get_position().distance_to(nests[fighter.get_team()]) <= SCORE_RADIUS


## Carriers run home; if our egg is out, hunt its carrier; otherwise half attack, half defend.
func _bot_objective(bot: Fighter) -> Vector3:
	var team: int = bot.get_team()
	var enemy: int = 1 - team
	if eggs[enemy].carrier == bot:
		return nests[team]
	if eggs[team].is_carried():
		return eggs[team].global_position
	if not eggs[team].is_at_home():
		return eggs[team].global_position
	if bot.id % 2 == 0:
		return eggs[enemy].global_position
	return nests[team]


func _objective_status() -> String:
	var notes: Array[String] = []
	for team: int in eggs_taken.size():
		if eggs_taken[team]:
			notes.append("%s egg taken" % name_of_team(team))
	return ", ".join(notes)


func _objective_snapshot() -> Dictionary:
	return {"eggs_taken": eggs_taken.duplicate()}


func _objective_apply(state: Dictionary) -> void:
	if state.has("eggs_taken"):
		eggs_taken.assign(state["eggs_taken"])
