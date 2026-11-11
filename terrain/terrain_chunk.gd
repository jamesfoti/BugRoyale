class_name TerrainChunk
extends MeshInstance3D
## One meshed chunk. Rebuilds from density when settings change.

## The water sheet's material: the terrarium's pool surface.
const WATER_MATERIAL_PATH: String = "res://materials/terrarium_water.tres"

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
	_apply_water(chunk_build_result.water_mesh_result)
	if rebuild_collision and _wants_collision():
		_create_trimesh_collision(chunk_build_result.collision_faces)


## The pools' sheet as a child mesh with the water material, dropped when the chunk has none.
func _apply_water(water_mesh_result: FlyingEdgesMesher.MeshResult) -> void:
	var water: MeshInstance3D = get_node_or_null("Water") as MeshInstance3D
	if water_mesh_result == null or water_mesh_result.indices.is_empty():
		if water != null:
			water.queue_free()
		return
	if water == null:
		water = MeshInstance3D.new()
		water.name = "Water"
		water.material_override = load(WATER_MATERIAL_PATH)
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(water)
	water.mesh = FlyingEdgesMesher.to_array_mesh(water_mesh_result)


func update_collision() -> void:
	if _wants_collision():
		_create_trimesh_collision()


func _wants_collision() -> bool:
	return not Engine.is_editor_hint() and mesh != null and mesh.get_surface_count() > 0


## The chunk's collision, from the triangles the build made on its worker thread; without
## them, from the mesh, which with a real renderer reads it back from the GPU and waits.
func _create_trimesh_collision(faces: PackedVector3Array = PackedVector3Array()) -> void:
	for child: Node in get_children():
		if child is StaticBody3D:
			child.queue_free()
	var static_body: StaticBody3D = StaticBody3D.new()
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	if faces.is_empty():
		collision_shape.shape = mesh.create_trimesh_shape()
	else:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		collision_shape.shape = shape
	static_body.add_child(collision_shape)
	add_child(static_body)
