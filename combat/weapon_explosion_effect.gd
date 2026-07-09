extends Node3D
class_name WeaponExplosionEffect
## One-shot weapon impact burst inspired by Godot's 3D particles demo.


const SMOKE_TEXTURE_PATH: String = "res://combat/effects/smoke_05.png"
const EFFECT_LIFETIME_SECONDS: float = 2.0

var _cleanup_timer_seconds: float = 0.0


static func spawn(world_root: Node, explosion_position: Vector3, explosion_radius: float) -> void:
	var effect: WeaponExplosionEffect = WeaponExplosionEffect.new()
	world_root.add_child(effect)
	effect.play(explosion_position, explosion_radius)


func play(explosion_position: Vector3, explosion_radius: float) -> void:
	global_position = explosion_position
	var effect_scale: float = clampf(explosion_radius / 2.0, 0.45, 2.5)
	_add_burst_particles(effect_scale)
	_add_fire_particles(effect_scale)
	_add_smoke_particles(effect_scale)
	_add_flash_light(effect_scale)
	_cleanup_timer_seconds = EFFECT_LIFETIME_SECONDS


func _process(delta: float) -> void:
	if _cleanup_timer_seconds <= 0.0:
		return
	_cleanup_timer_seconds -= delta
	if _cleanup_timer_seconds <= 0.0:
		queue_free()


func _add_burst_particles(effect_scale: float) -> void:
	var burst_particles: GPUParticles3D = GPUParticles3D.new()
	burst_particles.name = "BurstParticles"
	burst_particles.emitting = true
	burst_particles.one_shot = true
	burst_particles.explosiveness = 1.0
	burst_particles.amount = clampi(int(120.0 * effect_scale), 80, 320)
	burst_particles.lifetime = 1.1
	burst_particles.randomness = 0.2
	burst_particles.local_coords = false
	burst_particles.visibility_aabb = _build_visibility_aabb(effect_scale)
	burst_particles.process_material = _create_burst_process_material(effect_scale)
	burst_particles.draw_pass_1 = _create_billboard_quad_mesh(effect_scale * 0.18)
	burst_particles.material_override = _create_smoke_billboard_material(0.45)
	add_child(burst_particles)
	burst_particles.restart()


func _add_fire_particles(effect_scale: float) -> void:
	var fire_particles: GPUParticles3D = GPUParticles3D.new()
	fire_particles.name = "FireParticles"
	fire_particles.emitting = true
	fire_particles.one_shot = true
	fire_particles.explosiveness = 0.85
	fire_particles.amount = clampi(int(70.0 * effect_scale), 40, 140)
	fire_particles.lifetime = 0.75
	fire_particles.randomness = 0.35
	fire_particles.local_coords = false
	fire_particles.visibility_aabb = _build_visibility_aabb(effect_scale)
	fire_particles.process_material = _create_fire_process_material(effect_scale)
	fire_particles.draw_pass_1 = _create_billboard_quad_mesh(effect_scale * 0.22)
	fire_particles.material_override = _create_smoke_billboard_material(0.35)
	add_child(fire_particles)
	fire_particles.restart()


func _add_smoke_particles(effect_scale: float) -> void:
	var smoke_particles: GPUParticles3D = GPUParticles3D.new()
	smoke_particles.name = "SmokeParticles"
	smoke_particles.emitting = true
	smoke_particles.one_shot = true
	smoke_particles.explosiveness = 0.7
	smoke_particles.amount = clampi(int(55.0 * effect_scale), 30, 110)
	smoke_particles.lifetime = 1.4
	smoke_particles.randomness = 0.4
	smoke_particles.local_coords = false
	smoke_particles.draw_order = 1
	smoke_particles.visibility_aabb = _build_visibility_aabb(effect_scale * 1.4)
	smoke_particles.process_material = _create_smoke_process_material(effect_scale)
	smoke_particles.draw_pass_1 = _create_billboard_quad_mesh(effect_scale * 0.35)
	smoke_particles.material_override = _create_smoke_billboard_material(0.3)
	add_child(smoke_particles)
	smoke_particles.restart()


func _add_flash_light(effect_scale: float) -> void:
	var flash_light: OmniLight3D = OmniLight3D.new()
	flash_light.name = "FlashLight"
	flash_light.light_color = Color(1.0, 0.72, 0.38, 1.0)
	flash_light.light_energy = 2.5 * effect_scale
	flash_light.omni_range = 3.5 * effect_scale
	flash_light.omni_attenuation = 0.8
	flash_light.shadow_enabled = false
	add_child(flash_light)
	var fade_tween: Tween = create_tween()
	fade_tween.tween_property(flash_light, "light_energy", 0.0, 0.35)


func _build_visibility_aabb(effect_scale: float) -> AABB:
	var extent: float = 4.0 * effect_scale
	return AABB(Vector3(-extent, -extent, -extent), Vector3(extent * 2.0, extent * 2.0, extent * 2.0))


func _create_burst_process_material(effect_scale: float) -> ParticleProcessMaterial:
	var color_ramp: GradientTexture1D = _create_burst_color_ramp()
	var process_material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 0.2 * effect_scale
	process_material.direction = Vector3(0.0, 1.0, 0.0)
	process_material.spread = 180.0
	process_material.initial_velocity_min = 3.0 * effect_scale
	process_material.initial_velocity_max = 5.0 * effect_scale
	process_material.angular_velocity_min = -360.0
	process_material.angular_velocity_max = 360.0
	process_material.gravity = Vector3.ZERO
	process_material.damping_min = 3.0
	process_material.damping_max = 3.5
	process_material.scale_min = 0.15 * effect_scale
	process_material.scale_max = 0.85 * effect_scale
	process_material.color = Color(4.0, 4.0, 4.0, 1.0)
	process_material.color_ramp = color_ramp
	return process_material


func _create_fire_process_material(effect_scale: float) -> ParticleProcessMaterial:
	var color_ramp: GradientTexture1D = _create_fire_color_ramp()
	var scale_curve: CurveTexture = _create_constant_scale_curve()
	var process_material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(0.35, 0.0, 0.35) * effect_scale
	process_material.direction = Vector3(0.0, 1.0, 0.0)
	process_material.spread = 18.0
	process_material.initial_velocity_min = 0.8 * effect_scale
	process_material.initial_velocity_max = 3.2 * effect_scale
	process_material.angular_velocity_min = -180.0
	process_material.angular_velocity_max = 180.0
	process_material.gravity = Vector3.ZERO
	process_material.damping_min = 1.8
	process_material.damping_max = 2.4
	process_material.scale_min = 0.08 * effect_scale
	process_material.scale_max = 0.65 * effect_scale
	process_material.scale_curve = scale_curve
	process_material.color = Color(4.0, 4.0, 4.0, 1.0)
	process_material.color_ramp = color_ramp
	return process_material


func _create_smoke_process_material(effect_scale: float) -> ParticleProcessMaterial:
	var color_ramp: GradientTexture1D = _create_smoke_color_ramp()
	var process_material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 0.25 * effect_scale
	process_material.direction = Vector3(0.0, 1.0, 0.0)
	process_material.spread = 28.0
	process_material.initial_velocity_min = 0.6 * effect_scale
	process_material.initial_velocity_max = 1.8 * effect_scale
	process_material.angular_velocity_min = -120.0
	process_material.angular_velocity_max = 120.0
	process_material.gravity = Vector3(0.0, -1.5, 0.0)
	process_material.tangential_accel_min = 2.0
	process_material.tangential_accel_max = 2.0
	process_material.scale_min = 0.25 * effect_scale
	process_material.scale_max = 1.1 * effect_scale
	process_material.color = Color(0.55, 0.55, 0.55, 1.0)
	process_material.color_ramp = color_ramp
	return process_material


func _create_burst_color_ramp() -> GradientTexture1D:
	var gradient: Gradient = Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	gradient.set_offsets(PackedFloat32Array([0.0, 0.13, 0.18, 0.32, 0.47, 0.75, 1.0]))
	gradient.set_colors(PackedColorArray([
		Color(0.25, 0.25, 0.25, 1.0),
		Color(1.0, 0.8, 0.66, 1.0),
		Color(1.0, 0.68, 0.0, 1.0),
		Color(1.0, 0.6, 0.37, 1.0),
		Color(1.0, 0.25, 0.1, 0.45),
		Color(0.0, 0.0, 0.0, 0.18),
		Color(0.25, 0.25, 0.25, 0.0),
	]))
	var gradient_texture: GradientTexture1D = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	return gradient_texture


func _create_fire_color_ramp() -> GradientTexture1D:
	var gradient: Gradient = Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	gradient.set_offsets(PackedFloat32Array([0.02, 0.07, 0.43, 0.72, 1.0]))
	gradient.set_colors(PackedColorArray([
		Color(0.0, 0.0, 0.0, 1.0),
		Color(0.69, 0.19, 0.0, 1.0),
		Color(1.0, 0.52, 0.08, 1.0),
		Color(1.0, 0.08, 0.0, 0.45),
		Color(0.25, 0.25, 0.25, 0.0),
	]))
	var gradient_texture: GradientTexture1D = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	return gradient_texture


func _create_smoke_color_ramp() -> GradientTexture1D:
	var gradient: Gradient = Gradient.new()
	gradient.set_offsets(PackedFloat32Array([0.0, 0.54, 1.0]))
	gradient.set_colors(PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.0),
	]))
	var gradient_texture: GradientTexture1D = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	return gradient_texture


func _create_constant_scale_curve() -> CurveTexture:
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 1.0))
	var curve_texture: CurveTexture = CurveTexture.new()
	curve_texture.curve = curve
	return curve_texture


func _create_billboard_quad_mesh(quad_size: float) -> QuadMesh:
	var quad_mesh: QuadMesh = QuadMesh.new()
	quad_mesh.size = Vector2(quad_size, quad_size)
	return quad_mesh


func _create_smoke_billboard_material(proximity_fade_distance: float) -> StandardMaterial3D:
	var billboard_material: StandardMaterial3D = StandardMaterial3D.new()
	billboard_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	billboard_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	billboard_material.vertex_color_use_as_albedo = true
	var smoke_texture: Texture2D = load(SMOKE_TEXTURE_PATH) as Texture2D
	if smoke_texture != null:
		billboard_material.albedo_texture = smoke_texture
	billboard_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	billboard_material.particles_anim_h_frames = 1
	billboard_material.particles_anim_v_frames = 1
	billboard_material.particles_anim_loop = false
	billboard_material.proximity_fade_enabled = true
	billboard_material.proximity_fade_distance = proximity_fade_distance
	return billboard_material
