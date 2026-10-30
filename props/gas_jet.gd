class_name GasJet
extends Node3D
## A jet of burning gas from a broken line, like a lit flamethrower: a stream of flame
## sprites along one direction, a flickering light, and a damage zone the length of the jet
## that burns any bug standing in it. One emitter and one light, so a dozen of them cost
## little; it never ignites other pipes.

const TICK_SECONDS: float = 0.2

var direction: Vector3 = Vector3.DOWN
var length: float = 6.0
var radius: float = 1.0
var damage_per_second: float = 10.0
var seconds: float = 20.0

var _particles: GPUParticles3D
var _light: OmniLight3D
var _area: Area3D
var _tick: float = 0.0
var _lit_for: float = 0.0
var _burning: bool = true


static func create(
	jet_direction: Vector3, jet_length: float, jet_radius: float, damage: float, burn_seconds: float
) -> GasJet:
	var jet := GasJet.new()
	jet.name = "GasJet"
	jet.direction = jet_direction.normalized()
	jet.length = jet_length
	jet.radius = jet_radius
	jet.damage_per_second = damage
	jet.seconds = burn_seconds
	return jet


func _ready() -> void:
	# The jet runs along the node's -Z.
	look_at(
		global_position + direction,
		Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	)
	_build_flames()
	_build_light()
	_build_damage_zone()


func _physics_process(delta: float) -> void:
	_lit_for += delta
	if _burning and _lit_for >= seconds:
		_burning = false
		_particles.emitting = false
		_area.monitoring = false
		var fade: Tween = create_tween()
		fade.tween_property(_light, "light_energy", 0.0, 0.6)
		get_tree().create_timer(_particles.lifetime + 0.7).timeout.connect(queue_free)
		return
	if not _burning:
		return
	_light.light_energy = 2.2 + 0.8 * sin(_lit_for * 23.0) * sin(_lit_for * 7.3)
	_tick += delta
	if _tick < TICK_SECONDS:
		return
	_tick = 0.0
	for body: Node3D in _area.get_overlapping_bodies():
		if body is UtilityPipe:
			continue
		var damageable: Damageable = _resolve_damageable(body)
		if damageable != null and damageable.is_alive():
			damageable.apply_damage(damage_per_second * TICK_SECONDS, self)


func _build_flames() -> void:
	_particles = GPUParticles3D.new()
	_particles.name = "Flames"
	var speed: float = length / 0.5
	_particles.amount = 96
	_particles.lifetime = 0.55
	_particles.local_coords = true
	_particles.visibility_aabb = AABB(
		Vector3(-radius * 3.0, -radius * 3.0, -length * 1.3),
		Vector3(radius * 6.0, radius * 6.0, length * 1.3 + radius * 3.0)
	)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius * 0.25
	process.direction = Vector3(0.0, 0.0, -1.0)
	process.spread = 6.0
	process.initial_velocity_min = speed * 0.85
	process.initial_velocity_max = speed * 1.1
	process.gravity = Vector3(0.0, radius * 2.0, 0.0)
	process.damping_min = speed * 0.4
	process.damping_max = speed * 0.6
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.35))
	scale_curve.add_point(Vector2(0.5, 1.0))
	scale_curve.add_point(Vector2(1.0, 1.5))
	var scale_texture := CurveTexture.new()
	scale_texture.curve = scale_curve
	process.scale_curve = scale_texture
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	ramp.set_color(1, Color(0.5, 0.05, 0.0, 0.0))
	ramp.add_point(0.35, Color(1.0, 0.55, 0.1, 0.9))
	ramp.add_point(0.7, Color(0.8, 0.2, 0.02, 0.5))
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	process.color_ramp = ramp_texture
	_particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * radius * 1.4
	_particles.draw_pass_1 = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _soft_dot()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_particles.material_override = material
	add_child(_particles)


## A round, soft sprite for the flame quads.
static func _soft_dot() -> GradientTexture2D:
	var texture := GradientTexture2D.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.45, Color(1.0, 1.0, 1.0, 0.8))
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture


func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.light_color = Color(1.0, 0.6, 0.25)
	_light.light_energy = 2.5
	_light.omni_range = length * 1.2
	_light.omni_attenuation = 1.2
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 0.0, -length * 0.4)
	add_child(_light)


func _build_damage_zone() -> void:
	_area = Area3D.new()
	_area.name = "Burn"
	_area.collision_layer = 0
	_area.collision_mask = MapInfo.FIGHTER_LAYER | 4 | 8
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = length
	shape.shape = cylinder
	# The cylinder's axis is Y; turn it onto the jet's -Z.
	shape.rotation.x = -PI * 0.5
	shape.position = Vector3(0.0, 0.0, -length * 0.5)
	_area.add_child(shape)
	add_child(_area)


func _resolve_damageable(target: Node) -> Damageable:
	if target is Damageable:
		return target as Damageable
	var direct: Damageable = target.get_node_or_null("Damageable") as Damageable
	if direct != null:
		return direct
	var parent_node: Node = target.get_parent()
	if parent_node == null:
		return null
	return parent_node.get_node_or_null("Damageable") as Damageable
