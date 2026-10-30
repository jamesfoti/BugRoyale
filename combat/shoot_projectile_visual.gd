class_name ShootProjectileVisual
extends Node3D
## Short-lived sphere that travels toward the shot target.

signal arrived

## One sphere mesh per radius and one material for every projectile, instead of a fresh mesh
## and material per shot (automatic weapons fire 9-12 of these a second).
static var _shared_meshes: Dictionary = {}
static var _shared_material: StandardMaterial3D

@export var travel_speed: float = 140.0

var _target_position: Vector3 = Vector3.ZERO
var _is_flying: bool = false


func launch(start_position: Vector3, target_position: Vector3, projectile_radius: float) -> void:
	global_position = start_position
	_target_position = target_position
	_is_flying = true
	_configure_mesh(projectile_radius)


func _process(delta: float) -> void:
	if not _is_flying:
		return

	var offset_to_target: Vector3 = _target_position - global_position
	var distance_remaining: float = offset_to_target.length()
	var travel_distance: float = travel_speed * delta
	if distance_remaining <= travel_distance:
		global_position = _target_position
		_is_flying = false
		arrived.emit()
		queue_free()
		return

	global_position += offset_to_target.normalized() * travel_distance


func _configure_mesh(projectile_radius: float) -> void:
	var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_instance == null:
		return
	var mesh_key: float = snappedf(projectile_radius, 0.005)
	var sphere_mesh: SphereMesh = _shared_meshes.get(mesh_key) as SphereMesh
	if sphere_mesh == null:
		sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = mesh_key
		sphere_mesh.height = mesh_key * 2.0
		sphere_mesh.radial_segments = 12
		sphere_mesh.rings = 8
		_shared_meshes[mesh_key] = sphere_mesh
	mesh_instance.mesh = sphere_mesh

	if _shared_material == null:
		_shared_material = StandardMaterial3D.new()
		_shared_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shared_material.albedo_color = Color(1.0, 0.82, 0.35, 1.0)
		_shared_material.emission_enabled = true
		_shared_material.emission = Color(1.0, 0.55, 0.12, 1.0)
		_shared_material.emission_energy_multiplier = 1.8
	mesh_instance.material_override = _shared_material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
