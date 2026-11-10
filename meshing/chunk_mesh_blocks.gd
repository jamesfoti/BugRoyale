class_name ChunkMeshBlocks
extends RefCounted
## A chunk's surface meshed in blocks of BLOCK_CELLS cells a side. A brush rebuild meshes
## only the blocks whose samples changed (SignedDensityField.changed_first and changed_last)
## and keeps the rest from the chunk's last build, since the mesher is the slow part of a
## rebuild and a stroke touches a corner of the chunk at most. The blocks merge into one
## mesh for the chunk: one surface, one collision shape. A vertex on a block face is made
## by both blocks, from the same samples, so the surface and its normals meet without a seam.

const BLOCK_CELLS: int = 8

var per_axis: Vector3i = Vector3i.ZERO
var blocks: Array[FlyingEdgesMesher.MeshResult] = []


## Meshes the field in blocks; with a previous build of the same chunk, only the blocks the
## field's changed samples touch, the rest taken from it.
static func build(
	field: SignedDensityField,
	chunk_extent: float,
	iso_level: float,
	grid_offset: Vector3i,
	grid_world_origin: Vector3,
	chunk_world_center: Vector3,
	density: DensitySampler.WorldDensity,
	previous: ChunkMeshBlocks = null
) -> ChunkMeshBlocks:
	var out := ChunkMeshBlocks.new()
	var cells: Vector3i = field.cell_counts()
	out.per_axis = Vector3i(
		ceili(float(cells.x) / BLOCK_CELLS),
		ceili(float(cells.y) / BLOCK_CELLS),
		ceili(float(cells.z) / BLOCK_CELLS)
	)
	var count: int = out.per_axis.x * out.per_axis.y * out.per_axis.z
	var reuse: bool = (
		previous != null and previous.per_axis == out.per_axis and previous.blocks.size() == count
	)
	var scratch := PackedInt32Array()
	scratch.resize(field.values.size() * 3)
	scratch.fill(-1)
	var index: int = 0
	for block_z: int in out.per_axis.z:
		for block_y: int in out.per_axis.y:
			for block_x: int in out.per_axis.x:
				var first: Vector3i = Vector3i(block_x, block_y, block_z) * BLOCK_CELLS
				var last: Vector3i = (first + Vector3i.ONE * (BLOCK_CELLS - 1)).min(
					cells - Vector3i.ONE
				)
				if reuse and not _touches(first, last, field):
					out.blocks.append(previous.blocks[index])
				else:
					out.blocks.append(
						FlyingEdgesMesher.build_mesh(
							field,
							chunk_extent,
							iso_level,
							grid_offset,
							grid_world_origin,
							chunk_world_center,
							density,
							first,
							last,
							scratch
						)
					)
				index += 1
	return out


## Whether the cells first..last read any sample the field marks changed: a cell reads the
## sample at its corner and the next one along each axis.
static func _touches(first: Vector3i, last: Vector3i, field: SignedDensityField) -> bool:
	return (
		first.x <= field.changed_last.x
		and last.x + 1 >= field.changed_first.x
		and first.y <= field.changed_last.y
		and last.y + 1 >= field.changed_first.y
		and first.z <= field.changed_last.z
		and last.z + 1 >= field.changed_first.z
	)


## How many blocks hold any surface.
func meshed_count() -> int:
	var count: int = 0
	for block: FlyingEdgesMesher.MeshResult in blocks:
		if not block.indices.is_empty():
			count += 1
	return count


## The blocks as one mesh.
func merge() -> FlyingEdgesMesher.MeshResult:
	var out := FlyingEdgesMesher.MeshResult.new()
	for block: FlyingEdgesMesher.MeshResult in blocks:
		if block.indices.is_empty():
			continue
		var base: int = out.vertices.size()
		out.vertices.append_array(block.vertices)
		out.normals.append_array(block.normals)
		out.colors.append_array(block.colors)
		if base == 0:
			out.indices.append_array(block.indices)
			continue
		var shifted: PackedInt32Array = block.indices.duplicate()
		for i: int in shifted.size():
			shifted[i] += base
		out.indices.append_array(shifted)
	return out
