extends Node
class_name GameMode
## Base for game modes. Added to a loaded map by the loading screen; waits for the local player
## to spawn, then sets up the match (_start_match) and keeps the HUD status current
## (_status_text). The match is a list of fighters: humans and bots alike, with the local human
## singled out only for what this screen shows. Provides bot spawning, deaths and respawns,
## out-of-bounds kills and the end-of-match screen.

const MAIN_MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"

var map: MapInfo
var hud: ModeHud
## Everyone in the match, humans first.
var fighters: Array[Fighter] = []
## The human at this keyboard.
var local_fighter: Fighter
var match_over: bool = false
var _started: bool = false


func _ready() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var player_body: FighterBody
	while true:
		player_body = get_tree().get_first_node_in_group("player") as FighterBody
		if player_body != null and player_body.is_spawned():
			break
		await get_tree().process_frame
	map = MapInfo.from_scene(get_parent())
	# The map's ambient swarm (open battlefield) is replaced by whatever the mode spawns.
	for flock: Node in get_tree().get_nodes_in_group("bird_flock"):
		flock.queue_free()

	local_fighter = _register(player_body)

	hud = ModeHud.new()
	hud.name = "ModeHud"
	add_child(hud)
	hud.play_again_pressed.connect(func() -> void: LoadingScreen.restart_current(get_tree()))
	hud.main_menu_pressed.connect(func() -> void: get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH))
	_start_match()
	_started = true


func _process(delta: float) -> void:
	if not _started:
		return
	if not match_over:
		for fighter: Fighter in fighters:
			if fighter.is_alive() and map.is_out_of_bounds(fighter.get_position()):
				fighter.health.apply_damage(fighter.health.max_health * 10.0)
	_update_match(delta)
	hud.set_status(_status_text())


# --- Overridables ---------------------------------------------------------------------------

func _start_match() -> void:
	pass


func _update_match(_delta: float) -> void:
	pass


func _status_text() -> String:
	return ""


## A fighter's health hit zero. Default: out of play for good.
func _on_fighter_died(fighter: Fighter) -> void:
	fighter.kill()


# --- Helpers ----------------------------------------------------------------------------------

## Adds a bot of a class to a team at a position. skin_path overrides the class's bot skin.
func spawn_bot(
	character: LoadingScreen.PlayerCharacter, team: int, position: Vector3, skin_path: String = ""
) -> Fighter:
	var spawner: PlayerSpawner = _find_spawner()
	if spawner == null:
		push_error("[GameMode] No PlayerSpawner in the map; cannot spawn a bot.")
		return null
	var brain := BotBrain.new()
	brain.name = "BotBrain"
	brain.map = map
	brain.weapon = CharacterSkin.bot_weapon_for(character)
	var body: FighterBody = spawner.create_fighter_body(character, brain, skin_path)
	body.name = "Bot"
	get_parent().add_child(body)
	var fighter: Fighter = _register(body)
	fighter.set_team(team)
	fighter.respawn_at(position)
	body.apply_hand_item(CharacterSkin.weapon_for(character))
	return fighter


## Puts a body on the fighter list: collision layers, the fighter group, death handling, and the
## class's gun in hand.
func _register(body: FighterBody) -> Fighter:
	body.collision_layer = MapInfo.FIGHTER_LAYER
	body.collision_mask = MapInfo.TERRAIN_LAYER | MapInfo.FIGHTER_LAYER | MapInfo.STRUCTURE_LAYER
	body.add_to_group("fighter")
	var fighter: Fighter = Fighter.for_body(body)
	fighter.health.died.connect(_on_fighter_died.bind(fighter))
	fighters.append(fighter)
	if fighter.is_human:
		body.apply_hand_item(CharacterSkin.weapon_for(fighter.character))
	return fighter


func _find_spawner() -> PlayerSpawner:
	var found: Array[Node] = get_parent().find_children("*", "PlayerSpawner", true, false)
	return found.front() as PlayerSpawner if not found.is_empty() else null


func humans() -> Array[Fighter]:
	var result: Array[Fighter] = []
	for fighter: Fighter in fighters:
		if fighter.is_human:
			result.append(fighter)
	return result


func bots() -> Array[Fighter]:
	var result: Array[Fighter] = []
	for fighter: Fighter in fighters:
		if fighter.is_bot():
			result.append(fighter)
	return result


func alive_fighters() -> Array[Fighter]:
	var result: Array[Fighter] = []
	for fighter: Fighter in fighters:
		if fighter.is_alive():
			result.append(fighter)
	return result


func alive_count() -> int:
	return alive_fighters().size()


func humans_alive() -> int:
	var count: int = 0
	for fighter: Fighter in fighters:
		if fighter.is_human and fighter.is_alive():
			count += 1
	return count


func is_local_alive() -> bool:
	return local_fighter != null and local_fighter.is_alive()


## Ends the match: shows the result panel and stops the bots thinking.
func end_match(title: String, subtitle: String) -> void:
	if match_over:
		return
	match_over = true
	for fighter: Fighter in fighters:
		if fighter.brain != null and is_instance_valid(fighter.brain):
			fighter.brain.enabled = false
	hud.show_end(title, subtitle)


## Team that dealt the killing blow to a Damageable (NO_TEAM if it fell or drowned).
static func killer_team(victim: Damageable) -> int:
	return Damageable.team_of(victim.last_damage_source)
