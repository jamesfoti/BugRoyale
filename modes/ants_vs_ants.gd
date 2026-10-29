extends GameMode
## Ants vs Ants: 10 vs 10 team deathmatch. The Red colony (soldier ants) against the Black colony
## (glossy black ants). Humans join the Red colony and bots fill the rest. Each colony starts and
## respawns on its own half of the map. First colony to KILL_LIMIT kills wins.

const RED_TEAM: int = 0
const BLACK_TEAM: int = 1
const TEAM_SIZE: int = 10
const KILL_LIMIT: int = 40
const RESPAWN_SECONDS: float = 5.0
const TEAM_NAMES: Array[String] = ["Red", "Black"]
## Which half of the map each colony holds.
const TEAM_SIDES: Array[float] = [-1.0, 1.0]

var scores: Array[int] = [0, 0]


# --- Deciding ---------------------------------------------------------------------------------

func _start_match() -> void:
	for human: Fighter in humans():
		human.set_team(RED_TEAM)
		human.respawn_at(_team_spawn(RED_TEAM))
	for index: int in TEAM_SIZE - humans().size():
		_spawn_colony_bot(RED_TEAM)
	for index: int in TEAM_SIZE:
		_spawn_colony_bot(BLACK_TEAM)
	announce("Ants vs Ants\nRed colony, first to %d kills!" % KILL_LIMIT, 4.0)


func _on_fighter_died(fighter: Fighter) -> void:
	var team: int = fighter.get_team()
	_score_kill(team)
	fighter.kill()
	if match_over:
		return
	announce_to(fighter, "You were squished! Respawning...", RESPAWN_SECONDS - 0.5)
	get_tree().create_timer(RESPAWN_SECONDS).timeout.connect(func() -> void:
		if not match_over and fighter.is_valid():
			fighter.respawn_at(_team_spawn(team))
	)


func _spawn_colony_bot(team: int) -> void:
	var skin: String = CharacterSkin.BLACK_ANT_BOT_SCENE_PATH if team == BLACK_TEAM else ""
	var bot: Fighter = spawn_bot(LoadingScreen.PlayerCharacter.ANT_WARRIOR, team, _team_spawn(team), skin)
	if bot != null:
		bot.brain.target_group = &"fighter"


## A death on victim_team scores for the other colony (falls and other accidents count too).
func _score_kill(victim_team: int) -> void:
	if match_over:
		return
	var scoring_team: int = BLACK_TEAM if victim_team == RED_TEAM else RED_TEAM
	scores[scoring_team] += 1
	if scores[scoring_team] >= KILL_LIMIT:
		var local_won: bool = local_fighter != null and scoring_team == local_fighter.get_team()
		end_match(
			"%s colony wins!" % TEAM_NAMES[scoring_team],
			("Victory! " if local_won else "Defeat. ") + "Final score: Red %d — %d Black" % [scores[RED_TEAM], scores[BLACK_TEAM]]
		)


func _team_spawn(team: int) -> Vector3:
	return map.random_surface_point(1.2, TEAM_SIDES[team])


# --- Showing ----------------------------------------------------------------------------------

func _status_text() -> String:
	return "Red %d  —  %d Black   ·   First to %d" % [scores[RED_TEAM], scores[BLACK_TEAM], KILL_LIMIT]


func _snapshot_state() -> Dictionary:
	return {"scores": scores.duplicate()}


func _apply_state(state: Dictionary) -> void:
	if state.has("scores"):
		scores.assign(state["scores"])
