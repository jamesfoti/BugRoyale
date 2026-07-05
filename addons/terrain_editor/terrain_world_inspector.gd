@tool
extends EditorInspectorPlugin

const _PLANET_SCRIPT = preload("res://terrain/planet.gd")
const _BOXED_IN_TERRAIN_SCRIPT = preload("res://terrain/boxed_in_terrain.gd")


func _can_handle(object: Object) -> bool:
	if not (object is Node3D):
		return false
	var object_script: Script = (object as Node3D).get_script()
	return object_script == _PLANET_SCRIPT or object_script == _BOXED_IN_TERRAIN_SCRIPT


func _parse_begin(object: Object) -> void:
	var terrain: Node3D = object as Node3D
	var root: Node = EditorInterface.get_edited_scene_root()
	var terrain_path: NodePath = root.get_path_to(terrain) if root != null else NodePath()

	var panel: VBoxContainer = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 6)

	var label: Label = Label.new()
	label.text = "Terrain Editor"
	panel.add_child(label)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var build_button: Button = Button.new()
	build_button.text = "Build Terrain"
	build_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_button.pressed.connect(func() -> void: _on_build_pressed(terrain_path))
	row.add_child(build_button)

	var destroy_button: Button = Button.new()
	destroy_button.text = "Destroy Terrain"
	destroy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	destroy_button.pressed.connect(func() -> void: _on_destroy_pressed(terrain_path))
	row.add_child(destroy_button)

	add_custom_control(panel)


func _get_terrain_node(terrain_path: NodePath) -> Node3D:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	return root.get_node_or_null(terrain_path) as Node3D


func _on_build_pressed(terrain_path: NodePath) -> void:
	var terrain: Node3D = _get_terrain_node(terrain_path)
	if terrain == null:
		push_error("[Terrain] Could not find terrain node.")
		return
	if not terrain.has_method("rebuild_all"):
		push_error("[Terrain] Script not loaded — check the Output panel for terrain script errors.")
		return
	terrain.rebuild_all()
	_mark_scene_unsaved()


func _on_destroy_pressed(terrain_path: NodePath) -> void:
	var terrain: Node3D = _get_terrain_node(terrain_path)
	if terrain == null:
		push_error("[Terrain] Could not find terrain node.")
		return
	if not terrain.has_method("destroy_all"):
		push_error("[Terrain] Script not loaded — check the Output panel for terrain script errors.")
		return
	terrain.destroy_all()
	_mark_scene_unsaved()


func _mark_scene_unsaved() -> void:
	EditorInterface.mark_scene_as_unsaved()
