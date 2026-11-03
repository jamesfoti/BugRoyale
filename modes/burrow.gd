extends GameMode
## Burrow: survival on a map that keeps what is dug into it, played from the ground as the
## colony's soldier. It opens with the colony on the march: four workers carry the queen and
## follow you, and where you decide is good ground you give the word (found_colony, G) and they
## set her down and dig her chamber. Until then she rides in the open, and hornets go for her;
## lose the workers and she lies where she fell until you pick her up yourself. Once she is
## below, the burrow is yours: days are for digging (a carve pays out what it removed, building
## with the pickaxe spends it), nights belong to the map (hornets in hordes, husks for the
## burrow, gone at dawn). The burrow is saved to disk with the ground it stands in (WorldSave)
## and is there, as left, next time. A fallen bug is back at the burrow after a few seconds;
## a fallen worker hatches again a while later. If the queen dies the colony is over.

enum Carry { NOBODY, WORKERS, YOU }

const MODE_ID: String = "burrow"
const TEAM: int = 0
const ENEMY_TEAM: int = 99
const PREY_GROUP: StringName = &"burrow_dwellers"
const RESPAWN_SECONDS: float = 4.0
const AUTOSAVE_SECONDS: float = 30.0
## Hordes this often through a night (the director's finale timer).
const NIGHT_HORDE_SECONDS: float = 45.0
const HORDE_BASE: int = 5
const HORDE_GROWTH: int = 2
const HORDE_MAX: int = 20
const HUSK_SPEED: float = 0.8
const MAX_HUSKS: int = 14
## Husks that come with each horde after dark.
const HUSKS_PER_HORDE: int = 2
## Enemies set out at least this far from the burrow.
const SPAWN_MIN_DISTANCE: float = 30.0
## The colony on the march: this many workers, at this share of a soldier's pace while they
## carry, and (once the colony is founded) hatching again this long after they fall.
const WORKERS: int = 4
const WORKER_SPEED: float = 0.8
const WORKER_RESPAWN_SECONDS: float = 20.0
## The word to set the queen down, how far from her a bug may be and still give it, how uneven
## the ground around her may be, and how fast the workers dig once she is down (one carve per
## interval).
const FOUND_ACTION: StringName = &"found_colony"
const FOUND_RADIUS: float = 20.0
const GROUND_SPREAD_LIMIT: float = 2.5
const GROUND_PROBE: float = 2.5
const DIG_INTERVAL: float = 1.2
## A bug this close to a queen on the ground picks her up.
const PICKUP_RADIUS: float = 1.6

var cycle: DayCycle
var director: HordeDirector
var stock: MaterialStock = MaterialStock.new()
## The burrow's entrance, once the colony is founded; INF on the march.
var home: Vector3 = Vector3.INF
var founded: bool = false
## Nights survived so far; the day shown is one more.
var nights: int = 0
var deaths: int = 0
var swatted: int = 0
var husks_down: int = 0
## Seconds into the day cycle, mirrored from the clock for the snapshot and the status line.
var time: float = DayCycle.DAY_SECONDS * 0.25
var play_seconds: float = 0.0
## Enemies still up, as last counted by the host.
var husks_left: int = 0
var hornets_left: int = 0
## The queen as the host last saw her, for the snapshot, the status line and the save: where
## she is (on the march: wherever she is carried; founded: the chamber floor), her state, her
## health, who carries her and how many workers are up.
var queen_position: Vector3 = Vector3.INF
var queen_state: int = QueenAnt.State.CARRIED
var queen_health: float = QueenAnt.MAX_HEALTH
var queen_carry: int = Carry.WORKERS
var workers_alive: int = WORKERS

var queen: QueenAnt

var _map_id: String = ""
var _dwellers: Array[Fighter] = []
var _workers: Array[Fighter] = []
var _husks: Array[Fighter] = []
## Fighter -> seconds until it is back at the burrow.
var _respawn_timers: Dictionary = {}
var _home_beacon: Beacon
var _autosave_left: float = AUTOSAVE_SECONDS
var _restored: bool = false
## The human carrying the queen when no worker can (null otherwise).
var _human_bearer: Fighter
## The carves still to make for the queen's chamber, and the way down once they are made.
var _dig_plan: Array[Dictionary] = []
var _dig_timer: float = 0.0
var _settle_path: PackedVector3Array = PackedVector3Array()
var _settled_announced: bool = false

# --- Deciding ---------------------------------------------------------------------------------


func _start_match() -> void:
	_map_id = ModeCatalog.map_id_for_scene(LoadingScreen.current_scene_path)
	var terrain: ChunkedTerrainWorld = map.editable_terrain()
	cycle = DayCycle.new()
	cycle.name = "DayCycle"
	add_child(cycle)
	cycle.attach(get_parent())
	cycle.set_time(time)
	cycle.dusk.connect(_on_dusk)
	cycle.dawn.connect(_on_dawn)

	var saved: Dictionary = WorldSave.load_world(MODE_ID, _map_id)
	if saved.is_empty():
		queen_position = map.random_surface_point(0.0)
	else:
		_restored = true
		_apply_state(saved.get("mode", {}))
		if terrain != null:
			terrain.import_edit_state(saved.get("terrain", {}))
	var anchor: Vector3 = home if founded else queen_position
	for human: Fighter in humans():
		human.set_team(TEAM)
		human.body.add_to_group(PREY_GROUP)
		_dwellers.append(human)
		# Straight onto the saved spot: the restored ground's collision is still being rebuilt,
		# so a probe for the floor here would find yesterday's.
		human.respawn_at(anchor + map.up_at(anchor) * 1.0)
	stock.attach(terrain)
	_spawn_queen(anchor)
	_spawn_workers(anchor)

	director = HordeDirector.new()
	director.name = "HordeDirector"
	director.setup(map, get_parent(), PREY_GROUP, ENEMY_TEAM)
	director.lull_seconds = INF
	director.finale_seconds = NIGHT_HORDE_SECONDS
	director.horde_base = HORDE_BASE
	director.horde_growth = HORDE_GROWTH
	director.horde_max = HORDE_MAX
	director.hordes = nights
	add_child(director)
	for dweller: Fighter in _dwellers:
		director.listen_to(dweller)
	director.listen_to_terrain()
	director.build_horde_flock()
	director.horde_flock().bird_died.connect(func(_bird: Bird) -> void: swatted += 1)
	director.horde_sent.connect(_on_horde_sent)
	if cycle.is_night():
		director.start_finale()
	if _restored and founded:
		announce(
			(
				"Burrow\nWelcome back: day %d, %s. The ground is as you left it."
				% [nights + 1, "night is on" if cycle.is_night() else "the sun is up"]
			),
			6.0
		)
	elif _restored:
		announce("Burrow\nThe colony is still on the march. Find good ground and press G.", 6.0)
	else:
		announce(
			(
				"Burrow\nYour workers carry the queen and follow you. Lead them to good ground "
				+ "and press G to found the colony there.\nHornets and husks come after dark."
			),
			8.0
		)


func _update_match(delta: float) -> void:
	if match_over:
		return
	play_seconds += delta
	time = cycle.time
	director.tick(delta, _dwellers)
	for fighter: Fighter in _respawn_timers.keys():
		var remaining: float = float(_respawn_timers[fighter]) - delta
		if remaining > 0.0:
			_respawn_timers[fighter] = remaining
			continue
		_respawn_timers.erase(fighter)
		fighter.respawn_at(_respawn_point())
	_tend_queen()
	if founded:
		_dig_tick(delta)
	else:
		_poll_found()
		for husk: Fighter in _husks:
			husk.brain.objective = queen_position
	husks_left = 0
	for husk: Fighter in _husks:
		if husk.is_alive():
			husks_left += 1
	hornets_left = director.horde_flock().alive_count()
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		_autosave_left = AUTOSAVE_SECONDS
		save_world()


func _on_fighter_died(fighter: Fighter) -> void:
	fighter.kill()
	if match_over:
		return
	if _dwellers.has(fighter):
		deaths += 1
		var where: String = "the burrow" if founded else "the colony"
		announce_to(fighter, "You're down. Back with %s in a moment..." % where, RESPAWN_SECONDS)
		_respawn_timers[fighter] = RESPAWN_SECONDS
	elif _workers.has(fighter):
		if founded:
			_respawn_timers[fighter] = WORKER_RESPAWN_SECONDS
		else:
			var up: int = _alive_workers().size()
			announce("A worker is down. %d still carry the queen." % up, 3.0)
	elif _husks.has(fighter):
		husks_down += 1


func _exit_tree() -> void:
	if _started and Authority.is_host():
		save_world()


# --- The colony ---------------------------------------------------------------------------------


func _spawn_queen(anchor: Vector3) -> void:
	var at: Vector3 = anchor + map.up_at(anchor) * QueenAnt.CARRY_HEIGHT
	if founded:
		at = queen_position
	queen = QueenAnt.spawn(get_parent(), at, map.up_at(anchor), TEAM)
	queen.health.health = clampf(queen_health, 1.0, QueenAnt.MAX_HEALTH)
	queen.health.died.connect(_on_queen_died)
	if founded:
		# A saved colony: she is below (the chamber was dug before the save).
		queen.rest_below(queen_position)
		_settled_announced = true
	else:
		queen.add_to_group(PREY_GROUP)


## The workers: unarmed ants at a carrier's pace. On the march they follow the local player
## (and the queen rides on them); founded, they keep to the entrance.
func _spawn_workers(anchor: Vector3) -> void:
	var leader: Node3D = local_fighter.body if local_fighter != null else null
	for _index: int in WORKERS:
		var spot: Vector3 = map.ground_point_near(anchor, 1.5, 3.5, 1.2)
		var worker: Fighter = spawn_bot(
			LoadingScreen.PlayerCharacter.ANT_WARRIOR,
			TEAM,
			spot,
			CharacterSkin.BLACK_ANT_BOT_SCENE_PATH
		)
		if worker == null:
			return
		worker.body.apply_hand_item(PlayerItems.Item.NONE)
		worker.body.scale_speed(WORKER_SPEED)
		worker.body.add_to_group(PREY_GROUP)
		worker.brain.weapon = {}
		worker.brain.detection_range = 0.0
		worker.brain.runs_to_keep_up = true
		if founded:
			worker.brain.objective = home
			worker.brain.objective_radius = 5.0
		else:
			worker.brain.leader = leader
		_workers.append(worker)


func _alive_workers() -> Array[Fighter]:
	var result: Array[Fighter] = []
	for worker: Fighter in _workers:
		if worker.is_alive():
			result.append(worker)
	return result


## Once a frame: who carries the queen, whether she has been dropped or picked up, and the
## numbers the snapshot and the status line show.
func _tend_queen() -> void:
	if queen == null or not is_instance_valid(queen):
		return
	workers_alive = _alive_workers().size()
	queen_health = queen.health.health
	if founded:
		queen_state = queen.state
		queen_carry = Carry.NOBODY
		if queen.state == QueenAnt.State.SETTLED and not _settled_announced:
			_settled_announced = true
			queen.remove_from_group(PREY_GROUP)
			announce("The queen is settled. The burrow is yours: dig in before dark.", 5.0)
		return
	var carriers: Array[Fighter] = _alive_workers()
	if carriers.is_empty() and _human_bearer != null and _human_bearer.is_alive():
		carriers.append(_human_bearer)
	if carriers.is_empty():
		if queen.state == QueenAnt.State.CARRIED:
			var ground: Dictionary = map.ground_below(queen.global_position)
			queen.set_down(ground.position if not ground.is_empty() else queen.global_position)
			_human_bearer = null
			announce("The queen is down! Get to her.", 4.0)
		for human: Fighter in _dwellers:
			if (
				human.is_alive()
				and human.get_position().distance_to(queen.global_position) < PICKUP_RADIUS
			):
				_human_bearer = human
				queen.carried_by([human])
				announce_to(human, "You have the queen. Find ground and press G.", 4.0)
				break
	else:
		if not carriers.has(_human_bearer):
			_human_bearer = null
		queen.carried_by(carriers)
	queen_position = queen.global_position
	queen_state = queen.state
	if queen.state != QueenAnt.State.CARRIED:
		queen_carry = Carry.NOBODY
	elif _human_bearer != null:
		queen_carry = Carry.YOU
	else:
		queen_carry = Carry.WORKERS


func _poll_found() -> void:
	if local_fighter == null or not local_fighter.is_alive():
		return
	if not InputMap.has_action(FOUND_ACTION) or not Input.is_action_just_pressed(FOUND_ACTION):
		return
	request_found(local_fighter)


## A bug asks for the colony to be founded where the queen is. The queen answers (through the
## HUD) when the ground will not do. True when the colony was founded.
func request_found(fighter: Fighter) -> bool:
	if founded or match_over or queen == null or fighter == null or not fighter.is_alive():
		return false
	if fighter.get_position().distance_to(queen.global_position) > FOUND_RADIUS:
		announce_to(fighter, "The queen is too far off to set down here.", 3.0)
		return false
	var ground: Dictionary = map.ground_below(queen.global_position)
	if ground.is_empty():
		announce_to(fighter, 'The queen stirs: "Not here. There is no ground."', 3.0)
		return false
	var problem: String = ground_problem(ground.position)
	if not problem.is_empty():
		announce_to(fighter, 'The queen stirs: "Not here. %s"' % problem, 3.0)
		return false
	var away: Vector3 = ground.position - fighter.get_position()
	_found(ground.position, away)
	return true


## Why a ground point will not do for the nest ("" when it will): under water, ground the map
## does not let anyone dig, something that is not ground at all (a wall top, a duct, a tree), a
## drop beside it (a terrarium's edge), or too uneven around it.
func ground_problem(point: Vector3) -> String:
	var up: Vector3 = map.up_at(point)
	if map.is_underwater(point + up * 0.3):
		return "Too wet."
	var terrain: ChunkedTerrainWorld = map.editable_terrain()
	if terrain == null or not terrain.can_edit_at(point):
		return "The ground is too hard to dig."
	if not terrain.is_solid_at(point - up * 0.6):
		return "This is not ground."
	var side: Vector3 = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD)
	side = side.normalized()
	var forward: Vector3 = side.cross(up).normalized()
	var lowest: float = 0.0
	var highest: float = 0.0
	for offset: Vector3 in [side, -side, forward, -forward]:
		var probe: Dictionary = map.ground_below(point + offset * GROUND_PROBE + up * 3.0, 9.0)
		if probe.is_empty():
			return "The ground falls away."
		var rise: float = (probe.position - point).dot(up)
		lowest = minf(lowest, rise)
		highest = maxf(highest, rise)
	if lowest < -GROUND_SPREAD_LIMIT * 2.0:
		return "The ground falls away."
	if highest - lowest > GROUND_SPREAD_LIMIT:
		return "Too steep."
	return ""


func _found(entrance: Vector3, direction: Vector3) -> void:
	founded = true
	home = entrance
	var up: Vector3 = map.up_at(entrance)
	_dig_plan = QueenAnt.nest_plan(entrance, up, direction)
	_settle_path = QueenAnt.settle_path(entrance, up, direction)
	queen_position = _settle_path[_settle_path.size() - 1]
	_human_bearer = null
	queen.set_down(entrance)
	for worker: Fighter in _workers:
		worker.brain.leader = null
		worker.brain.objective = home
		worker.brain.objective_radius = 5.0
	_dig_timer = 0.8
	announce("The colony is founded here. The workers dig the queen's chamber.", 5.0)
	save_world()


## The workers dig the nest a carve at a time; when the last is made the queen goes below.
func _dig_tick(delta: float) -> void:
	if _dig_plan.is_empty():
		return
	_dig_timer -= delta
	if _dig_timer > 0.0:
		return
	_dig_timer = DIG_INTERVAL
	var terrain: ChunkedTerrainWorld = map.editable_terrain()
	var carve: Dictionary = _dig_plan.pop_front()
	if terrain != null:
		terrain.apply_edit(carve)
	if _dig_plan.is_empty():
		queen.settle_along(_settle_path)
		announce("The chamber is dug. The queen goes below.", 4.0)


func _on_queen_died() -> void:
	if match_over:
		return
	queen.remove_from_group(PREY_GROUP)
	queen_health = 0.0
	WorldSave.delete(MODE_ID, _map_id)
	end_match(
		"The queen is dead.",
		(
			"The colony died with her on day %d. The next game on this map starts a new one."
			% (nights + 1)
		)
	)


## Where a fallen bug comes back: by the burrow, or by the queen while the colony marches.
func _respawn_point() -> Vector3:
	var anchor: Vector3 = home if founded else queen_position
	return map.ground_point_near(anchor, 1.0, 3.0, 1.2)


# --- Night and day -----------------------------------------------------------------------------


func _on_dusk() -> void:
	director.start_finale()
	for _index: int in mini(2 + nights * 2, MAX_HUSKS):
		_send_husk()
	announce("Night %d falls. They're coming." % (nights + 1), 4.0)


func _on_dawn() -> void:
	nights += 1
	director.stop_finale()
	director.disperse_hordes()
	for husk: Fighter in _husks:
		if husk.is_alive():
			husk.health.apply_damage(husk.health.max_health * 10.0)
	announce("Dawn. Night %d survived; the husks crumble in the light." % nights, 4.0)
	save_world()


func _on_horde_sent(_count: int, reason: HordeDirector.Reason) -> void:
	match reason:
		HordeDirector.Reason.NOISE:
			announce("They heard you!", 3.0)
		HordeDirector.Reason.FINALE:
			announce("Hornets in the dark!", 3.0)
			for _index: int in HUSKS_PER_HORDE:
				if husks_left < MAX_HUSKS:
					_send_husk()
		_:
			announce("A horde is coming!", 3.0)


## A husk sets out from far off for the burrow (or the queen, while the colony marches); a dead
## one from earlier is sent back out before a new body is made.
func _send_husk() -> void:
	var spot: Vector3 = map.ground_point_near(_far_point(), 0.0, 4.0, 1.2)
	var husk: Fighter = null
	for candidate: Fighter in _husks:
		if not candidate.is_alive() and candidate.is_valid():
			husk = candidate
			break
	if husk == null:
		var classes: Array = LoadingScreen.PlayerCharacter.values()
		husk = spawn_bot(classes[randi() % classes.size()], ENEMY_TEAM, spot)
		if husk == null:
			return
		husk.brain.target_group = &"fighter"
		husk.brain.become_husk(ENEMY_TEAM, HUSK_SPEED)
		_husks.append(husk)
	else:
		husk.respawn_at(spot)
		husk.brain.become_husk(ENEMY_TEAM, HUSK_SPEED)
	husk.brain.detection_range = 120.0
	husk.brain.objective = home if founded else queen_position
	husk.brain.objective_radius = 4.0
	husk.hold_fire(2.0)
	husks_left += 1


## A ground point well away from the colony (the first of several tries that manages it).
func _far_point() -> Vector3:
	var anchor: Vector3 = home if founded else queen_position
	var best: Vector3 = map.random_surface_point(0.0)
	var best_distance: float = best.distance_to(anchor)
	for _attempt: int in 10:
		var candidate: Vector3 = map.random_surface_point(0.0)
		var distance: float = candidate.distance_to(anchor)
		if distance >= SPAWN_MIN_DISTANCE:
			return candidate
		if distance > best_distance:
			best_distance = distance
			best = candidate
	return best


# --- Saving -------------------------------------------------------------------------------------


## Writes the burrow to disk: the ground as it stands and this mode's numbers. A dead colony
## is not written (its save was deleted).
func save_world() -> void:
	if not Authority.is_host() or map == null or _map_id.is_empty() or match_over:
		return
	var terrain: ChunkedTerrainWorld = map.editable_terrain()
	var terrain_state: Dictionary = (
		terrain.export_edit_state() if terrain != null and is_instance_valid(terrain) else {}
	)
	var summary: String = (
		"Day %d  ·  %d night%s survived" % [nights + 1, nights, "" if nights == 1 else "s"]
	)
	if not founded:
		summary += "  ·  the colony is still on the march"
	WorldSave.save(
		MODE_ID, _map_id, LoadingScreen.last_terrain_seed, terrain_state, _snapshot_state(), summary
	)


# --- Showing ----------------------------------------------------------------------------------


func _status_text() -> String:
	var change: String = DayCycle.clock_text(DayCycle.seconds_to_change_at(time))
	var night: bool = DayCycle.is_night_at(time)
	var workers_text: String = "Workers %d/%d" % [workers_alive, WORKERS]
	if not founded:
		var carry: String = "The queen is down"
		if queen_carry == Carry.WORKERS:
			carry = "The workers carry the queen"
		elif queen_carry == Carry.YOU:
			carry = "You carry the queen"
		return (
			"%s  ·  %s to %s  ·  %s  ·  Queen %d%%  ·  G: found the colony here"
			% [
				carry,
				change,
				"dawn" if night else "dusk",
				workers_text,
				roundi(queen_health / QueenAnt.MAX_HEALTH * 100.0)
			]
		)
	if night:
		return (
			"Night %d  ·  %s to dawn  ·  Husks %d  ·  Hornets %d  ·  %s  ·  Deaths %d"
			% [nights + 1, change, husks_left, hornets_left, workers_text, deaths]
		)
	return (
		"Day %d  ·  %s to dusk  ·  %s  ·  %s  ·  Deaths %d"
		% [nights + 1, change, stock.text(), workers_text, deaths]
	)


func _present() -> void:
	super()
	hud.set_stock(stock.counts)
	if map == null or home == Vector3.INF:
		return
	if _home_beacon == null:
		_home_beacon = Beacon.build(get_parent(), map, home, Color(0.3, 1.0, 0.5), 1.0, 40.0)


func _snapshot_state() -> Dictionary:
	return {
		"home": home,
		"founded": founded,
		"stock": stock.export_counts(),
		"nights": nights,
		"deaths": deaths,
		"swatted": swatted,
		"husks_down": husks_down,
		"time": time,
		"play_seconds": play_seconds,
		"husks_left": husks_left,
		"hornets_left": hornets_left,
		"queen_position": queen_position,
		"queen_state": queen_state,
		"queen_health": queen_health,
		"queen_carry": queen_carry,
		"workers_alive": workers_alive,
	}


func _apply_state(state: Dictionary) -> void:
	home = state.get("home", home)
	founded = bool(state.get("founded", founded))
	if state.has("stock"):
		stock.import_counts(state["stock"])
	nights = int(state.get("nights", nights))
	deaths = int(state.get("deaths", deaths))
	swatted = int(state.get("swatted", swatted))
	husks_down = int(state.get("husks_down", husks_down))
	time = float(state.get("time", time))
	play_seconds = float(state.get("play_seconds", play_seconds))
	husks_left = int(state.get("husks_left", husks_left))
	hornets_left = int(state.get("hornets_left", hornets_left))
	queen_position = state.get("queen_position", queen_position)
	queen_state = int(state.get("queen_state", queen_state))
	queen_health = float(state.get("queen_health", queen_health))
	queen_carry = int(state.get("queen_carry", queen_carry))
	workers_alive = int(state.get("workers_alive", workers_alive))
	if cycle != null:
		cycle.set_time(time)
