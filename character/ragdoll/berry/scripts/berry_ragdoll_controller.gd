extends CharacterBody3D
class_name BerryRagdollController
## Locomotion + camera for CBerry22-style active ragdoll.
## Video: https://www.youtube.com/watch?v=0MHY2TDeMLM

const GROUND_RAY_HEIGHT: float = 80.0
const GROUND_CLEARANCE: float = 0.05

@export_range(0.0, 1.0) var mouse_sensitivity: float = 0.25
@export var anim_tree: AnimationTree
@export var speed: float = 4.0
@export var run_speed: float = 6.5
@export var jump_velocity: float = 4.5
@export var floor_max_angle_deg: float = 55.0
@export var capsule_radius: float = 0.35
@export var capsule_height: float = 1.2
@export var capsule_center_y: float = 0.65

var _physical_springs: SkeletonModifier3D
var _interpolated_blend: SkeletonModifier3D
var _camera: Camera3D
var _mouse_delta: Vector2 = Vector2.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func is_terrain_focus_active() -> bool:
	return false


func _ready() -> void:
	_physical_springs = get_node_or_null(
		"Armature/Skeleton3D/PhysicalSprings"
	) as SkeletonModifier3D
	_interpolated_blend = get_node_or_null(
		"InterpolatedMan/Armature/Skeleton3D/InterpolatedBlend"
	) as SkeletonModifier3D
	_camera = get_node_or_null("Camera3D") as Camera3D
	if _camera != null:
		_camera.current = true
	floor_max_angle = deg_to_rad(floor_max_angle_deg)
	floor_stop_on_slope = true
	floor_snap_length = 0.35
	add_to_group("player")
	_normalize_character_root()
	_fix_collision_shape()
	_disable_extra_players()
	_setup_animation()
	_setup_display_meshes()
	call_deferred("_snap_to_ground_when_ready")
	call_deferred("_capture_mouse")


func _normalize_character_root() -> void:
	var saved_position: Vector3 = global_position if is_inside_tree() else Vector3.ZERO
	transform = Transform3D.IDENTITY
	if is_inside_tree():
		global_position = saved_position


func _fix_collision_shape() -> void:
	var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null:
		return
	var capsule := CapsuleShape3D.new()
	capsule.radius = capsule_radius
	capsule.height = capsule_height
	collision_shape.shape = capsule
	collision_shape.position = Vector3(0.0, capsule_center_y, 0.0)


func _disable_extra_players() -> void:
	for extra_path: NodePath in [
		NodePath("AnimationPlayer"),
		NodePath("InterpolatedMan/AnimationPlayer"),
	]:
		var extra_player: AnimationPlayer = get_node_or_null(extra_path) as AnimationPlayer
		if extra_player != null:
			extra_player.active = false


func _setup_animation() -> void:
	if anim_tree == null:
		anim_tree = get_node_or_null("AnimatedMan/AnimationTree") as AnimationTree
	if anim_tree == null:
		push_warning("[BerryRagdoll] Missing AnimationTree.")
		return
	anim_tree.active = true
	anim_tree.set("parameters/blend_position", Vector2.ZERO)


func _setup_display_meshes() -> void:
	_set_skeleton_meshes_visible("AnimatedMan/Armature/Skeleton3D", false)
	_set_skeleton_meshes_visible("Armature/Skeleton3D", false)
	_set_skeleton_meshes_visible("InterpolatedMan/Armature/Skeleton3D", true)
	if _interpolated_blend != null:
		_interpolated_blend.active = true


func _set_skeleton_meshes_visible(skeleton_path: String, mesh_visible: bool) -> void:
	var skeleton: Skeleton3D = get_node_or_null(skeleton_path) as Skeleton3D
	if skeleton == null:
		return
	for child: Node in skeleton.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = mesh_visible


func _snap_to_ground_when_ready() -> void:
	for _attempt: int in range(20):
		if _try_snap_to_ground():
			return
		await get_tree().physics_frame


func _try_snap_to_ground() -> bool:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space_state == null:
		return false
	var ray_from: Vector3 = global_position + Vector3(0.0, GROUND_RAY_HEIGHT, 0.0)
	var ray_to: Vector3 = global_position + Vector3(0.0, -GROUND_RAY_HEIGHT, 0.0)
	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	query.collision_mask = collision_mask
	query.exclude = [self.get_rid()]
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	global_position.y = (hit.position as Vector3).y + GROUND_CLEARANCE
	return true


func _capture_mouse() -> void:
	if not get_tree().paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event.is_action_pressed("ragdoll"):
		_toggle_ragdoll()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_mouse_delta = event.relative


func _process(_delta: float) -> void:
	if get_tree().paused:
		return
	var yaw: float = _mouse_delta.x * mouse_sensitivity
	_mouse_delta = Vector2.ZERO
	if absf(yaw) > 0.0001:
		rotate_y(deg_to_rad(-yaw))


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var move_speed: float = run_speed if Input.is_action_pressed("run") else speed

	if direction:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)

	_update_locomotion_anim()
	move_and_slide()


func _update_locomotion_anim() -> void:
	if anim_tree == null:
		return
	var local_vel: Vector3 = transform.basis.inverse() * velocity
	anim_tree.set("parameters/blend_position", Vector2(local_vel.x, -local_vel.z))


func _toggle_ragdoll() -> void:
	if _physical_springs == null or not _physical_springs.has_method("set_ragdoll_mode"):
		return
	var enabled: bool = not _physical_springs.call("is_ragdoll_mode")
	_physical_springs.call("set_ragdoll_mode", enabled)
