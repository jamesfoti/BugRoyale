extends Node
class_name Damageable
## Health container for players and other entities that can take damage.


signal health_changed(current: float, maximum: float)
signal damaged(amount: float, source: Node)
signal died

@export var max_health: float = 100.0
@export var start_at_max: bool = true

var health: float = 0.0


func _ready() -> void:
	add_to_group("damageable")
	if start_at_max:
		health = max_health


func is_alive() -> bool:
	return health > 0.0


func apply_damage(amount: float, source: Node = null) -> bool:
	if amount <= 0.0 or not is_alive():
		return false
	health = maxf(health - amount, 0.0)
	damaged.emit(amount, source)
	health_changed.emit(health, max_health)
	if not is_alive():
		died.emit()
	return true


func heal(amount: float) -> void:
	if amount <= 0.0 or not is_alive():
		return
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)
