class_name Beacon
extends MeshInstance3D
## A tall column of light over a point on the map: an extraction point, a colony's nest, a
## hill. Unshaded and translucent so it reads from across the map; the colour says whose it is.


## Builds a beacon in the map at a ground point, standing along the map's up there.
static func build(
	parent: Node,
	map: MapInfo,
	point: Vector3,
	color: Color,
	radius: float = 2.5,
	height: float = 60.0
) -> Beacon:
	var beacon := Beacon.new()
	var column := CylinderMesh.new()
	column.top_radius = radius
	column.bottom_radius = radius
	column.height = height
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission_energy_multiplier = 1.5
	column.material = material
	beacon.mesh = column
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(beacon)
	beacon.set_color(color)
	beacon.move_to(map, point)
	return beacon


func set_color(color: Color) -> void:
	var material: StandardMaterial3D = (mesh as CylinderMesh).material as StandardMaterial3D
	material.albedo_color = Color(color.r, color.g, color.b, 0.22)
	material.emission = color


## Stands the beacon on a ground point, along the map's up there.
func move_to(map: MapInfo, point: Vector3) -> void:
	var up: Vector3 = map.up_at(point)
	var side: Vector3 = (
		up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	)
	var height: float = (mesh as CylinderMesh).height
	global_transform = Transform3D(
		Basis(side, up, side.cross(up).normalized()), point + up * height * 0.5
	)
