class_name FluidPool
extends Area3D
## Puddle under a damaged utility pipe: sewage, scalding water or plain cold water. Hurts any bug
## standing in it when its damage is above zero (half-second pulses so the health bar flashes a
## few times a second), spreads to full size after a burst, then dries up once the line has
## drained. Sits on the dirt where it was created.

const PULSE_SECONDS: float = 0.5
const DRY_SECONDS: float = 4.0

var damage_per_second: float = 6.0
var target_radius: float = 6.0
var grow_seconds: float = 6.0
var lifetime: float = 30.0
var color: Color = Color(0.27, 0.3, 0.12)
## Burning gas: the patch glows and flickers with flame particles.
var burning: bool = false
## When set, the pool rides this water's surface instead of sitting on the dirt (sewage backing
## up into a flood, a shorted bulb's shock).
var surface_water: TerrariumWater

var _radius: float = 0.5
var _age: float = 0.0
var _pulse: float = 0.0
var _drying: float = -1.0
var _mesh: MeshInstance3D
var _shape: CylinderShape3D


static func create(pool_radius: float, damage: float, seconds: float, pool_color: Color, is_burning: bool = false) -> FluidPool:
	var pool := FluidPool.new()
	pool.name = "FluidPool"
	pool.target_radius = pool_radius
	pool.damage_per_second = damage
	pool.lifetime = seconds
	pool.color = pool_color
	pool.burning = is_burning
	return pool


func _ready() -> void:
	collision_layer = 0
	collision_mask = MapInfo.FIGHTER_LAYER
	monitoring = true
	monitorable = false
	var shape_node := CollisionShape3D.new()
	_shape = CylinderShape3D.new()
	_shape.height = 1.6
	shape_node.shape = _shape
	shape_node.position = Vector3(0.0, 0.8, 0.0)
	add_child(shape_node)
	_mesh = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.12
	disc.radial_segments = 24
	_mesh.mesh = disc
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.2
	if burning:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.6
	_mesh.material_override = material
	_mesh.position = Vector3(0.0, 0.06, 0.0)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	if burning:
		add_child(_make_flames())
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.6, 0.25)
		light.light_energy = 2.0
		light.omni_range = 14.0
		light.position = Vector3(0.0, 1.5, 0.0)
		add_child(light)
	_apply_radius()


func _make_flames() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Flames"
	particles.amount = 60
	particles.lifetime = 1.1
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3.ONE * -10.0, Vector3.ONE * 20.0)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 2.5
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 15.0
	process.initial_velocity_min = 2.0
	process.initial_velocity_max = 4.0
	process.gravity = Vector3.ZERO
	process.scale_min = 0.5
	process.scale_max = 1.6
	process.color = color.lerp(Color.WHITE, 0.15)
	particles.process_material = process
	var tongue := SphereMesh.new()
	tongue.radius = 0.3
	tongue.height = 0.9
	tongue.radial_segments = 6
	tongue.rings = 3
	particles.draw_pass_1 = tongue
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	particles.material_override = material
	return particles


## Widens the pool (a cracked drip turning into a burst) and extends its life.
func spread(pool_radius: float, damage: float, seconds: float) -> void:
	target_radius = maxf(target_radius, pool_radius)
	damage_per_second = maxf(damage_per_second, damage)
	lifetime = maxf(lifetime, _age + seconds)
	_drying = -1.0


func _physics_process(delta: float) -> void:
	_age += delta
	if surface_water != null and is_instance_valid(surface_water):
		global_position.y = surface_water.get_water_surface_y() - 0.05
	if _drying >= 0.0:
		_drying += delta
		_radius = maxf(target_radius * (1.0 - _drying / DRY_SECONDS), 0.0)
		_apply_radius()
		if _drying >= DRY_SECONDS:
			queue_free()
		return
	if _age >= lifetime:
		_drying = 0.0
		return
	if _radius < target_radius:
		_radius = minf(_radius + target_radius * delta / maxf(grow_seconds, 0.01), target_radius)
		_apply_radius()
	if damage_per_second <= 0.0:
		return
	_pulse += delta
	if _pulse < PULSE_SECONDS:
		return
	_pulse -= PULSE_SECONDS
	for body: Node3D in get_overlapping_bodies():
		var damageable: Damageable = body.get_node_or_null("Damageable") as Damageable
		if damageable != null:
			damageable.apply_damage(damage_per_second * PULSE_SECONDS, self)


func _apply_radius() -> void:
	var safe: float = maxf(_radius, 0.01)
	_shape.radius = safe
	_mesh.scale = Vector3(safe, 1.0, safe)
