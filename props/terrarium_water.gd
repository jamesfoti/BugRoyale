class_name TerrariumWater
extends Node3D
## Shader water pool at the bottom of a terrarium with splash particles on entry.


const WATER_SURFACE_MATERIAL_PATH: String = "res://materials/terrarium_water.tres"
const WATER_VOLUME_MATERIAL_PATH: String = "res://materials/terrarium_water_volume.tres"
const SPLASH_PARTICLE_MATERIAL_PATH: String = "res://materials/water_splash_particle.tres"

const MIN_WATER_LEVEL_RATIO: float = 0.05
const MAX_WATER_LEVEL_RATIO: float = 0.6
const DEFAULT_WATER_LEVEL_RATIO: float = 0.18
const SURFACE_INSET: float = 0.04
const SPLASH_MIN_SPEED: float = 0.35
const SPLASH_COOLDOWN_SEC: float = 0.3
const SPLASH_AIR_PROBE_RATIO: float = 0.08
const MIN_SPLASH_AIR_PROBE: float = 1.0


var _world_size: Vector3 = Vector3.ONE * 5.0
var _water_level_y: float = 0.9
var _splash_detector: Area3D
var _splash_particles: GPUParticles3D
var _submerged_bodies: Dictionary = {}
var _last_splash_time: Dictionary = {}
var _last_body_y: Dictionary = {}


static func create(
	world_size: Vector3,
	water_level_ratio: float = DEFAULT_WATER_LEVEL_RATIO
) -> TerrariumWater:
	var water := TerrariumWater.new()
	water.name = "TerrariumWater"
	water._configure(world_size, water_level_ratio)
	water._build_visuals()
	water._build_splash_detector()
	water._build_splash_particles()
	return water


func _ready() -> void:
	if _splash_detector != null:
		_splash_detector.monitoring = not Engine.is_editor_hint()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _splash_detector == null:
		return
	var surface_y: float = get_water_surface_y()
	for body: Node3D in _splash_detector.get_overlapping_bodies():
		if not (body is PhysicsBody3D):
			continue
		var physics_body: PhysicsBody3D = body as PhysicsBody3D
		var anchor: Node = _get_splash_anchor(physics_body)
		var body_id: int = anchor.get_instance_id()
		var current_y: float = physics_body.global_position.y
		var previous_y: float = float(_last_body_y.get(body_id, current_y + 1.0))
		_last_body_y[body_id] = current_y
		if previous_y <= surface_y + 0.1:
			continue
		if current_y > surface_y + 0.25:
			continue
		var speed_y: float = _get_vertical_speed(physics_body)
		if speed_y > -SPLASH_MIN_SPEED and previous_y - current_y < 0.2:
			continue
		if not _can_splash(body_id):
			continue
		_submerged_bodies[body_id] = true
		_emit_splash(physics_body.global_position, speed_y)


func get_water_surface_y() -> float:
	return global_position.y + _water_level_y


## Moves the water surface to a world height (clamped to the terrarium), resizing the volume, the
## surface and the splash detector. Used by Battle Royale's rising water.
func set_water_surface_y(world_y: float) -> void:
	_water_level_y = clampf(world_y - global_position.y, 0.05, _world_size.y)
	var volume: MeshInstance3D = get_node_or_null("WaterVolume") as MeshInstance3D
	if volume != null:
		(volume.mesh as BoxMesh).size.y = _water_level_y
		volume.position.y = _water_level_y * 0.5
		if volume.material_override is ShaderMaterial:
			(volume.material_override as ShaderMaterial).set_shader_parameter("volume_height", _water_level_y)
	var surface: MeshInstance3D = get_node_or_null("WaterSurface") as MeshInstance3D
	if surface != null:
		surface.position.y = _water_level_y
	if _splash_detector != null:
		var air_probe: float = maxf(_world_size.y * SPLASH_AIR_PROBE_RATIO, MIN_SPLASH_AIR_PROBE)
		var detector_height: float = _water_level_y + air_probe
		_splash_detector.position.y = detector_height * 0.5
		var shape: CollisionShape3D = _splash_detector.get_child(0) as CollisionShape3D
		if shape != null and shape.shape is BoxShape3D:
			(shape.shape as BoxShape3D).size.y = detector_height


func get_water_level_ratio() -> float:
	if _world_size.y <= 0.001:
		return DEFAULT_WATER_LEVEL_RATIO
	return _water_level_y / _world_size.y


func _configure(world_size: Vector3, water_level_ratio: float) -> void:
	_world_size = world_size
	var ratio: float = clampf(water_level_ratio, MIN_WATER_LEVEL_RATIO, MAX_WATER_LEVEL_RATIO)
	_water_level_y = maxf(_world_size.y * ratio, 0.05)


func _build_visuals() -> void:
	var inner_x: float = maxf(_world_size.x - SURFACE_INSET * 2.0, 0.25)
	var inner_z: float = maxf(_world_size.z - SURFACE_INSET * 2.0, 0.25)

	if _water_level_y > 0.05:
		var volume := MeshInstance3D.new()
		volume.name = "WaterVolume"
		var volume_mesh := BoxMesh.new()
		volume_mesh.size = Vector3(inner_x, _water_level_y, inner_z)
		volume.mesh = volume_mesh
		volume.position = Vector3(0.0, _water_level_y * 0.5, 0.0)
		volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var volume_material: Material = _load_material(WATER_VOLUME_MATERIAL_PATH)
		if volume_material is ShaderMaterial:
			volume_material = (volume_material as ShaderMaterial).duplicate()
			(volume_material as ShaderMaterial).set_shader_parameter("volume_height", _water_level_y)
		volume.material_override = volume_material
		add_child(volume)

	var surface := MeshInstance3D.new()
	surface.name = "WaterSurface"
	var plane := PlaneMesh.new()
	plane.size = Vector2(inner_x, inner_z)
	surface.mesh = plane
	surface.position = Vector3(0.0, _water_level_y, 0.0)
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var surface_material: Material = _load_material(WATER_SURFACE_MATERIAL_PATH)
	if surface_material is ShaderMaterial:
		# Per-instance copy; shader params come from terrarium_water.tres.
		surface_material = (surface_material as ShaderMaterial).duplicate()
	surface.material_override = surface_material
	add_child(surface)


func _build_splash_detector() -> void:
	var air_probe: float = maxf(_world_size.y * SPLASH_AIR_PROBE_RATIO, MIN_SPLASH_AIR_PROBE)
	var detector_height: float = maxf(_water_level_y, 0.08) + air_probe

	var area := Area3D.new()
	area.name = "SplashDetector"
	area.monitoring = not Engine.is_editor_hint()
	area.monitorable = false
	area.collision_layer = 0
	area.collision_mask = 0x7FFFFFFF
	area.position = Vector3(0.0, detector_height * 0.5, 0.0)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(
		maxf(_world_size.x - SURFACE_INSET, 0.25),
		detector_height,
		maxf(_world_size.z - SURFACE_INSET, 0.25)
	)
	shape.shape = box
	area.add_child(shape)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	add_child(area)
	_splash_detector = area


func _build_splash_particles() -> void:
	var particle_size: float = _get_particle_quad_size()
	var world_span: float = maxf(_world_size.x, maxf(_world_size.y, _world_size.z))
	var velocity_scale: float = maxf(world_span * 0.08, 1.0)

	_splash_particles = GPUParticles3D.new()
	_splash_particles.name = "SplashParticles"
	_splash_particles.emitting = false
	_splash_particles.one_shot = true
	_splash_particles.explosiveness = 1.0
	_splash_particles.amount = 48
	_splash_particles.lifetime = 0.75
	_splash_particles.randomness = 0.45
	_splash_particles.local_coords = false
	_splash_particles.visibility_aabb = AABB(
		Vector3(-world_span, -world_span * 0.25, -world_span),
		Vector3(world_span * 2.0, world_span, world_span * 2.0)
	)
	_splash_particles.position = Vector3(0.0, _water_level_y, 0.0)
	_splash_particles.process_material = _create_splash_process_material(velocity_scale)
	_splash_particles.draw_pass_1 = _create_splash_quad_mesh(particle_size)
	_splash_particles.material_override = _load_material(SPLASH_PARTICLE_MATERIAL_PATH)
	add_child(_splash_particles)


func _get_particle_quad_size() -> float:
	return clampf(minf(_world_size.x, _world_size.z) * 0.015, 0.15, 2.5)


func _create_splash_process_material(velocity_scale: float) -> ParticleProcessMaterial:
	var gradient := Gradient.new()
	gradient.set_offsets(PackedFloat32Array([0.0, 0.35, 0.75, 1.0]))
	gradient.set_colors(PackedColorArray([
		Color(0.85, 0.97, 1.0, 0.0),
		Color(0.7, 0.92, 1.0, 0.95),
		Color(0.25, 0.65, 0.95, 0.55),
		Color(0.1, 0.4, 0.8, 0.0),
	]))
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = gradient

	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = maxf(velocity_scale * 0.12, 0.15)
	process_material.direction = Vector3(0.0, 1.0, 0.0)
	process_material.spread = 52.0
	process_material.initial_velocity_min = velocity_scale * 0.9
	process_material.initial_velocity_max = velocity_scale * 2.4
	process_material.angular_velocity_min = -10.0
	process_material.angular_velocity_max = 10.0
	process_material.gravity = Vector3(0.0, -9.8 * maxf(velocity_scale * 0.35, 1.0), 0.0)
	var particle_scale: float = _get_particle_quad_size()
	process_material.scale_min = particle_scale * 0.65
	process_material.scale_max = particle_scale * 1.35
	process_material.color_ramp = gradient_texture
	return process_material


func _create_splash_quad_mesh(size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	return quad


func _on_body_entered(body: Node3D) -> void:
	if not (body is PhysicsBody3D):
		return
	var physics_body: PhysicsBody3D = body as PhysicsBody3D
	var anchor: Node = _get_splash_anchor(physics_body)
	var body_id: int = anchor.get_instance_id()
	if _submerged_bodies.has(body_id):
		return
	_submerged_bodies[body_id] = true

	var speed_y: float = _get_vertical_speed(physics_body)
	var surface_y: float = get_water_surface_y()
	var entering_from_above: bool = physics_body.global_position.y >= surface_y - 0.15
	if not entering_from_above and speed_y > -SPLASH_MIN_SPEED:
		return
	if not _can_splash(body_id):
		return
	_emit_splash(physics_body.global_position, speed_y)


func _on_body_exited(body: Node3D) -> void:
	if not (body is PhysicsBody3D):
		return
	var anchor: Node = _get_splash_anchor(body as PhysicsBody3D)
	var body_id: int = anchor.get_instance_id()
	_submerged_bodies.erase(body_id)
	_last_body_y.erase(body_id)


func _get_splash_anchor(body: PhysicsBody3D) -> Node:
	if body.is_in_group("player"):
		return body
	var node: Node = body.get_parent()
	while node != null:
		if node.is_in_group("player"):
			return node
		node = node.get_parent()
	return body


func _can_splash(body_id: int) -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	var last_time: float = float(_last_splash_time.get(body_id, 0.0))
	if now - last_time < SPLASH_COOLDOWN_SEC:
		return false
	_last_splash_time[body_id] = now
	return true


func _emit_splash(world_position: Vector3, speed_y: float) -> void:
	if _splash_particles == null:
		return
	var world_span: float = maxf(_world_size.x, maxf(_world_size.y, _world_size.z))
	var velocity_scale: float = maxf(world_span * 0.08, 1.0)
	var impact: float = clampf(absf(speed_y), 0.5, velocity_scale * 2.0)
	_splash_particles.global_position = Vector3(
		world_position.x,
		get_water_surface_y(),
		world_position.z
	)
	_splash_particles.amount = clampi(24 + int(impact * 4.0), 24, 96)
	var process_material: ParticleProcessMaterial = _splash_particles.process_material as ParticleProcessMaterial
	if process_material != null:
		process_material.initial_velocity_min = velocity_scale * 0.6 + impact * 0.2
		process_material.initial_velocity_max = velocity_scale * 1.6 + impact * 0.45
	_splash_particles.restart()
	_splash_particles.emitting = true


func _get_vertical_speed(body: Node) -> float:
	if body is CharacterBody3D:
		return (body as CharacterBody3D).velocity.y
	if body is RigidBody3D:
		return (body as RigidBody3D).linear_velocity.y
	return 0.0


func _load_material(path: String) -> Material:
	if ResourceLoader.exists(path):
		return load(path) as Material
	return null
