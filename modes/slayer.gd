extends ColonyMatch
## Slayer: deathmatch. Solo, every bug for itself; in colonies, the Red soldier ants against the
## Black ants. First to the kill limit wins, or the most kills when time runs out.

## Tuned from the editor (modes/slayer.tscn): the kill limit of a solo match, and in
## colonies this many kills per member of a colony, held between the two limits.
@export var solo_kill_limit: int = 25
@export var kills_per_member: int = 5
@export var colony_kill_limit_min: int = 40
@export var colony_kill_limit_max: int = 100


func _score_limit() -> int:
	if is_solo():
		return solo_kill_limit
	return clampi(team_size * kills_per_member, colony_kill_limit_min, colony_kill_limit_max)


func _intro_text() -> String:
	if is_solo():
		return "Slayer\nEvery bug for itself. First to %d kills." % score_limit
	return "Slayer\nRed colony, first to %d kills!" % score_limit


func _on_kill(victim: Fighter, killer: int) -> void:
	score_kill(victim, killer)
