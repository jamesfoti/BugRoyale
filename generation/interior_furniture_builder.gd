class_name InteriorFurnitureBuilder
extends RefCounted
## Builds recognizable furniture from simple box primitives.


static func build(
	placement: InteriorRoomFurniture.Placement, furniture_scale: float = 1.0
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	body.position = placement.position
	body.rotation.y = placement.rotation_y
	body.name = InteriorRoomFurniture.FurnitureType.keys()[placement.furniture_type]
	var mesh_scale: float = maxf(furniture_scale, 0.1)

	match placement.furniture_type:
		InteriorRoomFurniture.FurnitureType.COUCH:
			_build_couch(body)
		InteriorRoomFurniture.FurnitureType.ARMCHAIR:
			_build_armchair(body)
		InteriorRoomFurniture.FurnitureType.COFFEE_TABLE:
			_build_coffee_table(body)
		InteriorRoomFurniture.FurnitureType.DINING_TABLE:
			_build_dining_table(body)
		InteriorRoomFurniture.FurnitureType.CHAIR, InteriorRoomFurniture.FurnitureType.DESK_CHAIR:
			_build_chair(body)
		InteriorRoomFurniture.FurnitureType.BED:
			_build_bed(body)
		InteriorRoomFurniture.FurnitureType.DESK:
			_build_desk(body)
		InteriorRoomFurniture.FurnitureType.DRESSER:
			_build_dresser(body)
		InteriorRoomFurniture.FurnitureType.BOOKSHELF:
			_build_bookshelf(body)
		InteriorRoomFurniture.FurnitureType.COUNTER:
			_build_counter(body)
		InteriorRoomFurniture.FurnitureType.ISLAND:
			_build_island(body)
		InteriorRoomFurniture.FurnitureType.TOILET:
			_build_toilet(body)
		InteriorRoomFurniture.FurnitureType.SINK:
			_build_sink(body)
		InteriorRoomFurniture.FurnitureType.TUB:
			_build_tub(body)
		InteriorRoomFurniture.FurnitureType.TV_STAND:
			_build_tv_stand(body)
		InteriorRoomFurniture.FurnitureType.FLOOR_LAMP:
			_build_floor_lamp(body)
		InteriorRoomFurniture.FurnitureType.RUG:
			_build_rug(body)
	if mesh_scale != 1.0:
		body.scale = Vector3.ONE * mesh_scale
	return body


static func _add_box(
	parent: Node3D, size: Vector3, position: Vector3, color: Color, add_collision: bool = true
) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh_instance.material_override = material
	mesh_instance.position = position
	parent.add_child(mesh_instance)
	if add_collision:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		collision.position = position
		parent.add_child(collision)


static func _add_four_legs(
	parent: Node3D,
	footprint_x: float,
	footprint_z: float,
	leg_height: float,
	inset: float,
	leg_size: float,
	color: Color,
	add_collision: bool = true
) -> void:
	if leg_height <= 0.05:
		return
	var offset_x: float = footprint_x * 0.5 - inset
	var offset_z: float = footprint_z * 0.5 - inset
	var leg_dim := Vector3(leg_size, leg_height, leg_size)
	var leg_y: float = leg_height * 0.5
	for x_sign: float in [-1.0, 1.0]:
		for z_sign: float in [-1.0, 1.0]:
			_add_box(
				parent,
				leg_dim,
				Vector3(x_sign * offset_x, leg_y, z_sign * offset_z),
				color,
				add_collision
			)


static func _build_table_with_legs(
	parent: Node3D,
	top_size: Vector3,
	top_center_y: float,
	color: Color,
	leg_inset: float = 0.1,
	leg_size: float = 0.06
) -> void:
	_add_box(parent, top_size, Vector3(0.0, top_center_y, 0.0), color)
	var leg_height: float = top_center_y - top_size.y * 0.5
	var leg_color := color.darkened(0.08)
	_add_four_legs(parent, top_size.x, top_size.z, leg_height, leg_inset, leg_size, leg_color)


static func _build_couch(parent: Node3D) -> void:
	_add_box(parent, Vector3(2.2, 0.45, 0.9), Vector3(0.0, 0.225, 0.0), Color(0.45, 0.35, 0.55))
	_add_box(parent, Vector3(2.2, 0.55, 0.2), Vector3(0.0, 0.55, -0.35), Color(0.42, 0.32, 0.52))


static func _build_armchair(parent: Node3D) -> void:
	_add_box(parent, Vector3(0.9, 0.4, 0.9), Vector3(0.0, 0.2, 0.0), Color(0.5, 0.4, 0.35))
	_add_box(parent, Vector3(0.9, 0.5, 0.15), Vector3(0.0, 0.45, -0.38), Color(0.48, 0.38, 0.33))


static func _build_coffee_table(parent: Node3D) -> void:
	_build_table_with_legs(
		parent, Vector3(1.1, 0.08, 0.7), 0.35, Color(0.35, 0.25, 0.15), 0.12, 0.05
	)


static func _build_dining_table(parent: Node3D) -> void:
	_build_table_with_legs(
		parent, Vector3(1.6, 0.08, 0.9), 0.75, Color(0.4, 0.28, 0.18), 0.14, 0.07
	)


static func _build_chair(parent: Node3D) -> void:
	var color := Color(0.38, 0.28, 0.2)
	var seat_size := Vector3(0.45, 0.05, 0.45)
	var seat_y: float = 0.45
	_add_box(parent, seat_size, Vector3(0.0, seat_y, 0.0), color)
	_add_four_legs(
		parent,
		seat_size.x,
		seat_size.z,
		seat_y - seat_size.y * 0.5,
		0.05,
		0.04,
		color.darkened(0.08)
	)
	_add_box(parent, Vector3(0.45, 0.5, 0.08), Vector3(0.0, 0.7, -0.2), color)


static func _build_bed(parent: Node3D) -> void:
	var mattress_color := Color(0.85, 0.85, 0.9)
	var frame_color := Color(0.55, 0.45, 0.4)
	var leg_color := frame_color.darkened(0.1)
	var leg_height: float = 0.12
	var leg_size: float = 0.08
	var base_thickness: float = 0.08
	var mattress_size := Vector3(1.6, 0.35, 2.1)
	var frame_size := Vector3(mattress_size.x - 0.12, base_thickness, mattress_size.z - 0.12)
	var frame_y: float = leg_height + base_thickness * 0.5
	var mattress_y: float = leg_height + base_thickness + mattress_size.y * 0.5

	_add_four_legs(parent, frame_size.x, frame_size.z, leg_height, 0.04, leg_size, leg_color)
	_add_box(parent, frame_size, Vector3(0.0, frame_y, 0.0), frame_color)
	_add_box(parent, mattress_size, Vector3(0.0, mattress_y, 0.0), mattress_color)
	_add_box(
		parent,
		Vector3(1.6, 0.6, 0.15),
		Vector3(0.0, mattress_y + 0.25, -mattress_size.z * 0.5 + 0.075),
		frame_color
	)


static func _build_desk(parent: Node3D) -> void:
	_build_table_with_legs(
		parent, Vector3(1.3, 0.08, 0.65), 0.75, Color(0.42, 0.3, 0.2), 0.12, 0.06
	)


static func _build_dresser(parent: Node3D) -> void:
	_add_box(parent, Vector3(1.0, 0.9, 0.45), Vector3(0.0, 0.45, 0.0), Color(0.4, 0.3, 0.22))


static func _build_bookshelf(parent: Node3D) -> void:
	_add_box(parent, Vector3(0.9, 1.8, 0.35), Vector3(0.0, 0.9, 0.0), Color(0.35, 0.25, 0.18))


static func _build_counter(parent: Node3D) -> void:
	_add_box(parent, Vector3(2.0, 0.9, 0.6), Vector3(0.0, 0.45, 0.0), Color(0.75, 0.75, 0.78))


static func _build_island(parent: Node3D) -> void:
	_add_box(parent, Vector3(1.2, 0.9, 0.8), Vector3(0.0, 0.45, 0.0), Color(0.7, 0.7, 0.72))


static func _build_toilet(parent: Node3D) -> void:
	_add_box(parent, Vector3(0.45, 0.4, 0.6), Vector3(0.0, 0.2, 0.0), Color(0.92, 0.92, 0.94))


static func _build_sink(parent: Node3D) -> void:
	_add_box(parent, Vector3(0.6, 0.85, 0.45), Vector3(0.0, 0.425, 0.0), Color(0.88, 0.88, 0.9))


static func _build_tub(parent: Node3D) -> void:
	_add_box(parent, Vector3(1.5, 0.55, 0.75), Vector3(0.0, 0.275, 0.0), Color(0.9, 0.9, 0.92))


static func _build_tv_stand(parent: Node3D) -> void:
	var color := Color(0.2, 0.2, 0.22)
	_build_table_with_legs(parent, Vector3(1.4, 0.06, 0.4), 0.45, color, 0.12, 0.05)
	_add_box(
		parent, Vector3(1.2, 0.7, 0.06), Vector3(0.0, 0.75, -0.05), Color(0.08, 0.08, 0.1), false
	)


static func _build_floor_lamp(parent: Node3D) -> void:
	_add_box(
		parent, Vector3(0.08, 1.6, 0.08), Vector3(0.0, 0.8, 0.0), Color(0.25, 0.25, 0.28), false
	)
	_add_box(
		parent, Vector3(0.35, 0.2, 0.35), Vector3(0.0, 1.5, 0.0), Color(0.95, 0.9, 0.75), false
	)


static func _build_rug(parent: Node3D) -> void:
	_add_box(
		parent, Vector3(2.0, 0.02, 1.4), Vector3(0.0, 0.01, 0.0), Color(0.55, 0.35, 0.3), false
	)
