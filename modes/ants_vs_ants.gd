extends GameMode
## Ants vs Ants: 10 vs 10 team deathmatch. The player's Red colony (soldier ants) against the Black
## colony (glossy black ants), all AI except the player. Each colony starts and respawns on its own
## half of the map. First colony to KILL_LIMIT kills wins.

const RED_TEAM: int = 0
const BLACK_TEAM: int = 1
const TEAM_SIZE: int = 10
const KILL_LIMIT: int = 40
const RESPAWN_SECONDS: float = 5.0
const TEAM_NAMES: Array[String] = ["Red", "Black"]
## Which half of the map each colony holds.
const TEAM_SIDES: Array[float] = [-1.0, 1.0]

var scores: Array[int] = [0, 0]


func _start_match() -> void:
	player_health.team = RED_TEAM
	respawn_player(_team_spawn(RED_TEAM))
	for index: int in TEAM_SIZE - 1:
		_spawn_colony_bot(RED_TEAM)
	for index: int in TEAM_SIZE:
		_spawn_colony_bot(BLACK_TEAM)
	hud.show_message("Ants vs Ants\nRed colony, first to %d kills!" % KILL_LIMIT, 4.0)


func _status_text() -> String:
	return "Red %d  —  %d Black   ·   First to %d" % [scores[RED_TEAM], scores[BLACK_TEAM], KILL_LIMIT]


func _on_player_died() -> void:
	_score_kill(RED_TEAM, player_health)
	kill_player()
	if match_over:
		return
	hud.show_message("You were squished! Respawning...", RESPAWN_SECONDS - 0.5)
	get_tree().create_timer(RESPAWN_SECONDS).timeout.connect(func() -> void:
		if not match_over:
			respawn_player(_team_spawn(RED_TEAM))
	)


func _on_bot_died(bot: BotFighter) -> void:
	var team: int = bot.damageable.team
	_score_kill(team, bot.damageable)
	bot.deactivate()
	get_tree().create_timer(RESPAWN_SECONDS).timeout.connect(func() -> void:
		if not match_over and is_instance_valid(bot):
			bot.respawn_at(_team_spawn(team))
	)


func _spawn_colony_bot(team: int) -> void:
	var skin: String = CharacterSkin.BLACK_ANT_BOT_SCENE_PATH if team == BLACK_TEAM else ""
	var bot: BotFighter = spawn_bot(LoadingScreen.PlayerCharacter.ANT_WARRIOR, team, _team_spawn(team), skin)
	bot.target_group = &"fighter"


## A death on victim_team scores for the other colony (falls and other accidents count too).
func _score_kill(victim_team: int, _victim: Damageable) -> void:
	if match_over:
		return
	var scoring_team: int = BLACK_TEAM if victim_team == RED_TEAM else RED_TEAM
	scores[scoring_team] += 1
	if scores[scoring_team] >= KILL_LIMIT:
		var player_won: bool = scoring_team == RED_TEAM
		end_match(
			"%s colony wins!" % TEAM_NAMES[scoring_team],
			("Victory! " if player_won else "Defeat. ") + "Final score: Red %d — %d Black" % [scores[RED_TEAM], scores[BLACK_TEAM]]
		)


func _team_spawn(team: int) -> Vector3:
	return map.random_surface_point(1.2, TEAM_SIDES[team])
