extends GutTest
## The director's meter on its own (no map, no flocks): what fills it, how it fades, and when a
## horde goes out.

var _director: HordeDirector


func before_each() -> void:
	_director = HordeDirector.new()
	autofree(_director)
	watch_signals(_director)


func test_noise_fades() -> void:
	_director.hear(50.0)
	_director.tick(1.0, [])
	assert_almost_eq(_director.noise, 50.0 - _director.noise_decay_per_second, 0.001)


func test_noise_never_overflows() -> void:
	_director.hear(500.0)
	assert_eq(_director.noise, HordeDirector.NOISE_MAX)


func test_a_bot_shot_counts_for_a_fraction() -> void:
	_director._on_fired(0.0, true)
	assert_almost_eq(_director.noise, _director.noise_shot, 0.001, "a player's shot")
	_director.noise = 0.0
	_director._on_fired(0.0, false)
	assert_almost_eq(_director.noise, _director.noise_shot * _director.bot_noise_share, 0.001)
	_director.noise = 0.0
	_director._on_fired(2.0, true)
	assert_almost_eq(_director.noise, _director.noise_blast, 0.001, "a blast is louder")


func test_a_full_meter_sends_one_horde_then_cools_down() -> void:
	_director.hear(HordeDirector.NOISE_MAX)
	_director.tick(0.01, [])
	assert_signal_emit_count(_director, "horde_sent", 1)
	assert_eq(_director.hordes, 1)
	assert_almost_eq(_director.noise, _director.noise_after_horde, 0.1, "the meter drops back")
	_director.hear(HordeDirector.NOISE_MAX)
	_director.tick(0.01, [])
	assert_signal_emit_count(_director, "horde_sent", 1, "no second horde inside the cooldown")


func test_a_long_lull_sends_a_horde() -> void:
	_director.tick(_director.lull_seconds + 1.0, [])
	assert_signal_emit_count(_director, "horde_sent", 1)
	assert_eq(get_signal_parameters(_director, "horde_sent")[1], HordeDirector.Reason.LULL)


func test_hordes_grow_up_to_the_cap() -> void:
	var sizes: Array[int] = []
	_director.horde_sent.connect(func(count: int, _reason: int) -> void: sizes.append(count))
	for _index: int in 20:
		_director.send_horde(HordeDirector.Reason.NOISE)
	assert_eq(sizes[0], _director.horde_base)
	assert_eq(sizes[1], _director.horde_base + _director.horde_growth)
	assert_eq(sizes[19], _director.horde_max)


func test_a_finale_sends_hordes_on_a_timer() -> void:
	_director.start_finale()
	_director.tick(_director.finale_seconds * 0.5 + 0.1, [])
	assert_signal_emit_count(_director, "horde_sent", 1, "the first comes soon")
	_director.tick(_director.finale_seconds + 0.1, [])
	assert_signal_emit_count(_director, "horde_sent", 2)
	_director.stop_finale()
	_director.tick(_director.finale_seconds + 0.1, [])
	assert_signal_emit_count(_director, "horde_sent", 2, "none after the finale")


func test_snapshot_round_trip() -> void:
	_director.hear(42.0)
	_director.send_horde(HordeDirector.Reason.NOISE)
	var copy := HordeDirector.new()
	autofree(copy)
	copy.apply(_director.snapshot())
	assert_eq(copy.snapshot(), _director.snapshot())


func test_noise_bar() -> void:
	assert_eq(HordeDirector.noise_bar(0.0, 6), "......")
	assert_eq(HordeDirector.noise_bar(50.0, 6), "###...")
	assert_eq(HordeDirector.noise_bar(100.0, 6), "######")
