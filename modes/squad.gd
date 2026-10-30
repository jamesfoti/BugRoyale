class_name Squad
extends RefCounted
## The co-op side of a match: the humans, plus AI squadmates filling the rest of its size, all on
## one team and in one group (the one the hornets hunt). The bots wear the classes the player
## did not pick and follow the local player. Modes keep deciding what the squad does; this only
## builds it and answers who is in it.

var team: int = 0
var group: StringName = &""
var members: Array[Fighter] = []


## Builds a squad of `size` on a mode: every human first, then bots placed where `place` says
## (called once per bot, returning a position).
static func fill(mode: GameMode, team: int, group: StringName, size: int, place: Callable) -> Squad:
	var squad := Squad.new()
	squad.team = team
	squad.group = group
	for human: Fighter in mode.humans():
		squad._add(human)
	var leader: Node3D = mode.local_fighter.body if mode.local_fighter != null else null
	var player_class: LoadingScreen.PlayerCharacter = LoadingScreen.selected_player_character
	var classes: Array = LoadingScreen.PlayerCharacter.values().filter(
		func(character: int) -> bool: return character != player_class
	)
	for index: int in size - squad.members.size():
		var character: LoadingScreen.PlayerCharacter = classes[index % classes.size()]
		var bot: Fighter = mode.spawn_bot(character, team, place.call())
		if bot == null:
			continue
		bot.brain.leader = leader
		squad._add(bot)
	return squad


func has(fighter: Fighter) -> bool:
	return members.has(fighter)


func humans() -> Array[Fighter]:
	var result: Array[Fighter] = []
	for fighter: Fighter in members:
		if fighter.is_human:
			result.append(fighter)
	return result


func bots() -> Array[Fighter]:
	var result: Array[Fighter] = []
	for fighter: Fighter in members:
		if fighter.is_bot():
			result.append(fighter)
	return result


func alive() -> Array[Fighter]:
	var result: Array[Fighter] = []
	for fighter: Fighter in members:
		if fighter.is_alive():
			result.append(fighter)
	return result


func alive_count() -> int:
	return alive().size()


## Back in the group after time away from it (out of play aboard a transport).
func rejoin(fighter: Fighter) -> void:
	if has(fighter):
		fighter.body.add_to_group(group)


## Out of the group for a while: not hunted, not counted by the flocks.
func leave(fighter: Fighter) -> void:
	if has(fighter):
		fighter.body.remove_from_group(group)


func _add(fighter: Fighter) -> void:
	fighter.set_team(team)
	fighter.body.add_to_group(group)
	members.append(fighter)
