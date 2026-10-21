class_name FluidPool
extends Area3D
## Puddle under a damaged utility pipe: sewage, scalding water or plain cold water. Hurts any bug
## standing in it when its damage is above zero (half-second pulses so the health bar flashes a
## few times a second), spreads to full size after a burst, then dries up once the line has
## drained.
##
## On dirt the liquid follows the ground: it floods outward from the spill point over a grid,
## only into cells it can reach without climbing more than a gentle rise, and its surface sits
## on the terrain under every cell (so it runs down into dips and stops at mounds instead of
## hanging as a flat disc you can walk under). Each flooded cell carries its own box collider.
## When `surface_water` is set the pool rides that flat water surface as a disc instead.

const PULSE_SECONDS: float = 0.5
const DRY_SECONDS: float = 4.0
## How far above the ground the liquid's surface is drawn, and how thick the damage zone is.
const SURFACE_LIFT: float = 0.3
const DEPTH: float = 1.6
## Liquid will not climb more than this fraction of a cell's width from one cell to the next.
const CLIMB_PER_CELL: float = 0.35
const REBUILD_SECONDS: float = 0.1

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
var _material: StandardMaterial3D
## Flat disc (on water).
var _disc_shape: CylinderShape3D
## Terrain-following flood: cell size, corner heights, and each flooded cell's path distance
## from the spill point, plus one collider per cell.
var _cell: float = 1.0
var _flooded: Dictionary = {}
var _corner_heights: Dictionary = {}
var _cell_shapes: Dictionary = {}
var _flood_radius: float = 0.0
var _shown_radius: float = -1.0
var _rebuild_in: float = 0.0


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
	_material = StandardMaterial3D.new()
	_material.albedo_color = color
	_material.roughness = 0.2
	# Seen from any side (a bug low in a dip looks up at liquid on the slope above it).
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if burning:
		_material.emission_enabled = true
		_material.emission = color
		_material.emission_energy_multiplier = 1.6
	_mesh = MeshInstance3D.new()
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	if surface_water != null:
		var shape_node := CollisionShape3D.new()
		_disc_shape = CylinderShape3D.new()
		_disc_shape.height = DEPTH
		shape_node.shape = _disc_shape
		shape_node.position = Vector3(0.0, DEPTH * 0.5, 0.0)
		add_child(shape_node)
		var disc := CylinderMesh.new()
		disc.top_radius = 1.0
		disc.bottom_radius = 1.0
		disc.height = 0.12
		disc.radial_segments = 24
		_mesh.mesh = disc
		_mesh.position = Vector3(0.0, 0.06, 0.0)
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
	elif _flood_radius < target_radius:
		# The spill point is known only once the creator has placed the pool, so the flood is
		# worked out here (and again after a spread).
		_flood(target_radius)
	_rebuild_in -= delta
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
	if surface_water != null:
		_disc_shape.radius = safe
		_mesh.scale = Vector3(safe, 1.0, safe)
		return
	if _flooded.is_empty():
		return
	if absf(safe - _shown_radius) < 0.01 or (_rebuild_in > 0.0 and safe < target_radius and _drying < 0.0):
		return
	_rebuild_in = REBUILD_SECONDS
	_shown_radius = safe
	_show_flood(safe)


# --- Terrain-following flood -----------------------------------------------------------------

## Floods outward from the spill point over a square grid: a cell joins when a flooded
## neighbour can reach it within the radius without the ground rising more than a gentle step.
func _flood(radius: float) -> void:
	_flood_radius = radius
	_cell = clampf(radius / 12.0, 0.4, 4.0)
	_flooded.clear()
	_corner_heights.clear()
	var origin: Vector3 = global_position
	var center_height: float = _ground_height(origin.x, origin.z)
	if is_nan(center_height):
		return
	var climb: float = CLIMB_PER_CELL * _cell
	var queue: Array = [Vector2i.ZERO]
	_flooded[Vector2i.ZERO] = 0.0
	var heights: Dictionary = {Vector2i.ZERO: center_height}
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		var distance: float = _flooded[cell]
		var height: float = heights[cell]
		for step: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			var next_distance: float = distance + _cell
			if next_distance > radius or _flooded.has(next):
				continue
			var next_height: float = heights.get(next, NAN)
			if is_nan(next_height):
				next_height = _ground_height(origin.x + next.x * _cell, origin.z + next.y * _cell)
				heights[next] = next_height
			if is_nan(next_height) or next_height > height + climb:
				continue
			_flooded[next] = next_distance
			queue.append(next)
	# Corner heights, shared between neighbouring cells so the surface is continuous. A corner
	# is kept within a step of the flooded cells around it, so a probe that lands on a loose
	# block or a rock beside the pool can't throw a spike into the surface.
	for cell: Vector2i in _flooded:
		for corner: Vector2i in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i(0, 1), Vector2i.ONE]:
			var key: Vector2i = cell + corner
			if _corner_heights.has(key):
				continue
			var low: float = INF
			var high: float = -INF
			for around: Vector2i in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
				var neighbour: Vector2i = key + around
				if _flooded.has(neighbour):
					low = minf(low, float(heights[neighbour]))
					high = maxf(high, float(heights[neighbour]))
			var corner_height: float = _ground_height(origin.x + (key.x - 0.5) * _cell, origin.z + (key.y - 0.5) * _cell)
			if is_nan(corner_height):
				corner_height = (low + high) * 0.5
			_corner_heights[key] = clampf(corner_height, low - climb, high + climb)
	# One collider per cell, switched on as the liquid reaches it.
	for shape: Node in _cell_shapes.values():
		shape.queue_free()
	_cell_shapes.clear()
	for cell: Vector2i in _flooded:
		var box := BoxShape3D.new()
		box.size = Vector3(_cell, DEPTH, _cell)
		var shape_node := CollisionShape3D.new()
		shape_node.shape = box
		shape_node.disabled = true
		var floor_y: float = _cell_floor(cell) - origin.y
		shape_node.position = Vector3(cell.x * _cell, floor_y + DEPTH * 0.5, cell.y * _cell)
		add_child(shape_node)
		_cell_shapes[cell] = shape_node
	_shown_radius = -1.0


## The ground under a point from the terrain's collision (NAN when there is none).
func _ground_height(x: float, z: float) -> float:
	var reach: float = target_radius + 6.0
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(x, global_position.y + reach, z), Vector3(x, global_position.y - reach, z), MapInfo.TERRAIN_LAYER
	)
	query.collide_with_areas = false
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return NAN
	return hit.position.y


func _cell_floor(cell: Vector2i) -> float:
	var lowest: float = INF
	for corner: Vector2i in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i(0, 1), Vector2i.ONE]:
		lowest = minf(lowest, float(_corner_heights[cell + corner]))
	return lowest


## Draws the cells within `radius` of the spill (by flow distance) as a surface on the ground,
## and enables their colliders.
func _show_flood(radius: float) -> void:
	var origin: Vector3 = global_position
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any: bool = false
	for cell: Vector2i in _flooded:
		var inside: bool = float(_flooded[cell]) <= radius
		var shape: CollisionShape3D = _cell_shapes.get(cell)
		if shape != null:
			shape.disabled = not inside
		if not inside:
			continue
		any = true
		var corners: Array = [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.ONE, Vector2i(0, 1)]
		var points := PackedVector3Array()
		for corner: Vector2i in corners:
			var key: Vector2i = cell + corner
			points.append(Vector3(
				(key.x - 0.5) * _cell, float(_corner_heights[key]) - origin.y + SURFACE_LIFT, (key.y - 0.5) * _cell
			))
		var normal: Vector3 = (points[1] - points[0]).cross(points[3] - points[0]).normalized()
		if normal.y < 0.0:
			normal = -normal
		for index: int in [0, 1, 2, 0, 2, 3]:
			st.set_normal(normal)
			st.add_vertex(points[index])
	_mesh.mesh = st.commit() if any else null
	_mesh.position = Vector3.ZERO
	_mesh.scale = Vector3.ONE
