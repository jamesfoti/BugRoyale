class_name UtilityPipe
extends StaticBody3D
## One section of a utility line in the crawlspace: a black ABS sewage drain, red PEX hot water
## or blue PEX cold water. Shots and explosions damage it through its Damageable: at half health
## it cracks and drips into a puddle below; at zero it bursts, sprays, and floods the dirt with a
## pool until the line drains. Sewage and scalding water hurt bugs standing in the pool; cold
## water is harmless. The pipe runs along its local Y axis; the builder rotates it into place.
## Collides on the structure layer, so bugs bump into it but ground probes ignore it.

signal cracked(pipe: UtilityPipe)
signal burst(pipe: UtilityPipe)

enum Fluid { SEWAGE, HOT_WATER, COLD_WATER, GAS }

const CRACK_FRACTION: float = 0.5
const DRAIN_SECONDS: float = 30.0
## Gas: a burst section explodes, hurting everything within this radius (full damage at the
## center, a quarter at the edge) and setting off neighboring sections a beat later.
const GAS_BLAST_RADIUS: float = 9.0
const GAS_BLAST_DAMAGE: float = 45.0
const GAS_CHAIN_DELAY: float = 0.25
const GAS_BURN_SECONDS: float = 20.0

## Per fluid: how the pipe and its fluid look, and how much the pool hurts.
const FLUIDS: Dictionary = {
	Fluid.SEWAGE: {
		"pipe_color": Color(0.07, 0.07, 0.08), "pipe_roughness": 0.55, "stain_color": Color(0.2, 0.2, 0.16),
		"fluid_color": Color(0.33, 0.38, 0.14), "pool_color": Color(0.27, 0.3, 0.12),
		"crack_damage": 2.0, "burst_damage": 6.0, "health": 60.0, "bang_radius": 2.4, "steam": false,
	},
	Fluid.HOT_WATER: {
		"pipe_color": Color(0.72, 0.12, 0.12), "pipe_roughness": 0.65, "stain_color": Color(0.5, 0.2, 0.18),
		"fluid_color": Color(0.85, 0.9, 0.95), "pool_color": Color(0.55, 0.65, 0.72),
		"crack_damage": 3.0, "burst_damage": 8.0, "health": 35.0, "bang_radius": 1.1, "steam": true,
	},
	Fluid.COLD_WATER: {
		"pipe_color": Color(0.14, 0.34, 0.8), "pipe_roughness": 0.65, "stain_color": Color(0.2, 0.3, 0.55),
		"fluid_color": Color(0.4, 0.6, 0.88), "pool_color": Color(0.3, 0.45, 0.65),
		"crack_damage": 0.0, "burst_damage": 0.0, "health": 35.0, "bang_radius": 1.1, "steam": false,
	},
	# Yellow gas line: a crack only hisses; a burst explodes and leaves a burning patch.
	Fluid.GAS: {
		"pipe_color": Color(0.95, 0.8, 0.12), "pipe_roughness": 0.5, "stain_color": Color(0.6, 0.52, 0.15),
		"fluid_color": Color(0.85, 0.85, 0.8, 0.5), "pool_color": Color(1.0, 0.45, 0.08),
		"crack_damage": 0.0, "burst_damage": 10.0, "health": 30.0, "bang_radius": 4.5, "steam": false,
	},
}

var fluid: Fluid = Fluid.SEWAGE
var length: float = 8.0
var radius: float = 0.3
## World Y of the dirt under the pipe, where the fluid pools.
var dirt_y: float = 0.0

var _damageable: Damageable
var _mesh: MeshInstance3D
var _is_cracked: bool = false
var _is_burst: bool = false
var _pool: FluidPool
var _drip: GPUParticles3D

## Pipe materials shared per fluid.
static var _pipe_materials: Dictionary = {}


static func create(pipe_fluid: Fluid, pipe_length: float, pipe_radius: float, ground_y: float) -> UtilityPipe:
	var pipe := UtilityPipe.new()
	pipe.name = "UtilityPipe"
	pipe.fluid = pipe_fluid
	pipe.length = pipe_length
	pipe.radius = pipe_radius
	pipe.dirt_y = ground_y
	pipe.collision_layer = MapInfo.STRUCTURE_LAYER
	pipe.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = pipe_radius
	shape.height = pipe_length
	shape_node.shape = shape
	pipe.add_child(shape_node)
	pipe._mesh = MeshInstance3D.new()
	pipe._mesh.name = "Pipe"
	pipe._mesh.mesh = _tube(pipe_radius, pipe_length)
	pipe._mesh.material_override = pipe_material(pipe_fluid)
	pipe.add_child(pipe._mesh)
	pipe._damageable = Damageable.new()
	pipe._damageable.name = "Damageable"
	pipe._damageable.max_health = FLUIDS[pipe_fluid]["health"]
	pipe.add_child(pipe._damageable)
	return pipe


static func pipe_material(pipe_fluid: Fluid) -> StandardMaterial3D:
	if _pipe_materials.has(pipe_fluid):
		return _pipe_materials[pipe_fluid]
	var material := StandardMaterial3D.new()
	material.albedo_color = FLUIDS[pipe_fluid]["pipe_color"]
	material.roughness = FLUIDS[pipe_fluid]["pipe_roughness"]
	_pipe_materials[pipe_fluid] = material
	return material


func _ready() -> void:
	_damageable.damaged.connect(_on_damaged)
	_damageable.died.connect(_on_died)


func is_cracked() -> bool:
	return _is_cracked


func is_burst() -> bool:
	return _is_burst


func _on_damaged(_amount: float, _source: Node) -> void:
	if not _is_cracked and _damageable.health <= _damageable.max_health * CRACK_FRACTION:
		_crack()


func _crack() -> void:
	_is_cracked = true
	var config: Dictionary = FLUIDS[fluid]
	var stained := StandardMaterial3D.new()
	stained.albedo_color = config["stain_color"]
	stained.roughness = 0.9
	_mesh.material_override = stained
	_drip = _make_particles(false)
	get_parent().add_child(_drip)
	_drip.global_position = global_position - Vector3.UP * radius
	if fluid != Fluid.GAS:
		# Gas only hisses from a crack; nothing pools until it ignites.
		_ensure_pool(2.0, config["crack_damage"], DRAIN_SECONDS * 2.0)
	cracked.emit(self)


func _on_died() -> void:
	if _is_burst:
		return
	_is_burst = true
	if not _is_cracked:
		_crack()
	var config: Dictionary = FLUIDS[fluid]
	# The middle of the section is gone: two stubs remain.
	_mesh.mesh = _tube(radius, length * 0.3)
	_mesh.position = Vector3(0.0, length * 0.35, 0.0)
	var other_stub := MeshInstance3D.new()
	other_stub.name = "Stub"
	other_stub.mesh = _mesh.mesh
	other_stub.material_override = _mesh.material_override
	other_stub.position = Vector3(0.0, -length * 0.35, 0.0)
	add_child(other_stub)
	var spray: GPUParticles3D = _make_particles(true)
	get_parent().add_child(spray)
	spray.global_position = global_position
	spray.finished.connect(spray.queue_free)
	if config["steam"]:
		var steam: GPUParticles3D = _make_steam()
		get_parent().add_child(steam)
		steam.global_position = global_position
		get_tree().create_timer(DRAIN_SECONDS).timeout.connect(func() -> void: steam.emitting = false)
	WeaponExplosionEffect.spawn(get_tree().current_scene, global_position, config["bang_radius"])
	if fluid == Fluid.GAS:
		_explode()
		# The leak keeps burning on the dirt for a while.
		_ensure_pool(3.0, config["burst_damage"], GAS_BURN_SECONDS)
		get_tree().create_timer(GAS_BURN_SECONDS).timeout.connect(_stop_dripping)
	else:
		_ensure_pool(6.5, config["burst_damage"], DRAIN_SECONDS)
		get_tree().create_timer(DRAIN_SECONDS).timeout.connect(_stop_dripping)
	burst.emit(self)


## Gas blast: hurts every bug in range now, and damages other pipes in range after a short
## delay so a line chains section by section instead of all at once.
func _explode() -> void:
	for node: Node in get_tree().get_nodes_in_group("damageable"):
		var damageable: Damageable = node as Damageable
		if damageable == null or damageable == _damageable or not damageable.is_alive():
			continue
		var target: Node3D = damageable.get_parent() as Node3D
		if target == null:
			continue
		var distance: float = target.global_position.distance_to(global_position)
		if distance > GAS_BLAST_RADIUS:
			continue
		var amount: float = lerpf(GAS_BLAST_DAMAGE, GAS_BLAST_DAMAGE * 0.25, distance / GAS_BLAST_RADIUS)
		if target is UtilityPipe:
			# Gas in range ignites outright, so the line goes up section by section.
			if (target as UtilityPipe).fluid == Fluid.GAS:
				amount = GAS_BLAST_DAMAGE
			get_tree().create_timer(GAS_CHAIN_DELAY).timeout.connect(damageable.apply_damage.bind(amount, self))
		else:
			damageable.apply_damage(amount, self)


func _stop_dripping() -> void:
	if _drip != null and is_instance_valid(_drip):
		_drip.emitting = false


func _ensure_pool(pool_radius: float, damage: float, seconds: float) -> void:
	if _pool != null and is_instance_valid(_pool):
		_pool.spread(pool_radius, damage, seconds)
		return
	_pool = FluidPool.create(pool_radius, damage, seconds, FLUIDS[fluid]["pool_color"], fluid == Fluid.GAS)
	get_parent().add_child(_pool)
	_pool.global_position = Vector3(global_position.x, dirt_y, global_position.z)


static func _tube(tube_radius: float, tube_length: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = tube_radius
	mesh.bottom_radius = tube_radius
	mesh.height = tube_length
	mesh.radial_segments = 14
	return mesh


## Fluid particles: a steady drip from a crack, or a one-shot spray from a burst.
func _make_particles(spray: bool) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "FluidSpray" if spray else "FluidDrip"
	particles.one_shot = spray
	particles.explosiveness = 0.85 if spray else 0.0
	particles.amount = 160 if spray else 28
	particles.lifetime = 1.8 if spray else 1.3
	particles.local_coords = false
	particles.emitting = true
	particles.visibility_aabb = AABB(Vector3.ONE * -12.0, Vector3.ONE * 24.0)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius
	process.direction = Vector3(0.0, 1.0, 0.0) if spray else Vector3(0.0, -1.0, 0.0)
	process.spread = 75.0 if spray else 20.0
	process.initial_velocity_min = 7.0 if spray else 0.5
	process.initial_velocity_max = 13.0 if spray else 1.5
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.4
	process.color = FLUIDS[fluid]["fluid_color"]
	particles.process_material = process
	var blob := SphereMesh.new()
	blob.radius = 0.16 if fluid == Fluid.SEWAGE else 0.11
	blob.height = blob.radius * 2.0
	blob.radial_segments = 6
	blob.rings = 3
	particles.draw_pass_1 = blob
	particles.material_override = _droplet_material()
	return particles


## Steam rising off a burst hot-water line.
func _make_steam() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Steam"
	particles.amount = 36
	particles.lifetime = 2.4
	particles.local_coords = false
	particles.emitting = true
	particles.visibility_aabb = AABB(Vector3.ONE * -8.0, Vector3.ONE * 16.0)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.6
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 25.0
	process.initial_velocity_min = 0.8
	process.initial_velocity_max = 1.6
	process.gravity = Vector3.ZERO
	process.scale_min = 0.8
	process.scale_max = 2.2
	process.color = Color(0.9, 0.92, 0.95, 0.35)
	particles.process_material = process
	var puff := SphereMesh.new()
	puff.radius = 0.35
	puff.height = 0.7
	puff.radial_segments = 6
	puff.rings = 3
	particles.draw_pass_1 = puff
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	particles.material_override = material
	return particles


static func _droplet_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.roughness = 0.3
	return material
