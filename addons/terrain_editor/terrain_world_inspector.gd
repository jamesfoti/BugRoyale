@tool
extends EditorInspectorPlugin

const _PLANET_SCRIPT_PATH: String = "res://terrain/planet.gd"
const _BOXED_IN_TERRAIN_SCRIPT_PATH: String = "res://terrain/boxed_in_terrain.gd"
const _OPEN_TERRAIN_SCRIPT_PATH: String = "res://terrain/open_terrain.gd"
const _INTERIOR_ROOM_SCRIPT_PATH: String = "res://terrain/interior_room.gd"


func _can_handle(object: Object) -> bool:
	if not (object is Node3D):
		return false
	return _get_script_path((object as Node3D).get_script()) in _handled_script_paths()


func _parse_begin(object: Object) -> void:
	var node: Node3D = object as Node3D
	var script_path: String = _get_script_path(node.get_script())
	var is_interior_room: bool = script_path == _INTERIOR_ROOM_SCRIPT_PATH
	var root: Node = EditorInterface.get_edited_scene_root()
	var node_path: NodePath = root.get_path_to(node) if root != null else NodePath()

	var panel: VBoxContainer = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 6)

	var label: Label = Label.new()
	label.text = "Interior Room Editor" if is_interior_room else "Terrain Editor"
	panel.add_child(label)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var build_button: Button = Button.new()
	build_button.text = "Build Room" if is_interior_room else "Build Terrain"
	build_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_button.pressed.connect(func() -> void: _on_build_pressed(node_path))
	row.add_child(build_button)

	var destroy_button: Button = Button.new()
	destroy_button.text = "Destroy Room" if is_interior_room else "Destroy Terrain"
	destroy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	destroy_button.pressed.connect(func() -> void: _on_destroy_pressed(node_path))
	row.add_child(destroy_button)

	if is_interior_room:
		var hint: Label = Label.new()
		hint.text = (
			"Generates a giant furnished room with a glass terrarium and small voxel terrain. "
			+ "Use Destroy Room before saving the scene."
		)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add_child(hint)

	add_custom_control(panel)


func _handled_script_paths() -> Array[String]:
	return [
		_PLANET_SCRIPT_PATH,
		_BOXED_IN_TERRAIN_SCRIPT_PATH,
		_OPEN_TERRAIN_SCRIPT_PATH,
		_INTERIOR_ROOM_SCRIPT_PATH,
	]


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
