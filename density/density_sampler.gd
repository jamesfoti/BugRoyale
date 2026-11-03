class_name DensitySampler
extends RefCounted
## Builds signed density fields from analytic shapes and noise.

## Height above the open-terrain surface where 3D noise can no longer win the max() and is skipped.
const OPEN_TERRAIN_NOISE_SKIP_HEIGHT: float = 2.0


static func create_open_terrain_world_density(
	noise_seed: int,
	noise_frequency: float,
	noise_amplitude: float,
	noise_octaves: int,
	noise_lacunarity: float,
	noise_gain: float,
	bounds_center: Vector3,
	bounds_half: Vector3,
	bounds_clip_inset: float = 0.5,
	open_edges_enabled: bool = true,
	heightmap_image: Image = null,
	surface_height_offset: float = 0.0,
	solid_fill: bool = false
) -> WorldDensity:
	var density: WorldDensity = WorldDensity.new()
	density.open_terrain_enabled = true
	density.open_terrain_edges_enabled = open_edges_enabled
	density.open_terrain_solid_fill = solid_fill
	density.surface_height_offset = surface_height_offset
	density.noise_enabled = true
	density.noise_amplitude = noise_amplitude
	density.noise_octaves = noise_octaves
	density.noise_lacunarity = noise_lacunarity
	density.noise_gain = noise_gain
	density.bounds_center = bounds_center
	density.bounds_half = bounds_half
	density.bounds_clip_inset = bounds_clip_inset
	if heightmap_image != null and not heightmap_image.is_empty():
		# Shared read-only: callers pass a private copy (OpenTerrain caches one per texture).
		density._heightmap_image = heightmap_image
	density._init_open_terrain_height_noise(
		noise_seed, noise_frequency, noise_octaves, noise_lacunarity, noise_gain
	)
	if not solid_fill:
		density._init_boxed_in_terrain_noise(
			noise_seed, noise_frequency, noise_octaves, noise_lacunarity, noise_gain
		)
	density._init_ground_noises(noise_seed)
	return density


static func create_boxed_in_terrain_world_density(
	noise_seed: int,
	noise_frequency: float,
	noise_octaves: int,
	noise_lacunarity: float,
	noise_gain: float,
	bounds_center: Vector3,
	bounds_half: Vector3,
	bounds_clip_inset: float = 0.5,
	boxed_edges_enabled: bool = true
) -> WorldDensity:
	var density: WorldDensity = WorldDensity.new()
	density.boxed_in_terrain_enabled = true
	density.boxed_in_edges_enabled = boxed_edges_enabled
	density.noise_enabled = true
	density.noise_octaves = noise_octaves
	density.noise_lacunarity = noise_lacunarity
	density.noise_gain = noise_gain
	density.bounds_center = bounds_center
	density.bounds_half = bounds_half
	density.bounds_clip_inset = bounds_clip_inset
	density._init_boxed_in_terrain_noise(
		noise_seed, noise_frequency, noise_octaves, noise_lacunarity, noise_gain
	)
	density._init_ground_noises(noise_seed)
	return density


static func fbm_noise_3d(
	noise: FastNoiseLite, world_pos: Vector3, octaves: int, lacunarity: float, gain: float
) -> float:
	var amplitude := 1.0
	var frequency := 1.0
	var total := 0.0
	var normalizer := 0.0
	for _i in octaves:
		total += (
			noise.get_noise_3d(
				world_pos.x * frequency, world_pos.y * frequency, world_pos.z * frequency
			)
			* amplitude
		)
		normalizer += amplitude
		amplitude *= gain
		frequency *= lacunarity
	if normalizer <= 0.0:
		return 0.0
	return total / normalizer


static func apply_noise(
	field: SignedDensityField,
	chunk_origin: Vector3,
	voxel_size: float,
	seed: int,
	frequency: float,
	amplitude: float,
	octaves: int,
	lacunarity: float,
	gain: float
) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = frequency
	for z in field.size.z:
		for y in field.size.y:
			for x in field.size.x:
				var world_pos := chunk_origin + Vector3(x, y, z) * voxel_size
				var n := fbm_noise_3d(noise, world_pos, octaves, lacunarity, gain)
				var current := field.get_sample(x, y, z)
				field.set_sample(x, y, z, current - n * amplitude)


static func boxed_in_terrain_box_sdf(
	world_pos: Vector3, bounds_center: Vector3, bounds_half: Vector3, clip_inset: float
) -> float:
	## Positive outside the playable box; negative inside (X, Y, and Z faces).
	var relative: Vector3 = world_pos - bounds_center
	var half_extent_x: float = maxf(bounds_half.x - clip_inset, 0.0)
	var half_extent_y: float = maxf(bounds_half.y - clip_inset, 0.0)
	var half_extent_z: float = maxf(bounds_half.z - clip_inset, 0.0)
	var outside_x: float = absf(relative.x) - half_extent_x
	var outside_y: float = absf(relative.y) - half_extent_y
	var outside_z: float = absf(relative.z) - half_extent_z
	return maxf(outside_x, maxf(outside_y, outside_z))


static func open_terrain_box_sdf(
	world_pos: Vector3, bounds_center: Vector3, bounds_half: Vector3, clip_inset: float
) -> float:
	## Positive outside the playable volume; clips X, Z, and bottom Y only (open top).
	var relative: Vector3 = world_pos - bounds_center
	var half_extent_x: float = maxf(bounds_half.x - clip_inset, 0.0)
	var half_extent_y: float = maxf(bounds_half.y - clip_inset, 0.0)
	var half_extent_z: float = maxf(bounds_half.z - clip_inset, 0.0)
	var outside_x: float = absf(relative.x) - half_extent_x
	var outside_z: float = absf(relative.z) - half_extent_z
	var outside_bottom: float = -half_extent_y - relative.y
	return maxf(outside_x, maxf(outside_z, outside_bottom))


static func sample_heightmap_image(
	heightmap_image: Image,
	world_x: float,
	world_z: float,
	bounds_center: Vector3,
	bounds_half: Vector3,
	height_scale: float
) -> float:
	if bounds_half.x <= 0.0 or bounds_half.z <= 0.0:
		return bounds_center.y
	var normalized_x: float = (world_x - bounds_center.x) / bounds_half.x
	var normalized_z: float = (world_z - bounds_center.z) / bounds_half.z
	if absf(normalized_x) > 1.0 or absf(normalized_z) > 1.0:
		return bounds_center.y
	var image_size: Vector2i = heightmap_image.get_size()
	var sample_x: int = clampi(
		int(floor((normalized_x * 0.5 + 0.5) * float(image_size.x - 1))), 0, image_size.x - 1
	)
	var sample_z: int = clampi(
		int(floor((normalized_z * 0.5 + 0.5) * float(image_size.y - 1))), 0, image_size.y - 1
	)
	var pixel: Color = heightmap_image.get_pixel(sample_x, sample_z)
	var height_sample: float = (pixel.r + pixel.g + pixel.b) / 3.0
	return bounds_center.y + (height_sample - 0.5) * height_scale * 2.0


## Samples density on the shared world grid: sample (x, y, z) sits at
## grid_world_origin + (grid_offset + (x, y, z)) * step, so neighbouring chunks get bit-identical
## values on their shared faces.
static func build_chunk_field(
	density: WorldDensity,
	sample_size: Vector3i,
	grid_world_origin: Vector3,
	grid_offset: Vector3i,
	step: float
) -> SignedDensityField:
	var field := SignedDensityField.new(sample_size)
	var values: PackedFloat32Array = field.values
	var size_x: int = sample_size.x
	var size_y: int = sample_size.y
	var size_z: int = sample_size.z
	var min_value: float = INF
	var max_value: float = -INF
	var column_heights: PackedFloat32Array = PackedFloat32Array()
	var use_column_heights: bool = density.open_terrain_enabled
	if use_column_heights:
		column_heights.resize(size_x * size_z)
		for z in size_z:
			var world_z: float = grid_world_origin.z + float(grid_offset.z + z) * step
			for x in size_x:
				var world_x: float = grid_world_origin.x + float(grid_offset.x + x) * step
				column_heights[x + z * size_x] = density.sample_open_terrain_height(
					world_x, world_z
				)
	var index: int = 0
	for z in size_z:
		var world_z: float = grid_world_origin.z + float(grid_offset.z + z) * step
		for y in size_y:
			var world_y: float = grid_world_origin.y + float(grid_offset.y + y) * step
			for x in size_x:
				var world_pos := Vector3(
					grid_world_origin.x + float(grid_offset.x + x) * step, world_y, world_z
				)
				var value: float
				if use_column_heights:
					value = density.evaluate_open_terrain_with_surface(
						world_pos, column_heights[x + z * size_x]
					)
				else:
					value = density.evaluate(world_pos)
				values[index] = value
				min_value = minf(min_value, value)
				max_value = maxf(max_value, value)
				index += 1
	field.values = values
	field.min_value = min_value
	field.max_value = max_value
	return field


## World position of a (possibly out-of-chunk) grid sample; matches build_chunk_field.
static func grid_sample_position(
	grid_world_origin: Vector3, global_sample: Vector3i, step: float
) -> Vector3:
	return Vector3(
		grid_world_origin.x + float(global_sample.x) * step,
		grid_world_origin.y + float(global_sample.y) * step,
		grid_world_origin.z + float(global_sample.z) * step
	)


class WorldDensity:
	## Analytic density + gradient at any world position (seam-consistent normals).

	## Topsoil this deep is the map's own ground (dirt when dug); below it lies stone, with veins
	## of sand, clay and gravel where the vein noise runs high.
	const TOPSOIL_DEPTH: float = 1.5
	const VEIN_THRESHOLD: float = 0.42
	## Stone whose ore noise runs above this is an element's pocket (about a twelfth of it).
	const ORE_THRESHOLD: float = 0.4
	## Pockets are drawn from cells this many metres on a side, one element per cell, so a
	## pocket is one ore and not a speckle of every element in reach.
	const ORE_POCKET_SIZE: float = 6.0

	var noise_enabled: bool = true
	var noise_amplitude: float = 3.0
	var noise_octaves: int = 3
	var noise_lacunarity: float = 2.0
	var noise_gain: float = 0.5
	var bounds_center: Vector3 = Vector3.ZERO
	var bounds_half: Vector3 = Vector3.ZERO
	var bounds_clip_inset: float = 0.5
	var boxed_in_terrain_enabled: bool = false
	var boxed_in_edges_enabled: bool = true
	var open_terrain_enabled: bool = false
	var open_terrain_edges_enabled: bool = true
	var open_terrain_solid_fill: bool = false
	var surface_height_offset: float = 0.0
	## Carves tunnels, caverns and bedrock under a solid-filled open terrain (null: none).
	var caves: CaveCarver = null
	var terrain_edits: TerrainEdits = null
	## Seeds which element each ore pocket is (with the vein and ore noises, the map's seed).
	var ore_seed: int = 0

	var _vein_noise: FastNoiseLite
	var _ore_noise: FastNoiseLite

	var _macro_noise: FastNoiseLite
	var _height_noise: FastNoiseLite
	var _heightmap_image: Image
	var _noise: FastNoiseLite

	static func create(
		noise_enabled: bool,
		noise_seed: int,
		noise_frequency: float,
		noise_amplitude: float,
		noise_octaves: int,
		noise_lacunarity: float,
		noise_gain: float,
		bounds_center: Vector3,
		bounds_half: Vector3,
		bounds_clip_inset: float = 0.5
	) -> WorldDensity:
		var density := WorldDensity.new()
		density.noise_enabled = noise_enabled
		density.noise_amplitude = noise_amplitude
		density.noise_octaves = noise_octaves
		density.noise_lacunarity = noise_lacunarity
		density.noise_gain = noise_gain
		density.bounds_center = bounds_center
		density.bounds_half = bounds_half
		density.bounds_clip_inset = bounds_clip_inset
		if noise_enabled:
			density._noise = FastNoiseLite.new()
			density._noise.seed = noise_seed
			density._noise.noise_type = FastNoiseLite.TYPE_PERLIN
			density._noise.frequency = noise_frequency
		density._init_ground_noises(noise_seed)
		return density

	## What a natural voxel is made of, from how deep it lies (density is roughly metres below
	## the surface, negative inside), the vein noise and the ore noise: the mesher colours dug
	## faces with it and the pickaxe pays it out. NATURAL means the map's own ground, which
	## digs as dirt. Below the topsoil the ground is stone, with veins of sand, clay and gravel
	## where the vein noise runs high and pockets of an element where the ore noise does.
	func natural_material(world_position: Vector3, density_value: float) -> TerrainMaterials.Kind:
		var depth: float = -density_value
		if depth < TOPSOIL_DEPTH or _vein_noise == null:
			return TerrainMaterials.Kind.NATURAL
		var vein: float = _vein_noise.get_noise_3dv(world_position)
		if vein < VEIN_THRESHOLD:
			if _ore_noise.get_noise_3dv(world_position) < ORE_THRESHOLD:
				return TerrainMaterials.Kind.STONE
			return ore_at(world_position, depth)
		# Which vein: a second, offset read of the same noise splits the veins three ways.
		var which: float = _vein_noise.get_noise_3dv(world_position + Vector3(131.0, 71.0, 17.0))
		if which < -0.15:
			return TerrainMaterials.Kind.SAND
		if which < 0.15:
			return TerrainMaterials.Kind.CLAY
		return TerrainMaterials.Kind.GRAVEL

	## The vertex colour of natural ground here (alpha 1: the terrain shader draws its own
	## ground, tinted by it). Plain white unless a world colours its ground by place.
	func natural_tint(_world_position: Vector3, _density_value: float) -> Color:
		return TerrainMaterials.NATURAL_VERTEX_COLOR

	## The element of the ore pocket at a point this deep: every element whose depth is reached
	## is a candidate, and the pocket's cell draws one of them by weight. Stone where nothing
	## is in reach yet (just under the topsoil, above the shallowest ore).
	func ore_at(world_position: Vector3, depth: float) -> TerrainMaterials.Kind:
		var total: int = 0
		for kind: TerrainMaterials.Kind in TerrainMaterials.ELEMENT_KINDS:
			if depth >= TerrainMaterials.ore_depth(kind):
				total += TerrainMaterials.ore_weight(kind)
		if total <= 0:
			return TerrainMaterials.Kind.STONE
		var cell: Vector3i = Vector3i((world_position / ORE_POCKET_SIZE).floor())
		var draw: int = (hash(Vector4i(cell.x, cell.y, cell.z, ore_seed)) & 0x7FFFFFFF) % total
		for kind: TerrainMaterials.Kind in TerrainMaterials.ELEMENT_KINDS:
			if depth < TerrainMaterials.ore_depth(kind):
				continue
			draw -= TerrainMaterials.ore_weight(kind)
			if draw < 0:
				return kind
		return TerrainMaterials.Kind.STONE

	## The noises that say what the ground under the topsoil is made of (every world has them,
	## whatever shapes its surface): the vein noise for sand, clay and gravel, the ore noise for
	## the elements' pockets.
	func _init_ground_noises(noise_seed: int) -> void:
		ore_seed = noise_seed
		_vein_noise = FastNoiseLite.new()
		_vein_noise.seed = noise_seed + 77
		_vein_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_vein_noise.frequency = 0.09
		_ore_noise = FastNoiseLite.new()
		_ore_noise.seed = noise_seed + 88
		_ore_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_ore_noise.frequency = 0.14

	func _init_boxed_in_terrain_noise(
		terrain_seed: int, surface_frequency: float, octaves: int, lacunarity: float, gain: float
	) -> void:
		_macro_noise = FastNoiseLite.new()
		_macro_noise.seed = terrain_seed
		_macro_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_macro_noise.frequency = maxf(surface_frequency, 0.001)
		_macro_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_macro_noise.fractal_octaves = octaves
		_macro_noise.fractal_lacunarity = lacunarity
		_macro_noise.fractal_gain = gain

	func _sample_boxed_in_terrain_noise(world_position: Vector3) -> float:
		if not noise_enabled or _macro_noise == null:
			return 1.0
		return _macro_noise.get_noise_3d(world_position.x, world_position.y, world_position.z)

	func _evaluate_boxed_in_terrain(world_pos: Vector3) -> float:
		var value: float = _sample_boxed_in_terrain_noise(world_pos)
		if boxed_in_edges_enabled:
			value = maxf(
				value,
				DensitySampler.boxed_in_terrain_box_sdf(
					world_pos, bounds_center, bounds_half, bounds_clip_inset
				)
			)
		if terrain_edits != null:
			value = terrain_edits.apply_to_density(value, world_pos)
		return value

	func _init_open_terrain_height_noise(
		terrain_seed: int, surface_frequency: float, octaves: int, lacunarity: float, gain: float
	) -> void:
		_height_noise = FastNoiseLite.new()
		_height_noise.seed = terrain_seed
		_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_height_noise.frequency = maxf(surface_frequency, 0.001)
		_height_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_height_noise.fractal_octaves = octaves
		_height_noise.fractal_lacunarity = lacunarity
		_height_noise.fractal_gain = gain

	func _sample_open_terrain_height(world_x: float, world_z: float) -> float:
		if _heightmap_image != null and not _heightmap_image.is_empty():
			return (
				DensitySampler.sample_heightmap_image(
					_heightmap_image, world_x, world_z, bounds_center, bounds_half, noise_amplitude
				)
				+ surface_height_offset
			)
		if not noise_enabled or _height_noise == null:
			return bounds_center.y + surface_height_offset
		var noise_value: float = _height_noise.get_noise_2d(world_x, world_z)
		return bounds_center.y + noise_value * noise_amplitude + surface_height_offset

	func sample_open_terrain_height(world_x: float, world_z: float) -> float:
		return _sample_open_terrain_height(world_x, world_z)

	func _evaluate_open_terrain(world_pos: Vector3) -> float:
		var surface_height: float = _sample_open_terrain_height(world_pos.x, world_pos.z)
		return evaluate_open_terrain_with_surface(world_pos, surface_height)

	## Open-terrain density when the column's surface height is already known (field builds
	## sample one height per XZ column instead of per voxel).
	func evaluate_open_terrain_with_surface(world_pos: Vector3, surface_height: float) -> float:
		var above_surface: float = world_pos.y - surface_height
		var value: float
		if open_terrain_solid_fill:
			value = above_surface
			if caves != null:
				value = caves.carve(value, world_pos, surface_height)
		elif above_surface >= OPEN_TERRAIN_NOISE_SKIP_HEIGHT:
			# FBM noise stays within [-1, 1], so max(noise, above_surface) is exactly above_surface.
			value = above_surface
		else:
			# Same 3D noise field as boxed-in terrain; heightmap clips the open top.
			value = _sample_boxed_in_terrain_noise(world_pos)
			if above_surface > 0.0:
				value = maxf(value, above_surface)
		if open_terrain_edges_enabled:
			value = maxf(
				value,
				DensitySampler.open_terrain_box_sdf(
					world_pos, bounds_center, bounds_half, bounds_clip_inset
				)
			)
		if terrain_edits != null:
			value = terrain_edits.apply_to_density(value, world_pos)
		return value

	func evaluate(world_pos: Vector3) -> float:
		if open_terrain_enabled:
			return _evaluate_open_terrain(world_pos)
		if boxed_in_terrain_enabled:
			return _evaluate_boxed_in_terrain(world_pos)
		# No shape of its own: solid where the 3D noise runs high, with the edits on top.
		var value := 1.0
		if noise_enabled:
			value -= (
				DensitySampler.fbm_noise_3d(
					_noise, world_pos, noise_octaves, noise_lacunarity, noise_gain
				)
				* noise_amplitude
			)
		if terrain_edits != null:
			value = terrain_edits.apply_to_density(value, world_pos)
		return value

	func gradient(world_pos: Vector3, epsilon: float) -> Vector3:
		var dx := (
			(
				evaluate(world_pos + Vector3(epsilon, 0.0, 0.0))
				- evaluate(world_pos - Vector3(epsilon, 0.0, 0.0))
			)
			/ (2.0 * epsilon)
		)
		var dy := (
			(
				evaluate(world_pos + Vector3(0.0, epsilon, 0.0))
				- evaluate(world_pos - Vector3(0.0, epsilon, 0.0))
			)
			/ (2.0 * epsilon)
		)
		var dz := (
			(
				evaluate(world_pos + Vector3(0.0, 0.0, epsilon))
				- evaluate(world_pos - Vector3(0.0, 0.0, epsilon))
			)
			/ (2.0 * epsilon)
		)
		return Vector3(dx, dy, dz)
