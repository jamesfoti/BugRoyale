extends GameMode
## Attack of the Hornets: a squad of four (humans plus AI squadmates) survives ever-bigger hornet
## waves, like COD Zombies. Fallen squad members return at the start of the next wave; the match
## ends when the whole squad is down at once.

const SQUAD_TEAM: int = 0
const HORNET_TEAM: int = 99
const SQUAD_SIZE: int = 4
const BREAK_SECONDS: float = 7.0
const PREY_GROUP: StringName = &"hornet_prey"

var squad: Squad
var swarm: BirdFlock
var wave: int = 0
var hornets_killed: int = 0
## Hornets still flying, as last counted by the host (the swarm itself lives on the host).
var hornets_left: int = 0

var _break_time_left: float = 0.0
var _in_break: bool = true

# --- Deciding ---------------------------------------------------------------------------------


func _start_match() -> void:
	for human: Fighter in humans():
		human.respawn_at(map.random_surface_point(1.2))
	var anchor: Vector3 = local_fighter.get_position() if local_fighter != null else map.center()
	squad = Squad.fill(
		self,
		SQUAD_TEAM,
		PREY_GROUP,
		SQUAD_SIZE,
		func() -> Vector3: return map.ground_point_near(anchor, 2.0, 4.0, 1.2)
	)
	for bot: Fighter in squad.bots():
		bot.brain.target_group = &"bird"
		bot.brain.detection_range = 45.0

	swarm = HordeDirector.make_flock(get_parent(), map, PREY_GROUP, HORNET_TEAM, "HornetSwarm")
	swarm.follow_targets = true
	# Waves spawn closer in the small maps.
	swarm.spawn_radius = (
		14.0 if map.kind in [MapInfo.Kind.TERRARIUM, MapInfo.Kind.CELESTIAL_BODY] else 24.0
	)
	swarm.bird_died.connect(func(_bird: Bird) -> void: hornets_killed += 1)
	_start_break()


func _update_match(delta: float) -> void:
	if match_over:
		return
	hornets_left = swarm.alive_count()
	if alive_count() == 0:
		end_match(
			"Overrun!",
			(
				"Your squad survived %d wave%s and swatted %d hornets."
				% [maxi(wave - 1, 0), "" if wave == 2 else "s", hornets_killed]
			)
		)
		return
	if _in_break:
		_break_time_left -= delta
		if _break_time_left <= 0.0:
			_start_wave()
	elif hornets_left == 0:
		announce("Wave %d cleared!" % wave, 3.0)
		_start_break()


func _on_fighter_died(fighter: Fighter) -> void:
	fighter.kill()
	if alive_count() > 0:
		announce_to(fighter, "You're down! Back next wave.", 3.0)


func _start_break() -> void:
	_in_break = true
	_break_time_left = BREAK_SECONDS
	if wave == 0:
		announce("Attack of the Hornets\nWave 1 incoming...", BREAK_SECONDS - 1.0)


func _start_wave() -> void:
	_in_break = false
	wave += 1
	_revive_fallen()
	# Each wave brings more, faster, harder-hitting hornets.
	swarm.max_speed = minf(10.0 + wave * 0.5, 16.0)
	swarm.max_attack_speed = minf(14.0 + wave * 0.7, 22.0)
	swarm.attack_damage = 6.0 + wave * 1.0
	swarm.spawn_wave(mini(6 + (wave - 1) * 4, 70))
	hornets_left = swarm.alive_count()
	announce("Wave %d" % wave, 2.5)


## Fallen squad members (humans included) return next to someone still standing, the local
## player for preference.
func _revive_fallen() -> void:
	var anchor: Vector3 = local_fighter.get_position() if local_fighter != null else map.center()
	if not is_local_alive():
		for fighter: Fighter in alive_fighters():
			anchor = fighter.get_position()
			break
	for fighter: Fighter in fighters:
		if not fighter.is_alive():
			fighter.respawn_at(map.ground_point_near(anchor, 2.0, 4.0, 1.2))


# --- Showing ----------------------------------------------------------------------------------


func _status_text() -> String:
	var squad: String = "Squad %d/%d" % [alive_count(), SQUAD_SIZE]
	if _in_break:
		return (
			"Wave %d in %ds  ·  %s  ·  Hornets swatted %d"
			% [wave + 1, ceili(_break_time_left), squad, hornets_killed]
		)
	return (
		"Wave %d  ·  Hornets left %d  ·  %s  ·  Swatted %d"
		% [wave, hornets_left, squad, hornets_killed]
	)


func _snapshot_state() -> Dictionary:
	return {
		"wave": wave,
		"hornets_killed": hornets_killed,
		"hornets_left": hornets_left,
		"in_break": _in_break,
		"break_time_left": _break_time_left,
	}


func _apply_state(state: Dictionary) -> void:
	wave = int(state.get("wave", wave))
	hornets_killed = int(state.get("hornets_killed", hornets_killed))
	hornets_left = int(state.get("hornets_left", hornets_left))
	_in_break = bool(state.get("in_break", _in_break))
	_break_time_left = float(state.get("break_time_left", _break_time_left))
