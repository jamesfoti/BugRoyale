@tool
extends EditorInspectorPlugin

const _BOXED_IN_TERRAIN_SCRIPT_PATH: String = "res://terrain/boxed_in_terrain.gd"
const _OPEN_TERRAIN_SCRIPT_PATH: String = "res://terrain/open_terrain.gd"
const _TERRARIUM_ROOM_SCRIPT_PATH: String = "res://terrain/terrarium_room.gd"
const _LEGACY_INTERIOR_ROOM_SCRIPT_PATH: String = "res://terrain/interior_room.gd"


func _can_handle(object: Object) -> bool:
	if not (object is Node3D):
		return false
	var node: Node3D = object as Node3D
	if _is_terrarium_room_node(node):
		return true
	return _get_script_path(node.get_script()) in _terrain_script_paths()


func _parse_begin(object: Object) -> void:
	var node: Node3D = object as Node3D
	var is_terrarium_room: bool = _is_terrarium_room_node(node)
	var root: Node = EditorInterface.get_edited_scene_root()
	var node_path: NodePath = root.get_path_to(node) if root != null else NodePath()

	var panel: VBoxContainer = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 6)

	var label: Label = Label.new()
	label.text = "Terrarium Editor" if is_terrarium_room else "Terrain Editor"
	panel.add_child(label)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var build_button: Button = Button.new()
	build_button.text = "Build Terrarium" if is_terrarium_room else "Build Terrain"
	build_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_button.disabled = is_terrarium_room and not node.has_method("rebuild_all")
	build_button.pressed.connect(func() -> void: _on_build_pressed(node_path))
	row.add_child(build_button)

	var destroy_button: Button = Button.new()
	destroy_button.text = "Destroy Terrarium" if is_terrarium_room else "Destroy Terrain"
	destroy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	destroy_button.disabled = is_terrarium_room and not node.has_method("destroy_all")
	destroy_button.pressed.connect(func() -> void: _on_destroy_pressed(node_path))
	row.add_child(destroy_button)

	var seed_button: Button = Button.new()
	seed_button.text = "New Seed"
	seed_button.tooltip_text = (
		"Rolls a new terrain seed and builds it (undo puts the old seed back). "
		+ "The rebuild line in the Output panel says what the seed rolled."
	)
	seed_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_button.disabled = is_terrarium_room and not node.has_method("rebuild_all")
	seed_button.pressed.connect(func() -> void: _on_new_seed_pressed(node_path))
	row.add_child(seed_button)

	var randomize_button: Button = Button.new()
	randomize_button.text = "Randomize"
	randomize_button.tooltip_text = (
		"Rolls a new seed and draws the Noise sliders (frequency, amplitude, octaves, "
		+ "lacunarity, gain) from the Noise Roll ranges, writing the values into the "
		+ "inspector with Noise Roll set to Fixed, so what you see is what built. The grid, "
		+ "chunk and voxel sizes stay. One undo step."
	)
	randomize_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	randomize_button.disabled = not _can_randomize(node)
	randomize_button.pressed.connect(func() -> void: _on_randomize_pressed(node_path))
	row.add_child(randomize_button)

	if is_terrarium_room:
		var hint: Label = Label.new()
		if not node.has_method("rebuild_all"):
			hint.text = (
				"TerrariumRoom script failed to load — check the Output panel, "
				+ "then reassign res://terrain/terrarium_room.gd on this node."
			)
		else:
			hint.text = (
				"Generates a giant furnished room with a glass terrarium and voxel terrain. "
				+ "Use Destroy Terrarium before saving the scene."
			)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add_child(hint)

	add_custom_control(panel)


func _terrain_script_paths() -> Array[String]:
	return [
		_BOXED_IN_TERRAIN_SCRIPT_PATH,
		_OPEN_TERRAIN_SCRIPT_PATH,
		_TERRARIUM_ROOM_SCRIPT_PATH,
		_LEGACY_INTERIOR_ROOM_SCRIPT_PATH,
	]


func _is_terrarium_room_node(node: Node3D) -> bool:
	var script_path: String = _get_script_path(node.get_script())
	if script_path in [_TERRARIUM_ROOM_SCRIPT_PATH, _LEGACY_INTERIOR_ROOM_SCRIPT_PATH]:
		return true
	var script: Script = node.get_script()
	if script == null:
		return false
	var global_name: StringName = script.get_global_name()
	return global_name == &"TerrariumRoom" or global_name == &"InteriorRoom"


func _get_script_path(script: Script) -> String:
	if script == null:
		return ""
	return script.resource_path


func _get_target_node(node_path: NodePath) -> Node3D:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	return root.get_node_or_null(node_path) as Node3D


func _on_build_pressed(node_path: NodePath) -> void:
	var node: Node3D = _get_target_node(node_path)
	if node == null:
		push_error("[Terrain] Could not find node.")
		return
	if not node.has_method("rebuild_all"):
		push_error("[Terrain] Script failed to load — check the Output panel.")
		return
	node.rebuild_all_editor()
	_mark_scene_unsaved()


## A new seed through the editor's undo history, so Ctrl+Z brings the old ground back. The
## seed property's setter rebuilds when Auto Rebuild In Editor is on; otherwise we build.
func _on_new_seed_pressed(node_path: NodePath) -> void:
	var node: Node3D = _get_target_node(node_path)
	if node == null:
		push_error("[Terrain] Could not find node.")
		return
	if not node.has_method("rebuild_all"):
		push_error("[Terrain] Script failed to load — check the Output panel.")
		return
	var property: String = (
		"terrarium_noise_seed" if _is_terrarium_room_node(node) else "noise_seed"
	)
	var new_seed: int = randi() % 1000000
	var undo_redo: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("New terrain seed")
	undo_redo.add_do_property(node, property, new_seed)
	undo_redo.add_undo_property(node, property, node.get(property))
	undo_redo.commit_action()
	print("[Terrain] Seed %d." % new_seed)
	if not bool(node.get("auto_rebuild_in_editor")):
		node.rebuild_all_editor()


## A terrain with Noise Roll ranges to draw from (an OpenTerrain, not a terrarium room).
func _can_randomize(node: Node3D) -> bool:
	return (
		node != null
		and node.has_method("rebuild_all")
		and not _is_terrarium_room_node(node)
		and node.get("roll_frequency") != null
	)


## A new seed and new Noise sliders drawn from the node's Noise Roll ranges, and the caves'
## numbers the new seed rolls, rounded to the sliders' steps and written to the node as one
## undo step, with Noise Roll and Cave Roll set to Fixed so the sliders are what builds.
## The setters coalesce into one rebuild when Auto Rebuild In Editor is on; otherwise we
## build.
func _on_randomize_pressed(node_path: NodePath) -> void:
	var node: Node3D = _get_target_node(node_path)
	if node == null:
		push_error("[Terrain] Could not find node.")
		return
	if not _can_randomize(node):
		push_error("[Terrain] This terrain has no Noise Roll ranges to draw from.")
		return
	var frequency: Vector2 = node.get("roll_frequency")
	var amplitude: Vector2 = node.get("roll_amplitude")
	var octaves: Vector2i = node.get("roll_octaves")
	var lacunarity: Vector2 = node.get("roll_lacunarity")
	var gain: Vector2 = node.get("roll_gain")
	var values: Dictionary = {
		"noise_seed": randi() % 1000000,
		"noise_frequency": snappedf(_draw(frequency), 0.0005),
		"noise_amplitude": snappedf(_draw(amplitude), 0.1),
		"noise_octaves": randi_range(mini(octaves.x, octaves.y), maxi(octaves.x, octaves.y)),
		"noise_lacunarity": snappedf(_draw(lacunarity), 0.05),
		"noise_gain": snappedf(_draw(gain), 0.01),
		"noise_roll": 0,
	}
	var caves: String = ""
	if node.get("cave_roll") != null:
		var carver: CaveCarver = CaveCarver.from_seed(
			values["noise_seed"], node.get_bedrock_y(), node.call("cave_ranges")
		)
		carver.apply(node.call("cave_shape"))
		var steps: Dictionary = OpenTerrain.CAVE_FIELDS
		for field: String in steps:
			values["cave_" + field] = snappedf(carver.get(field), steps[field])
		# The roll stays Seeded: the sliders show the roll, the seed still carves the caves.
		caves = " Caves: " + carver.summary() + "."
	var undo_redo: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Randomize terrain")
	for property: String in values:
		undo_redo.add_do_property(node, property, values[property])
		undo_redo.add_undo_property(node, property, node.get(property))
	undo_redo.commit_action()
	print(
		"[Terrain] Randomized: seed %d, frequency %.4f, amplitude %.1f m, %d octaves, lacunarity %.2f, gain %.2f.%s"
		% [
			values["noise_seed"],
			values["noise_frequency"],
			values["noise_amplitude"],
			values["noise_octaves"],
			values["noise_lacunarity"],
			values["noise_gain"],
			caves
		]
	)
	if not bool(node.get("auto_rebuild_in_editor")):
		node.rebuild_all_editor()


static func _draw(value_range: Vector2) -> float:
	return randf_range(minf(value_range.x, value_range.y), maxf(value_range.x, value_range.y))


func _on_destroy_pressed(node_path: NodePath) -> void:
	var node: Node3D = _get_target_node(node_path)
	if node == null:
		push_error("[Terrain] Could not find node.")
		return
	if not node.has_method("destroy_all"):
		push_error("[Terrain] Script failed to load — check the Output panel.")
		return
	node.destroy_all()
	_mark_scene_unsaved()


func _mark_scene_unsaved() -> void:
	EditorInterface.mark_scene_as_unsaved()
