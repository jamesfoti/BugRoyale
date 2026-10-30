extends GameMode
## Forage: extraction. A squad of four (humans plus AI squadmates) is flown onto hostile ground
## by a dragonfly, gathers materials (crumbs, sugar, seeds) scattered over the map, and rides the
## dragonfly out again from the extraction beacon. The ground is held by hornet nests and husks:
## a handful in any one place. But every shot, blast, dig and sprint feeds the director's noise
## meter, and when it fills a horde comes for the squad (inspired by State of Decay's noise and
## Left 4 Dead's pacing), and one comes anyway after a long lull. Once the quota is gathered, or
## time runs out, the dragonfly heads for the beacon and hovers for a short window while hordes
## keep coming: whoever is aboard when it leaves is out. What a bug carries drops where it falls.
## No respawns.

enum Phase { INSERTION, FORAGE, INBOUND, BOARDING, LEAVING, DONE }

const SQUAD_TEAM: int = 0
const ENEMY_TEAM: int = 99
const SQUAD_SIZE: int = 4
const PREY_GROUP: StringName = &"forage_squad"
const MATERIALS: int = 18
const QUOTA: int = 10
const MATCH_SECONDS: float = 420.0
## How long the dragonfly waits at the beacon, and how close a bug must be to climb aboard.
const BOARDING_SECONDS: float = 35.0
const BOARD_RADIUS: float = 6.0
## The dragonfly appears and leaves this far out at most (big maps would make the ride a slog).
const APPROACH_DISTANCE: float = 90.0
## Hornet nests on the ground at the drop, hornets per nest, and husks shambling about.
const NESTS: int = 4
const NEST_HORNETS: int = 5
const HUSKS: int = 8
const HUSK_SPEED: float = 0.75
## Enemies keep at least this far from the landing zone at the drop.
const QUIET_RADIUS: float = 28.0
const NOISE_CELLS: int = 6

var squad: Squad
var director: HordeDirector
var dragonfly: Dragonfly
var phase: Phase = Phase.INSERTION
## Materials safe aboard the dragonfly, and carried per fighter id.
var banked: int = 0
var carried: Dictionary = {}
## The director's meter and horde count, mirrored here for the snapshot and the status line.
var noise: float = 0.0
var hordes: int = 0
var time_left: float = MATCH_SECONDS
var window_left: float = 0.0
## Fighter ids aboard the dragonfly (hidden, carried with it, not targetable).
var aboard: Array[int] = []
var landing_zone: Vector3 = Vector3.INF
var extraction: Vector3 = Vector3.INF

var _beacon: MeshInstance3D
var _leave_timer: float = 0.0

# --- Deciding ---------------------------------------------------------------------------------


func _start_match() -> void:
	landing_zone = map.random_surface_point(0.0)
	extraction = _far_surface_point(landing_zone, 10)
	squad = Squad.fill(
		self, SQUAD_TEAM, PREY_GROUP, SQUAD_SIZE, func() -> Vector3: return landing_zone
	)
	for bot: Fighter in squad.bots():
		bot.brain.target_group = &"fighter"
		bot.brain.secondary_target_group = &"bird"
		bot.brain.gather_group = ForageMaterial.GROUP
		bot.brain.detection_range = 40.0
	for member: Fighter in squad.members:
		carried[member.id] = 0

	director = HordeDirector.new()
	director.name = "HordeDirector"
	director.setup(map, get_parent(), PREY_GROUP, ENEMY_TEAM)
	add_child(director)
	for member: Fighter in squad.members:
		director.listen_to(member)
	director.listen_to_terrain()
	director.horde_sent.connect(_on_horde_sent)
	_scatter_materials()
	_place_enemies()

	dragonfly = Dragonfly.new()
	dragonfly.name = "Dragonfly"
	dragonfly.map = map
	get_parent().add_child(dragonfly)
	dragonfly.arrived.connect(_on_dragonfly_arrived)
	dragonfly.departed.connect(_on_dragonfly_departed)
	for member: Fighter in squad.members:
		_board(member)
	dragonfly.fly_in(_sky_edge(landing_zone), landing_zone)
	announce(
		(
			(
				"Forage\nGather %d materials, then make for the green beacon.\n"
				+ "Stay quiet: noise brings the horde."
			)
			% QUOTA
		),
		6.0
	)


func _update_match(delta: float) -> void:
	if match_over:
		return
	if phase != Phase.INSERTION and _squad_standing() == 0:
		end_match("Overrun!", "Nobody made it out. %d materials gathered." % _gathered())
		return
	match phase:
		Phase.FORAGE:
			time_left = maxf(time_left - delta, 0.0)
			_run_director(delta)
			if _gathered() >= QUOTA:
				_call_dragonfly("Quota met! The dragonfly is heading for the beacon.")
			elif time_left <= 0.0:
				_call_dragonfly("Time's up: last flight out. Get to the beacon!")
		Phase.INBOUND:
			_run_director(delta)
		Phase.BOARDING:
			_run_director(delta)
			window_left = maxf(window_left - delta, 0.0)
			_board_nearby()
			if window_left <= 0.0 or _everyone_standing_is_aboard():
				_leave()
		Phase.LEAVING:
			_leave_timer -= delta
			if _leave_timer <= 0.0:
				_on_dragonfly_departed()


func _physics_process(_delta: float) -> void:
	if dragonfly == null or not is_instance_valid(dragonfly) or aboard.is_empty():
		return
	var seat: Vector3 = dragonfly.seat_point()
	for fighter_id: int in aboard:
		var fighter: Fighter = fighter_by_id(fighter_id)
		if fighter != null and fighter.is_valid():
			fighter.body.global_position = seat


func _on_fighter_died(fighter: Fighter) -> void:
	fighter.kill()
	if match_over or squad == null or not squad.has(fighter):
		return
	_drop_carried(fighter)
	announce_to(fighter, "You're down.", 3.0)


func _run_director(delta: float) -> void:
	director.tick(delta, squad.members)
	noise = director.noise
	hordes = director.hordes


func _on_horde_sent(_count: int, reason: HordeDirector.Reason) -> void:
	match reason:
		HordeDirector.Reason.NOISE:
			announce("They heard you!", 3.0)
		HordeDirector.Reason.LULL:
			announce("A horde is coming!", 3.0)
		HordeDirector.Reason.FINALE:
			announce("The horde is on the beacon!", 3.0)


# --- The squad ---------------------------------------------------------------------------------


## Squad members still in the match: on the ground alive, or aboard.
func _squad_standing() -> int:
	if squad == null:
		return 0
	var count: int = 0
	for fighter: Fighter in squad.members:
		if fighter.is_alive() or aboard.has(fighter.id):
			count += 1
	return count


func _everyone_standing_is_aboard() -> bool:
	for fighter: Fighter in squad.members:
		if fighter.is_alive() and not aboard.has(fighter.id):
			return false
	return true


## Hidden, carried under the dragonfly, off the hornets' menu; what it carries is banked.
func _board(fighter: Fighter) -> void:
	if aboard.has(fighter.id):
		return
	aboard.append(fighter.id)
	banked += int(carried.get(fighter.id, 0))
	carried[fighter.id] = 0
	squad.leave(fighter)
	fighter.body.set_in_play(false)
	if dragonfly != null:
		fighter.body.global_position = dragonfly.seat_point()


## Back on the ground near a point.
func _drop_off(fighter: Fighter, point: Vector3) -> void:
	aboard.erase(fighter.id)
	fighter.respawn_at(map.ground_point_near(point, 2.0, 4.5, 1.2))
	squad.rejoin(fighter)


## Anyone alive and close to the hovering dragonfly climbs aboard.
func _board_nearby() -> void:
	for fighter: Fighter in squad.members:
		if not fighter.is_alive() or aboard.has(fighter.id):
			continue
		var offset: Vector3 = fighter.get_position() - extraction
		var up: Vector3 = map.up_at(extraction)
		if offset.slide(up).length() <= BOARD_RADIUS and absf(offset.dot(up)) <= 4.0:
			_board(fighter)
			announce_to(fighter, "Aboard! Hold on.", 2.5)


# --- Materials ---------------------------------------------------------------------------------


func _scatter_materials() -> void:
	var taken: Array[Vector3] = []
	for index: int in MATERIALS:
		var spot: Vector3 = _spread_point(taken, 5.0, 0.4)
		_place_material(spot, index)


func _place_material(spot: Vector3, index: int) -> void:
	var kind: ForageMaterial.Kind = (index % ForageMaterial.Kind.size()) as ForageMaterial.Kind
	var material: ForageMaterial = ForageMaterial.spawn(get_parent(), spot, kind, map.up_at(spot))
	material.picked_up.connect(_on_material_picked_up)


func _on_material_picked_up(material: ForageMaterial, body: FighterBody) -> void:
	if not Authority.is_host() or material.is_taken() or match_over:
		return
	var fighter: Fighter = fighter_by_id(body.fighter_id)
	if fighter == null or not squad.has(fighter):
		return
	material.take()
	carried[fighter.id] = int(carried.get(fighter.id, 0)) + 1
	announce_to(fighter, "Material %d/%d" % [_gathered(), QUOTA], 1.5)


func _gathered() -> int:
	var total: int = banked
	for fighter_id: int in carried:
		total += int(carried[fighter_id])
	return total


## A fallen bug's materials land beside it for someone else to pick up.
func _drop_carried(fighter: Fighter) -> void:
	var count: int = int(carried.get(fighter.id, 0))
	carried[fighter.id] = 0
	for index: int in count:
		_place_material(map.ground_point_near(fighter.get_position(), 1.0, 2.5, 0.4), index)


# --- Enemies -----------------------------------------------------------------------------------


func _place_enemies() -> void:
	for _index: int in NESTS:
		director.add_nest(_far_surface_point(landing_zone, 8, QUIET_RADIUS), NEST_HORNETS)
	director.build_horde_flock()
	var classes: Array = LoadingScreen.PlayerCharacter.values()
	for _index: int in HUSKS:
		var spot: Vector3 = _far_surface_point(landing_zone, 6, QUIET_RADIUS)
		var character: LoadingScreen.PlayerCharacter = classes[randi() % classes.size()]
		var husk: Fighter = spawn_bot(character, ENEMY_TEAM, spot)
		if husk == null:
			continue
		husk.brain.target_group = &"fighter"
		husk.brain.become_husk(ENEMY_TEAM, HUSK_SPEED)
		husk.brain.detection_range = 30.0


# --- The dragonfly -----------------------------------------------------------------------------


func _on_dragonfly_arrived() -> void:
	match phase:
		Phase.INSERTION:
			for fighter: Fighter in squad.members:
				_drop_off(fighter, landing_zone)
			announce("Go! Go! Go!", 2.0)
			dragonfly.fly_out(_sky_edge(landing_zone))
			phase = Phase.FORAGE
		Phase.INBOUND:
			phase = Phase.BOARDING
			window_left = BOARDING_SECONDS
			director.start_finale()
			announce("The dragonfly is on the beacon. Climb aboard!", 3.0)


func _call_dragonfly(message: String) -> void:
	phase = Phase.INBOUND
	announce(message, 4.0)
	dragonfly.fly_in(_sky_edge(extraction), extraction)


func _leave() -> void:
	phase = Phase.LEAVING
	_leave_timer = 8.0
	director.stop_finale()
	announce("The dragonfly is leaving!", 3.0)
	dragonfly.fly_out(_sky_edge(extraction))


func _on_dragonfly_departed() -> void:
	if phase != Phase.LEAVING or match_over:
		return
	phase = Phase.DONE
	var out: int = aboard.size()
	var haul: String = "%d materials brought home." % banked
	if local_fighter != null and aboard.has(local_fighter.id):
		end_match("Extracted!", "%d of %d made it out. %s" % [out, SQUAD_SIZE, haul])
	elif is_local_alive():
		end_match("Left behind", "The dragonfly left with %d of your squad. %s" % [out, haul])
	else:
		end_match("You didn't make it", "%d of %d extracted. %s" % [out, SQUAD_SIZE, haul])


## A sky point in a random direction from a ground point, at the edge of the map or
## APPROACH_DISTANCE out on a big one: where the dragonfly appears from and leaves through.
func _sky_edge(from: Vector3) -> Vector3:
	var up: Vector3 = map.up_at(from)
	var direction: Vector3 = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD)
	direction = direction.rotated(up, randf_range(0.0, TAU)).normalized()
	if map.kind == MapInfo.Kind.CELESTIAL_BODY:
		var radial: Vector3 = (from - map.body_center).normalized()
		var axis: Vector3 = radial.cross(direction).normalized()
		return map.body_center + radial.rotated(axis, deg_to_rad(55.0)) * map.body_radius
	var edge: Vector3 = map.clamp_to_bounds(from + direction * 1000.0)
	if edge.distance_to(from) > APPROACH_DISTANCE:
		edge = from + direction * APPROACH_DISTANCE
	return edge


# --- Points on the map -------------------------------------------------------------------------


## A random ground point at least min_distance from a point (the first candidate that manages
## it), else the farthest of the tries. With no minimum: the farthest of the tries.
func _far_surface_point(from: Vector3, tries: int, min_distance: float = 0.0) -> Vector3:
	var best: Vector3 = map.random_surface_point(0.0)
	var best_distance: float = best.distance_to(from)
	for _attempt: int in tries:
		var candidate: Vector3 = map.random_surface_point(0.0)
		var distance: float = candidate.distance_to(from)
		if min_distance > 0.0 and distance >= min_distance:
			return candidate
		if distance > best_distance:
			best_distance = distance
			best = candidate
	return best


## A ground point keeping a gap from the ones already taken (the best of a few).
func _spread_point(taken: Array[Vector3], gap: float, clearance: float) -> Vector3:
	var best: Vector3 = map.random_surface_point(clearance)
	var best_gap: float = -1.0
	for _attempt: int in 6:
		var candidate: Vector3 = map.random_surface_point(clearance)
		var nearest: float = INF
		for other: Vector3 in taken:
			nearest = minf(nearest, candidate.distance_to(other))
		if nearest > best_gap:
			best_gap = nearest
			best = candidate
		if nearest >= gap:
			break
	taken.append(best)
	return best


# --- Showing ----------------------------------------------------------------------------------


func _status_text() -> String:
	var squad_line: String = "Squad %d/%d" % [_squad_standing(), SQUAD_SIZE]
	var materials: String = "Materials %d/%d" % [_gathered(), QUOTA]
	var noise_bar: String = HordeDirector.noise_bar(noise, NOISE_CELLS)
	match phase:
		Phase.INSERTION:
			return "Forage  ·  Dragonfly inbound  ·  %s" % squad_line
		Phase.FORAGE:
			return (
				"%s  ·  Noise [%s]  ·  Hordes %d  ·  %s  ·  %d:%02d"
				% [
					materials,
					noise_bar,
					hordes,
					squad_line,
					floori(time_left / 60.0),
					int(time_left) % 60,
				]
			)
		Phase.INBOUND:
			return (
				"%s  ·  Noise [%s]  ·  %s  ·  Dragonfly heading for the beacon"
				% [materials, noise_bar, squad_line]
			)
		Phase.BOARDING:
			return (
				"%s  ·  %s  ·  Board now! %ds  ·  Aboard %d"
				% [materials, squad_line, ceili(window_left), aboard.size()]
			)
	return "%s  ·  Dragonfly leaving  ·  Aboard %d" % [materials, aboard.size()]


func _present() -> void:
	super()
	if _beacon == null and extraction != Vector3.INF and map != null:
		_build_beacon()


## A tall green column of light over the extraction point.
func _build_beacon() -> void:
	var column := CylinderMesh.new()
	column.top_radius = 2.5
	column.bottom_radius = 2.5
	column.height = 60.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 1.0, 0.5, 0.22)
	material.emission_enabled = true
	material.emission = Color(0.3, 1.0, 0.5)
	material.emission_energy_multiplier = 1.5
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	column.material = material
	_beacon = MeshInstance3D.new()
	_beacon.name = "ExtractionBeacon"
	_beacon.mesh = column
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(_beacon)
	var up: Vector3 = map.up_at(extraction)
	var side: Vector3 = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD)
	_beacon.global_transform = Transform3D(
		Basis(side.normalized(), up, side.cross(up).normalized()), extraction + up * 30.0
	)


func _snapshot_state() -> Dictionary:
	return {
		"phase": phase,
		"banked": banked,
		"carried": carried.duplicate(),
		"noise": noise,
		"hordes": hordes,
		"time_left": time_left,
		"window_left": window_left,
		"aboard": aboard.duplicate(),
		"landing_zone": landing_zone,
		"extraction": extraction,
	}


func _apply_state(state: Dictionary) -> void:
	phase = int(state.get("phase", phase)) as Phase
	banked = int(state.get("banked", banked))
	if state.has("carried"):
		carried = (state["carried"] as Dictionary).duplicate()
	noise = float(state.get("noise", noise))
	hordes = int(state.get("hordes", hordes))
	time_left = float(state.get("time_left", time_left))
	window_left = float(state.get("window_left", window_left))
	if state.has("aboard"):
		aboard.assign(state["aboard"])
	landing_zone = state.get("landing_zone", landing_zone)
	extraction = state.get("extraction", extraction)
