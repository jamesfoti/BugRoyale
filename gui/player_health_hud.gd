extends PanelContainer
class_name PlayerHealthHud
## Always-visible player health bar. Binds to the player's Damageable child.


@onready var _bar: ProgressBar = $Margin/Row/HealthBar
@onready var _value_label: Label = $Margin/Row/ValueLabel

var _damageable: Damageable


func _ready() -> void:
	visible = false
	call_deferred("_try_bind")


func _process(_delta: float) -> void:
	if _damageable != null and is_instance_valid(_damageable):
		return
	_try_bind()


func _try_bind() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		visible = false
		return

	var damageable: Damageable = player.get_node_or_null("Damageable") as Damageable
	if damageable == null:
		visible = false
		return
	if damageable == _damageable:
		return

	_disconnect_damageable()
	_damageable = damageable
	_damageable.health_changed.connect(_on_health_changed)
	_damageable.damaged.connect(_on_damaged)
	_damageable.died.connect(_on_died)
	_update_display(_damageable.health, _damageable.max_health)
	visible = true


func _disconnect_damageable() -> void:
	if _damageable == null or not is_instance_valid(_damageable):
		_damageable = null
		return
	if _damageable.health_changed.is_connected(_on_health_changed):
		_damageable.health_changed.disconnect(_on_health_changed)
	if _damageable.damaged.is_connected(_on_damaged):
		_damageable.damaged.disconnect(_on_damaged)
	if _damageable.died.is_connected(_on_died):
		_damageable.died.disconnect(_on_died)
	_damageable = null


func _on_health_changed(current: float, maximum: float) -> void:
	_update_display(current, maximum)


func _on_damaged(_amount: float, _source: Node) -> void:
	modulate = Color(1.4, 0.75, 0.75)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.25)


func _on_died() -> void:
	_value_label.text = "0 / %.0f" % _damageable.max_health
	_bar.value = 0.0


func _update_display(current: float, maximum: float) -> void:
	_bar.max_value = maximum
	_bar.value = current
	_value_label.text = "%.0f / %.0f" % [current, maximum]
