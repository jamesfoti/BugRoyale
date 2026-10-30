class_name GhostSimulation
extends Node
## Far bots as ghosts. A bot nobody is near gives up its body: the ghost keeps the fighter's
## position and health, wanders the ground, and fights other ghosts by rolls, so the match's
## numbers (alive, scores, infections) stay honest while the cost of a body is paid only inside
## a bubble around the humans. When a human comes within the radius the body is put back where
## the ghost stands, with the health it has. Runs on the host; a mode opts in with uses_ghosts.

## A ghost's wander goal is picked at least this far from where it stands.
const TICK_SECONDS: float = 0.5
const GOAL_REACHED: float = 3.0
const CLEARANCE: float = 1.2

var map: MapInfo
var mode: GameMode
## Bodies within this distance of a human; ghosts beyond it plus the hysteresis band. Past the
## longest gun's reach (the spider's 90 m), so nothing in a scope ever blinks out.
var radius: float = 100.0
var hysteresis: float = 15.0
var ghost_speed: float = 4.0
## Two enemy ghosts within this range trade blows at this rate, give or take.
var fight_range: float = 20.0
var fight_damage_per_second: float = 6.0

## Wander goal per ghost fighter id.
var _goals: Dictionary = {}
var _accumulator: float = 0.0


func update(delta: float) -> void:
	_accumulator += delta
	if _accumulator < TICK_SECONDS:
		return
	_accumulator -= TICK_SECONDS
	_tick()


func ghost_count() -> int:
	var count: int = 0
	for fighter: Fighter in mode.fighters:
		if fighter.ghost:
			count += 1
	return count


func _tick() -> void:
	var humans: PackedVector3Array = PackedVector3Array()
	for human: Fighter in mode.humans():
		if human.is_alive():
			humans.append(human.get_position())
	var ghosts: Array[Fighter] = []
	for fighter: Fighter in mode.fighters:
		if not fighter.is_bot() or not fighter.is_valid():
			continue
		if fighter.ghost:
			if fighter.body.is_in_play():
				# Someone put the body back (a respawn, a husk rising): no longer a ghost.
				_forget(fighter)
			elif not fighter.health.is_alive():
				_forget(fighter)
			elif _nearest(humans, fighter.ghost_position) < radius:
				_embody(fighter)
			else:
				ghosts.append(fighter)
		elif fighter.is_alive() and _nearest(humans, fighter.get_position()) > radius + hysteresis:
			_make_ghost(fighter)
			ghosts.append(fighter)
	for ghost: Fighter in ghosts:
		_wander(ghost)
	_fight(ghosts)


func _make_ghost(fighter: Fighter) -> void:
	fighter.ghost = true
	fighter.ghost_position = fighter.body.global_position
	fighter.body.set_in_play(false)


func _embody(fighter: Fighter) -> void:
	fighter.body.place(fighter.ghost_position)
	fighter.ghost = false
	_goals.erase(fighter.id)
	if fighter.brain != null:
		fighter.brain.on_respawn()


func _forget(fighter: Fighter) -> void:
	fighter.ghost = false
	_goals.erase(fighter.id)


## A step toward the ghost's goal along the ground; a new goal when it gets there.
func _wander(fighter: Fighter) -> void:
	var goal: Vector3 = _goals.get(fighter.id, Vector3.INF)
	if goal == Vector3.INF or fighter.ghost_position.distance_to(goal) < GOAL_REACHED:
		goal = map.random_surface_point(CLEARANCE)
		_goals[fighter.id] = goal
	var up: Vector3 = map.up_at(fighter.ghost_position)
	var direction: Vector3 = (goal - fighter.ghost_position).slide(up)
	if direction.length_squared() < 0.0001:
		return
	var next: Vector3 = fighter.ghost_position + direction.normalized() * ghost_speed * TICK_SECONDS
	var ground: Dictionary = map.ground_hit(next)
	if not ground.is_empty():
		next = ground.position + map.up_at(ground.position) * CLEARANCE
	fighter.ghost_position = next
	# The hidden body rides along, so anything that reads it finds the ghost's spot.
	fighter.body.global_position = next


## Each ghost hits the nearest enemy ghost in range; damage goes through the health gate like
## any other, so deaths, scores and conversions follow as usual.
func _fight(ghosts: Array[Fighter]) -> void:
	var damage: float = fight_damage_per_second * TICK_SECONDS
	for attacker: Fighter in ghosts:
		var team: int = attacker.get_team()
		var nearest: Fighter = null
		var nearest_distance: float = fight_range
		for victim: Fighter in ghosts:
			if victim == attacker or (team != Damageable.NO_TEAM and victim.get_team() == team):
				continue
			var distance: float = attacker.ghost_position.distance_to(victim.ghost_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = victim
		if nearest != null and nearest.health.is_alive():
			nearest.health.apply_damage(damage * randf_range(0.5, 1.5), attacker.body)


static func _nearest(points: PackedVector3Array, from: Vector3) -> float:
	var best_sq: float = INF
	for point: Vector3 in points:
		best_sq = minf(best_sq, from.distance_squared_to(point))
	return sqrt(best_sq) if best_sq < INF else INF
