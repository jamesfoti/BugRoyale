extends ZoneMatch
## King of the Anthill: one hill. The team that holds it, with someone standing on it, scores a
## point a second. The hill moves every so often.

const HILL_SECONDS: float = 60.0

var hill_timer: float = HILL_SECONDS

var _accumulated: float = 0.0


func _zone_count() -> int:
	return 1


func _score_limit() -> int:
	return 50 if is_solo() else 100


func _intro_text() -> String:
	return "King of the Anthill\nHold the hill. First to %d." % score_limit


func _objective_tick(delta: float) -> void:
	super(delta)
	var hill: ControlZone = zones[0]
	var occupants: Dictionary = occupants_of(hill)
	var owner: int = hill.owner_team
	if owner != ControlZone.NEUTRAL and not hill.contested and int(occupants.get(owner, 0)) > 0:
		_accumulated += delta
		if _accumulated >= 1.0:
			_accumulated -= 1.0
			add_score(owner, 1)
	hill_timer -= delta
	if hill_timer <= 0.0:
		hill_timer = HILL_SECONDS
		_relocate(hill)
		announce("The hill has moved!", 2.5)


func _objective_status() -> String:
	return "%s · Hill moves in %ds" % [_zone_summary(), ceili(hill_timer)]


func _objective_snapshot() -> Dictionary:
	var state: Dictionary = super()
	state["hill_timer"] = hill_timer
	return state


func _objective_apply(state: Dictionary) -> void:
	super(state)
	hill_timer = float(state.get("hill_timer", hill_timer))
