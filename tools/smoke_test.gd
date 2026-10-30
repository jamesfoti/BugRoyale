extends Node
## Headless smoke test: loads a map with a game mode exactly as the main menu would, lets it run
## for a number of physics frames, and prints what the fighters did: how far each moved, how
## many shots it fired, who died, and the mode's status line. Quits when done.
##
## Run without a window from the project folder:
##   godot --headless --path . res://tools/smoke_test.tscn \
##       -- map=battlefield mode=ants_vs_ants frames=900
## Arguments (all optional): map=<ModeCatalog map id>, mode=<ModeCatalog mode id>,
## frames=<physics frames to run after the match starts>, character=<0..3>, seed=<terrain seed>,
## drive=1 to work the local player's controls too (run forward, jump, hold the trigger) so the
## keyboard path is exercised, fighters=<n> to override how many fighters a mode with a free
## count spawns (scaling runs), brains=0 to switch the bots' AI off once the match starts (what
## the bodies alone cost), ghosts=0 to keep every far bot in its body. The result line starts
## with "SMOKE RESULT" so a script can grep for it, and carries the average and worst physics
## and process frame times in milliseconds after a warm-up; "SMOKE FAIL" means the match never
## started.

const DEFAULT_MAP: String = "battlefield"
const DEFAULT_MODE: String = "ants_vs_ants"
const DEFAULT_FRAMES: int = 900
## Give up waiting for the match to start after this many physics frames.
const START_TIMEOUT_FRAMES: int = 3600


func _ready() -> void:
	var options: Dictionary = _parse_args()
	var map_id: String = str(options.get("map", DEFAULT_MAP))
	var mode_id: String = str(options.get("mode", DEFAULT_MODE))
	var scene_path: String = ModeCatalog.map_scene(map_id)
	if scene_path.is_empty() or ModeCatalog.mode(mode_id).is_empty():
		print("SMOKE FAIL: unknown map '%s' or mode '%s'." % [map_id, mode_id])
		get_tree().quit(1)
		return
	LoadingScreen.selected_player_character = (
		int(options.get("character", 0)) as LoadingScreen.PlayerCharacter
	)
	LoadingScreen.pending_terrain_seed = int(options.get("seed", 0))
	GameMode.fighter_count_override = int(options.get("fighters", 0))
	GameMode.ghosts_enabled = str(options.get("ghosts", "1")) != "0"
	LoadingScreen.pending_mode_id = mode_id
	LoadingScreen.pending_scene_path = scene_path
	var runner := Runner.new()
	runner.name = "SmokeTestRunner"
	runner.frames_to_run = int(options.get("frames", DEFAULT_FRAMES))
	runner.drive_local = str(options.get("drive", "0")) == "1"
	runner.brains_off = str(options.get("brains", "1")) == "0"
	get_tree().root.add_child.call_deferred(runner)
	print("[SmokeTest] %s on %s for %d frames." % [mode_id, map_id, runner.frames_to_run])
	get_tree().change_scene_to_file.call_deferred("res://scenes/loading_screen.tscn")


func _parse_args() -> Dictionary:
	var options: Dictionary = {}
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.split("=", true, 1)
		if parts.size() == 2:
			options[parts[0].strip_edges()] = parts[1].strip_edges()
	return options


class Runner:
	extends Node

	## Frames left out of the timing: the map is still building and bodies still spawning.
	const WARM_UP_FRAMES: int = 60

	var frames_to_run: int = DEFAULT_FRAMES
	var drive_local: bool = false
	var brains_off: bool = false

	var _mode: GameMode
	var _frames_run: int = 0
	var _frames_waited: int = 0
	var _spawn_positions: Dictionary = {}
	var _deaths: Dictionary = {}
	var _bodies_hooked: Dictionary = {}
	## Frame times in seconds, summed and the worst seen, from Godot's own monitors.
	var _physics_total: float = 0.0
	var _physics_peak: float = 0.0
	var _process_total: float = 0.0
	var _process_peak: float = 0.0

	func _physics_process(_delta: float) -> void:
		if _mode == null or not is_instance_valid(_mode):
			_mode = null
			var scene: Node = get_tree().current_scene
			if scene != null:
				_mode = scene.get_node_or_null("GameMode") as GameMode
			if _mode == null or not _mode._started:
				_frames_waited += 1
				if _frames_waited > START_TIMEOUT_FRAMES:
					print("SMOKE FAIL: the match never started.")
					get_tree().quit(1)
				return
			print(
				(
					"[SmokeTest] Match started after %d frames with %d fighters."
					% [_frames_waited, _mode.fighters.size()]
				)
			)
		_hook_fighters()
		_frames_run += 1
		_sample_frame_times()
		if brains_off and _frames_run == 1:
			for fighter: Fighter in _mode.fighters:
				if fighter.brain != null:
					fighter.brain.enabled = false
		if drive_local:
			_drive_local_player()
		if _frames_run == 120:
			_test_terrain_edits()
		if _frames_run % 300 == 0:
			print("[SmokeTest] %d frames: %s" % [_frames_run, _mode._status_text()])
		if _frames_run >= frames_to_run:
			_report()
			get_tree().quit(0)

	## Plays the local bug from the second second on: runs forward with the trigger held, and
	## jumps now and then. Actions go through the Input singleton, so the local controller and
	## the weapon read them exactly as they would a keyboard and mouse.
	func _drive_local_player() -> void:
		if _frames_run == 60:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			Input.action_press("move_forward")
			Input.action_press("run")
			Input.action_press("shoot")
		if _frames_run > 60 and _frames_run % 240 == 0:
			var jump := InputEventAction.new()
			jump.action = "jump"
			jump.pressed = true
			Input.parse_input_event(jump)
		if _frames_run == frames_to_run - 30:
			Input.action_release("move_forward")
			Input.action_release("run")
			Input.action_release("shoot")

	## Exercises the terrain edit log once the match is running: an ADD at a bot's feet must be
	## refused (it would bury the bot), a carve well away from everyone must go through with a
	## sequence number, and exporting then importing the edit state must keep every override.
	func _test_terrain_edits() -> void:
		var terrain: ChunkedTerrainWorld = (
			get_tree().get_first_node_in_group("terrain_world") as ChunkedTerrainWorld
		)
		if terrain == null:
			print("SMOKE TERRAIN: no ChunkedTerrainWorld on this map")
			return
		var victim: Fighter = null
		for fighter: Fighter in _mode.fighters:
			if fighter.is_alive() and not fighter.ghost:
				victim = fighter
				break
		if victim == null:
			print("SMOKE TERRAIN: nobody alive to test against")
			return
		var feet: Vector3 = victim.get_position()
		var refused: bool = not terrain.apply_edit(
			ChunkedTerrainWorld.sphere_edit(feet, 1.5, true, TerrainMaterials.Kind.NATURAL)
		)
		var far: Vector3 = feet + Vector3(0.0, -0.5, 0.0)
		var ground: Dictionary = _mode.map.ground_hit(feet + Vector3(8.0, 0.0, 0.0))
		if not ground.is_empty():
			far = ground.position
		var applied: bool = terrain.apply_edit(
			ChunkedTerrainWorld.sphere_edit(far, 1.5, false, TerrainMaterials.Kind.NATURAL)
		)
		var log_size: int = terrain.get_edit_log().size()
		var sequence: int = (
			int(terrain.get_edit_log().back().get("sequence", -1)) if log_size > 0 else -1
		)
		var before: int = terrain.get_edited_voxel_count()
		var state: Dictionary = terrain.export_edit_state()
		terrain.import_edit_state(state)
		var after: int = terrain.get_edited_voxel_count()
		print(
			(
				(
					"SMOKE TERRAIN: refused_burying_add=%s applied_far_carve=%s log=%d "
					+ "last_sequence=%d overrides_before=%d after_roundtrip=%d"
				)
				% [str(refused), str(applied), log_size, sequence, before, after]
			)
		)

	## The last frame's physics and process times (the whole step, scripts included).
	func _sample_frame_times() -> void:
		if _frames_run <= WARM_UP_FRAMES:
			return
		var physics: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		var process: float = Performance.get_monitor(Performance.TIME_PROCESS)
		_physics_total += physics
		_physics_peak = maxf(_physics_peak, physics)
		_process_total += process
		_process_peak = maxf(_process_peak, process)

	func _hook_fighters() -> void:
		for fighter: Fighter in _mode.fighters:
			if not fighter.is_valid() or _bodies_hooked.has(fighter):
				continue
			_bodies_hooked[fighter] = true
			_spawn_positions[fighter] = fighter.get_position()
			_deaths[fighter] = 0
			fighter.health.died.connect(
				func() -> void: _deaths[fighter] = int(_deaths[fighter]) + 1
			)

	func _report() -> void:
		var moved: int = 0
		var shooters: int = 0
		var total_shots: int = 0
		var total_deaths: int = 0
		var alive: int = 0
		var lines: Array[String] = []
		for fighter: Fighter in _mode.fighters:
			if not fighter.is_valid():
				lines.append("  fighter freed")
				continue
			var distance: float = fighter.get_position().distance_to(
				_spawn_positions.get(fighter, fighter.get_position())
			)
			var shooter: Node = fighter.body.get_node_or_null("ShooterTest")
			var shots: int = (
				int(shooter.get("shots_fired"))
				if shooter != null and "shots_fired" in shooter
				else 0
			)
			var deaths: int = int(_deaths.get(fighter, 0))
			if distance > 2.0:
				moved += 1
			if shots > 0:
				shooters += 1
			total_shots += shots
			total_deaths += deaths
			if fighter.is_alive():
				alive += 1
			(
				lines
				. append(
					(
						"  %-5s %-16s team %2d  moved %6.1f m  shots %4d  deaths %d  health %5.1f  %s"
						% [
							"human" if fighter.is_human else "bot",
							CharacterSkin.display_name_for(fighter.character),
							fighter.get_team(),
							distance,
							shots,
							deaths,
							fighter.health.health,
							(
								"alive"
								if fighter.is_alive()
								else ("husk" if fighter.is_husk() else "dead")
							),
						]
					)
				)
			)
		print("[SmokeTest] Fighters:")
		for line: String in lines:
			print(line)
		# A client shows the match from the host's state snapshot alone: applying this mode's own
		# snapshot back onto itself must leave what it shows unchanged.
		var status_before: String = _mode._status_text()
		var state: Dictionary = _mode.snapshot_state()
		_mode.apply_state(state)
		var roundtrip: String = "ok" if _mode._status_text() == status_before else "MISMATCH"
		print(
			(
				(
					"SMOKE RESULT: fighters=%d alive=%d moved=%d shooters=%d shots=%d deaths=%d "
					+ "over=%s state_roundtrip=%s ghosts=%d physics_ms=%.2f/%.1f "
					+ "process_ms=%.2f/%.1f status='%s'"
				)
				% [
					_mode.fighters.size(),
					alive,
					moved,
					shooters,
					total_shots,
					total_deaths,
					str(_mode.match_over),
					roundtrip,
					_mode.ghost_count(),
					_physics_total / maxi(_frames_run - WARM_UP_FRAMES, 1) * 1000.0,
					_physics_peak * 1000.0,
					_process_total / maxi(_frames_run - WARM_UP_FRAMES, 1) * 1000.0,
					_process_peak * 1000.0,
					_mode._status_text()
				]
			)
		)
