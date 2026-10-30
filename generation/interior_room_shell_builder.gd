class_name InteriorRoomShellBuilder
extends RefCounted
## Floor, ceiling, and wall meshes for a single interior room.


static func build(layout: InteriorRoomLayout.Layout, wall_thickness: float) -> Node3D:
	var root := Node3D.new()
	root.name = "RoomShell"

	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.62, 0.58, 0.52)
	floor_material.roughness = 0.85

	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.78, 0.76, 0.72)
	wall_material.roughness = 0.9

	var ceiling_material := StandardMaterial3D.new()
	ceiling_material.albedo_color = Color(0.9, 0.9, 0.92)
	ceiling_material.roughness = 0.95

	_add_room_shell(
		root,
		layout.world_aabb,
		maxf(wall_thickness, 0.2),
		floor_material,
		wall_material,
		ceiling_material
	)
	return root


static func _add_room_shell(
	parent: Node3D,
	bounds: AABB,
	wall_thickness: float,
	floor_material: StandardMaterial3D,
	wall_material: StandardMaterial3D,
	ceiling_material: StandardMaterial3D
) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	parent.add_child(body)

	var center: Vector3 = bounds.get_center()
	var floor_y: float = bounds.position.y
	var story_height: float = bounds.size.y
	var ceiling_y: float = floor_y + story_height

	_add_box_part(
		body,
		Vector3(bounds.size.x, 0.12, bounds.size.z),
		Vector3(center.x, floor_y + 0.06, center.z),
		floor_material
	)
	_add_box_part(
		body,
		Vector3(bounds.size.x, 0.08, bounds.size.z),
		Vector3(center.x, ceiling_y - 0.04, center.z),
		ceiling_material
	)
	_add_box_part(
		body,
		Vector3(bounds.size.x, story_height, wall_thickness),
		Vector3(center.x, floor_y + story_height * 0.5, bounds.position.z + wall_thickness * 0.5),
		wall_material
	)
	_add_box_part(
		body,
		Vector3(bounds.size.x, story_height, wall_thickness),
		Vector3(
			center.x,
			floor_y + story_height * 0.5,
			bounds.position.z + bounds.size.z - wall_thickness * 0.5
		),
		wall_material
	)
	_add_box_part(
		body,
		Vector3(wall_thickness, story_height, bounds.size.z),
		Vector3(bounds.position.x + wall_thickness * 0.5, floor_y + story_height * 0.5, center.z),
		wall_material
	)
	_add_box_part(
		body,
		Vector3(wall_thickness, story_height, bounds.size.z),
		Vector3(
			bounds.position.x + bounds.size.x - wall_thickness * 0.5,
			floor_y + story_height * 0.5,
			center.z
		),
		wall_material
	)


static func _add_box_part(
	parent: Node3D, size: Vector3, position: Vector3, material: StandardMaterial3D
) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = material
	mesh_instance.position = position
	parent.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = position
	parent.add_child(collision)
