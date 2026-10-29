extends RefCounted
class_name Fighter
## One combatant in a match as the modes see it: a body, its health, and (for a bot) its brain.
## A human at this keyboard, a bot, and later a remote player all look the same here, so a mode
## never has to ask which one it is dealing with except to decide what to show on this screen.

var body: FighterBody
var health: Damageable
## The AI piloting a bot; null for a human.
var brain: BotBrain
var is_human: bool = false
## The human playing at this machine (there is at most one).
var is_local: bool = false
var character: LoadingScreen.PlayerCharacter = LoadingScreen.PlayerCharacter.ANT_WARRIOR


static func for_body(fighter_body: FighterBody) -> Fighter:
	var fighter := Fighter.new()
	fighter.body = fighter_body
	fighter.health = fighter_body.get_node_or_null("Damageable") as Damageable
	fighter.character = fighter_body.character
	for child: Node in fighter_body.get_children():
		if child is BotBrain:
			fighter.brain = child as BotBrain
			break
	fighter.is_human = fighter.brain == null
	fighter.is_local = fighter_body.is_local
	return fighter


func is_valid() -> bool:
	return body != null and is_instance_valid(body) and health != null and is_instance_valid(health)


## Standing on the map with health left.
func is_alive() -> bool:
	return is_valid() and body.is_in_play() and health.is_alive()


## In the match (not dead): a fighter whose health is being drained is still in play.
func is_in_play() -> bool:
	return is_valid() and body.is_in_play()


func is_bot() -> bool:
	return brain != null


## A fungus husk (Cordyceps Royale).
func is_husk() -> bool:
	return brain != null and brain.husk


func get_team() -> int:
	return health.team if health != null else Damageable.NO_TEAM


func set_team(team: int) -> void:
	if health != null:
		health.team = team


func get_position() -> Vector3:
	return body.global_position if is_valid() else Vector3.ZERO


## Takes the fighter out of play (dead): frozen, hidden, not targetable.
func kill() -> void:
	if is_valid():
		body.set_in_play(false)


## Back into play with full health, at a position or (INF) a random spot on the ground.
func respawn_at(position_on_map: Vector3 = Vector3.INF) -> void:
	if not is_valid():
		return
	body.respawn_at(position_on_map)
	health.revive()
	if brain != null:
		brain.on_respawn()


## Bots stop firing for a while (a royale's drop-in grace).
func hold_fire(seconds: float) -> void:
	if brain != null:
		brain.hold_fire(seconds)


func display_name() -> String:
	if is_local:
		return "You"
	return CharacterSkin.display_name_for(character)
