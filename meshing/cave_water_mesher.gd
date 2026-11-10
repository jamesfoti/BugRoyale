class_name CaveWaterMesher
extends RefCounted
## The pools in the caves: a chunk's water surface, meshed from the aquifer levels its carver
## gives each column (CaveCarver.water_level). The level is a flat sheet per aquifer, so the
## sheet is meshed as the zero crossing of height minus level over the chunk's samples, and
## then cut back to where the ground's own field is air well under the surface: no sheet
## inside the rock, none in the open air of a valley that happens to lie below a level. A
## pool is only its surface; the submerged walls are the terrain's own, seen through it.

## Pools stay this far under the surface, so none opens to the sky through thin ground.
const SURFACE_MARGIN: float = 4.0
## The water field's value where a column is dry: far outside, so no sheet is made.
const DRY: float = 1000000.0


## The water sheet of a chunk whose ground field is given, as the terrain mesher's result
## (vertices relative to chunk_world_center); empty when no aquifer reaches the chunk.
static func build(
	field: SignedDensityField,
	density: DensitySampler.WorldDensity,
	grid_world_origin: Vector3,
	grid_offset: Vector3i,
	step: float,
	chunk_extent: float,
	chunk_world_center: Vector3
) -> FlyingEdgesMesher.MeshResult:
	var empty := FlyingEdgesMesher.MeshResult.new()
	var caves: CaveCarver = density.caves
	if caves == null or caves.water_top == -INF or not field.is_valid():
		return empty
	var size: Vector3i = field.size
	var corner: Vector3 = DensitySampler.grid_sample_position(grid_world_origin, grid_offset, step)
	var bottom: float = corner.y - step
	var top: float = corner.y + float(size.y - 1) * step + step
	# The level of each column, and whether any lies within the chunk's height.
	var levels: PackedFloat32Array = PackedFloat32Array()
	levels.resize(size.x * size.z)
	var any_level: bool = false
	for z: int in size.z:
		for x: int in size.x:
			var level: float = caves.water_level(
				corner.x + float(x) * step, corner.z + float(z) * step
			)
			levels[x + z * size.x] = level
			if level > bottom and level < top:
				any_level = true
	if not any_level:
		return empty
	var water := SignedDensityField.new(size)
	var values: PackedFloat32Array = water.values
	var lowest: float = INF
	var highest: float = -INF
	var index: int = 0
	for z: int in size.z:
		for y: int in size.y:
			var world_y: float = corner.y + float(y) * step
			for x: int in size.x:
				var level: float = levels[x + z * size.x]
				var value: float = DRY if level == -INF else world_y - level
				values[index] = value
				lowest = minf(lowest, value)
				highest = maxf(highest, value)
				index += 1
	water.values = values
	water.min_value = lowest
	water.max_value = highest
	var sheet: FlyingEdgesMesher.MeshResult = FlyingEdgesMesher.build_mesh(
		water, chunk_extent, 0.0, grid_offset, grid_world_origin, chunk_world_center, null
	)
	return _cut_to_the_caves(sheet, field, density, corner, step, chunk_world_center)


## Keeps the flat triangles whose corners all lie in the ground field's air, at least
## SURFACE_MARGIN under the surface: the sheet where a pool really is.
static func _cut_to_the_caves(
	sheet: FlyingEdgesMesher.MeshResult,
	field: SignedDensityField,
	density: DensitySampler.WorldDensity,
	corner: Vector3,
	step: float,
	chunk_world_center: Vector3
) -> FlyingEdgesMesher.MeshResult:
	var kept := FlyingEdgesMesher.MeshResult.new()
	if sheet.indices.is_empty():
		return kept
	var in_pool: PackedByteArray = PackedByteArray()
	in_pool.resize(sheet.vertices.size())
	for vertex: int in sheet.vertices.size():
		var world: Vector3 = chunk_world_center + sheet.vertices[vertex]
		if field.sample_world(world, corner, step) < 0.0:
			continue
		var depth: float = density.sample_open_terrain_height(world.x, world.z) - world.y
		if depth < SURFACE_MARGIN:
			continue
		in_pool[vertex] = 1
	var remap: PackedInt32Array = PackedInt32Array()
	remap.resize(sheet.vertices.size())
	remap.fill(-1)
	var triangle: int = 0
	while triangle + 2 < sheet.indices.size():
		var a: int = sheet.indices[triangle]
		var b: int = sheet.indices[triangle + 1]
		var c: int = sheet.indices[triangle + 2]
		triangle += 3
		if in_pool[a] == 0 or in_pool[b] == 0 or in_pool[c] == 0:
			continue
		# A pool's surface is flat: the steps the mesher makes between columns of different
		# levels (or a wet column and a dry one) are no surface at all.
		var facing: Vector3 = (sheet.vertices[b] - sheet.vertices[a]).cross(
			sheet.vertices[c] - sheet.vertices[a]
		)
		if absf(facing.y) < 0.7 * facing.length():
			continue
		for old: int in [a, b, c]:
			if remap[old] < 0:
				remap[old] = kept.vertices.size()
				kept.vertices.append(sheet.vertices[old])
				kept.normals.append(sheet.normals[old])
			kept.indices.append(remap[old])
	return kept
