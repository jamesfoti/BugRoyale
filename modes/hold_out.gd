extends GameMode
## Hold Out: a squad of four (humans plus AI squadmates) holds a spot against waves of whatever
## the map has: hornets from the air, husks shambling in on the ground, and armed enemy ants from
## the middle waves on, all arriving from marked approaches. Between waves the squad digs: a
## carve pays out what it removed (the map's ground as dirt, stone below it, veins of sand, clay
## and gravel), and building with the pickaxe spends the stock, so the fort grows from the ground
## it stands on. The director's noise meter runs during the build; a loud squad gets rushed.
## Fallen squadmates return each wave; the match ends when the whole squad is down at once.

const SQUAD_TEAM: int = 0
const ENEMY_TEAM: int = 99
const PREY_GROUP: StringName = &"hold_out_squad"

## Tuned from the editor: open modes/hold_out.tscn and select the root. These are the
## defaults; the scene saves only what differs.
## The squad, humans included; seconds to dig in before the first wave and between waves;
## how many marked approaches the enemies come from and how far from the fort they start; a
## husk's pace as a share of a soldier's; and the dirt paid into the stock for every wave
## cleared.
@export var squad_size: int = 4
@export var first_build_seconds: float = 60.0
@export var build_seconds: float = 35.0
@export var approaches_count: int = 3
@export var approach_min_distance: float = 30.0
@export var husk_speed: float = 0.85
## Dirt is counted in voxels: at the maps' 1 m voxels a 2 m pickaxe carve frees about 18.
@export var wave_bonus_dirt: int = 160

var squad: Squad
var director: HordeDirector
var swarm: BirdFlock
var wave: int = 0
var swatted: int = 0
var in_build: bool = true
var build_time_left: float = 0.0
## Enemies still up, as last counted by the host.
var enemies_left: int = 0
## What the squad has dug and not yet built with.
var stock: MaterialStock = MaterialStock.new()
var fort: Vector3 = Vector3.INF
var approaches: Array[Vector3] = []

var _fort_beacon: Beacon
var _approach_beacons: Array[Beacon] = []
var _enemies: Array[Fighter] = []

# --- Deciding ---------------------------------------------------------------------------------


func _start_match() -> void:
	fort = map.random_surface_point(0.0)
	for _index: int in approaches_count:
		approaches.append(_approach_point())
	for human: Fighter in humans():
		human.respawn_at(_near_fort())
	squad = Squad.fill(self, SQUAD_TEAM, PREY_GROUP, squad_size, _near_fort)
	for bot: Fighter in squad.bots():
		bot.brain.target_group = &"fighter"
		bot.brain.secondary_target_group = &"bird"
		bot.brain.detection_range = 45.0

	director = HordeDirector.new()
	director.name = "HordeDirector"
	director.setup(map, get_parent(), PREY_GROUP, ENEMY_TEAM)
	director.lull_seconds = INF
	add_child(director)
	for member: Fighter in squad.members:
		director.listen_to(member)
	director.listen_to_terrain()
	director.horde_sent.connect(_on_rushed)
	swarm = HordeDirector.make_flock(get_parent(), map, PREY_GROUP, ENEMY_TEAM, "Swarm")
	swarm.follow_targets = true
	swarm.spawn_radius = 30.0
	swarm.bird_died.connect(func(_bird: Bird) -> void: swatted += 1)

	stock.attach(map.editable_terrain())
	_start_build(first_build_seconds)
	announce(
		(
			(
				"Hold Out\nDig in: what you carve is what you build with. "
				+ "The first wave comes from the amber beacons in %d seconds."
			)
			% int(first_build_seconds)
		),
		6.0
	)


func _update_match(delta: float) -> void:
	if match_over:
		return
	if squad.alive_count() == 0:
		end_match(
			"Overrun!",
			(
				"Your squad held for %d wave%s and swatted %d."
				% [maxi(wave - 1, 0), "" if wave == 2 else "s", swatted]
			)
		)
		return
	if in_build:
		build_time_left -= delta
		director.tick(delta, squad.members)
		if build_time_left <= 0.0:
			_start_wave()
		return
	enemies_left = swarm.alive_count()
	for enemy: Fighter in _enemies:
		if enemy.is_alive():
			enemies_left += 1
	if enemies_left == 0:
		_end_wave()


func _on_fighter_died(fighter: Fighter) -> void:
	fighter.kill()
	if match_over:
		return
	if squad.has(fighter):
		if squad.alive_count() > 0:
			announce_to(fighter, "You're down! Back next wave.", 3.0)
	else:
		swatted += 1


# --- Waves ---------------------------------------------------------------------------------------


func _start_build(seconds: float) -> void:
	in_build = true
	build_time_left = seconds
	director.noise = 0.0
	_show_markers(true)


func _start_wave() -> void:
	in_build = false
	wave += 1
	_revive_fallen()
	_show_markers(false)
	var counts: Dictionary = _wave_counts(wave)
	var hornets: int = int(counts["hornets"])
	for index: int in approaches.size():
		var share: int = (
			hornets / approaches.size() + (1 if index < hornets % approaches.size() else 0)
		)
		if share > 0:
			swarm.follow_targets = false
			swarm.global_position = approaches[index] + map.up_at(approaches[index]) * 6.0
			swarm.spawn_wave(share)
	swarm.follow_targets = true
	swarm.max_speed = minf(10.0 + wave * 0.5, 16.0)
	swarm.attack_damage = 6.0 + wave * 1.0
	for index: int in int(counts["husks"]):
		_send_enemy(true, approaches[index % approaches.size()])
	for index: int in int(counts["ants"]):
		_send_enemy(false, approaches[index % approaches.size()])
	announce("Wave %d" % wave, 2.5)


func _end_wave() -> void:
	stock.add(TerrainMaterials.Kind.DIRT, wave_bonus_dirt)
	announce("Wave %d cleared! Dig in: %d seconds." % [wave, int(build_seconds)], 3.0)
	_start_build(build_seconds)


## Each wave brings more: hornets from the first, husks from the second, armed ants from the third.
func _wave_counts(wave_number: int) -> Dictionary:
	return {
		"hornets": mini(4 + wave_number * 3, 40),
		"husks": mini(maxi(wave_number - 1, 0) * 2, 16),
		"ants": mini(maxi(wave_number - 2, 0) * 2, 12),
	}


## A husk or an armed ant at an approach, heading for the fort: a dead one from an earlier wave
## is sent back out before a new body is made.
func _send_enemy(husk: bool, approach: Vector3) -> void:
	var spot: Vector3 = map.ground_point_near(approach, 1.0, 6.0, 1.2)
	var enemy: Fighter = null
	for candidate: Fighter in _enemies:
		if not candidate.is_alive() and candidate.is_valid() and (candidate.brain.husk == husk):
			enemy = candidate
			break
	if enemy == null:
		var character: LoadingScreen.PlayerCharacter
		var skin: String = ""
		if husk:
			var classes: Array = LoadingScreen.PlayerCharacter.values()
			character = classes[randi() % classes.size()]
		else:
			character = LoadingScreen.PlayerCharacter.ANT_WARRIOR
			skin = CharacterSkin.BLACK_ANT_BOT_SCENE_PATH
		enemy = spawn_bot(character, ENEMY_TEAM, spot, skin)
		if enemy == null:
			return
		enemy.brain.target_group = &"fighter"
		if husk:
			enemy.brain.become_husk(ENEMY_TEAM, husk_speed)
		_enemies.append(enemy)
	else:
		enemy.respawn_at(spot)
	enemy.brain.detection_range = 120.0
	enemy.brain.objective = fort
	enemy.brain.objective_radius = 4.0
	enemy.hold_fire(2.0)


func _revive_fallen() -> void:
	for fighter: Fighter in squad.members:
		if not fighter.is_alive():
			fighter.respawn_at(_near_fort())


## The director filled its meter during the build: the wave comes now.
func _on_rushed(_count: int, _reason: HordeDirector.Reason) -> void:
	if in_build and build_time_left > 1.0:
		announce("They heard you! Here they come.", 3.0)
		build_time_left = 0.0


# --- Points and markers -----------------------------------------------------------------------


func _near_fort() -> Vector3:
	return map.ground_point_near(fort, 2.0, 5.0, 1.2)


## A ground point well away from the fort (the first of several tries that manages it).
func _approach_point() -> Vector3:
	var best: Vector3 = map.random_surface_point(0.0)
	var best_distance: float = best.distance_to(fort)
	for _attempt: int in 10:
		var candidate: Vector3 = map.random_surface_point(0.0)
		var distance: float = candidate.distance_to(fort)
		if distance >= approach_min_distance:
			return candidate
		if distance > best_distance:
			best_distance = distance
			best = candidate
	return best


func _show_markers(building: bool) -> void:
	for beacon: Beacon in _approach_beacons:
		beacon.visible = building


# --- Showing ----------------------------------------------------------------------------------


func _status_text() -> String:
	var squad_line: String = (
		"Squad %d/%d" % [squad.alive_count() if squad != null else 0, squad_size]
	)
	if in_build:
		return (
			"Wave %d in %ds  ·  %s  ·  %s  ·  Swatted %d"
			% [wave + 1, ceili(build_time_left), stock.text(), squad_line, swatted]
		)
	return (
		"Wave %d  ·  Enemies left %d  ·  %s  ·  Swatted %d"
		% [wave, enemies_left, squad_line, swatted]
	)


func _present() -> void:
	super()
	hud.set_stock(stock.counts)
	if map == null or fort == Vector3.INF:
		return
	if _fort_beacon == null:
		_fort_beacon = Beacon.build(get_parent(), map, fort, Color(0.3, 1.0, 0.5), 1.5, 30.0)
	while _approach_beacons.size() < approaches.size():
		var point: Vector3 = approaches[_approach_beacons.size()]
		_approach_beacons.append(
			Beacon.build(get_parent(), map, point, Color(1.0, 0.7, 0.2), 1.0, 25.0)
		)
		_approach_beacons.back().visible = in_build


func _snapshot_state() -> Dictionary:
	return {
		"wave": wave,
		"swatted": swatted,
		"in_build": in_build,
		"build_time_left": build_time_left,
		"enemies_left": enemies_left,
		"stock": stock.export_counts(),
		"fort": fort,
		"approaches": approaches.duplicate(),
	}


func _apply_state(state: Dictionary) -> void:
	wave = int(state.get("wave", wave))
	swatted = int(state.get("swatted", swatted))
	in_build = bool(state.get("in_build", in_build))
	build_time_left = float(state.get("build_time_left", build_time_left))
	enemies_left = int(state.get("enemies_left", enemies_left))
	if state.has("stock"):
		stock.import_counts(state["stock"])
	fort = state.get("fort", fort)
	if state.has("approaches"):
		approaches.assign(state["approaches"])
