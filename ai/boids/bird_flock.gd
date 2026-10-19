extends Node3D
class_name BirdFlock
## Flock of wasp drones (cones if no drone model is set) using boids steering, with optional
## attack behavior. Works on any map when given a MapInfo, and spawns in waves for game modes.


const BirdScene: PackedScene = preload("res://ai/boids/bird.tscn")
const BIRD_CONE_HEIGHT: float = 0.42
const BIRD_CONE_RADIUS: float = 0.13
const WING_FLAP_SHADER: Shader = preload("res://ai/boids/wasp_wing_flap.gdshader")
## Flocks up to this size refresh every bird's steering and ground probe every physics tick.
const FULL_RATE_BIRD_COUNT: int = 24
const UNKNOWN_ALTITUDE: float = -INF

signal bird_died(bird: Bird)

@export_group("Flock")
@export var enabled: bool = true
## Build bird_count members on ready. Game modes turn this off and call spawn_wave() instead.
@export var auto_build: bool = true
## Group the flock hunts (players; "hornet_prey" in Attack of the Hornets includes AI squadmates).
@export var target_group: StringName = &"player"
## Center the flock on the targets it hunts instead of flock_center_path.
@export var follow_targets: bool = false
## Damageable team given to every member (Damageable.NO_TEAM = anyone can hurt them).
@export var hornet_team: int = Damageable.NO_TEAM
@export_range(1, 128, 1) var bird_count: int = 28
@export var flock_center_path: NodePath
@export var terrain_path: NodePath = ^"../TerrainWorld"
@export var spawn_radius: float = 28.0
## Flight band, as height above the ground.
@export var min_height: float = 10.0
@export var max_height: float = 22.0
## Model drawn for each flock member (a rig-free drone from create_bugs.py --drone); empty = cone.
@export var drone_scene: PackedScene = preload("res://character/wasp/models/yellowjacket_wasp_drone.glb")
## Same scale as the playable Wasp skin (yellowjacket_wasp.tscn), so a hornet is wasp-sized.
@export var drone_scale: float = 1.15
## Tips the (upright, centaur-style) drone forward so it flies nose-first.
@export_range(0.0, 90.0, 1.0) var drone_pitch_degrees: float = 45.0

@export_group("Movement")
@export var max_speed: float = 11.0
@export var max_attack_speed: float = 18.0
@export var max_steer_force: float = 7.0
@export var separation_radius: float = 3.0
@export var alignment_radius: float = 9.0
@export var cohesion_radius: float = 14.0
@export var separation_weight: float = 1.6
@export var alignment_weight: float = 0.85
@export var cohesion_weight: float = 0.55
@export var boundary_weight: float = 1.2
@export var height_weight: float = 0.8

@export_group("Attack")
@export var attack_detection_radius: float = 24.0
@export var attack_range: float = 2.4
@export var attack_damage: float = 12.0
@export var attack_cooldown: float = 1.1
@export var attack_weight: float = 2.4

var _birds: Array[Bird] = []
var _positions: PackedVector3Array
var _velocities: PackedVector3Array
## Flocking steering and ground probe per bird, refreshed in a staggered round-robin (see
## _simulate_flock): the O(n²) neighbor loop and the per-bird terrain raycast are the two costly
## parts of the simulation, and at 60 Hz a bird can coast on a one- or two-tick-old answer.
var _flock_steering: PackedVector3Array
## Height above the ground per bird; UNKNOWN_ALTITUDE forces a probe on the bird's next tick.
var _altitudes: PackedFloat32Array
var _tick: int = 0
## Targets found this tick, shared by the flock center and every bird.
var _targets: Array[Node3D] = []
var _flock_center: Vector3 = Vector3.ZERO
var _terrain: OpenTerrain
## Set by game modes so the flock flies correctly on any map (celestial body up, terrarium glass).
var map: MapInfo
## Draws every bird cone in one call instead of one MeshInstance3D per bird.
var _bird_multimesh_instance: MultiMeshInstance3D
var _bird_mesh_offset: Transform3D = _make_bird_mesh_offset()
## Shot-down birds still tumbling to the ground; drawn but no longer flocking.
var _falling_birds: Array[Bird] = []
var _spawned_total: int = 0


func _ready() -> void:
	add_to_group("bird_flock")
	if auto_build:
		call_deferred("_build_flock")


func _physics_process(delta: float) -> void:
	if not enabled or (_birds.is_empty() and _falling_birds.is_empty()):
		return

	if not _birds.is_empty():
		_targets = _get_attack_targets()
		_update_flock_center()
		_simulate_flock(delta)
	_update_bird_multimesh()


func _build_flock() -> void:
	if not is_inside_tree():
		call_deferred("_build_flock")
		return
	_clear_birds()
	_resolve_terrain()
	spawn_wave(bird_count)


## Adds count flock members around the flock center (on top of any still alive). Used for the
## initial flock and for each wave in Attack of the Hornets.
func spawn_wave(count: int) -> void:
	if _terrain == null:
		_resolve_terrain()
	_targets = _get_attack_targets()
	_update_flock_center()
	var previous_count: int = _birds.size()
	for _index: int in count:
		var bird: Bird = BirdScene.instantiate() as Bird
		if bird == null:
			continue
		bird.name = "Bird%d" % _spawned_total
		_spawned_total += 1
		var spawn_position: Vector3 = _random_spawn_position()
		bird.velocity = _random_horizontal_velocity()
		add_child(bird)
		bird.global_position = spawn_position
		bird.altitude = _altitude
		bird.up = _up
		bird.get_node("Damageable").team = hornet_team
		bird.killed.connect(_on_bird_killed)
		_birds.append(bird)
	_resize_arrays()
	for index: int in range(previous_count, _birds.size()):
		_altitudes[index] = UNKNOWN_ALTITUDE
	_build_bird_multimesh()
	_update_bird_multimesh()


func alive_count() -> int:
	return _birds.size()


func _build_bird_multimesh() -> void:
	if _bird_multimesh_instance == null:
		var mesh: Mesh = _make_drone_mesh()
		if mesh != null:
			_bird_mesh_offset = _make_drone_offset(mesh)
		else:
			mesh = _make_cone_mesh()
			_bird_mesh_offset = _make_bird_mesh_offset()

		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh

		_bird_multimesh_instance = MultiMeshInstance3D.new()
		_bird_multimesh_instance.name = "BirdMeshes"
		_bird_multimesh_instance.multimesh = multimesh
		# Instance transforms are written in world space.
		_bird_multimesh_instance.top_level = true
		add_child(_bird_multimesh_instance)
		_bird_multimesh_instance.global_transform = Transform3D.IDENTITY
		_apply_graphics_quality(GraphicsSettings.low_quality)
		GraphicsSettings.low_quality_changed.connect(_apply_graphics_quality)
	_bird_multimesh_instance.multimesh.instance_count = _birds.size()


## Drone shadows double the swarm's draw cost, so Low graphics turns them off.
func _apply_graphics_quality(low_quality: bool) -> void:
	if _bird_multimesh_instance == null:
		return
	_bird_multimesh_instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if low_quality
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	)


## Low-detail wasp mesh (frozen in flight, built by create_bugs.py --drone) with buzzing wings.
func _make_drone_mesh() -> Mesh:
	if drone_scene == null:
		return null
	var drone_root: Node = drone_scene.instantiate()
	var source: MeshInstance3D = (
		drone_root if drone_root is MeshInstance3D
		else drone_root.find_children("*", "MeshInstance3D", true, false).front() as MeshInstance3D
	)
	var mesh: Mesh = source.mesh.duplicate() if source != null and source.mesh != null else null
	drone_root.free()
	if mesh == null:
		return null
	for surface_index: int in mesh.get_surface_count():
		var material: Material = mesh.surface_get_material(surface_index)
		if material != null and material.resource_name.to_lower().contains("wing"):
			var wing_material := ShaderMaterial.new()
			wing_material.shader = WING_FLAP_SHADER
			mesh.surface_set_material(surface_index, wing_material)
	return mesh


## The drone model faces +Z; birds fly toward -Z. Turn it around, scale it, center it on the bird,
## then pitch it nose-down.
func _make_drone_offset(mesh: Mesh) -> Transform3D:
	var basis := Basis(Vector3.UP, PI).scaled(Vector3.ONE * drone_scale)
	var centered := Transform3D(basis, -(basis * mesh.get_aabb().get_center()))
	return Transform3D(Basis(Vector3.RIGHT, -deg_to_rad(drone_pitch_degrees)), Vector3.ZERO) * centered


func _make_cone_mesh() -> Mesh:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = BIRD_CONE_RADIUS
	cone.height = BIRD_CONE_HEIGHT
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.28, 0.24, 0.2)
	material.roughness = 0.72
	material.metallic = 0.05
	cone.material = material
	return cone


func _update_bird_multimesh() -> void:
	if _bird_multimesh_instance == null:
		return
	var still_falling: Array[Bird] = []
	# Untyped on purpose: a freed bird must not be cast while filtering it out.
	for falling_bird in _falling_birds:
		if is_instance_valid(falling_bird):
			still_falling.append(falling_bird)
	_falling_birds = still_falling
	var multimesh: MultiMesh = _bird_multimesh_instance.multimesh
	var total: int = _birds.size() + _falling_birds.size()
	if multimesh.instance_count < total:
		multimesh.instance_count = total
	var drawn: int = 0
	for bird: Bird in _birds:
		multimesh.set_instance_transform(drawn, bird.global_transform * _bird_mesh_offset)
		drawn += 1
	for bird: Bird in _falling_birds:
		multimesh.set_instance_transform(drawn, bird.global_transform * _bird_mesh_offset)
		drawn += 1
	multimesh.visible_instance_count = drawn


func _on_bird_killed(bird: Bird) -> void:
	var index: int = _birds.find(bird)
	if index >= 0:
		_birds.remove_at(index)
		# Keep the per-bird caches aligned with the birds that follow it.
		_flock_steering.remove_at(index)
		_altitudes.remove_at(index)
	_falling_birds.append(bird)
	_resize_arrays()
	bird_died.emit(bird)


## Cone points along the bird's -Z (look_at forward), with its base at the bird origin.
static func _make_bird_mesh_offset() -> Transform3D:
	var offset := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO)
	offset.origin = Vector3(0.0, 0.0, BIRD_CONE_HEIGHT * 0.5)
	return offset


func _simulate_flock(delta: float) -> void:
	var targets: Array[Node3D] = _targets
	_tick += 1
	# Small flocks refresh every bird every tick; big waves spread the neighbor loop and the
	# ground raycasts over 2-3 ticks (a 70-hornet wave does a third of the work per tick).
	var refresh_interval: int = clampi(ceili(_birds.size() / float(FULL_RATE_BIRD_COUNT)), 1, 3)

	for bird_index in _birds.size():
		_positions[bird_index] = _birds[bird_index].global_position
		_velocities[bird_index] = _birds[bird_index].velocity

	for bird_index in _birds.size():
		var bird: Bird = _birds[bird_index]
		bird.tick_cooldown(delta)

		var altitude: float = _altitudes[bird_index]
		if (_tick + bird_index) % refresh_interval == 0 or altitude == UNKNOWN_ALTITUDE:
			var flock_steering: Vector3 = BoidsRules.compute_steering(
				bird_index,
				_positions,
				_velocities,
				separation_radius,
				alignment_radius,
				cohesion_radius,
				separation_weight,
				alignment_weight,
				cohesion_weight
			)
			flock_steering += _compute_boundary_steering(_positions[bird_index])
			altitude = _altitude(_positions[bird_index])
			flock_steering += _compute_height_steering(_positions[bird_index], altitude)
			_flock_steering[bird_index] = flock_steering
		var steering: Vector3 = _flock_steering[bird_index]

		var target: Node3D = _find_nearest_target(_positions[bird_index], targets)
		var speed_limit: float = max_speed
		if target != null:
			var to_target: Vector3 = target.global_position - _positions[bird_index]
			var distance: float = to_target.length()
			if distance <= attack_detection_radius:
				steering += to_target.normalized() * attack_weight
				speed_limit = max_attack_speed
			if distance <= attack_range and bird.can_attack():
				_try_attack_target(bird, target)

		steering = steering.limit_length(max_steer_force)
		var new_velocity: Vector3 = (_velocities[bird_index] + steering * delta).limit_length(speed_limit)
		var new_position: Vector3 = _positions[bird_index] + new_velocity * delta
		# Stay above the ground (altitude estimated from this frame's probe) and inside the map.
		var up: Vector3 = _up(new_position)
		var new_altitude: float = altitude + (new_position - _positions[bird_index]).dot(up)
		if new_altitude < 1.5:
			new_position += up * (1.5 - new_altitude)
			new_altitude = 1.5
		if map != null:
			new_position = map.clamp_to_bounds(new_position)

		bird.set_motion(new_position, new_velocity)
		_positions[bird_index] = new_position
		_velocities[bird_index] = new_velocity
		# Dead-reckoned until this bird's next ground probe.
		_altitudes[bird_index] = new_altitude


func _try_attack_target(bird: Bird, target: Node3D) -> void:
	var damageable: Damageable = _find_damageable(target)
	if damageable == null or not damageable.is_alive():
		return
	damageable.apply_damage(attack_damage, bird)
	bird.reset_attack_cooldown(attack_cooldown)


func _find_damageable(target: Node3D) -> Damageable:
	return target.get_node_or_null("Damageable") as Damageable


func _get_attack_targets() -> Array[Node3D]:
	var targets: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(target_group):
		var candidate: Node3D = node as Node3D
		if candidate == null or not candidate.visible:
			continue
		var damageable: Damageable = _find_damageable(candidate)
		if damageable == null or damageable.is_alive():
			targets.append(candidate)
	return targets


func _find_nearest_target(position: Vector3, targets: Array[Node3D]) -> Node3D:
	var closest: Node3D = null
	var closest_distance_sq: float = INF
	for target in targets:
		var distance_sq: float = position.distance_squared_to(target.global_position)
		if distance_sq < closest_distance_sq:
			closest_distance_sq = distance_sq
			closest = target
	return closest


func _compute_boundary_steering(position: Vector3) -> Vector3:
	var offset: Vector3 = (position - _flock_center).slide(_up(position))
	var distance: float = offset.length()
	if distance <= spawn_radius:
		return Vector3.ZERO
	return -offset.normalized() * boundary_weight


func _compute_height_steering(position: Vector3, altitude: float) -> Vector3:
	if altitude < min_height:
		return _up(position) * height_weight
	if altitude > max_height:
		return -_up(position) * height_weight
	return Vector3.ZERO


## Up at a point: the map's (radial on the celestial body), else world up.
func _up(position: Vector3) -> Vector3:
	return map.up_at(position) if map != null else Vector3.UP


## Height above the ground under a point.
func _altitude(position: Vector3) -> float:
	if map != null:
		return map.altitude(position)
	return position.y - _minimum_flight_height(position)


func _minimum_flight_height(position: Vector3) -> float:
	if _terrain == null:
		return 0.0
	return _terrain.get_surface_height_at(position)


func _random_spawn_position() -> Vector3:
	var up: Vector3 = _up(_flock_center)
	var tangent: Vector3 = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var bitangent: Vector3 = up.cross(tangent).normalized()
	var angle: float = randf_range(0.0, TAU)
	var radius: float = randf_range(spawn_radius * 0.4, spawn_radius)
	var position: Vector3 = _flock_center + (tangent * cos(angle) + bitangent * sin(angle)) * radius
	position += _up(position) * (randf_range(min_height, max_height) - _altitude(position))
	return map.clamp_to_bounds(position) if map != null else position


func _random_horizontal_velocity() -> Vector3:
	var up: Vector3 = _up(_flock_center)
	var direction: Vector3 = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	direction = direction.rotated(up, randf_range(0.0, TAU))
	return direction * randf_range(4.0, max_speed)


## Uses the targets gathered this tick (_targets) when following them.
func _update_flock_center() -> void:
	if follow_targets:
		if not _targets.is_empty():
			var sum: Vector3 = Vector3.ZERO
			for target: Node3D in _targets:
				sum += target.global_position
			_flock_center = sum / _targets.size()
		return
	if flock_center_path != NodePath():
		var center_node: Node3D = get_node_or_null(flock_center_path) as Node3D
		if center_node != null:
			_flock_center = center_node.global_position
			return
	_flock_center = global_position


func _resolve_terrain() -> void:
	if terrain_path == NodePath():
		return
	var terrain_node: Node = get_node_or_null(terrain_path)
	if terrain_node is OpenTerrain:
		_terrain = terrain_node as OpenTerrain


func _resize_arrays() -> void:
	_positions.resize(_birds.size())
	_velocities.resize(_birds.size())
	_flock_steering.resize(_birds.size())
	_altitudes.resize(_birds.size())


func _clear_birds() -> void:
	for bird in _birds + _falling_birds:
		if is_instance_valid(bird):
			bird.queue_free()
	_birds.clear()
	_falling_birds.clear()
	_positions = PackedVector3Array()
	_velocities = PackedVector3Array()
	_flock_steering = PackedVector3Array()
	_altitudes = PackedFloat32Array()
