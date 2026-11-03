extends ColonyMatch
## Slayer: deathmatch. Solo, every bug for itself; in colonies, the Red soldier ants against the
## Black ants. First to the kill limit wins, or the most kills when time runs out.


func _score_limit() -> int:
	if is_solo():
		return 25
	return clampi(team_size * 5, 40, 100)


func _intro_text() -> String:
	if is_solo():
		return "Slayer\nEvery bug for itself. First to %d kills." % score_limit
	return "Slayer\nRed colony, first to %d kills!" % score_limit


func _on_kill(victim: Fighter, killer: int) -> void:
	score_kill(victim, killer)
