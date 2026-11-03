extends GutTest
## The day cycle's clock on its own (no map): daylight by the hour, the twilight, the dusk and
## dawn crossings, the time to the next change, the clock text and where the sun stands.

var _cycle: DayCycle


func before_each() -> void:
	_cycle = DayCycle.new()
	autofree(_cycle)
	watch_signals(_cycle)


func test_full_daylight_at_midday() -> void:
	assert_almost_eq(DayCycle.daylight_at(DayCycle.DAY_SECONDS * 0.5), 1.0, 0.001)


func test_dark_in_the_middle_of_the_night() -> void:
	var midnight: float = DayCycle.DAY_SECONDS + DayCycle.NIGHT_SECONDS * 0.5
	assert_almost_eq(DayCycle.daylight_at(midnight), 0.0, 0.001)


func test_twilight_is_half_light_at_dusk_and_dawn() -> void:
	assert_almost_eq(DayCycle.daylight_at(DayCycle.DAY_SECONDS), 0.5, 0.001, "dusk")
	assert_almost_eq(DayCycle.daylight_at(0.0), 0.5, 0.001, "dawn")
	assert_almost_eq(DayCycle.daylight_at(DayCycle.CYCLE_SECONDS), 0.5, 0.001, "dawn, wrapped")


func test_night_starts_at_dusk_and_ends_at_dawn() -> void:
	assert_false(DayCycle.is_night_at(DayCycle.DAY_SECONDS - 1.0))
	assert_true(DayCycle.is_night_at(DayCycle.DAY_SECONDS))
	assert_true(DayCycle.is_night_at(DayCycle.CYCLE_SECONDS - 1.0))
	assert_false(DayCycle.is_night_at(DayCycle.CYCLE_SECONDS), "the clock wraps at dawn")


func test_seconds_to_the_next_change() -> void:
	assert_almost_eq(DayCycle.seconds_to_change_at(100.0), DayCycle.DAY_SECONDS - 100.0, 0.001)
	assert_almost_eq(
		DayCycle.seconds_to_change_at(DayCycle.DAY_SECONDS + 50.0),
		DayCycle.NIGHT_SECONDS - 50.0,
		0.001
	)


func test_clock_text() -> void:
	assert_eq(DayCycle.clock_text(245.0), "4:05")
	assert_eq(DayCycle.clock_text(0.0), "0:00")
	assert_eq(DayCycle.clock_text(59.2), "1:00", "rounded up, so the last second reads 0:01")


func test_advance_rings_dusk_then_dawn() -> void:
	_cycle.set_time(DayCycle.DAY_SECONDS - 1.0)
	assert_eq(_cycle.advance(2.0), 1, "crossed dusk")
	assert_signal_emitted(_cycle, "dusk")
	assert_signal_not_emitted(_cycle, "dawn")
	assert_true(_cycle.is_night())
	assert_eq(_cycle.advance(DayCycle.NIGHT_SECONDS), 2, "crossed dawn")
	assert_signal_emitted(_cycle, "dawn")
	assert_false(_cycle.is_night())
	assert_eq(_cycle.advance(1.0), 0, "a plain second")


func test_set_time_does_not_ring() -> void:
	_cycle.set_time(DayCycle.DAY_SECONDS + 10.0)
	assert_signal_not_emitted(_cycle, "dusk")
	assert_true(_cycle.is_night())
	assert_eq(_cycle.advance(1.0), 0, "already night: no dusk to cross")


func test_sun_rises_in_the_east_and_sets_in_the_west() -> void:
	var east: Vector3 = Vector3.RIGHT
	var north: Vector3 = Vector3.FORWARD
	var dawn: Vector3 = DayCycle.sun_direction_at(0.0, east, north)
	assert_gt(dawn.x, 0.9, "on the east horizon")
	assert_almost_eq(dawn.y, 0.0, 0.001)
	var noon: Vector3 = DayCycle.sun_direction_at(DayCycle.DAY_SECONDS * 0.5, east, north)
	assert_gt(noon.y, 0.9, "overhead")
	var dusk: Vector3 = DayCycle.sun_direction_at(DayCycle.DAY_SECONDS, east, north)
	assert_lt(dusk.x, -0.9, "on the west horizon")
	var midnight: Vector3 = DayCycle.sun_direction_at(
		DayCycle.DAY_SECONDS + DayCycle.NIGHT_SECONDS * 0.5, east, north
	)
	assert_lt(midnight.y, -0.9, "under the ground")
