extends Node3D
class_name BirdFlock
## Flock of cone birds using boids steering with optional player attack behavior.


const BirdScene: PackedScene = preload("res://ai/boids/bird.tscn")
const BIRD_CONE_HEIGHT: float = 0.42
const BIRD_CONE_RADIUS: float = 0.13

@export_group("Flock")
@export var enabled: bool = true
@export_range(1, 128, 1) var bird_count: int = 28
@export var flock_center_path: NodePath
@export var terrain_path: NodePath = ^"../TerrainWorld"
@export var spawn_radius: float = 28.0
@export var min_height: float = 10.0
@export var max_height: float = 22.0

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
var _flock_center: Vector3 = Vector3.ZERO
var _terrain: OpenTerrain
## Draws every bird cone in one call instead of one MeshInstance3D per bird.
var _bird_multimesh_instance: MultiMeshInstance3D
var _bird_mesh_offset: Transform3D = _make_bird_mesh_offset()
## Shot-down birds still tumbling to the ground; drawn but no longer flocking.
var _falling_birds: Array[Bird] = []


func _ready() -> void:
	add_to_group("bird_flock")
	call_deferred("_build_flock")


func _physics_process(delta: float) -> void:
	if not enabled or (_birds.is_empty() and _falling_birds.is_empty()):
		return

	if not _birds.is_empty():
		_update_flock_center()
		_simulate_flock(delta)
	_update_bird_multimesh()


func _build_flock() -> void:
	if not is_inside_tree():
		call_deferred("_build_flock")
		return
	_clear_birds()
	_resolve_terrain()
	_update_flock_center()

	for bird_index in bird_count:
		var bird: Bird = BirdScene.instantiate() as Bird
		if bird == null:
			continue
		bird.name = "Bird%d" % bird_index
		var spawn_position: Vector3 = _random_spawn_position()
		bird.velocity = _random_horizontal_velocity()
		add_child(bird)
		bird.global_position = spawn_position
		bird.ground_height = _minimum_flight_height
		bird.killed.connect(_on_bird_killed)
		_birds.append(bird)

	_resize_arrays()
	_build_bird_multimesh()
	_update_bird_multimesh()


func _build_bird_multimesh() -> void:
	if _bird_multimesh_instance == null:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = BIRD_CONE_RADIUS
		cone.height = BIRD_CONE_HEIGHT
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.28, 0.24, 0.2)
		material.roughness = 0.72
		material.metallic = 0.05
		cone.material = material

		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = cone

		_bird_multimesh_instance = MultiMeshInstance3D.new()
		_bird_multimesh_instance.name = "BirdMeshes"
		_bird_multimesh_instance.multimesh = multimesh
		_bird_multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# Instance transforms are written in world space.
		_bird_multimesh_instance.top_level = true
		add_child(_bird_multimesh_instance)
		_bird_multimesh_instance.global_transform = Transform3D.IDENTITY
	_bird_multimesh_instance.multimesh.instance_count = _birds.size()


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
	var drawn: int = 0
	for bird: Bird in _birds + _falling_birds:
		multimesh.set_instance_transform(drawn, bird.global_transform * _bird_mesh_offset)
		drawn += 1
	multimesh.visible_instance_count = drawn


func _on_bird_killed(bird: Bird) -> void:
	_birds.erase(bird)
	_falling_birds.append(bird)
	_resize_arrays()


## Cone points along the bird's -Z (look_at forward), with its base at the bird origin.
static func _make_bird_mesh_offset() -> Transform3D:
	var offset := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO)
	offset.origin = Vector3(0.0, 0.0, BIRD_CONE_HEIGHT * 0.5)
	return offset


func _simulate_flock(delta: float) -> void:
	var targets: Array[Node3D] = _get_attack_targets()

	for bird_index in _birds.size():
		_positions[bird_index] = _birds[bird_index].global_position
		_velocities[bird_index] = _birds[bird_index].velocity

	for bird_index in _birds.size():
		var bird: Bird = _birds[bird_index]
		bird.tick_cooldown(delta)

		var steering: Vector3 = BoidsRules.compute_steering(
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
		steering += _compute_boundary_steering(_positions[bird_index])
		steering += _compute_height_steering(_positions[bird_index])

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
		new_position.y = maxf(new_position.y, _minimum_flight_height(new_position) + 1.5)

		bird.global_position = new_position
		bird.set_velocity(new_velocity)
		_positions[bird_index] = new_position
		_velocities[bird_index] = new_velocity


func _try_attack_target(bird: Bird, target: Node3D) -> void:
	var damageable: Damageable = _find_damageable(target)
	if damageable == null or not damageable.is_alive():
		return
	damageable.apply_damage(attack_damage, bird)
	bird.reset_attack_cooldown(attack_cooldown)


func _find_damageable(target: Node3D) -> Damageable:
	for child in target.get_children():
		if child is Damageable:
			return child as Damageable
	return null


func _get_attack_targets() -> Array[Node3D]:
	var targets: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("player"):
		if node is Node3D:
			var player: Node3D = node as Node3D
			var damageable: Damageable = _find_damageable(player)
			if damageable == null or damageable.is_alive():
				targets.append(player)
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
	var offset: Vector3 = position - _flock_center
	offset.y = 0.0
	var distance: float = offset.length()
	if distance <= spawn_radius:
		return Vector3.ZERO
	return -offset.normalized() * boundary_weight


func _compute_height_steering(position: Vector3) -> Vector3:
	var steering: Vector3 = Vector3.ZERO
	if position.y < min_height:
		steering.y += height_weight
	elif position.y > max_height:
		steering.y -= height_weight
	return steering


func _minimum_flight_height(position: Vector3) -> float:
	if _terrain == null:
		return 0.0
	return _terrain.get_surface_height_at(position)


func _random_spawn_position() -> Vector3:
	var angle: float = randf_range(0.0, TAU)
	var radius: float = randf_range(spawn_radius * 0.2, spawn_radius)
	var position := _flock_center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	position.y = randf_range(min_height, max_height)
	return position


func _random_horizontal_velocity() -> Vector3:
	var angle: float = randf_range(0.0, TAU)
	return Vector3(cos(angle), randf_range(-0.15, 0.15), sin(angle)) * randf_range(4.0, max_speed)


func _update_flock_center() -> void:
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


func _clear_birds() -> void:
	for bird in _birds + _falling_birds:
		if is_instance_valid(bird):
			bird.queue_free()
	_birds.clear()
	_falling_birds.clear()
	_positions = PackedVector3Array()
	_velocities = PackedVector3Array()
