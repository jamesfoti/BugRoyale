extends Node
## Dev tool: loads a map with a game mode exactly as the main menu would, lets it run for a
## number of physics frames after the match starts, saves what the local player's camera sees
## to a PNG, and quits. Needs a window (no --headless). Run from the project folder:
##   godot --path . res://tools/screenshot.tscn --resolution 1152x648 \
##       -- map=battlefield mode=burrow frames=240 out=C:/somewhere/shot.png
## Arguments: map=, mode=, format=, seed=, character= as the smoke test takes them,
## frames=<physics frames after the match starts>, out=<png path>, hud=0 to hide every
## CanvasLayer first, and cam=x,h,z look=x,h,z for a free camera: x and z in world metres, h
## metres above the ground there. Without cam= the local player's own camera is used.
## dig=x,r,z carves a sphere of radius r into the ground at x, z half a second in, so the
## capture shows what digging exposes.

const DEFAULT_MAP: String = "battlefield"
const DEFAULT_MODE: String = "burrow"
const DEFAULT_FRAMES: int = 240
const START_TIMEOUT_FRAMES: int = 3600


func _ready() -> void:
	var options: Dictionary = _parse_args()
	var map_id: String = str(options.get("map", DEFAULT_MAP))
	var mode_id: String = str(options.get("mode", DEFAULT_MODE))
	var scene_path: String = ModeCatalog.map_scene(map_id)
	if scene_path.is_empty() or ModeCatalog.mode(mode_id).is_empty():
		print("SCREENSHOT FAIL: unknown map '%s' or mode '%s'." % [map_id, mode_id])
		get_tree().quit(1)
		return
	LoadingScreen.selected_player_character = (
		int(options.get("character", 0)) as LoadingScreen.PlayerCharacter
	)
	LoadingScreen.pending_terrain_seed = int(options.get("seed", 0))
	# A persistent mode's saved world stays out of it unless asked (save=1 loads it, as the
	# game would, which a bug report filed in a restored world needs).
	WorldSave.enabled = str(options.get("save", "0")) == "1"
	LoadingScreen.pending_mode_id = mode_id
	LoadingScreen.pending_format_id = str(options.get("format", ""))
	LoadingScreen.pending_scene_path = scene_path
	var runner := Runner.new()
	runner.name = "ScreenshotRunner"
	runner.frames_to_run = int(options.get("frames", DEFAULT_FRAMES))
	runner.out_path = str(options.get("out", "user://screenshot.png"))
	runner.hide_hud = str(options.get("hud", "1")) == "0"
	runner.cam = _vector(str(options.get("cam", "")))
	runner.look = _vector(str(options.get("look", "")))
	runner.dig = _vector(str(options.get("dig", "")))
	runner.report = int(options.get("report", 0))
	runner.player_at = _vector(str(options.get("player", "")))
	runner.view = _vector(str(options.get("view", "")))
	runner.replay_path = str(options.get("replay", ""))
	runner.place_absolute = str(options.get("absolute", "0")) == "1"
	runner.zoom = float(options.get("zoom", 0.0))
	runner.settle = int(options.get("settle", 2))
	get_tree().root.add_child.call_deferred(runner)
	get_tree().change_scene_to_file.call_deferred("res://scenes/loading_screen.tscn")


## "x,h,z" -> Vector3, or Vector3.INF when empty or malformed.
static func _vector(text: String) -> Vector3:
	var parts: PackedStringArray = text.split(",")
	if parts.size() != 3:
		return Vector3.INF
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


func _parse_args() -> Dictionary:
	var options: Dictionary = {}
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.split("=", true, 1)
		if parts.size() == 2:
			options[parts[0].strip_edges()] = parts[1].strip_edges()
	return options


class Runner:
	extends Node

	var frames_to_run: int = DEFAULT_FRAMES
	var out_path: String = "user://screenshot.png"
	var hide_hud: bool = false
	var cam: Vector3 = Vector3.INF
	var look: Vector3 = Vector3.INF
	var dig: Vector3 = Vector3.INF
	## 1: open the report form and save a report before capturing; 2: the pause menu's route.
	var report: int = 0
	## Where to put the local player (x, h above the ground, z) and which way to point their
	## orbit camera (pitch, yaw in degrees, third unused) before capturing through it.
	var player_at: Vector3 = Vector3.INF
	var view: Vector3 = Vector3.INF
	## A bug report's report.json: its terrain edits are replayed and the player put where the
	## report was filed, looking the same way. Run with the report's map, mode and seed.
	var replay_path: String = ""
	## player= is an absolute position (its h is the height itself) rather than above ground.
	var place_absolute: bool = false
	## Orbit camera distance to ask for, as the scroll wheel would (0: leave it).
	var zoom: float = 0.0
	## Frames drawn before the capture. 1 with frames= equal to the placement frame (90)
	## captures the very first frame after the player and camera were placed, where a
	## one-frame camera lag would show.
	var settle: int = 2
	## The player root's rotation in degrees (a climbing bug is tilted); INF leaves it.
	var facing: Vector3 = Vector3.INF
	var _arm: SpringArm3D
	var _mode: GameMode
	var _frames_run: int = 0
	var _frames_waited: int = 0
	var _done: bool = false

	func _physics_process(_delta: float) -> void:
		if _done:
			return
		if _mode == null or not is_instance_valid(_mode):
			_mode = null
			var scene: Node = get_tree().current_scene
			if scene != null:
				_mode = scene.get_node_or_null("GameMode") as GameMode
			if _mode == null or not _mode._started:
				_frames_waited += 1
				if _frames_waited > START_TIMEOUT_FRAMES:
					print("SCREENSHOT FAIL: the match never started.")
					get_tree().quit(1)
				return
		_frames_run += 1
		if _frames_run == 30 and dig != Vector3.INF:
			_dig()
		if _frames_run == 30 and not replay_path.is_empty():
			_replay()
		if _frames_run == 90 and player_at != Vector3.INF:
			_place_player()
		if _frames_run >= frames_to_run:
			_done = true
			_capture()

	## Replays a bug report: every terrain edit it lists, in order, then the player goes where
	## the report was filed with the camera turned as it was (placed at frame 90, like player=).
	func _replay() -> void:
		var text: String = FileAccess.get_file_as_string(replay_path)
		var data: Variant = JSON.parse_string(text)
		if not data is Dictionary:
			print("SCREENSHOT: could not read report %s" % replay_path)
			return
		var report_data: Dictionary = data
		var terrain: ChunkedTerrainWorld = _mode.map.editable_terrain()
		var terrain_data: Dictionary = report_data.get("terrain", {})
		var edits: Array = terrain_data.get("last_edits", [])
		var applied: int = 0
		if terrain != null and terrain_data.has("edit_state"):
			# The exact voxels, keys written back from their "(x, y, z)" text.
			var state: Dictionary = terrain_data["edit_state"]
			var saved: Dictionary = state.get("edits", {})
			var overrides: Dictionary = {}
			for key: String in saved.get("overrides", {}):
				overrides[str_to_var("Vector3i" + key)] = float(saved["overrides"][key])
			var materials: Dictionary = {}
			for key: String in saved.get("materials", {}):
				materials[str_to_var("Vector3i" + key)] = int(saved["materials"][key])
			(
				terrain
				. import_edit_state(
					{
						"next_sequence": int(state.get("next_sequence", 1)),
						"edits": {"overrides": overrides, "materials": materials},
					}
				)
			)
			print("SCREENSHOT: restored %d overridden voxels" % overrides.size())
		elif terrain != null:
			for edit: Dictionary in edits:
				var copy: Dictionary = edit.duplicate()
				copy["position"] = _vector_from_report(str(edit.get("position", "")))
				if copy.has("half_extents"):
					copy["half_extents"] = _vector_from_report(str(edit["half_extents"]))
				copy.erase("sequence")
				if terrain.apply_edit(copy):
					applied += 1
		var player: Dictionary = report_data.get("player", {})
		if player.has("position"):
			var spot: Vector3 = _vector_from_report(str(player["position"]))
			# Absolute: h is the height itself, not above the ground (there may be none).
			player_at = Vector3(spot.x, spot.y, spot.z)
			place_absolute = true
		if player.has("facing_degrees"):
			facing = _vector_from_report(str(player["facing_degrees"]))
		if player.has("camera_degrees"):
			var camera: Vector3 = _vector_from_report(str(player["camera_degrees"]))
			view = Vector3(camera.x, camera.y, 0.0)
		print("SCREENSHOT: replayed %d of %d edits from %s" % [applied, edits.size(), replay_path])

	## "(x, y, z)" as a report writes a vector.
	static func _vector_from_report(text: String) -> Vector3:
		var parsed: Variant = str_to_var("Vector3" + text)
		return parsed if parsed is Vector3 else Vector3.ZERO

	## Drops the local player at player_at (after any dig has rebuilt, so a hole is a hole) and
	## turns their orbit camera to view, so the capture is what a player there would see.
	func _place_player() -> void:
		var player: CharacterBody3D = (
			get_tree().get_first_node_in_group("player") as CharacterBody3D
		)
		if player == null:
			print("SCREENSHOT: no local player to place")
			return
		player.global_position = player_at if place_absolute else _above_ground(player_at)
		player.velocity = Vector3.ZERO
		if facing != Vector3.INF:
			player.global_rotation_degrees = facing
		var arm: SpringArm3D = player.get_node_or_null("OrbitCamera") as SpringArm3D
		if arm != null and view != Vector3.INF:
			arm.rotation_degrees = Vector3(view.x, view.y, 0.0)
		if arm != null and zoom > 0.0:
			arm.set("_user_spring_length", zoom)
		print("SCREENSHOT: player placed at %s" % str(player.global_position))
		if arm != null:
			_arm = arm

	## What the orbit camera's arm did, for camera bug hunts.
	func _describe_arm() -> void:
		if _arm == null:
			return
		var camera: Camera3D = _arm.get_node_or_null("Camera3D") as Camera3D
		var space: PhysicsDirectSpaceState3D = _arm.get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(
			_arm.global_position,
			_arm.global_position - _arm.global_basis.z * -_arm.spring_length,
			_arm.collision_mask
		)
		var hit: Dictionary = space.intersect_ray(query)
		var terrain: ChunkedTerrainWorld = _mode.map.editable_terrain()
		if terrain != null and camera != null:
			var player: Node3D = _arm.get_parent() as Node3D
			for named: Array in [
				["player root", player.global_position],
				["pivot", _arm.global_position],
				["camera", camera.global_position],
			]:
				var point: Vector3 = named[1]
				# Inside the drawn ground if a ray straight up first meets a back face.
				var probe := PhysicsRayQueryParameters3D.create(
					point, point + Vector3.UP * 60.0, MapInfo.TERRAIN_LAYER
				)
				probe.hit_back_faces = true
				var up_hit: Dictionary = space.intersect_ray(probe)
				var inside_mesh: String = "no ground above"
				if not up_hit.is_empty():
					inside_mesh = (
						"inside mesh"
						if Vector3(up_hit["normal"]).dot(Vector3.UP) > 0.0
						else "in air"
					)
				print(
					(
						"SCREENSHOT: %s %s density %.3f (%s), mesh says %s"
						% [
							named[0],
							str(point),
							terrain.density_at(point),
							"solid" if terrain.is_solid_at(point) else "air",
							inside_mesh,
						]
					)
				)
		print(
			(
				"SCREENSHOT: arm pivot %s length %.2f hit_length %.2f mask %d shape %s camera %s ray_hit %s"
				% [
					str(_arm.global_position),
					_arm.spring_length,
					_arm.get_hit_length(),
					_arm.collision_mask,
					str(_arm.shape),
					str(camera.global_position) if camera != null else "none",
					str(hit.get("position", "none")),
				]
			)
		)

	## Carves a sphere of radius dig.y into the ground at dig.x, dig.z, so a capture can show
	## what digging exposes. The chunks rebuild in the frames that follow.
	func _dig() -> void:
		var terrain: ChunkedTerrainWorld = _mode.map.editable_terrain()
		var hit: Dictionary = _mode.map.ground_hit(Vector3(dig.x, 0.0, dig.z))
		if terrain == null or hit.is_empty():
			print("SCREENSHOT: nothing to dig at %s" % str(dig))
			return
		var applied: bool = terrain.apply_edit(
			ChunkedTerrainWorld.sphere_edit(
				hit.position, dig.y, false, TerrainMaterials.Kind.NATURAL
			)
		)
		print("SCREENSHOT: dug at %s applied=%s" % [str(hit.position), applied])

	func _capture() -> void:
		if hide_hud:
			for layer: Node in get_tree().current_scene.find_children(
				"*", "CanvasLayer", true, false
			):
				(layer as CanvasLayer).visible = false
		if cam != Vector3.INF and look != Vector3.INF:
			var camera := Camera3D.new()
			get_tree().current_scene.add_child(camera)
			camera.global_position = _above_ground(cam)
			camera.look_at(_above_ground(look))
			camera.current = true
		if report == 1:
			# The report form over the frozen game, then a saved report to inspect.
			BugReporter.open()
			for _frame: int in 3:
				await RenderingServer.frame_post_draw
			var folder: String = BugReporter.save_report("Screenshot tool test report.")
			print("SCREENSHOT: bug report in %s" % ProjectSettings.globalize_path(folder))
		elif report == 2:
			# The pause menu's route: pause (captured beside the output as *_paused.png), press
			# its report button, save, close, and the final capture should show the menu back.
			var pause := InputEventAction.new()
			pause.action = "pause"
			pause.pressed = true
			Input.parse_input_event(pause)
			for _frame: int in 3:
				await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				out_path.get_basename() + "_paused.png"
			)
			var menu: Node = get_tree().current_scene.get_node("PauseMenu")
			menu.call("_on_report_pressed")
			for _frame: int in 3:
				await RenderingServer.frame_post_draw
			var folder: String = BugReporter.save_report("Pause menu route test report.")
			print("SCREENSHOT: bug report in %s" % ProjectSettings.globalize_path(folder))
			BugReporter.close()
			for _frame: int in 3:
				await RenderingServer.frame_post_draw
		for _frame: int in maxi(settle, 1):
			await RenderingServer.frame_post_draw
		_describe_arm()
		if dig != Vector3.INF:
			var terrain: ChunkedTerrainWorld = _mode.map.editable_terrain()
			var hit: Dictionary = _mode.map.ground_hit(Vector3(dig.x, 0.0, dig.z))
			print(
				(
					"SCREENSHOT: after the dig, %d voxels overridden, ground at %s"
					% [terrain.get_edited_voxel_count(), str(hit.get("position", "nothing"))]
				)
			)
		var image: Image = get_viewport().get_texture().get_image()
		var error: Error = image.save_png(out_path)
		print("SCREENSHOT: %s -> %s (%s)" % [str(image.get_size()), out_path, error_string(error)])
		get_tree().quit(0 if error == OK else 1)

	## (x, h, z) -> the world point h metres above the ground at x, z (or at y = h if there is
	## no ground there).
	func _above_ground(point: Vector3) -> Vector3:
		var hit: Dictionary = _mode.map.ground_hit(Vector3(point.x, 0.0, point.z))
		if hit.is_empty():
			return point
		return Vector3(point.x, float(hit.position.y) + point.y, point.z)
