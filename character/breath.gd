class_name Breath
extends Node
## Air supply for a bug whose head goes under the terrarium water. Breath drains while the head
## is submerged; at zero the bug takes drowning damage until it surfaces. Breath refills quickly
## in air. Attached to the player by PlayerSpawner, next to its Damageable.

signal breath_changed(current: float, maximum: float)
signal submerged_changed(submerged: bool)

const WATER_GROUP: StringName = &"terrarium_water"
const DAMAGE_PULSE_SECONDS: float = 0.5

## Seconds the bug can stay under before it starts drowning.
@export var max_breath_seconds: float = 10.0
## Health lost per second once breath runs out.
@export var drown_damage_per_second: float = 10.0
## Seconds from empty to full once back in the air.
@export var recover_seconds: float = 3.0
## Height of the head above the body's origin (its feet).
@export var head_height: float = 0.9

var breath: float = 0.0
var submerged: bool = false

var _body: Node3D
var _damageable: Damageable
var _water: TerrariumWater
var _damage_accumulated: float = 0.0
var _was_alive: bool = true


func _ready() -> void:
	breath = max_breath_seconds
	_body = get_parent() as Node3D
	_damageable = get_parent().get_node_or_null("Damageable") as Damageable


func _physics_process(delta: float) -> void:
	if _body == null:
		return
	if _damageable != null:
		var alive: bool = _damageable.is_alive()
		if alive and not _was_alive:
			_reset()
		_was_alive = alive
		if not alive:
			return
	breath = minf(breath, max_breath_seconds)
	var under: bool = _is_head_underwater()
	if under != submerged:
		submerged = under
		submerged_changed.emit(submerged)
	if submerged:
		breath = maxf(breath - delta, 0.0)
		breath_changed.emit(breath, max_breath_seconds)
		if breath <= 0.0:
			_drown(delta)
	elif breath < max_breath_seconds:
		breath = minf(breath + delta * max_breath_seconds / maxf(recover_seconds, 0.01), max_breath_seconds)
		breath_changed.emit(breath, max_breath_seconds)
		_damage_accumulated = 0.0


func _drown(delta: float) -> void:
	if _damageable == null:
		return
	# Damage lands in half-second pulses so the health bar flashes a few times a second, not
	# every physics tick.
	_damage_accumulated += drown_damage_per_second * delta
	var pulse: float = drown_damage_per_second * DAMAGE_PULSE_SECONDS
	if _damage_accumulated >= pulse:
		_damage_accumulated -= pulse
		_damageable.apply_damage(pulse)


func _is_head_underwater() -> bool:
	if _water == null or not is_instance_valid(_water):
		_water = get_tree().get_first_node_in_group(WATER_GROUP) as TerrariumWater
		if _water == null:
			return false
	return _body.global_position.y + head_height < _water.get_water_surface_y()


func _reset() -> void:
	breath = max_breath_seconds
	_damage_accumulated = 0.0
	breath_changed.emit(breath, max_breath_seconds)
