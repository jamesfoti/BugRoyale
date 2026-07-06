class_name InteriorRoomLighting
extends RefCounted
## Ceiling light for a single interior room.


static func build(layout: InteriorRoomLayout.Layout, light_energy: float) -> Node3D:
	var root := Node3D.new()
	root.name = "RoomLight"

	var center: Vector3 = layout.world_aabb.get_center()
	var ceiling_y: float = layout.world_aabb.position.y + layout.world_aabb.size.y - 0.15

	var light := OmniLight3D.new()
	light.position = Vector3(center.x, ceiling_y, center.z)
	light.light_energy = maxf(light_energy, 0.1)
	light.omni_range = maxf(layout.world_aabb.size.x, layout.world_aabb.size.z) * 0.75
	light.shadow_enabled = true
	root.add_child(light)
	return root
