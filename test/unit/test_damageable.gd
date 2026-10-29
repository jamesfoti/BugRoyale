extends GutTest
## Health rules: team immunity, the no-team case, dying once, and the authority gate that keeps
## a client from deciding damage.

var _victim: Damageable


## A node carrying a Damageable on a team, the way bodies and hornets carry theirs.
func _attacker(team: int) -> Node:
	var attacker: Node = Node.new()
	var health: Damageable = Damageable.new()
	health.name = "Damageable"
	health.team = team
	attacker.add_child(health)
	add_child_autofree(attacker)
	return attacker


func before_each() -> void:
	Authority.host = true
	_victim = Damageable.new()
	_victim.max_health = 100.0
	add_child_autofree(_victim)


func after_each() -> void:
	Authority.host = true


func test_starts_at_full_health() -> void:
	assert_eq(_victim.health, 100.0)
	assert_true(_victim.is_alive())


func test_damage_reduces_health_and_credits_the_source() -> void:
	var attacker: Node = _attacker(2)
	assert_true(_victim.apply_damage(30.0, attacker))
	assert_eq(_victim.health, 70.0)
	assert_eq(_victim.last_damage_source, attacker)


func test_dies_once_and_takes_no_more_damage() -> void:
	watch_signals(_victim)
	assert_true(_victim.apply_damage(150.0))
	assert_false(_victim.is_alive())
	assert_eq(_victim.health, 0.0)
	assert_signal_emit_count(_victim, "died", 1)
	assert_false(_victim.apply_damage(10.0), "a dead thing takes no damage")
	assert_signal_emit_count(_victim, "died", 1)


func test_same_team_cannot_hurt_each_other() -> void:
	_victim.team = 1
	assert_false(_victim.apply_damage(30.0, _attacker(1)))
	assert_eq(_victim.health, 100.0)


func test_other_teams_can() -> void:
	_victim.team = 1
	assert_true(_victim.apply_damage(30.0, _attacker(2)))
	assert_eq(_victim.health, 70.0)


func test_no_team_is_hurt_by_everyone_including_the_teamless() -> void:
	_victim.team = Damageable.NO_TEAM
	assert_true(_victim.apply_damage(10.0, _attacker(1)))
	assert_true(_victim.apply_damage(10.0, _attacker(Damageable.NO_TEAM)))
	assert_true(_victim.apply_damage(10.0, null), "falls and drowning have no source")
	assert_eq(_victim.health, 70.0)


func test_killer_team_is_read_from_the_last_source() -> void:
	_victim.apply_damage(5.0, _attacker(7))
	assert_eq(GameMode.killer_team(_victim), 7)
	_victim.apply_damage(5.0)
	assert_eq(GameMode.killer_team(_victim), Damageable.NO_TEAM, "an accident credits nobody")


func test_only_the_host_changes_health() -> void:
	Authority.host = false
	assert_false(_victim.apply_damage(50.0, _attacker(2)))
	assert_eq(_victim.health, 100.0, "a client cannot deal damage")
	_victim.health = 40.0
	_victim.heal(20.0)
	assert_eq(_victim.health, 40.0, "a client cannot heal either")
	Authority.host = true
	_victim.heal(60.0)
	assert_eq(_victim.health, 100.0, "the host heals")
	assert_true(_victim.apply_damage(50.0, _attacker(2)))
	assert_eq(_victim.health, 50.0, "the host deals damage")


func test_revive_restores_full_health_and_forgets_the_killer() -> void:
	_victim.apply_damage(150.0, _attacker(2))
	_victim.revive()
	assert_true(_victim.is_alive())
	assert_eq(_victim.health, 100.0)
	assert_null(_victim.last_damage_source)
