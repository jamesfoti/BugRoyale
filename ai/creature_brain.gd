class_name CreatureBrain
extends BotBrain
## A creature of a biome (CreatureFeature): it wanders near home and hunts no one until hurt.
## Then it, and its kin within the call radius, go after the attacker for a while, and come
## home when the anger runs out or the attacker gets too far from home.

## Where it lives (a termite mound's foot) and how far it strays from there.
var home: Vector3 = Vector3.INF
var wander_radius: float = 18.0
var anger_seconds: float = 20.0
var call_radius: float = 20.0

var _attacker: Node3D
var _anger_left: float = 0.0


func _ready() -> void:
	super._ready()
	detection_range = 0.0
	if _damageable != null:
		_damageable.damaged.connect(_on_damaged)


## Turns on an attacker for the anger's length (again from the start if already angry).
func provoke(attacker: Node3D) -> void:
	if attacker == null or attacker == _body or not is_instance_valid(attacker):
		return
	_attacker = attacker
	_anger_left = anger_seconds
	_retarget_timer = 0.0


## The attacker while angry, else null.
func attacker() -> Node3D:
	return _attacker if _anger_left > 0.0 else null


func sample(body: CharacterBody3D, delta: float) -> FighterInput:
	_anger_left -= delta
	if _attacker != null and home != Vector3.INF and is_instance_valid(_attacker):
		# Chased off far enough: let it go.
		if _attacker.global_position.distance_to(home) > wander_radius * 4.0:
			_anger_left = 0.0
	if _anger_left <= 0.0:
		_attacker = null
	return super.sample(body, delta)


func on_respawn() -> void:
	super.on_respawn()
	_attacker = null
	_anger_left = 0.0


func _find_target() -> Node3D:
	var hunted: Node3D = attacker()
	return hunted if hunted != null and _is_valid_target(hunted) else null


func _wander_goal() -> Vector3:
	if home == Vector3.INF:
		return super._wander_goal()
	var position_now: Vector3 = _body.global_position
	var reached: bool = (
		_wander_point != Vector3.INF and position_now.distance_to(_wander_point) < 2.0
	)
	if _wander_point == Vector3.INF or reached or _wander_timer <= 0.0:
		var turn: float = randf() * TAU
		var out_by: float = sqrt(randf()) * wander_radius
		var column: Vector3 = home + Vector3(cos(turn), 0.0, sin(turn)) * out_by
		var ground: Dictionary = map.ground_hit(column)
		_wander_point = ground.position if not ground.is_empty() else column
		_wander_timer = randf_range(5.0, 10.0)
	return _wander_point


func _on_damaged(_amount: float, source: Node) -> void:
	var attacker_body: Node3D = _body_of(source)
	if attacker_body == null or Damageable.team_of(attacker_body) == _damageable.team:
		return
	provoke(attacker_body)
	if call_radius <= 0.0:
		return
	for node: Node in get_tree().get_nodes_in_group(CreatureFeature.GROUP):
		var kin: FighterBody = node as FighterBody
		if kin == null or kin == _body or not kin.is_in_play():
			continue
		if kin.global_position.distance_to(_body.global_position) > call_radius:
			continue
		var kin_brain: CreatureBrain = kin.controller as CreatureBrain
		if kin_brain != null and Damageable.team_of(kin) == _damageable.team:
			kin_brain.provoke(attacker_body)


## The body behind a hit: the shooter for a shot, a bird for a sting; null for drowning, gas
## and the like (nothing to hunt).
static func _body_of(source: Node) -> Node3D:
	if source == null or not is_instance_valid(source) or not (source is Node3D):
		return null
	if source.get_node_or_null("Damageable") == null:
		return null
	return source as Node3D
