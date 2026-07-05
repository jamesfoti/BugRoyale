class_name BerryInterpolatedSkeletonModifier3D
extends SkeletonModifier3D
## Blends animated and physics skeleton poses for the visible mesh.
## Adapted from CBerry22 Active Ragdoll demo (MIT).

@export_range(0.0, 1.0) var physics_interpolation: float = 0.35

@export var physics_skeleton: Skeleton3D
@export var animated_skeleton: Skeleton3D


func _process_modification() -> void:
	if animated_skeleton == null or physics_skeleton == null:
		return
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		return
	var bone_count: int = mini(
		skeleton.get_bone_count(),
		mini(animated_skeleton.get_bone_count(), physics_skeleton.get_bone_count())
	)
	for i: int in range(bone_count):
		var animated_pose: Transform3D = animated_skeleton.get_bone_pose(i)
		var physics_pose: Transform3D = physics_skeleton.get_bone_pose(i)
		skeleton.set_bone_pose(i, animated_pose.interpolate_with(physics_pose, physics_interpolation))
