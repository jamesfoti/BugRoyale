extends GameMode
## Cordyceps Royale: Battle Royale with a Cordyceps cloud for a storm. 12 bugs of mixed classes
## (humans plus bots), every bug for itself, no respawns. Spores fill everything outside a safe
## circle that closes in stages; a few seconds in them and a bug turns: it rises again as a husk
## on the fungus team, slow and unarmed but biting, immune to the spores, and it walks out of the
## cloud to hunt the clean. A bug a husk kills turns too. A husk that dies fruits where it fell,
## sprouting a stalk and a spore patch of its own, so the map only gets worse. The circle closes
## to nothing, so the match can't stall: the last clean bug wins.

const FIGHTERS: int = 12
const HUSK_TEAM: int = 99
## Nobody (bots) fires for this long after the drop, so everyone can scatter.
const GRACE_SECONDS: float = 10.0
## Seconds in the spores before a bug turns.
const TURN_SECONDS: float = 6.0
## How much of a full infection fades per second outside the spores.
const RECOVER_PER_SECOND: float = 0.12
## Husks move at this fraction of their class speed.
const HUSK_SPEED: float = 0.8
## Radius of the spore patch a fruiting body puts out.
const PATCH_RADIUS: float = 4.0
## Fruiting bodies already on the map at the drop.
const SEED_PATCHES: int = 3
## Stages: hold the circle still, then shrink it to `radius` (a fraction of the starting radius)
## over `shrink` seconds, drifting to a new centre inside the old circle. The last stage closes it.
const STAGES: Array[Dictionary] = [
	{"hold": 35.0, "radius": 0.6, "shrink": 30.0},
	{"hold": 25.0, "radius": 0.38, "shrink": 25.0},
	{"hold": 20.0, "radius": 0.22, "shrink": 25.0},
	{"hold": 15.0, "radius": 0.1, "shrink": 20.0},
	{"hold": 12.0, "radius": 0.0, "shrink": 20.0},
]

const OVERLAY_SHADER_CODE: String = """
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint : source_color = vec3(0.55, 0.7, 0.3);

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 1.6;
	float edge = smoothstep(1.15 - intensity * 0.9, 1.35, r + 0.25 * intensity);
	float veins = sin(atan(p.y, p.x) * 14.0 + TIME * 0.6 + r * 9.0) * 0.5 + 0.5;
	float a = clamp(edge * (0.55 + 0.45 * veins) * (0.35 + intensity), 0.0, 0.92);
	COLOR = vec4(tint * (0.4 + 0.3 * veins), a * intensity);
}
"""

var storm: SporeStorm
var _stage: int = 0
var _stage_time: float = 0.0
var _full_radius: float = 100.0
var _radius_from: float = 100.0
var _center_from: Vector3 = Vector3.ZERO
var _center_to: Vector3 = Vector3.ZERO
## Infection per clean fighter by id, 0..1 (a bug turns at 1). Part of the state snapshot, so a
## client can show its own infection without running the spores.
var _infection: Dictionary = {}
## Ids of humans the fungus has taken: their body is out, a husk walks in its place.
var _turned_humans: Dictionary = {}
var _local_in_spores: bool = false
var _overlay: ShaderMaterial
var _turned_count: int = 0
var _fruited_count: int = 0


# --- Deciding ---------------------------------------------------------------------------------

func _start_match() -> void:
	_build_storm()
	_build_overlay()

	var taken: Array[Vector3] = []
	var team: int = 0
	for human: Fighter in humans():
		human.set_team(team)
		team += 1
		human.respawn_at(_spread_spawn_point(taken))
		_infection[human.id] = 0.0
	var classes: Array = LoadingScreen.PlayerCharacter.values()
	for index: int in FIGHTERS - humans().size():
		var character: LoadingScreen.PlayerCharacter = classes[randi() % classes.size()]
		var bot: Fighter = spawn_bot(character, team, _spread_spawn_point(taken))
		team += 1
		if bot == null:
			continue
		bot.brain.target_group = &"fighter"
		bot.brain.avoid_water = true
		bot.brain.detection_range = 45.0
		bot.hold_fire(GRACE_SECONDS)
		_infection[bot.id] = 0.0
	for index: int in SEED_PATCHES:
		var spot: Vector3 = _patch_spot(taken)
		storm.add_patch(spot, PATCH_RADIUS, hash(spot) + index)
	announce(
		"Cordyceps Royale\nStay out of the spores. Whatever they take comes back for you.\nWeapons free in %d seconds." % GRACE_SECONDS,
		5.0
	)


func _update_match(delta: float) -> void:
	if match_over:
		return
	_update_storm(delta)
	_tick_infection(delta)
	for bot: Fighter in bots():
		bot.brain.storm_center = storm.center
		bot.brain.storm_radius = storm.radius


func _on_fighter_died(fighter: Fighter) -> void:
	if match_over or _turned_humans.has(fighter.id):
		return
	if fighter.is_husk():
		_fruit(fighter)
	elif killer_team(fighter.health) == HUSK_TEAM or storm.is_in_spores(fighter.get_position()):
		_turn(fighter)
	else:
		fighter.kill()
		_infection.erase(fighter.id)
		if fighter.is_human and _clean_humans() == 0:
			# Everyone still clean finished ahead of the last human.
			end_match("Eliminated", "You placed #%d of %d." % [_clean_count() + 1, FIGHTERS])
			return
	_check_victory()


# --- The cloud --------------------------------------------------------------------------------

func _build_storm() -> void:
	var center: Vector3 = map.center()
	if map.bowl_radius > 0.0:
		center = Vector3(map.bowl_center.x, center.y, map.bowl_center.z)
		_full_radius = map.bowl_radius
	else:
		_full_radius = Vector2(map.bounds.size.x, map.bounds.size.z).length() * 0.5
	storm = SporeStorm.create(center, _full_radius, map.bounds.position.y, map.bounds.end.y)
	get_parent().add_child(storm)
	var environments: Array[Node] = get_parent().find_children("*", "WorldEnvironment", true, false)
	if not environments.is_empty():
		storm.attach_environment(environments[0] as WorldEnvironment)
	_radius_from = _full_radius
	_center_from = center
	_center_to = center


func _update_storm(delta: float) -> void:
	if _stage >= STAGES.size():
		return
	var stage: Dictionary = STAGES[_stage]
	var hold: float = stage["hold"]
	var shrink: float = stage["shrink"]
	var target_radius: float = _full_radius * float(stage["radius"])
	_stage_time += delta
	if _stage_time < hold:
		return
	if _stage_time - delta < hold:
		_center_to = _pick_center(target_radius)
		announce("The spores are closing in!", 2.5)
	var progress: float = clampf((_stage_time - hold) / shrink, 0.0, 1.0)
	storm.set_zone(_center_from.lerp(_center_to, progress), lerpf(_radius_from, target_radius, progress))
	if progress >= 1.0:
		_stage += 1
		_stage_time = 0.0
		_radius_from = target_radius
		_center_from = _center_to
		if _stage >= STAGES.size():
			announce("Summit Disease: the spores have taken everything!", 3.0)


## The next circle's centre: inside the current one, over dry ground where possible.
func _pick_center(next_radius: float) -> Vector3:
	var slack: float = maxf(storm.radius - next_radius, 0.0) * 0.85
	var best: Vector3 = storm.center
	for _attempt: int in 8:
		var angle: float = randf() * TAU
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * randf_range(0.0, slack)
		var candidate: Vector3 = storm.center + offset
		if map.bowl_radius > 0.0:
			var from_bowl: Vector3 = candidate - Vector3(map.bowl_center.x, candidate.y, map.bowl_center.z)
			var limit: float = maxf(map.bowl_radius - next_radius, 0.0)
			if from_bowl.length() > limit:
				candidate = Vector3(map.bowl_center.x, candidate.y, map.bowl_center.z) + from_bowl.normalized() * limit
		else:
			var inset: float = next_radius * 0.5
			candidate.x = clampf(candidate.x, map.bounds.position.x + inset, map.bounds.end.x - inset)
			candidate.z = clampf(candidate.z, map.bounds.position.z + inset, map.bounds.end.z - inset)
		best = candidate
		var ground: Dictionary = map.ground_hit(candidate)
		if not ground.is_empty() and ground.position.y > map.water_surface_y() + 1.0:
			break
	return best


# --- Infection --------------------------------------------------------------------------------

func _tick_infection(delta: float) -> void:
	for fighter_id: int in _infection.keys():
		var fighter: Fighter = fighter_by_id(fighter_id)
		if fighter == null or not fighter.is_alive() or fighter.is_husk():
			continue
		var in_spores: bool = storm.is_in_spores(fighter.get_position())
		var level: float = _advance(_infection[fighter_id], in_spores, delta)
		_infection[fighter_id] = level
		if in_spores and not _local_in_spores and fighter.is_local:
			announce_to(fighter, "You're in the spores! Get out!", 2.0)
		if fighter.is_local:
			_local_in_spores = in_spores
		if level >= 1.0:
			_turn(fighter)
			_check_victory()


func _advance(level: float, in_spores: bool, delta: float) -> float:
	if in_spores:
		return minf(level + delta / TURN_SECONDS, 1.0)
	return maxf(level - RECOVER_PER_SECOND * delta, 0.0)


## The fungus takes a fighter: a bot rises as a husk where it stands (or fell); a human's body
## is done and a husk of their class gets up in its place.
func _turn(fighter: Fighter) -> void:
	if fighter.is_human:
		_turn_human(fighter)
		return
	_infection.erase(fighter.id)
	fighter.brain.become_husk(HUSK_TEAM, HUSK_SPEED)
	storm.dress_husk(fighter.body.get_visual_root(), hash(fighter.body.get_instance_id()))
	_turned_count += 1
	if is_local_alive() and fighter.get_position().distance_to(local_fighter.get_position()) < 30.0:
		announce_to(local_fighter, "A bug nearby has turned!", 2.0)


func _turn_human(fighter: Fighter) -> void:
	if _turned_humans.has(fighter.id):
		return
	_turned_humans[fighter.id] = true
	_infection[fighter.id] = 1.0
	var spot: Vector3 = fighter.get_position()
	var placement: int = _clean_count()  # the turned bug no longer counts as clean
	fighter.kill()
	var husk: Fighter = spawn_bot(fighter.character, HUSK_TEAM, spot)
	if husk != null:
		husk.brain.become_husk(HUSK_TEAM, HUSK_SPEED)
		storm.dress_husk(husk.body.get_visual_root(), hash(spot))
	_turned_count += 1
	announce_to(fighter, "Summit Disease takes you...", 2.5)
	if _clean_humans() == 0:
		get_tree().create_timer(2.5).timeout.connect(
			end_match.bind("You turned", "The spores took you. You placed #%d of %d." % [placement, FIGHTERS])
		)


## A dead husk fruits: a stalk and a spore patch grow where it fell.
func _fruit(fighter: Fighter) -> void:
	var spot: Vector3 = fighter.get_position()
	fighter.kill()
	var ground: Dictionary = map.ground_hit(spot)
	if not ground.is_empty():
		spot = ground.position
	storm.add_patch(spot, PATCH_RADIUS, hash(spot) + _fruited_count)
	_fruited_count += 1
	if is_local_alive() and spot.distance_to(local_fighter.get_position()) < 30.0:
		announce_to(local_fighter, "A husk has fruited. Keep clear of the stalk!", 2.5)


func _check_victory() -> void:
	if match_over or _clean_count() != 1:
		return
	var survivor: Fighter = _clean_fighters()[0]
	if survivor.is_local:
		end_match("Victory Royale!", "Last clean bug of %d. %d turned, and none of them got you." % [FIGHTERS, _turned_count])
	elif _clean_humans() == 0:
		end_match("%s wins" % survivor.display_name(), "Last clean bug of %d. %d turned." % [FIGHTERS, _turned_count])


# --- Counting and spawning --------------------------------------------------------------------

func _clean_fighters() -> Array[Fighter]:
	var clean: Array[Fighter] = []
	for fighter: Fighter in fighters:
		if fighter.is_alive() and not fighter.is_husk() and not _turned_humans.has(fighter.id):
			clean.append(fighter)
	return clean


func _clean_count() -> int:
	return _clean_fighters().size()


func _clean_humans() -> int:
	var count: int = 0
	for fighter: Fighter in _clean_fighters():
		if fighter.is_human:
			count += 1
	return count


func _husk_count() -> int:
	var husks: int = 0
	for fighter: Fighter in fighters:
		if fighter.is_alive() and fighter.is_husk():
			husks += 1
	return husks


## Drop point far from everyone already placed: the best of several random dry spots.
func _spread_spawn_point(taken: Array[Vector3]) -> Vector3:
	var best: Vector3 = Vector3.ZERO
	var best_gap: float = -1.0
	for _attempt: int in 10:
		var candidate: Vector3 = map.random_surface_point(1.2, 0.0, map.water_surface_y() + 2.0)
		var gap: float = INF
		for other: Vector3 in taken:
			gap = minf(gap, candidate.distance_to(other))
		if gap > best_gap:
			best_gap = gap
			best = candidate
	taken.append(best)
	return best


## Somewhere on the ground for a seed fruiting body, away from every drop point.
func _patch_spot(taken: Array[Vector3]) -> Vector3:
	var best: Vector3 = map.center()
	var best_gap: float = -1.0
	for _attempt: int in 8:
		var candidate: Vector3 = map.random_surface_point(0.0, 0.0, map.water_surface_y() + 1.0)
		var gap: float = INF
		for other: Vector3 in taken:
			gap = minf(gap, candidate.distance_to(other))
		if gap > best_gap:
			best_gap = gap
			best = candidate
	return best


# --- Showing ----------------------------------------------------------------------------------

func _status_text() -> String:
	var counts: String = "Clean %d  ·  Husks %d" % [_clean_count(), _husk_count()]
	if _stage >= STAGES.size():
		return counts + "  ·  Everything is spores!"
	var stage: Dictionary = STAGES[_stage]
	if _stage_time < stage["hold"]:
		return counts + "  ·  Spores close in %ds" % ceili(stage["hold"] - _stage_time)
	return counts + "  ·  The spores are closing in!"


## The hyphae overlay and the reeling walk follow the local fighter's infection from the state.
func _present() -> void:
	super()
	if local_fighter == null:
		return
	var level: float = float(_infection.get(local_fighter.id, 0.0))
	if _overlay != null:
		_overlay.set_shader_parameter("intensity", level)
	if local_fighter.is_valid() and "control_wobble" in local_fighter.body:
		local_fighter.body.set("control_wobble", level)


func _snapshot_state() -> Dictionary:
	return {
		"stage": _stage,
		"stage_time": _stage_time,
		"infection": _infection.duplicate(),
		"turned_humans": _turned_humans.duplicate(),
		"turned_count": _turned_count,
	}


func _apply_state(state: Dictionary) -> void:
	_stage = int(state.get("stage", _stage))
	_stage_time = float(state.get("stage_time", _stage_time))
	if state.has("infection"):
		_infection = (state["infection"] as Dictionary).duplicate()
	if state.has("turned_humans"):
		_turned_humans = (state["turned_humans"] as Dictionary).duplicate()
	_turned_count = int(state.get("turned_count", _turned_count))


# --- Overlay ----------------------------------------------------------------------------------

## Hyphae creep in from the screen edges as the infection climbs.
func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SporeOverlay"
	layer.layer = 5
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = OVERLAY_SHADER_CODE
	_overlay = ShaderMaterial.new()
	_overlay.shader = shader
	rect.material = _overlay
	layer.add_child(rect)
