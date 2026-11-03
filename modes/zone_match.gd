class_name ZoneMatch
extends ColonyMatch
## Base for the modes played over control zones (King of the Anthill, Nests, Total Control,
## Land Grab): places the zones, updates who holds them every frame, points bots at the zone
## their team needs most, and snapshots the owners for a client to draw.

const ZONE_RADIUS: float = 6.0
const ZONE_GAP: float = 30.0

var zones: Array[ControlZone] = []
## Per zone, for a client: owner teams and where they stand.
var zone_owners: Array[int] = []
var zone_points: Array[Vector3] = []


## How many zones the mode plays over.
func _zone_count() -> int:
	return 3


func _place_objectives() -> void:
	for index: int in _zone_count():
		var zone: ControlZone = ControlZone.place(
			get_parent(), map, open_point(zone_points, ZONE_GAP), ZONE_RADIUS, color_of_team
		)
		zone.captured.connect(_on_zone_captured)
		zones.append(zone)
		zone_points.append(zone.global_position)
		zone_owners.append(ControlZone.NEUTRAL)


func _objective_tick(delta: float) -> void:
	for index: int in zones.size():
		zones[index].update(occupants_of(zones[index]), delta)
		zone_owners[index] = zones[index].owner_team


## A zone changed hands (modes score or lock it here).
func _on_zone_captured(_zone: ControlZone, _team: int) -> void:
	pass


## Moves a zone to fresh ground and forgets who held it.
func _relocate(zone: ControlZone) -> void:
	var index: int = zones.find(zone)
	var others: Array[Vector3] = zone_points.duplicate()
	others.remove_at(index)
	var point: Vector3 = open_point(others, ZONE_GAP)
	zone.reset()
	zone.move_to(point)
	zone_points[index] = point
	zone_owners[index] = ControlZone.NEUTRAL


func zones_owned_by(team: int) -> int:
	var count: int = 0
	for zone: ControlZone in zones:
		if zone.owner_team == team:
			count += 1
	return count


## The nearest zone the bot's team does not hold (and could take), else the nearest held one.
func _bot_objective(bot: Fighter) -> Vector3:
	var team: int = bot.get_team()
	var best: Vector3 = Vector3.INF
	var best_distance: float = INF
	var fallback: Vector3 = Vector3.INF
	var fallback_distance: float = INF
	for zone: ControlZone in zones:
		var distance: float = bot.get_position().distance_to(zone.global_position)
		if zone.owner_team != team and not zone.locked:
			if distance < best_distance:
				best_distance = distance
				best = zone.global_position
		elif distance < fallback_distance:
			fallback_distance = distance
			fallback = zone.global_position
	return best if best != Vector3.INF else fallback


func _zone_summary() -> String:
	if is_solo():
		var owner: int = zones[0].owner_team if not zones.is_empty() else ControlZone.NEUTRAL
		return "Held by %s" % name_of_team(owner) if owner != ControlZone.NEUTRAL else "Unclaimed"
	return "Zones: Red %d · Black %d" % [zones_owned_by(0), zones_owned_by(1)]


func _objective_snapshot() -> Dictionary:
	return {"zone_owners": zone_owners.duplicate(), "zone_points": zone_points.duplicate()}


func _objective_apply(state: Dictionary) -> void:
	if state.has("zone_owners"):
		zone_owners.assign(state["zone_owners"])
	if state.has("zone_points"):
		zone_points.assign(state["zone_points"])
