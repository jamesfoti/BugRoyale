extends GutTest
## Skirts (ChunkSkirts): a chunk the surface crosses gets strips hung from the edges where its
## surface meets its faces; they lie in those faces, in solid ground (a pocket dug at the seam
## stops them), face out of the chunk toward the neighbour, and are not in the collision.


func _world() -> OpenTerrain:
	var world: OpenTerrain = OpenTerrain.new()
	world.rebuild_on_ready = false
	world.chunks_x = 3
	world.chunks_y = 3
	world.chunks_z = 3
	world.chunk_size = 8.0
	world.voxel_size = 1.0
	world.solid_underside = true
	world.noise_amplitude = 2.0
	return world


## The triangles lying wholly in one face of the chunk (the skirts), as [a, b, c, face].
func _skirt_triangles(mesh: FlyingEdgesMesher.MeshResult, half: float) -> Array:
	var found: Array = []
	for first: int in range(0, mesh.indices.size(), 3):
		var corners: Array[Vector3] = [
			mesh.vertices[mesh.indices[first]],
			mesh.vertices[mesh.indices[first + 1]],
			mesh.vertices[mesh.indices[first + 2]],
		]
		for axis: int in 3:
			for side: float in [-1.0, 1.0]:
				var all_on: bool = true
				for corner: Vector3 in corners:
					if absf(corner[axis] - side * half) > 0.001:
						all_on = false
				if all_on:
					var face := Vector3.ZERO
					face[axis] = side
					found.append([corners[0], corners[1], corners[2], face])
	return found


## The chunk of the middle column the surface crosses, built as the map would.
func _surface_chunk(world: OpenTerrain) -> Array:
	var settings: ChunkedTerrainWorld.SettingsSnapshot = world._make_settings_snapshot()
	for chunk_y: int in 3:
		var coordinate := Vector3i(1, chunk_y, 1)
		var result: ChunkMeshBuilder.ChunkBuildResult = ChunkMeshBuilder.build_chunk(
			coordinate, settings
		)
		if not result.mesh_result.indices.is_empty():
			return [coordinate, result, settings]
	return []


func test_skirts_hang_into_the_ground_face_out_and_stay_out_of_the_collision() -> void:
	var world: OpenTerrain = _world()
	add_child_autofree(world)
	var built: Array = _surface_chunk(world)
	assert_false(built.is_empty(), "the surface crosses the middle column")
	var result: ChunkMeshBuilder.ChunkBuildResult = built[1]
	var mesh: FlyingEdgesMesher.MeshResult = result.mesh_result
	var skirts: Array = _skirt_triangles(mesh, 4.0)
	assert_gt(skirts.size(), 4, "skirts on the faces the surface meets")
	assert_eq(
		result.collision_faces.size(),
		mesh.indices.size() - skirts.size() * 3,
		"the collision is the surface alone"
	)
	var centre: Vector3 = result.local_position + world.global_position
	var density: DensitySampler.WorldDensity = world._get_bake_density()
	for skirt: Array in skirts:
		var normal: Vector3 = ((skirt[1] - skirt[0]) as Vector3).cross(skirt[2] - skirt[0])
		if normal.length_squared() > 0.000001:
			assert_lt(normal.dot(skirt[3]), 0.0, "faces out of the chunk")
		for corner: int in 3:
			var at: Vector3 = centre + (skirt[corner] as Vector3)
			assert_lt(density.evaluate(at), 0.6, "in the ground, or on its surface")


func test_a_pocket_at_the_seam_stops_the_skirts() -> void:
	var world: OpenTerrain = _world()
	add_child_autofree(world)
	var built: Array = _surface_chunk(world)
	var coordinate: Vector3i = built[0]
	var settings: ChunkedTerrainWorld.SettingsSnapshot = built[2]
	var corner: Vector3 = world.global_position + world._chunk_corner_local(coordinate, settings)
	# A pocket on the chunk's +x face, a little under the surface there.
	var seam := Vector3(corner.x + 8.0, 0.0, corner.z + 4.0)
	seam.y = world.get_surface_height_at(seam) - 2.5
	world.apply_brush(seam, 1.5, false)
	var result: ChunkMeshBuilder.ChunkBuildResult = ChunkMeshBuilder.build_chunk(
		coordinate, world._make_settings_snapshot()
	)
	var centre: Vector3 = result.local_position + world.global_position
	var skirts: Array = _skirt_triangles(result.mesh_result, 4.0)
	assert_gt(skirts.size(), 0)
	for skirt: Array in skirts:
		for index: int in 3:
			var at: Vector3 = centre + (skirt[index] as Vector3)
			assert_false(
				at.distance_to(seam) < 1.2, "no skirt hangs into the pocket at %s" % str(at)
			)


## The crack the skirts are for: a fine chunk beside a coarse one, their surfaces apart at
## the face they share. Along that face every point between the two surfaces is covered by a
## skirt of one side or the other.
func test_a_fine_chunk_beside_a_coarse_one_leaves_no_crack() -> void:
	var world: OpenTerrain = _world()
	world.noise_amplitude = 3.0
	add_child_autofree(world)
	var built: Array = _surface_chunk(world)
	var fine_at: Vector3i = built[0]
	var coarse_at: Vector3i = fine_at + Vector3i(1, 0, 0)
	var fine_settings: ChunkedTerrainWorld.SettingsSnapshot = world._make_settings_snapshot()
	var coarse_settings: ChunkedTerrainWorld.SettingsSnapshot = world._make_settings_snapshot()
	world._coarsen(coarse_settings)
	var fine: ChunkMeshBuilder.ChunkBuildResult = ChunkMeshBuilder.build_chunk(
		fine_at, fine_settings
	)
	var coarse: ChunkMeshBuilder.ChunkBuildResult = ChunkMeshBuilder.build_chunk(
		coarse_at, coarse_settings
	)
	var origin: Vector3 = world.global_position
	var fine_centre: Vector3 = origin + fine.local_position
	var coarse_centre: Vector3 = origin + coarse.local_position
	# The surfaces' heights along the face, and the skirts on it, in world space.
	var fine_edge: Array = _face_edges(fine.mesh_result, fine_centre, 0, 4.0)
	var coarse_edge: Array = _face_edges(coarse.mesh_result, coarse_centre, 0, -4.0)
	var skirts: Array = []
	for skirt: Array in _skirt_triangles(fine.mesh_result, 4.0):
		if (skirt[3] as Vector3).x > 0.0:
			skirts.append([fine_centre + skirt[0], fine_centre + skirt[1], fine_centre + skirt[2]])
	for skirt: Array in _skirt_triangles(coarse.mesh_result, 4.0):
		if (skirt[3] as Vector3).x < 0.0:
			skirts.append(
				[coarse_centre + skirt[0], coarse_centre + skirt[1], coarse_centre + skirt[2]]
			)
	var widest: float = 0.0
	var uncovered: int = 0
	var checked: int = 0
	var z: float = fine_centre.z - 3.9
	while z < fine_centre.z + 3.9:
		var fine_y: float = _height_on(fine_edge, z)
		var coarse_y: float = _height_on(coarse_edge, z)
		if not is_nan(fine_y) and not is_nan(coarse_y):
			var low: float = minf(fine_y, coarse_y)
			var high: float = maxf(fine_y, coarse_y)
			widest = maxf(widest, high - low)
			var y: float = low + 0.05
			while y < high - 0.05:
				checked += 1
				if not _covered(skirts, Vector2(z, y)):
					uncovered += 1
				y += 0.1
		z += 0.2
	assert_gt(widest, 0.3, "the two surfaces part at the seam (a crack to cover)")
	assert_gt(checked, 0)
	assert_eq(uncovered, 0, "every point of the crack is behind a skirt (%d checked)" % checked)


## The surface's edges on one face (axis, side: the face's offset from the centre), as world
## segments.
func _face_edges(
	mesh: FlyingEdgesMesher.MeshResult, centre: Vector3, axis: int, side: float
) -> Array:
	var edges: Array = []
	var surface: int = mesh.indices.size()
	for first: int in range(0, surface, 3):
		for corner: int in 3:
			var a: Vector3 = mesh.vertices[mesh.indices[first + corner]]
			var b: Vector3 = mesh.vertices[mesh.indices[first + (corner + 1) % 3]]
			if absf(a[axis] - side) < 0.001 and absf(b[axis] - side) < 0.001:
				edges.append([centre + a, centre + b])
	return edges


## The highest surface edge over a z on the face, or NAN where none crosses it.
func _height_on(edges: Array, z: float) -> float:
	var best: float = NAN
	for edge: Array in edges:
		var a: Vector3 = edge[0]
		var b: Vector3 = edge[1]
		if z < minf(a.z, b.z) or z > maxf(a.z, b.z) or absf(b.z - a.z) < 0.0001:
			continue
		var y: float = lerpf(a.y, b.y, (z - a.z) / (b.z - a.z))
		if is_nan(best) or y > best:
			best = y
	return best


## Whether a point (z, y) of the face lies in any of the skirt triangles, seen along x.
func _covered(skirts: Array, point: Vector2) -> bool:
	for skirt: Array in skirts:
		var a := Vector2((skirt[0] as Vector3).z, (skirt[0] as Vector3).y)
		var b := Vector2((skirt[1] as Vector3).z, (skirt[1] as Vector3).y)
		var c := Vector2((skirt[2] as Vector3).z, (skirt[2] as Vector3).y)
		if Geometry2D.point_is_inside_triangle(point, a, b, c):
			return true
	return false
