extends GameMode
## Burrow: survival on a map that keeps what is dug into it, played from the ground as the
## colony's soldier. It opens with the colony on the march: four workers carry the queen and
## follow you, and where you decide is good ground you give the word (found_colony, G) and they
## set her down and dig her chamber. Until then she rides in the open, and hornets go for her;
## lose the workers and she lies where she fell until you pick her up yourself. Once she is
## below, the burrow is yours. Days are for digging (a carve pays out what it removed, building
## with the pickaxe spends it) and for food: crumbs, seeds and sugar lie about the surface, the
## workers carry them to the entrance one at a time, and so can you. Every six food the queen
## lays an egg, one a day, which lies in the chamber and hatches a worker at the next dawn if
## it is still there. The colony can only be as big as the room dug for it: the founding four,
## plus one more for every forty cubic metres dug below the surface once the nest is done.
## Hornets hunt by day and by night: a few now and then through the day, more when the
## colony is loud, and more often after dark. They drift about the colony's patch and only
## dive at a bug that comes close; a forager carrying food is what they want most. Nights
## belong to the map besides: husks (bugs the fungus took)
## shambling for the burrow, and from the second night a raiding party of black ants from a
## rival colony, all gone at dawn. Days have their own danger once the colony is founded:
## trapdoor spiders lurk where the food lies, more of them as the days pass, and strike at
## whatever comes near, gone to ground at dusk. A worker that falls is gone for good,
## and its food lies where it fell; you are back at the burrow after a few seconds. The burrow
## is saved to disk with the ground it stands in (WorldSave) and is there, as left, next time.
## If the queen dies the colony is over.

enum Carry { NOBODY, WORKERS, YOU }

const MODE_ID: String = "burrow"
const TEAM: int = 0
const ENEMY_TEAM: int = 99
const PREY_GROUP: StringName = &"burrow_dwellers"
## A bug carrying food: the hornets' favourite.
const LADEN_GROUP: StringName = &"burrow_laden"
## The word to set the queen down.
const FOUND_ACTION: StringName = &"found_colony"

## Everything from here down is tuned from the editor: open modes/burrow.tscn, select the
## root and change what you like. These are the defaults; the scene saves only what differs.
@export_group("Match")
## Seconds a fallen soldier waits before it is back at the burrow, and how often the world is
## saved to disk.
@export var respawn_seconds: float = 4.0
@export var autosave_seconds: float = 30.0
@export_group("Hornets")
## Hornets come this often through a night (the director's finale timer), and this often
## through a day when nothing has stirred them (the director's lull), at this share of a
## night's number. Kept small for now: a few hornets, not a horde.
@export var night_horde_seconds: float = 90.0
@export var day_horde_seconds: float = 150.0
@export var day_horde_share: float = 0.5
## The first hornets of a day are out this soon after dawn (or the start), not a whole lull
## later.
@export var first_hornets_seconds: float = 40.0
## How many hornets a horde brings on the first night, how many more each night, and the most.
@export var horde_base: int = 2
@export var horde_growth: int = 1
@export var horde_max: int = 6
## How a Burrow hornet behaves, gentler than the director's defaults: it dives only at a bug
## within this distance, pulled this hard, at this speed, stinging for this much this often.
@export var hornet_detection: float = 14.0
@export var hornet_attack_weight: float = 1.4
@export var hornet_attack_speed: float = 14.0
@export var hornet_sting: float = 5.0
@export var hornet_sting_seconds: float = 2.0
@export_group("Husks")
## A husk's pace as a share of a soldier's, the most up at once, and how many come with each
## horde after dark.
@export var husk_speed: float = 0.8
@export var max_husks: int = 14
@export var husks_per_horde: int = 2
## Enemies set out at least this far from the burrow.
@export var spawn_min_distance: float = 30.0
@export_group("Raiders")
## The rival colony's raiders: from which night they come, how many on that night, how many
## more each night after, and the most at once. They come for the entrance with the colony's
## own guns.
@export var raiders_from_night: int = 2
@export var raider_base: int = 3
@export var raider_growth: int = 1
@export var raider_max: int = 10
@export_group("Spiders")
## Trapdoor spiders: from which day they lurk (one more every other day after), the most at
## once, how far off one notices a bug (it sits still at its spot until then), and its bite:
## an ambusher that lunges at what comes close, not the class's sniper rifle, so a forager
## that keeps its distance lives.
@export var spiders_from_day: int = 1
@export var spider_max: int = 4
@export var spider_detection: float = 8.0
@export var spider_bite_damage: float = 18.0
@export var spider_bite_cooldown: float = 1.5
@export var spider_bite_range: float = 2.5
@export_group("Colony")
## The colony on the march: this many workers, at this share of a soldier's pace while they
## carry. The rest is the brood's arithmetic (ColonyBrood): food per egg, eggs a day at most,
## and the room dug below the surface that each worker past the founding ones needs.
@export var starting_workers: int = ColonyBrood.STARTING_WORKERS
@export var worker_speed: float = 0.8
@export var food_per_egg: int = ColonyBrood.FOOD_PER_EGG
@export var eggs_per_day: int = ColonyBrood.EGGS_PER_DAY
@export var room_per_worker_m3: float = ColonyBrood.ROOM_PER_WORKER_M3
@export_group("Founding")
## How far from the queen a bug may be and still give the word to set her down, how uneven
## the ground around her may be, and how fast the workers dig once she is down (one carve per
## interval).
@export var found_radius: float = 20.0
@export var ground_spread_limit: float = 2.5
@export var ground_probe: float = 2.5
@export var dig_interval: float = 1.2
## A bug this close to a queen on the ground picks her up.
@export var pickup_radius: float = 1.6
@export_group("Food")
## Food: how many pieces lie on the surface at most (topped up at founding and every dawn),
## how near the entrance they start, how far out the workers forage on the first day and how
## much farther each day survived, how often the workers think about it, how close to the
## entrance a bug must come to hand its food in, how much a soldier can carry at once (a
## worker carries one), and the pace of a laden worker.
@export var food_on_map: int = 12
@export var food_min_distance: float = 12.0
@export var first_day_forage_radius: float = 35.0
@export var forage_radius_per_day: float = 10.0
@export var forage_think_seconds: float = 0.5
@export var deliver_radius: float = 3.5
@export var soldier_carry: int = 3
@export var laden_speed: float = 0.75
@export_group("Eggs")
## Eggs lie this far from the queen on the chamber floor. (How many hornet hits one takes is
## AntEgg.MAX_HEALTH.)
@export var egg_spread: float = 1.4
@export_group("")

var cycle: DayCycle
var director: HordeDirector
var stock: MaterialStock = MaterialStock.new()
var brood: ColonyBrood = ColonyBrood.new()
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
var raiders_left: int = 0
var spiders_left: int = 0
## The queen as the host last saw her, for the snapshot, the status line and the save: where
## she is (on the march: wherever she is carried; founded: the chamber floor), her state, her
## health, who carries her and how many workers are up.
var queen_position: Vector3 = Vector3.INF
var queen_state: int = QueenAnt.State.CARRIED
var queen_health: float = QueenAnt.MAX_HEALTH
var queen_carry: int = Carry.WORKERS
var workers_alive: int = 0
## Food in hand, by fighter id (a worker carries one at most).
var carried: Dictionary = {}

var queen: QueenAnt

var _map_id: String = ""
var _dwellers: Array[Fighter] = []
var _workers: Array[Fighter] = []
var _husks: Array[Fighter] = []
var _raiders: Array[Fighter] = []
var _spiders: Array[Fighter] = []
## Fighter -> seconds until it is back at the burrow.
var _respawn_timers: Dictionary = {}
var _home_beacon: Beacon
var _autosave_left: float = 0.0
var _restored: bool = false
## The human carrying the queen when no worker can (null otherwise).
var _human_bearer: Fighter
## The carves still to make for the queen's chamber, and the way down once they are made.
var _dig_plan: Array[Dictionary] = []
var _dig_timer: float = 0.0
var _settle_path: PackedVector3Array = PackedVector3Array()
var _settled_announced: bool = false
## The nest's carves are all made: digging below ground from here on is room for the colony.
var _nest_dug: bool = false
## Food on the map that a worker has set out for (material -> fighter id), and the think timer.
var _claims: Dictionary = {}
var _forage_timer: float = 0.0
var _eggs: Array[AntEgg] = []


## The editor's numbers reach the brood and the counters here: an exported value is set after the
## script's own initialisers ran, so nothing above may be copied from one until now.
func _ready() -> void:
	super()
	brood.starting_workers = starting_workers
	brood.food_per_egg = food_per_egg
	brood.eggs_per_day = eggs_per_day
	brood.room_per_worker_m3 = room_per_worker_m3
	workers_alive = starting_workers
	_autosave_left = autosave_seconds


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
		carried[human.id] = 0
		# Straight onto the saved spot: the restored ground's collision is still being rebuilt,
		# so a probe for the floor here would find yesterday's.
		human.respawn_at(anchor + map.up_at(anchor) * 1.0)
	stock.attach(terrain)
	if terrain != null:
		terrain.edit_applied.connect(_on_edit_applied)
	_spawn_queen(anchor)
	_spawn_workers(anchor)
	if founded:
		for _index: int in brood.eggs:
			_place_egg()
		_scatter_food()

	director = HordeDirector.new()
	director.name = "HordeDirector"
	director.setup(map, get_parent(), PREY_GROUP, ENEMY_TEAM)
	director.lull_seconds = day_horde_seconds
	director.lull_share = day_horde_share
	director.finale_seconds = night_horde_seconds
	director.horde_base = horde_base
	director.horde_growth = horde_growth
	director.horde_max = horde_max
	director.hordes = nights
	add_child(director)
	for dweller: Fighter in _dwellers:
		director.listen_to(dweller)
	director.listen_to_terrain()
	director.build_horde_flock()
	var flock: BirdFlock = director.horde_flock()
	flock.lure_group = LADEN_GROUP
	flock.attack_detection_radius = hornet_detection
	flock.attack_weight = hornet_attack_weight
	flock.max_attack_speed = hornet_attack_speed
	flock.attack_damage = hornet_sting
	flock.attack_cooldown = hornet_sting_seconds
	flock.bird_died.connect(func(_bird: Bird) -> void: swatted += 1)
	director.horde_sent.connect(_on_horde_sent)
	if cycle.is_night():
		director.start_finale()
	else:
		director.hasten_lull(first_hornets_seconds)
		if founded:
			_send_day_spiders()
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
				+ "and press G to found the colony there.\nHornets hunt by day; the husks come "
				+ "after dark."
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
		_forage_tick(delta)
		_tend_brood()
	else:
		_poll_found()
		for husk: Fighter in _husks:
			husk.brain.objective = queen_position
	husks_left = _count_alive(_husks)
	raiders_left = _count_alive(_raiders)
	spiders_left = _count_alive(_spiders)
	hornets_left = director.horde_flock().alive_count()
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		_autosave_left = autosave_seconds
		save_world()


func _on_fighter_died(fighter: Fighter) -> void:
	fighter.kill()
	if match_over:
		return
	_drop_food(fighter)
	if _dwellers.has(fighter):
		deaths += 1
		var where: String = "the burrow" if founded else "the colony"
		announce_to(fighter, "You're down. Back with %s in a moment..." % where, respawn_seconds)
		_respawn_timers[fighter] = respawn_seconds
	elif _workers.has(fighter):
		_release_claims(fighter)
		var up: int = _alive_workers().size()
		if founded:
			announce("A worker is down for good. %d left." % up, 3.0)
		else:
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
		_nest_dug = true
	else:
		queen.add_to_group(PREY_GROUP)


## The workers: unarmed ants at a carrier's pace. On the march they follow the local player
## (and the queen rides on them); founded, they forage by day from the entrance. A saved
## colony gets back the workers it had.
func _spawn_workers(anchor: Vector3) -> void:
	var count: int = workers_alive if founded else starting_workers
	for _index: int in count:
		if _spawn_worker(anchor) == null:
			return
	workers_alive = _alive_workers().size()


func _spawn_worker(anchor: Vector3) -> Fighter:
	var spot: Vector3 = map.ground_point_near(anchor, 1.5, 3.5, 1.2)
	var worker: Fighter = spawn_bot(
		LoadingScreen.PlayerCharacter.ANT_WARRIOR,
		TEAM,
		spot,
		CharacterSkin.BLACK_ANT_BOT_SCENE_PATH
	)
	if worker == null:
		return null
	worker.body.apply_hand_item(PlayerItems.Item.NONE)
	worker.body.scale_speed(worker_speed)
	worker.body.add_to_group(PREY_GROUP)
	worker.brain.weapon = {}
	worker.brain.detection_range = 0.0
	worker.brain.runs_to_keep_up = true
	carried[worker.id] = 0
	if founded:
		_send_home(worker)
	else:
		worker.brain.leader = local_fighter.body if local_fighter != null else null
	_workers.append(worker)
	return worker


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
				and human.get_position().distance_to(queen.global_position) < pickup_radius
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
	if fighter.get_position().distance_to(queen.global_position) > found_radius:
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
		var probe: Dictionary = map.ground_below(point + offset * ground_probe + up * 3.0, 9.0)
		if probe.is_empty():
			return "The ground falls away."
		var rise: float = (probe.position - point).dot(up)
		lowest = minf(lowest, rise)
		highest = maxf(highest, rise)
	if lowest < -ground_spread_limit * 2.0:
		return "The ground falls away."
	if highest - lowest > ground_spread_limit:
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
		_send_home(worker)
	_dig_timer = 0.8
	_scatter_food()
	if not cycle.is_night():
		_send_day_spiders()
	announce(
		(
			(
				"The colony is founded here. The workers dig the queen's chamber, then forage: "
				+ "every %d food is an egg."
			)
			% brood.food_per_egg
		),
		6.0
	)
	save_world()


## The workers dig the nest a carve at a time; when the last is made the queen goes below.
func _dig_tick(delta: float) -> void:
	if _dig_plan.is_empty():
		return
	_dig_timer -= delta
	if _dig_timer > 0.0:
		return
	_dig_timer = dig_interval
	var terrain: ChunkedTerrainWorld = map.editable_terrain()
	var carve: Dictionary = _dig_plan.pop_front()
	if terrain != null:
		terrain.apply_edit(carve)
	if _dig_plan.is_empty():
		_nest_dug = true
		queen.settle_along(_settle_path)
		announce("The chamber is dug. The queen goes below.", 4.0)


## Ground dug below the surface once the nest is done is room for the colony to grow into.
func _on_edit_applied(edit: Dictionary) -> void:
	if not founded or not _nest_dug or bool(edit.get("add", false)):
		return
	if str(edit.get("tool", "")) != TerrainBrush.PICKAXE_TOOL:
		return
	var position: Vector3 = edit.get("position", Vector3.INF)
	if position == Vector3.INF or map.altitude(position) > -0.5:
		return
	var voxels: int = 0
	var removed: Dictionary = edit.get("removed", {})
	for kind: int in removed:
		voxels += int(removed[kind])
	var terrain: ChunkedTerrainWorld = map.editable_terrain()
	var voxel_size: float = terrain.get_voxel_size() if terrain != null else 1.0
	brood.add_room(float(voxels) * voxel_size * voxel_size * voxel_size)


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


# --- Food and eggs -------------------------------------------------------------------------------


## How far from the entrance the workers forage today.
func forage_radius() -> float:
	return first_day_forage_radius + forage_radius_per_day * float(nights)


## Tops the surface up to food_on_map pieces, scattered within today's reach of the entrance.
func _scatter_food() -> void:
	if home == Vector3.INF:
		return
	var present: int = 0
	for node: Node in get_tree().get_nodes_in_group(ForageMaterial.GROUP):
		if node is ForageMaterial and not (node as ForageMaterial).is_taken():
			present += 1
	for index: int in food_on_map - present:
		var spot: Vector3 = map.ground_point_near(home, food_min_distance, forage_radius(), 0.4)
		_place_food(spot, index)


func _place_food(spot: Vector3, index: int) -> void:
	var kind: ForageMaterial.Kind = (index % ForageMaterial.Kind.size()) as ForageMaterial.Kind
	var food: ForageMaterial = ForageMaterial.spawn(get_parent(), spot, kind, map.up_at(spot))
	food.picked_up.connect(_on_food_picked_up)


func _on_food_picked_up(food: ForageMaterial, body: FighterBody) -> void:
	if not Authority.is_host() or food.is_taken() or match_over or not founded:
		return
	var fighter: Fighter = fighter_by_id(body.fighter_id)
	if fighter == null:
		return
	var in_hand: int = int(carried.get(fighter.id, 0))
	if _workers.has(fighter):
		if in_hand > 0:
			return
		food.take()
		_claims.erase(food)
		_set_carried(fighter, 1)
		_send_home(fighter, deliver_radius - 1.5)
	elif _dwellers.has(fighter):
		if in_hand >= soldier_carry:
			announce_to(fighter, "Your hands are full. Bring it to the entrance.", 2.0)
			return
		food.take()
		_claims.erase(food)
		_set_carried(fighter, in_hand + 1)
		announce_to(
			fighter,
			"Food %d/%d in hand. Bring it to the entrance." % [in_hand + 1, soldier_carry],
			2.0
		)


## Food in hand: a laden bug is slower (a worker) and what the hornets go for (anyone).
func _set_carried(fighter: Fighter, count: int) -> void:
	var before: int = int(carried.get(fighter.id, 0))
	carried[fighter.id] = count
	if not fighter.is_valid():
		return
	if count > 0 and not fighter.body.is_in_group(LADEN_GROUP):
		fighter.body.add_to_group(LADEN_GROUP)
	elif count == 0 and fighter.body.is_in_group(LADEN_GROUP):
		fighter.body.remove_from_group(LADEN_GROUP)
	if _workers.has(fighter):
		if before == 0 and count > 0:
			fighter.body.scale_speed(laden_speed)
		elif before > 0 and count == 0:
			fighter.body.scale_speed(1.0 / laden_speed)


## A fallen bug's food lands beside it for someone else to pick up.
func _drop_food(fighter: Fighter) -> void:
	var count: int = int(carried.get(fighter.id, 0))
	if count <= 0:
		return
	_set_carried(fighter, 0)
	for index: int in count:
		_place_food(map.ground_point_near(fighter.get_position(), 1.0, 2.5, 0.4), index)


## Twice a second: hands in the food of whoever is at the entrance, and gives each idle worker
## something to fetch (by day, within reach, one worker per piece) or sends it home.
func _forage_tick(delta: float) -> void:
	for fighter: Fighter in _dwellers + _workers:
		if int(carried.get(fighter.id, 0)) > 0 and fighter.is_alive() and _at_entrance(fighter):
			_hand_in(fighter)
	_forage_timer -= delta
	if _forage_timer > 0.0:
		return
	_forage_timer = forage_think_seconds
	for food: Variant in _claims.keys():
		if not is_instance_valid(food) or (food as ForageMaterial).is_taken():
			_claims.erase(food)
	var night: bool = cycle.is_night()
	for worker: Fighter in _alive_workers():
		if int(carried.get(worker.id, 0)) > 0:
			_send_home(worker, deliver_radius - 1.5)
			continue
		var claimed: ForageMaterial = _claim_of(worker)
		if night:
			if claimed != null:
				_claims.erase(claimed)
			_send_home(worker)
			continue
		if claimed == null:
			claimed = _nearest_free_food(worker)
			if claimed != null:
				_claims[claimed] = worker.id
		if claimed == null:
			_send_home(worker)
		else:
			worker.brain.objective = claimed.global_position
			worker.brain.objective_radius = 0.6


func _at_entrance(fighter: Fighter) -> bool:
	return fighter.get_position().distance_to(home) <= deliver_radius


func _hand_in(fighter: Fighter) -> void:
	var count: int = int(carried.get(fighter.id, 0))
	brood.deliver(count)
	_set_carried(fighter, 0)
	if _dwellers.has(fighter):
		announce_to(fighter, "%d food handed in. %s" % [count, brood.text()], 2.5)


## Idle workers keep to the entrance; a laden one comes right up to it to hand in.
func _send_home(worker: Fighter, radius: float = 5.0) -> void:
	worker.brain.objective = home
	worker.brain.objective_radius = radius


func _claim_of(worker: Fighter) -> ForageMaterial:
	for food: Variant in _claims:
		if int(_claims[food]) == worker.id:
			return food as ForageMaterial
	return null


func _release_claims(worker: Fighter) -> void:
	for food: Variant in _claims.keys():
		if int(_claims[food]) == worker.id:
			_claims.erase(food)


## The nearest food within today's reach of the entrance that no other worker is fetching.
func _nearest_free_food(worker: Fighter) -> ForageMaterial:
	var best: ForageMaterial = null
	var best_distance: float = INF
	var reach: float = forage_radius()
	var from: Vector3 = worker.get_position()
	for node: Node in get_tree().get_nodes_in_group(ForageMaterial.GROUP):
		var food: ForageMaterial = node as ForageMaterial
		if food == null or food.is_taken() or _claims.has(food):
			continue
		if food.global_position.distance_to(home) > reach:
			continue
		var distance: float = from.distance_to(food.global_position)
		if distance < best_distance:
			best_distance = distance
			best = food
	return best


## The queen lays when the food is there, the day's egg is not yet laid and the room allows.
func _tend_brood() -> void:
	if queen == null or queen.state != QueenAnt.State.SETTLED:
		return
	if brood.lay(workers_alive):
		_place_egg()
		announce("The queen has laid an egg. It hatches at dawn.", 4.0)


func _place_egg() -> void:
	if queen_position == Vector3.INF:
		return
	var up: Vector3 = map.up_at(queen_position)
	var side: Vector3 = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD)
	side = side.normalized().rotated(up, randf_range(0.0, TAU))
	var egg: AntEgg = AntEgg.spawn(get_parent(), queen_position + side * egg_spread, up, TEAM)
	egg.add_to_group(PREY_GROUP)
	egg.health.died.connect(_on_egg_died.bind(egg))
	_eggs.append(egg)


func _on_egg_died(egg: AntEgg) -> void:
	if match_over or not _eggs.has(egg):
		return
	_eggs.erase(egg)
	egg.queue_free()
	brood.lose_egg()
	announce("An egg was destroyed.", 3.0)


## Dawn: the eggs hatch into workers at the entrance.
func _hatch() -> void:
	var hatched: int = brood.dawn()
	for egg: AntEgg in _eggs:
		if is_instance_valid(egg):
			egg.queue_free()
	_eggs.clear()
	for _index: int in hatched:
		_spawn_worker(home)
	workers_alive = _alive_workers().size()
	if hatched == 1:
		announce("An egg hatched: a new worker joins the colony.", 4.0)
	elif hatched > 1:
		announce("%d eggs hatched: new workers join the colony." % hatched, 4.0)


# --- Night and day -----------------------------------------------------------------------------


func _on_dusk() -> void:
	director.start_finale()
	for _index: int in mini(2 + nights * 2, max_husks):
		_send_husk()
	_retire(_spiders)
	if founded and nights + 1 >= raiders_from_night:
		var party: int = mini(
			raider_base + raider_growth * (nights + 1 - raiders_from_night), raider_max
		)
		var from: Vector3 = _far_point()
		for _index: int in party:
			_send_raider(from)
		announce(
			"Night %d falls. A raiding party from the black colony is out." % (nights + 1), 4.0
		)
	else:
		announce("Night %d falls. They're coming." % (nights + 1), 4.0)


func _on_dawn() -> void:
	nights += 1
	director.stop_finale()
	director.disperse_hordes()
	for husk: Fighter in _husks:
		if husk.is_alive():
			husk.health.apply_damage(husk.health.max_health * 10.0)
	_retire(_raiders)
	announce("Dawn. Night %d survived; the husks crumble in the light." % nights, 4.0)
	director.hasten_lull(first_hornets_seconds)
	if founded:
		_hatch()
		_scatter_food()
		_send_day_spiders()
	save_world()


## The day's spiders dig in among the food: one from the first day, one more every other
## day after, up to spider_max.
func _send_day_spiders() -> void:
	if nights + 1 < spiders_from_day:
		return
	for _index: int in mini(1 + floori((nights + 1 - spiders_from_day) / 2.0), spider_max):
		_send_spider()
	announce("Trapdoor spiders have dug in among the food. Watch the foragers.", 4.0)


func _on_horde_sent(_count: int, reason: HordeDirector.Reason) -> void:
	match reason:
		HordeDirector.Reason.NOISE:
			announce("They heard you!", 3.0)
		HordeDirector.Reason.FINALE:
			announce("Hornets in the dark!", 3.0)
			for _index: int in husks_per_horde:
				if husks_left < max_husks:
					_send_husk()
		_:
			announce("Hornets overhead!", 3.0)


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
		husk.brain.become_husk(ENEMY_TEAM, husk_speed)
		_husks.append(husk)
	else:
		husk.respawn_at(spot)
		husk.brain.become_husk(ENEMY_TEAM, husk_speed)
	husk.brain.detection_range = 120.0
	husk.brain.objective = home if founded else queen_position
	husk.brain.objective_radius = 4.0
	husk.hold_fire(2.0)
	husks_left += 1


## A black ant from the rival colony, armed like a soldier, setting out from one point with the
## rest of its party for the entrance; a dead one from an earlier night is sent back out first.
func _send_raider(from: Vector3) -> void:
	var spot: Vector3 = map.ground_point_near(from, 0.0, 6.0, 1.2)
	var raider: Fighter = _retired_one(_raiders)
	if raider == null:
		raider = spawn_bot(
			LoadingScreen.PlayerCharacter.ANT_WARRIOR,
			ENEMY_TEAM,
			spot,
			CharacterSkin.BLACK_ANT_BOT_SCENE_PATH
		)
		if raider == null:
			return
		raider.brain.target_group = &"fighter"
		_raiders.append(raider)
	else:
		raider.respawn_at(spot)
	raider.brain.detection_range = 60.0
	raider.brain.objective = home
	raider.brain.objective_radius = 6.0
	raider.brain.objective_focus = 30.0
	raider.hold_fire(2.0)


## A trapdoor spider dug in among the food: it sits at its spot and strikes at whatever comes
## within spider_detection, and bites.
func _send_spider() -> void:
	var spot: Vector3 = map.ground_point_near(home, food_min_distance, forage_radius(), 1.2)
	var spider: Fighter = _retired_one(_spiders)
	if spider == null:
		spider = spawn_bot(LoadingScreen.PlayerCharacter.TRAPDOOR_SPIDER, ENEMY_TEAM, spot)
		if spider == null:
			return
		spider.brain.target_group = &"fighter"
		_spiders.append(spider)
	else:
		spider.respawn_at(spot)
	spider.brain.detection_range = spider_detection
	spider.brain.weapon = {
		"melee": true,
		"damage": spider_bite_damage,
		"cooldown": spider_bite_cooldown,
		"range": spider_bite_range,
	}
	spider.brain.objective = spot
	spider.brain.objective_radius = 1.5
	spider.brain.objective_focus = spider_detection


## A dead body in a pool, ready to be sent out again (null when every one is up).
func _retired_one(pool: Array[Fighter]) -> Fighter:
	for candidate: Fighter in pool:
		if not candidate.is_alive() and candidate.is_valid():
			return candidate
	return null


## The enemies of a pool leave the map (dawn for the raiders, dusk for the spiders).
func _retire(pool: Array[Fighter]) -> void:
	for fighter: Fighter in pool:
		if fighter.is_alive():
			fighter.kill()


func _count_alive(pool: Array[Fighter]) -> int:
	var count: int = 0
	for fighter: Fighter in pool:
		if fighter.is_alive():
			count += 1
	return count


## A ground point well away from the colony (the first of several tries that manages it).
func _far_point() -> Vector3:
	var anchor: Vector3 = home if founded else queen_position
	var best: Vector3 = map.random_surface_point(0.0)
	var best_distance: float = best.distance_to(anchor)
	for _attempt: int in 10:
		var candidate: Vector3 = map.random_surface_point(0.0)
		var distance: float = candidate.distance_to(anchor)
		if distance >= spawn_min_distance:
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
	else:
		summary += "  ·  %d worker%s" % [workers_alive, "" if workers_alive == 1 else "s"]
	WorldSave.save(
		MODE_ID, _map_id, LoadingScreen.last_terrain_seed, terrain_state, _snapshot_state(), summary
	)


# --- Showing ----------------------------------------------------------------------------------


func _status_text() -> String:
	var change: String = DayCycle.clock_text(DayCycle.seconds_to_change_at(time))
	var night: bool = DayCycle.is_night_at(time)
	if not founded:
		var carry: String = "The queen is down"
		if queen_carry == Carry.WORKERS:
			carry = "The workers carry the queen"
		elif queen_carry == Carry.YOU:
			carry = "You carry the queen"
		return (
			"%s  ·  %s to %s  ·  Workers %d  ·  Queen %d%%  ·  G: found the colony here"
			% [
				carry,
				change,
				"dawn" if night else "dusk",
				workers_alive,
				roundi(queen_health / QueenAnt.MAX_HEALTH * 100.0)
			]
		)
	var workers_text: String = "Workers %d/%d" % [workers_alive, brood.capacity()]
	if night:
		var enemies: String = "Husks %d  ·  Hornets %d" % [husks_left, hornets_left]
		if raiders_left > 0:
			enemies += "  ·  Raiders %d" % raiders_left
		return (
			"Night %d  ·  %s to dawn  ·  %s  ·  %s  ·  %s  ·  Deaths %d"
			% [nights + 1, change, enemies, brood.text(), workers_text, deaths]
		)
	var day_text: String = "Day %d  ·  %s to dusk" % [nights + 1, change]
	if hornets_left > 0:
		day_text += "  ·  Hornets %d" % hornets_left
	if spiders_left > 0:
		day_text += "  ·  Spiders %d" % spiders_left
	return (
		"%s  ·  %s  ·  %s  ·  %s  ·  Deaths %d"
		% [day_text, brood.text(), stock.text(), workers_text, deaths]
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
		"brood": brood.export_state(),
		"nights": nights,
		"deaths": deaths,
		"swatted": swatted,
		"husks_down": husks_down,
		"time": time,
		"play_seconds": play_seconds,
		"husks_left": husks_left,
		"hornets_left": hornets_left,
		"raiders_left": raiders_left,
		"spiders_left": spiders_left,
		"queen_position": queen_position,
		"queen_state": queen_state,
		"queen_health": queen_health,
		"queen_carry": queen_carry,
		"workers_alive": workers_alive,
		"carried": carried.duplicate(),
	}


func _apply_state(state: Dictionary) -> void:
	home = state.get("home", home)
	founded = bool(state.get("founded", founded))
	if state.has("stock"):
		stock.import_counts(state["stock"])
	if state.has("brood"):
		brood.import_state(state["brood"])
	nights = int(state.get("nights", nights))
	deaths = int(state.get("deaths", deaths))
	swatted = int(state.get("swatted", swatted))
	husks_down = int(state.get("husks_down", husks_down))
	time = float(state.get("time", time))
	play_seconds = float(state.get("play_seconds", play_seconds))
	husks_left = int(state.get("husks_left", husks_left))
	hornets_left = int(state.get("hornets_left", hornets_left))
	raiders_left = int(state.get("raiders_left", raiders_left))
	spiders_left = int(state.get("spiders_left", spiders_left))
	queen_position = state.get("queen_position", queen_position)
	queen_state = int(state.get("queen_state", queen_state))
	queen_health = float(state.get("queen_health", queen_health))
	queen_carry = int(state.get("queen_carry", queen_carry))
	workers_alive = int(state.get("workers_alive", workers_alive))
	if state.has("carried"):
		carried = {}
		for fighter_id: Variant in state["carried"]:
			carried[int(fighter_id)] = int(state["carried"][fighter_id])
	if cycle != null:
		cycle.set_time(time)
