class_name TerrainChunk
extends MeshInstance3D
## One meshed chunk. Rebuilds from density when settings change.

var chunk_coordinate: Vector3i = Vector3i.ZERO


func rebuild(settings: ChunkedTerrainWorld.SettingsSnapshot) -> void:
	var chunk_build_result: ChunkMeshBuilder.ChunkBuildResult = ChunkMeshBuilder.build_chunk(
		chunk_coordinate, settings
	)
	apply_build_result(chunk_build_result, settings.rebuild_collision)


func apply_build_result(
	chunk_build_result: ChunkMeshBuilder.ChunkBuildResult, rebuild_collision: bool
) -> void:
	mesh = FlyingEdgesMesher.to_array_mesh(chunk_build_result.mesh_result)
	position = chunk_build_result.local_position
	if rebuild_collision and mesh.get_surface_count() > 0:
		_create_trimesh_collision()


func update_collision() -> void:
	if mesh != null and mesh.get_surface_count() > 0:
		_create_trimesh_collision()


func _create_trimesh_collision() -> void:
	for child: Node in get_children():
		if child is StaticBody3D:
			child.queue_free()
	var static_body: StaticBody3D = StaticBody3D.new()
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.shape = mesh.create_trimesh_shape()
	static_body.add_child(collision_shape)
	add_child(static_body)
