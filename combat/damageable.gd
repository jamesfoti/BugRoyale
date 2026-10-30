class_name Damageable
extends Node
## Health container for players and other entities that can take damage.
## Teams: damage from a source on the same team is ignored (no friendly fire). team -1 means
## "no team", which everyone may damage.
## Only the authority (this machine offline, the host online) changes health: every caller,
## from shots to drowning to falling off the map, passes through here, so none of them has to
## know. A client's copy only ever receives health from the host.

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, source: Node)
signal died

const NO_TEAM: int = -1

@export var max_health: float = 100.0
@export var start_at_max: bool = true
@export var team: int = NO_TEAM

var health: float = 0.0
## Whatever dealt the most recent damage (used to credit kills).
var last_damage_source: Node = null


func _ready() -> void:
	add_to_group("damageable")
	if start_at_max:
		health = max_health


func is_alive() -> bool:
	return health > 0.0


func apply_damage(amount: float, source: Node = null) -> bool:
	if not Authority.is_host():
		return false
	if amount <= 0.0 or not is_alive():
		return false
	if team != NO_TEAM and team_of(source) == team:
		return false
	health = maxf(health - amount, 0.0)
	last_damage_source = source if is_instance_valid(source) else null
	damaged.emit(amount, source)
	health_changed.emit(health, max_health)
	if not is_alive():
		died.emit()
	return true


func heal(amount: float) -> void:
	if not Authority.is_host():
		return
	if amount <= 0.0 or not is_alive():
		return
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)


## Brings a dead (or hurt) entity back to full health.
func revive() -> void:
	health = max_health
	last_damage_source = null
	health_changed.emit(health, max_health)


## Team of a damage source: the node itself if it is a Damageable, else its "Damageable" child.
static func team_of(source: Node) -> int:
	if source == null or not is_instance_valid(source):
		return NO_TEAM
	if source is Damageable:
		return (source as Damageable).team
	var child: Damageable = source.get_node_or_null("Damageable") as Damageable
	return child.team if child != null else NO_TEAM
