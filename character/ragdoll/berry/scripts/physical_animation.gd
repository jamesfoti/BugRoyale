class_name BerryPhysicalSpringModifier3D
extends SkeletonModifier3D
## Spring forces on physical bones toward the animated skeleton target.
## Adapted from CBerry22 Active Ragdoll demo (MIT).

@export var target_skeleton: Skeleton3D

@export var linear_spring_stiffness: float = 1200.0
@export var linear_spring_damping: float = 40.0
@export var max_linear_force: float = 9999.0

@export var angular_spring_stiffness: float = 4000.0
@export var angular_spring_damping: float = 80.0
@export var max_angular_force: float = 9999.0

var physics_bones: Array[PhysicalBone3D] = []
var _delta: float = 1.0 / 60.0
var _ragdoll_mode: bool = false
var _saved_springs: Dictionary = {}
var _simulation_started: bool = false


func _ready() -> void:
	_start_simulation()


func _start_simulation() -> void:
	if _simulation_started:
		return
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		return
	skeleton.physical_bones_start_simulation()
	for child: Node in skeleton.get_children():
		if child is PhysicalBone3D:
			physics_bones.append(child as PhysicalBone3D)
	_simulation_started = true


func set_ragdoll_mode(enabled: bool) -> void:
	if enabled == _ragdoll_mode:
		return
	_ragdoll_mode = enabled
	if enabled:
		_saved_springs = {
			"linear_stiffness": linear_spring_stiffness,
			"linear_damping": linear_spring_damping,
			"angular_stiffness": angular_spring_stiffness,
			"angular_damping": angular_spring_damping,
		}
		linear_spring_stiffness = 0.0
		angular_spring_stiffness = 0.0
		linear_spring_damping = 5.0
		angular_spring_damping = 5.0
	else:
		linear_spring_stiffness = _saved_springs.get("linear_stiffness", linear_spring_stiffness)
		linear_spring_damping = _saved_springs.get("linear_damping", linear_spring_damping)
		angular_spring_stiffness = _saved_springs.get("angular_stiffness", angular_spring_stiffness)
		angular_spring_damping = _saved_springs.get("angular_damping", angular_spring_damping)


func is_ragdoll_mode() -> bool:
	return _ragdoll_mode


func hookes_law(
	displacement: Vector3, current_velocity: Vector3, stiffness: float, damping: float
) -> Vector3:
	return (stiffness * displacement) - (damping * current_velocity)


func _process_modification_with_delta(delta: float) -> void:
	_delta = maxf(delta, 0.0001)
	if _ragdoll_mode or target_skeleton == null:
		return
	if not _simulation_started:
		_start_simulation()
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		return
	for b: PhysicalBone3D in physics_bones:
		var target_transform: Transform3D = (
			target_skeleton.global_transform * target_skeleton.get_bone_global_pose(b.get_bone_id())
		)
		var current_transform: Transform3D = (
			skeleton.global_transform * skeleton.get_bone_global_pose(b.get_bone_id())
		)
		var rotation_difference: Basis = target_transform.basis * current_transform.basis.inverse()
		var position_difference: Vector3 = target_transform.origin - current_transform.origin

		if position_difference.length_squared() > 1.0:
			b.global_position = target_transform.origin
		else:
			var force: Vector3 = hookes_law(
				position_difference,
				b.linear_velocity,
				linear_spring_stiffness,
				linear_spring_damping
			)
			force = force.limit_length(max_linear_force)
			b.linear_velocity += force * _delta

		var torque: Vector3 = hookes_law(
			rotation_difference.get_euler(),
			b.angular_velocity,
			angular_spring_stiffness,
			angular_spring_damping
		)
		torque = torque.limit_length(max_angular_force)
		b.angular_velocity += torque * _delta
