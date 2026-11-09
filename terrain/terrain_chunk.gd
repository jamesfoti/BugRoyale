class_name TerrainChunk
extends MeshInstance3D
## One meshed chunk. Rebuilds from density when settings change.

var chunk_coordinate: Vector3i = Vector3i.ZERO


func rebuild(settings: ChunkedTerrainWorld.SettingsSnapshot) -> void:
	var chunk_build_result: ChunkMeshBuilder.ChunkBuildResult = ChunkMeshBuilder.build_chunk(
		chunk_coordinate, settings
	)
	apply_build_result(chunk_build_result, settings.rebuild_collision)


## Takes a built mesh, and the trimesh collision for it unless this is the editor: nothing in
## the editor walks on the ground (spawns and the terrarium's raycasts are runtime), and
## every editor collision shape is drawn twice over as debug lines and fill, which on a
## lab-sized build is a few million extra triangles uploaded on every slider step.
func apply_build_result(
	chunk_build_result: ChunkMeshBuilder.ChunkBuildResult, rebuild_collision: bool
) -> void:
	mesh = FlyingEdgesMesher.to_array_mesh(chunk_build_result.mesh_result)
	position = chunk_build_result.local_position
	if rebuild_collision and _wants_collision():
		_create_trimesh_collision()


func update_collision() -> void:
	if _wants_collision():
		_create_trimesh_collision()


func _wants_collision() -> bool:
	return not Engine.is_editor_hint() and mesh != null and mesh.get_surface_count() > 0


func _create_trimesh_collision() -> void:
	for child: Node in get_children():
		if child is StaticBody3D:
			child.queue_free()
	var static_body: StaticBody3D = StaticBody3D.new()
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.shape = mesh.create_trimesh_shape()
	static_body.add_child(collision_shape)
	add_child(static_body)
