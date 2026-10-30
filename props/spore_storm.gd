class_name SporeStorm
extends Node3D
## The Cordyceps cloud of Cordyceps Royale: spores fill everything outside a shrinking safe circle,
## the way the storm does in a battle royale. A tall translucent wall marks the edge on any
## renderer, and a world-sized FogVolume fills the outside with drifting volumetric spores where
## the environment supports it. Fruiting bodies (dead husks) add small spore patches of their
## own, each with a stalk, a puff of fog and a few floating motes.

const SPORE_COLOR := Color(0.62, 0.7, 0.34)
## Tint a turned bug's skin takes on (multiplied into its colours).
const HUSK_TINT := Color(0.62, 0.72, 0.5)
const HUSK_GLOW := Color(0.2, 0.3, 0.08)

const WALL_SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform vec3 spore_color : source_color = vec3(0.62, 0.7, 0.34);
uniform float alpha_max : hint_range(0.0, 1.0) = 0.6;
uniform float wall_radius = 100.0;

void fragment() {
	vec2 uv = vec2(UV.x * wall_radius * 0.12, UV.y * 5.0);
	float n = sin(uv.x * 3.1 + TIME * 0.6) * sin(uv.y * 2.3 - TIME * 0.45);
	n += 0.5 * sin(uv.x * 7.7 - TIME * 1.1 + uv.y * 3.0);
	n = n * 0.3 + 0.5;
	ALBEDO = spore_color * (0.7 + 0.5 * n);
	ALPHA = alpha_max * (0.45 + 0.55 * n);
}
"""

const FOG_SHADER_CODE: String = """
shader_type fog;

uniform vec3 zone_center = vec3(0.0);
uniform float zone_radius = 10000.0;
uniform float edge_width = 6.0;
uniform float top_y = 1000.0;
uniform float density_max = 0.14;
uniform vec3 spore_color : source_color = vec3(0.62, 0.7, 0.34);

void fog() {
	vec2 flat_offset = WORLD_POSITION.xz - zone_center.xz;
	float outside = smoothstep(
		zone_radius - edge_width * 0.5, zone_radius + edge_width, length(flat_offset)
	);
	float under_roof = 1.0 - smoothstep(top_y, top_y + 4.0, WORLD_POSITION.y);
	float drift = 0.7 + 0.3 * sin(WORLD_POSITION.x * 0.35 + TIME * 0.7)
		* sin(WORLD_POSITION.z * 0.29 - TIME * 0.5);
	DENSITY = density_max * outside * under_roof * drift;
	ALBEDO = spore_color;
	EMISSION = spore_color * 0.4 * outside;
}
"""

var center: Vector3 = Vector3.ZERO
var radius: float = INF
var floor_y: float = 0.0
var top_y: float = 100.0
## Spore patches from fruiting bodies: {"position": Vector3, "radius": float}.
var patches: Array[Dictionary] = []

var _wall: MeshInstance3D
var _wall_material: ShaderMaterial
var _fog: FogVolume
var _fog_material: ShaderMaterial
var _mote_texture: GradientTexture2D


## Builds the cloud for a map: the safe circle starts at zone_radius around zone_center, and the
## cloud fills from bottom_y up to ceiling_y (the top of the playable box).
static func create(
	zone_center: Vector3, zone_radius: float, bottom_y: float, ceiling_y: float
) -> SporeStorm:
	var storm := SporeStorm.new()
	storm.name = "SporeStorm"
	storm.center = zone_center
	storm.radius = zone_radius
	storm.floor_y = bottom_y
	storm.top_y = ceiling_y
	return storm


func _ready() -> void:
	add_to_group("spore_storm")
	_build_wall()
	_build_fog()
	set_zone(center, radius)


## Turns on volumetric fog for the cloud (on a copy of the environment, so the map's own
## resource is untouched). Low graphics keeps volumetric fog off; the wall still shows the edge.
func attach_environment(world_environment: WorldEnvironment) -> void:
	if world_environment == null or world_environment.environment == null:
		return
	var environment: Environment = world_environment.environment.duplicate() as Environment
	world_environment.environment = environment
	var forward_plus: bool = RenderingServer.get_current_rendering_method() == "forward_plus"
	environment.volumetric_fog_enabled = forward_plus and not GraphicsSettings.low_quality
	environment.volumetric_fog_density = 0.0
	environment.volumetric_fog_length = 150.0
	environment.volumetric_fog_ambient_inject = 1.0


## Moves the safe circle: everything outside it (planar) is spores.
func set_zone(zone_center: Vector3, zone_radius: float) -> void:
	center = zone_center
	radius = maxf(zone_radius, 0.0)
	var height: float = top_y - floor_y + 6.0
	if _wall != null:
		_wall.visible = radius > 0.3
		_wall.scale = Vector3(maxf(radius, 0.01), height, maxf(radius, 0.01))
		_wall.global_position = Vector3(center.x, (top_y + floor_y) * 0.5, center.z)
		_wall_material.set_shader_parameter("wall_radius", maxf(radius, 1.0))
	if _fog_material != null:
		_fog_material.set_shader_parameter("zone_center", center)
		_fog_material.set_shader_parameter("zone_radius", radius)


## How far into the spores a point is: positive outside the safe circle, negative inside.
func depth(position: Vector3) -> float:
	return Vector2(position.x - center.x, position.z - center.z).length() - radius


## True when a point is in the cloud or inside a fruiting body's patch.
func is_in_spores(position: Vector3) -> bool:
	if depth(position) > 0.0:
		return true
	for patch: Dictionary in patches:
		if position.distance_to(patch["position"]) < float(patch["radius"]):
			return true
	return false


## Grows a fruiting body at a spot: a stalk, a puff of spore fog and drifting motes, and a patch
## that infects anything standing in it.
func add_patch(position: Vector3, patch_radius: float, seed: int) -> void:
	patches.append({"position": position, "radius": patch_radius})
	var body := Node3D.new()
	body.name = "FruitingBody"
	add_child(body)
	body.global_position = position

	var stalk: MeshInstance3D = make_stalk(seed, 1.4)
	body.add_child(stalk)

	var puff := FogVolume.new()
	puff.name = "SporePuff"
	puff.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	puff.size = Vector3(patch_radius * 2.0, patch_radius * 1.5, patch_radius * 2.0)
	puff.position = Vector3(0.0, patch_radius * 0.5, 0.0)
	var puff_material := FogMaterial.new()
	puff_material.density = 0.5
	puff_material.albedo = SPORE_COLOR
	puff_material.emission = SPORE_COLOR * 0.35
	puff_material.edge_fade = 0.35
	puff.material = puff_material
	body.add_child(puff)
	body.add_child(_make_motes(patch_radius))


## A Cordyceps stalk: an ink cap grown from a seed, leaning over, stem length `size` metres.
func make_stalk(seed: int, size: float) -> MeshInstance3D:
	var built: Dictionary = MushroomMeshBuilder.build(seed, MushroomMeshBuilder.Species.INKCAP)
	var stalk := MeshInstance3D.new()
	stalk.name = "Stalk"
	stalk.mesh = built["mesh"]
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(0.9, 0.95, 0.75)
	material.roughness = 0.9
	stalk.material_override = material
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var lean: float = deg_to_rad(rng.randf_range(12.0, 30.0))
	var basis: Basis = Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, lean)
	stalk.basis = basis * Basis.from_scale(Vector3(size * 0.45, size, size * 0.45))
	stalk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return stalk


## Dresses a turned bug: its skin goes a sickly fungal grey-green with a faint glow, and a stalk
## sprouts from the top of its head.
func dress_husk(visual_root: Node3D, seed: int) -> void:
	var top: float = 0.8
	for node: Node in visual_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if not mesh_instance.visible or mesh_instance.mesh == null:
			continue
		var box: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
		top = maxf(top, box.end.y - visual_root.global_position.y)
		if mesh_instance.material_override != null:
			mesh_instance.material_override = _husk_material(mesh_instance.material_override)
			continue
		for surface: int in mesh_instance.mesh.get_surface_count():
			var material: Material = mesh_instance.get_surface_override_material(surface)
			if material == null:
				material = mesh_instance.mesh.surface_get_material(surface)
			if material != null:
				mesh_instance.set_surface_override_material(surface, _husk_material(material))
	var stalk: MeshInstance3D = make_stalk(seed, 0.6)
	stalk.position = Vector3(0.0, top * 0.9, 0.0)
	visual_root.add_child(stalk)


func _husk_material(material: Material) -> Material:
	var copy: Material = material.duplicate() as Material
	if copy is ShaderMaterial:
		var shader_material: ShaderMaterial = copy as ShaderMaterial
		var albedo: Variant = shader_material.get_shader_parameter("albedo")
		var base: Color = albedo if albedo is Color else Color.WHITE
		shader_material.set_shader_parameter("albedo", base * HUSK_TINT)
		shader_material.set_shader_parameter("emission", HUSK_GLOW)
		shader_material.set_shader_parameter("emission_energy", 0.5)
	elif copy is StandardMaterial3D:
		var standard: StandardMaterial3D = copy as StandardMaterial3D
		standard.albedo_color *= HUSK_TINT
		standard.emission_enabled = true
		standard.emission = HUSK_GLOW
		standard.emission_energy_multiplier = 0.5
	return copy


func _build_wall() -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 1.0
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	cylinder.radial_segments = 72
	cylinder.rings = 1
	_wall = MeshInstance3D.new()
	_wall.name = "SporeWall"
	_wall.mesh = cylinder
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wall.extra_cull_margin = 16384.0
	var shader := Shader.new()
	shader.code = WALL_SHADER_CODE
	_wall_material = ShaderMaterial.new()
	_wall_material.shader = shader
	_wall_material.set_shader_parameter("spore_color", SPORE_COLOR)
	_wall.material_override = _wall_material
	add_child(_wall)


func _build_fog() -> void:
	_fog = FogVolume.new()
	_fog.name = "SporeFog"
	_fog.shape = RenderingServer.FOG_VOLUME_SHAPE_WORLD
	var shader := Shader.new()
	shader.code = FOG_SHADER_CODE
	_fog_material = ShaderMaterial.new()
	_fog_material.shader = shader
	_fog_material.set_shader_parameter("spore_color", SPORE_COLOR)
	_fog_material.set_shader_parameter("top_y", top_y)
	_fog.material = _fog_material
	add_child(_fog)


## A few pale motes drifting up out of a patch.
func _make_motes(patch_radius: float) -> GPUParticles3D:
	var motes := GPUParticles3D.new()
	motes.name = "SporeMotes"
	motes.amount = 28
	motes.lifetime = 5.0
	motes.visibility_aabb = AABB(
		Vector3(-patch_radius, 0.0, -patch_radius) * 1.5,
		Vector3(patch_radius * 3.0, patch_radius * 3.0, patch_radius * 3.0)
	)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = patch_radius * 0.6
	process.direction = Vector3.UP
	process.spread = 60.0
	process.initial_velocity_min = 0.2
	process.initial_velocity_max = 0.6
	process.gravity = Vector3(0.0, 0.12, 0.0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.4
	process.turbulence_noise_scale = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(SPORE_COLOR, 0.0))
	ramp.add_point(0.2, Color(SPORE_COLOR, 0.8))
	ramp.set_color(1, Color(SPORE_COLOR, 0.0))
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	process.color_ramp = ramp_texture
	motes.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.18
	motes.draw_pass_1 = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _soft_dot()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	motes.material_override = material
	return motes


func _soft_dot() -> GradientTexture2D:
	if _mote_texture != null:
		return _mote_texture
	_mote_texture = GradientTexture2D.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	_mote_texture.gradient = gradient
	_mote_texture.fill = GradientTexture2D.FILL_RADIAL
	_mote_texture.fill_from = Vector2(0.5, 0.5)
	_mote_texture.fill_to = Vector2(1.0, 0.5)
	_mote_texture.width = 32
	_mote_texture.height = 32
	return _mote_texture
