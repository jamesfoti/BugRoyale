extends Node
class_name GameMode
## Base for game modes. Added to a loaded map by the loading screen; waits for the player to spawn,
## then sets up the match (_start_match) and keeps the HUD status current (_status_text).
## Provides bot spawning, player death/respawn, out-of-bounds kills and the end-of-match screen.

const MAIN_MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"

var map: MapInfo
var player: CharacterBody3D
var player_health: Damageable
var hud: ModeHud
var bots: Array[BotFighter] = []
var match_over: bool = false
var _started: bool = false


func _ready() -> void:
	call_deferred("_begin")


func _begin() -> void:
	while true:
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		if player != null and player.get("_spawned") == true:
			break
		await get_tree().process_frame
	map = MapInfo.from_scene(get_parent())
	# The map's ambient swarm (open battlefield) is replaced by whatever the mode spawns.
	for flock: Node in get_tree().get_nodes_in_group("bird_flock"):
		flock.queue_free()

	player.collision_layer = MapInfo.FIGHTER_LAYER
	player.collision_mask = MapInfo.TERRAIN_LAYER | MapInfo.FIGHTER_LAYER
	player.add_to_group("fighter")
	player_health = player.get_node_or_null("Damageable") as Damageable
	player_health.died.connect(_on_player_died)
	_equip_class_weapon()

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
	if not match_over and player_health.is_alive() and map.is_out_of_bounds(player.global_position):
		player_health.apply_damage(player_health.max_health * 10.0)
	_update_match(delta)
	hud.set_status(_status_text())


# --- Overridables ---------------------------------------------------------------------------

func _start_match() -> void:
	pass


func _update_match(_delta: float) -> void:
	pass


func _status_text() -> String:
	return ""


func _on_player_died() -> void:
	kill_player()


func _on_bot_died(bot: BotFighter) -> void:
	bot.deactivate()


# --- Helpers ----------------------------------------------------------------------------------

## Adds a bot of a class to a team at a position. skin_path overrides the class's bot skin.
func spawn_bot(
	character: LoadingScreen.PlayerCharacter, team: int, position: Vector3, skin_path: String = ""
) -> BotFighter:
	var bot: BotFighter = BotFighter.create(character, team, map, skin_path)
	get_parent().add_child(bot)
	bot.respawn_at(position)
	bot.damageable.died.connect(_on_bot_died.bind(bot))
	bots.append(bot)
	return bot


## Takes the player out of play (dead): frozen, hidden, not targetable.
func kill_player() -> void:
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.get_node("VisualRoot").visible = false
	player.collision_layer = 0


## Brings the player back with full health, at a position (or a random spot when INF).
func respawn_player(position: Vector3 = Vector3.INF) -> void:
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.get_node("VisualRoot").visible = true
	player.collision_layer = MapInfo.FIGHTER_LAYER
	if player.has_method("respawn_random"):
		player.call("respawn_random")
	if position != Vector3.INF and map.kind != MapInfo.Kind.CELESTIAL_BODY:
		player.global_position = position
	player.velocity = Vector3.ZERO
	player_health.revive()


func is_player_alive() -> bool:
	return player_health != null and player_health.is_alive()


## Ends the match: shows the result panel and stops the bots.
func end_match(title: String, subtitle: String) -> void:
	if match_over:
		return
	match_over = true
	for bot: BotFighter in bots:
		if is_instance_valid(bot):
			bot.set_physics_process(false)
	hud.show_end(title, subtitle)


## Team that dealt the killing blow to a Damageable (NO_TEAM if it fell or drowned).
static func killer_team(victim: Damageable) -> int:
	return Damageable.team_of(victim.last_damage_source)


## Gives the player their class's gun so every mode starts armed.
func _equip_class_weapon() -> void:
	var weapon: PlayerItems.Item = CharacterSkin.weapon_for(LoadingScreen.selected_player_character)
	if player.has_method("apply_hand_item"):
		player.call("apply_hand_item", weapon)
