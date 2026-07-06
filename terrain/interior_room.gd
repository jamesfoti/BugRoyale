@tool
class_name InteriorRoom
extends Node3D
## Procedurally generates a single furnished interior room (no terrain).


@export_group("Room")
@export var room_seed: int = 77:
	set(value):
		room_seed = value
		_request_rebuild()
@export var room_type: InteriorRoomLayout.RoomType = InteriorRoomLayout.RoomType.RANDOM:
	set(value):
		room_type = value
		_request_rebuild()
@export var room_size: Vector3 = Vector3(8.0, 3.5, 8.0):
	set(value):
		room_size = Vector3(maxf(value.x, 3.0), maxf(value.y, 2.5), maxf(value.z, 3.0))
		_request_rebuild()
@export_range(0.2, 1.0, 0.05) var wall_thickness: float = 0.4:
	set(value):
		wall_thickness = maxf(value, 0.2)
		_request_rebuild()

@export_group("Content")
@export var spawn_shell: bool = true:
	set(value):
		spawn_shell = value
		_request_rebuild()
@export var spawn_furniture: bool = true:
	set(value):
		spawn_furniture = value
		_request_rebuild()
@export var spawn_light: bool = true:
	set(value):
		spawn_light = value
		_request_rebuild()
@export var spawn_glass_box: bool = true:
	set(value):
		spawn_glass_box = value
		_request_rebuild()
@export var glass_box_size: Vector3 = Vector3(1.5, 1.5, 1.5):
	set(value):
		glass_box_size = Vector3(
			maxf(value.x, 0.25),
			maxf(value.y, 0.25),
			maxf(value.z, 0.25)
		)
		_request_rebuild()
@export_range(0.1, 8.0, 0.1, "or_greater") var ceiling_light_energy: float = 1.2:
	set(value):
		ceiling_light_energy = maxf(value, 0.1)
		_request_rebuild()

@export_group("Runtime")
@export var rebuild_on_ready: bool = true
@export var auto_rebuild_in_editor: bool = false


var _layout: InteriorRoomLayout.Layout
var _shell_root: Node3D
var _furniture_root: Node3D
var _light_root: Node3D
var _glass_box_root: Node3D
var _dirty: bool = true


func _ready() -> void:
	_ensure_export_defaults()
	add_to_group("interior_room")
	add_to_group("boxed_in_terrain")
	if Engine.is_editor_hint():
		if auto_rebuild_in_editor:
			call_deferred("rebuild_all")
	elif rebuild_on_ready:
		call_deferred("rebuild_all")


func get_surface_height_at(_world_position: Vector3) -> float:
	if _layout != null:
		return global_position.y + _layout.floor_y
	return global_position.y


func get_world_extents() -> Vector3:
	if _layout != null:
		return _layout.world_aabb.size
	return room_size


func get_spawn_position() -> Vector3:
	if _layout != null:
		return global_position + _layout.spawn_position
	return global_position + Vector3(0.0, 1.4, 0.0)


func get_room_type_name() -> String:
	if _layout == null:
		return InteriorRoomLayout.RoomType.keys()[room_type]
	return InteriorRoomLayout.RoomType.keys()[_layout.room_type]


func rebuild_all() -> void:
	_ensure_export_defaults()
	_dirty = true
	if Engine.is_editor_hint():
		_rebuild_content()
	else:
		call_deferred("_rebuild_content")


func destroy_all() -> void:
	_clear_content()
	_layout = null
	_dirty = true
	if Engine.is_editor_hint():
		print("[InteriorRoom] Destroyed room (editor)")


func _request_rebuild() -> void:
	_dirty = true
	if not is_node_ready():
		return
	if Engine.is_editor_hint() and not auto_rebuild_in_editor:
		return
	call_deferred("rebuild_all")


func _rebuild_content() -> void:
	if not _dirty:
		return
	_dirty = false
	_clear_content()
	_layout = InteriorRoomLayout.generate(
		room_seed,
		room_type,
		room_size,
		wall_thickness,
		room_size.y
	)
	if spawn_shell:
		_shell_root = InteriorRoomShellBuilder.build(_layout, wall_thickness)
		add_child(_shell_root)
		_register_generated_node(_shell_root)
	if spawn_light:
		_light_root = InteriorRoomLighting.build(_layout, ceiling_light_energy)
		add_child(_light_root)
		_register_generated_node(_light_root)

	var placements: Array[InteriorRoomFurniture.Placement] = []
	if spawn_furniture:
		placements = InteriorRoomFurniture.place_for_layout(_layout, room_seed)
		_furniture_root = Node3D.new()
		_furniture_root.name = "Furniture"
		add_child(_furniture_root)
		_register_generated_node(_furniture_root)
		for placement: InteriorRoomFurniture.Placement in placements:
			var furniture_body: StaticBody3D = InteriorFurnitureBuilder.build(placement)
			_furniture_root.add_child(furniture_body)
			_register_generated_node(furniture_body)

	if spawn_glass_box:
		_glass_box_root = InteriorGlassBoxSpawner.build_if_clear(_layout, placements, glass_box_size)
		if _glass_box_root != null:
			add_child(_glass_box_root)
			_refresh_glass_box_visuals(_glass_box_root)
			_register_generated_node(_glass_box_root)
	if Engine.is_editor_hint():
		print(
			"[InteriorRoom] Built %s (editor, seed %d)"
			% [get_room_type_name(), room_seed]
		)


func _clear_content() -> void:
	_free_generated_root(_shell_root)
	_shell_root = null
	_free_generated_root(_furniture_root)
	_furniture_root = null
	_free_generated_root(_light_root)
	_light_root = null
	_free_generated_root(_glass_box_root)
	_glass_box_root = null
	_remove_children_named(&"RoomShell")
	_remove_children_named(&"Furniture")
	_remove_children_named(&"RoomLight")
	_remove_children_named(&"GlassBoxProp")


func _free_generated_root(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	remove_child(node)
	if Engine.is_editor_hint():
		node.free()
	else:
		node.queue_free()


func _remove_children_named(child_name: StringName) -> void:
	for child in get_children():
		if child.name != child_name:
			continue
		remove_child(child)
		if Engine.is_editor_hint():
			child.free()
		else:
			child.queue_free()


func _register_generated_node(node: Node) -> void:
	if not Engine.is_editor_hint():
		return
	var scene_root: Node = get_tree().edited_scene_root
	if scene_root == null or node == scene_root:
		return
	node.owner = scene_root
	for child in node.get_children():
		_register_generated_node(child)


func _refresh_glass_box_visuals(glass_box_root: Node3D) -> void:
	var glass_box: Node = glass_box_root.get_node_or_null("GlassBox")
	if glass_box != null and glass_box.has_method("rebuild"):
		glass_box.call("rebuild")


func _ensure_export_defaults() -> void:
	# Scenes saved before glass box exports were added can deserialize them as null.
	if get("spawn_glass_box") == null:
		spawn_glass_box = true
	if get("glass_box_size") == null:
		glass_box_size = Vector3(1.5, 1.5, 1.5)
