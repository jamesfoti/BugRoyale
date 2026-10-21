@tool
extends Node3D
class_name GlassBox
## 1 m reference glass box. Uses imported GLB when present, otherwise builds thin panels.


const GLB_PATH: String = "res://props/glass_box/glass_box.glb"
const REFERENCE_SIZE: Vector3 = Vector3.ONE
const WALL_THICKNESS: float = 0.025
const WALL_COLLISION_LAYER: int = 1


func _ready() -> void:
	if not Engine.is_editor_hint() or is_inside_tree():
		rebuild()


func rebuild() -> void:
	_clear_visuals()
	if _try_spawn_imported_mesh():
		return
	_build_procedural_panels()


func get_reference_size() -> Vector3:
	return REFERENCE_SIZE


func get_bottom_y() -> float:
	return global_position.y


func _clear_visuals() -> void:
	for child in get_children():
		remove_child(child)
		if Engine.is_editor_hint():
			child.free()
		else:
			child.queue_free()


func _try_spawn_imported_mesh() -> bool:
	if not ResourceLoader.exists(GLB_PATH):
		return false
	var scene: PackedScene = load(GLB_PATH) as PackedScene
	if scene == null:
		return false
	var model: Node3D = scene.instantiate() as Node3D
	if model == null:
		return false
	model.name = "Model"
	add_child(model)
	if Engine.is_editor_hint() and is_inside_tree():
		model.owner = get_tree().edited_scene_root
	return true


func _build_procedural_panels() -> void:
	var glass_material := _create_glass_material()
	var sx: float = REFERENCE_SIZE.x
	var sy: float = REFERENCE_SIZE.y
	var sz: float = REFERENCE_SIZE.z
	var thickness: float = WALL_THICKNESS

	# Every panel collides (including the floor) so climbing bugs can't crawl out of the terrarium.
	_add_panel("Bottom", Vector3(sx, thickness, sz), Vector3(0.0, thickness * 0.5, 0.0), glass_material)
	_add_panel("Top", Vector3(sx, thickness, sz), Vector3(0.0, sy - thickness * 0.5, 0.0), glass_material)
	_add_panel(
		"Front",
		Vector3(sx, sy, thickness),
		Vector3(0.0, sy * 0.5, sz * 0.5 - thickness * 0.5),
		glass_material
	)
	_add_panel(
		"Back",
		Vector3(sx, sy, thickness),
		Vector3(0.0, sy * 0.5, -sz * 0.5 + thickness * 0.5),
		glass_material
	)
	_add_panel(
		"Left",
		Vector3(thickness, sy, sz),
		Vector3(-sx * 0.5 + thickness * 0.5, sy * 0.5, 0.0),
		glass_material
	)
	_add_panel(
		"Right",
		Vector3(thickness, sy, sz),
		Vector3(sx * 0.5 - thickness * 0.5, sy * 0.5, 0.0),
		glass_material
	)


func _add_panel(
	panel_name: String,
	size: Vector3,
	position: Vector3,
	material: StandardMaterial3D,
	include_collision: bool = true
) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = panel_name
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = material
	mesh_instance.position = position
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	if include_collision:
		_add_panel_collider(panel_name, size, position)
	if Engine.is_editor_hint() and is_inside_tree():
		mesh_instance.owner = get_tree().edited_scene_root


func _add_panel_collider(panel_name: String, size: Vector3, position: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "%sCollider" % panel_name
	body.collision_layer = WALL_COLLISION_LAYER
	body.collision_mask = 0
	body.position = position

	var shape_node := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape_node.shape = box_shape
	body.add_child(shape_node)
	add_child(body)

	if Engine.is_editor_hint() and is_inside_tree():
		body.owner = get_tree().edited_scene_root
		shape_node.owner = get_tree().edited_scene_root


## Glass tint. Shaded per vertex and (for box panels, whose inner faces point inward) back-face
## culled: a transparent panel is a full-screen layer from inside the terrarium, and per-pixel
## lighting on several of them costs an integrated GPU 10 ms a frame. The bowl's single-sided
## sphere keeps both faces so it is visible from inside.
static func _create_glass_material(two_sided: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.85, 0.95, 1.0, 0.2)
	material.roughness = 0.04
	material.metallic = 0.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.cull_mode = BaseMaterial3D.CULL_DISABLED if two_sided else BaseMaterial3D.CULL_BACK
	return material
