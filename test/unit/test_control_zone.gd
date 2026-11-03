extends GutTest
## A control zone's capture rules, fed occupants by hand: one team alone takes it over
## capture_seconds, two teams freeze it, the owner alone keeps it, a locked zone never changes.

var _zone: ControlZone


func before_each() -> void:
	_zone = ControlZone.new()
	_zone.capture_seconds = 4.0
	autofree(_zone)
	watch_signals(_zone)


func test_one_team_alone_takes_the_zone() -> void:
	_zone.update({0: 2}, 3.9)
	assert_eq(_zone.owner_team, ControlZone.NEUTRAL, "not yet")
	assert_almost_eq(_zone.progress, 0.975, 0.001)
	_zone.update({0: 2}, 0.2)
	assert_eq(_zone.owner_team, 0)
	assert_signal_emitted(_zone, "captured")


func test_two_teams_inside_freeze_it() -> void:
	_zone.update({0: 1}, 2.0)
	_zone.update({0: 1, 1: 1}, 10.0)
	assert_true(_zone.contested)
	assert_almost_eq(_zone.progress, 0.5, 0.001, "no progress while contested")
	assert_eq(_zone.owner_team, ControlZone.NEUTRAL)


func test_a_new_team_starts_over() -> void:
	_zone.update({0: 1}, 3.0)
	_zone.update({1: 1}, 1.0)
	assert_eq(_zone.progress_team, 1)
	assert_almost_eq(_zone.progress, 0.25, 0.001, "team 1 starts from nothing")


func test_the_owner_alone_keeps_it_secure() -> void:
	_zone.update({0: 1}, 5.0)
	_zone.update({1: 1}, 2.0)
	_zone.update({0: 3}, 0.1)
	assert_eq(_zone.owner_team, 0)
	assert_eq(_zone.progress, 0.0, "the owner standing in it wipes the other team's progress")


func test_nobody_inside_changes_nothing() -> void:
	_zone.update({0: 1}, 2.0)
	_zone.update({}, 100.0)
	assert_almost_eq(_zone.progress, 0.5, 0.001)


func test_a_locked_zone_never_changes_hands() -> void:
	_zone.update({0: 1}, 5.0)
	_zone.locked = true
	_zone.update({1: 4}, 100.0)
	assert_eq(_zone.owner_team, 0)
	assert_signal_emit_count(_zone, "captured", 1)


func test_reset_opens_it_again() -> void:
	_zone.update({0: 1}, 5.0)
	_zone.locked = true
	_zone.reset()
	assert_eq(_zone.owner_team, ControlZone.NEUTRAL)
	assert_false(_zone.locked)
