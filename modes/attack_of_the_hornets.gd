extends GameMode
## Attack of the Hornets: the player and 3 AI squadmates survive ever-bigger hornet waves, like
## COD Zombies. Fallen squadmates (player included) return at the start of the next wave; the
## match ends when the whole squad is down at once.

const SQUAD_TEAM: int = 0
const HORNET_TEAM: int = 99
const SQUAD_SIZE: int = 4
const BREAK_SECONDS: float = 7.0
const PREY_GROUP: StringName = &"hornet_prey"

var swarm: BirdFlock
var wave: int = 0
var hornets_killed: int = 0
var _break_time_left: float = 0.0
var _in_break: bool = true
var _squad_bots: Array[BotFighter] = []


func _start_match() -> void:
	player_health.team = SQUAD_TEAM
	player.add_to_group(PREY_GROUP)

	var player_class: LoadingScreen.PlayerCharacter = LoadingScreen.selected_player_character
	var squad_classes: Array = LoadingScreen.PlayerCharacter.values().filter(
		func(character: int) -> bool: return character != player_class
	)
	for index: int in SQUAD_SIZE - 1:
		var character: LoadingScreen.PlayerCharacter = squad_classes[index % squad_classes.size()]
		var bot: BotFighter = spawn_bot(character, SQUAD_TEAM, _near(player.global_position))
		bot.target_group = &"bird"
		bot.leader = player
		bot.detection_range = 45.0
		bot.add_to_group(PREY_GROUP)
		_squad_bots.append(bot)

	swarm = BirdFlock.new()
	swarm.name = "HornetSwarm"
	swarm.auto_build = false
	swarm.map = map
	swarm.target_group = PREY_GROUP
	swarm.follow_targets = true
	swarm.hornet_team = HORNET_TEAM
	match map.kind:
		MapInfo.Kind.TERRARIUM:
			swarm.min_height = 3.0
			swarm.max_height = 9.0
			swarm.spawn_radius = 14.0
		MapInfo.Kind.CELESTIAL_BODY:
			swarm.min_height = 6.0
			swarm.max_height = 13.0
			swarm.spawn_radius = 14.0
		_:
			swarm.min_height = 8.0
			swarm.max_height = 16.0
			swarm.spawn_radius = 24.0
	if map.ceiling_y < INF:
		# Under a ceiling (the crawlspace): fly low enough to stay beneath the joists.
		swarm.min_height = 2.0
		swarm.max_height = clampf(map.ceiling_y - map.center().y - 3.0, 3.0, swarm.max_height)
	var network: DuctNetwork = get_tree().get_first_node_in_group("duct_network") as DuctNetwork
	if network != null:
		# Ducts, furnace and piers are solid to the swarm.
		swarm.obstacles = network.obstacles.duplicate()
	get_parent().add_child(swarm)
	swarm.bird_died.connect(func(_bird: Bird) -> void: hornets_killed += 1)
	_start_break()


func _update_match(delta: float) -> void:
	if match_over:
		return
	if _squad_alive() == 0:
		end_match(
			"Overrun!",
			"Your squad survived %d wave%s and swatted %d hornets." % [maxi(wave - 1, 0), "" if wave == 2 else "s", hornets_killed]
		)
		return
	if _in_break:
		_break_time_left -= delta
		if _break_time_left <= 0.0:
			_start_wave()
	elif swarm.alive_count() == 0:
		hud.show_message("Wave %d cleared!" % wave, 3.0)
		_start_break()


func _status_text() -> String:
	var squad: String = "Squad %d/%d" % [_squad_alive(), SQUAD_SIZE]
	if _in_break:
		return "Wave %d in %ds  ·  %s  ·  Hornets swatted %d" % [wave + 1, ceili(_break_time_left), squad, hornets_killed]
	return "Wave %d  ·  Hornets left %d  ·  %s  ·  Swatted %d" % [wave, swarm.alive_count(), squad, hornets_killed]


func _on_player_died() -> void:
	kill_player()
	if _squad_alive() > 0:
		hud.show_message("You're down! Back next wave.", 3.0)


func _start_break() -> void:
	_in_break = true
	_break_time_left = BREAK_SECONDS
	if wave == 0:
		hud.show_message("Attack of the Hornets\nWave 1 incoming...", BREAK_SECONDS - 1.0)


func _start_wave() -> void:
	_in_break = false
	wave += 1
	_revive_fallen()
	# Each wave brings more, faster, harder-hitting hornets.
	swarm.max_speed = minf(10.0 + wave * 0.5, 16.0)
	swarm.max_attack_speed = minf(14.0 + wave * 0.7, 22.0)
	swarm.attack_damage = 6.0 + wave * 1.0
	swarm.spawn_wave(mini(6 + (wave - 1) * 4, 70))
	hud.show_message("Wave %d" % wave, 2.5)


## Fallen squad members (player included) return next to someone still standing.
func _revive_fallen() -> void:
	var anchor: Vector3 = player.global_position
	for bot: BotFighter in _squad_bots:
		if bot.is_active():
			anchor = bot.global_position
			break
	if is_player_alive():
		anchor = player.global_position
	if not is_player_alive():
		respawn_player(_near(anchor))
	for bot: BotFighter in _squad_bots:
		if not bot.is_active():
			bot.respawn_at(_near(anchor))


func _squad_alive() -> int:
	var alive: int = 1 if is_player_alive() else 0
	for bot: BotFighter in _squad_bots:
		if bot.is_active():
			alive += 1
	return alive


## A spot on the ground a few meters from a point.
func _near(point: Vector3) -> Vector3:
	var up: Vector3 = map.up_at(point)
	var offset: Vector3 = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	offset = offset.rotated(up, randf_range(0.0, TAU)) * randf_range(2.0, 4.0)
	var probe: Vector3 = point + offset
	var ground: Dictionary = map.ground_hit(probe)
	return (ground.position + map.up_at(ground.position) * 1.2) if not ground.is_empty() else point + up * 1.2
