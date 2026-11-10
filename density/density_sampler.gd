class_name DensitySampler
extends RefCounted
## Builds signed density fields from analytic shapes and noise.

## Under an open terrain whose underside is a sponge of 3D noise, the noise (in [-1, 1]) is
## scaled to this many metres before it meets the surface's distance, so a hole's wall and the
## ground round it are on a comparable scale where the two meet. The zero crossings do not
## move, so the sponge keeps its shape whatever the scale.
const SPONGE_NOISE_METRES: float = 4.0
## Height above the open-terrain surface where the scaled 3D noise can no longer win the max()
## and is skipped.
const OPEN_TERRAIN_NOISE_SKIP_HEIGHT: float = SPONGE_NOISE_METRES


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
	if not density.solids.is_empty() or (density.caves != null and density.caves.systems != null):
		var halo: Vector3 = Vector3.ONE * step * 2.0
		var region_start: Vector3 = grid_world_origin + Vector3(grid_offset) * step - halo
		density.prepare_for_region(AABB(region_start, Vector3(sample_size) * step + halo * 2.0))
	var min_value: float = INF
	var max_value: float = -INF
	var column_heights: PackedFloat32Array = PackedFloat32Array()
	# The surface's slope per column, read only when the relief wants it (0 otherwise).
	var column_slopes: PackedFloat32Array = PackedFloat32Array()
	var use_column_heights: bool = density.open_terrain_enabled
	if use_column_heights:
		column_heights.resize(size_x * size_z)
		column_slopes.resize(size_x * size_z)
		var want_slopes: bool = (
			density.open_terrain_solid_fill
			and (density.relief_amplitude > 0.0 or density.caves != null)
		)
		var highest: float = -INF
		for z in size_z:
			var world_z: float = grid_world_origin.z + float(grid_offset.z + z) * step
			for x in size_x:
				var world_x: float = grid_world_origin.x + float(grid_offset.x + x) * step
				var height: float = density.sample_open_terrain_height(world_x, world_z)
				column_heights[x + z * size_x] = height
				if want_slopes:
					column_slopes[x + z * size_x] = density.surface_slope(world_x, world_z, height)
				highest = maxf(highest, height)
		# A chunk whose lowest sample row clears the highest surface under it is sky: the
		# column heights have already said so, and the per-voxel pass (where the caves' noise
		# reads are) would only confirm it. A third of a three-deep map is this chunk.
		var bottom_y: float = grid_world_origin.y + float(grid_offset.y) * step
		var halo: Vector3 = Vector3.ONE * step
		var region := AABB(
			grid_world_origin + Vector3(grid_offset) * step - halo,
			Vector3(sample_size - Vector3i.ONE) * step + halo * 2.0
		)
		if density.is_sky(highest + density.relief_reach(), bottom_y, region):
			var clearance: float = bottom_y - highest
			values.fill(clearance)
			field.values = values
			field.min_value = clearance
			field.max_value = clearance
			field.sky = true
			return field
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
						world_pos,
						column_heights[x + z * size_x],
						true,
						column_slopes[x + z * size_x]
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

	## The kinds of ground on top, by the land biome noise. NONE is no fixed biome.
	enum LandBiome { NONE = -1, MEADOW, DRYLAND, MARSH, BARRENS }

	## Topsoil this deep is the map's own ground (dirt when dug); below it lies stone, with veins
	## of sand, clay and gravel where the vein noise runs high.
	const TOPSOIL_DEPTH: float = 1.5
	const VEIN_THRESHOLD: float = 0.42
	## Stone whose ore noise runs above this is an element's pocket (about a twelfth of it).
	const ORE_THRESHOLD: float = 0.4
	## Pockets are drawn from cells this many metres on a side, one element per cell, so a
	## pocket is one ore and not a speckle of every element in reach.
	const ORE_POCKET_SIZE: float = 6.0
	## How softly the height curve's floor meets the ground above it, in unit height.
	const CURVE_FLOOR_SOFTNESS: float = 0.1
	## Slopes (rise over run) the relief fades in between: none on gentler ground, all of
	## it on faces at 45 degrees and steeper.
	const RELIEF_SLOPE_START: float = 0.5
	const RELIEF_SLOPE_END: float = 1.0
	## How level a flat spot is at its centre (1 a billiard table; a little ground is kept
	## so it still reads as ground), and the metres over which it fades into the land.
	const FLAT_SPOT_BLEND: float = 0.9
	const FLAT_SPOT_FADE: float = 10.0
	## The land biomes' names, in LandBiome order, for the rebuild line.
	const LAND_BIOME_NAMES: PackedStringArray = ["meadow", "dryland", "marsh", "barrens"]

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
	## Terraces: the open terrain's surface stepped into shelves (see terrace_height), rolled
	## from the seed by roll_terraces or set by hand. Each shelf is terrace_step metres above
	## the one below, offset by terrace_phase; terrace_strength runs from 0, a soft benching,
	## to 1, flat treads and steep risers; and a slow noise says where the ground is terraced
	## at all, terrace_coverage being the share of it that is.
	var terrace_enabled: bool = false
	var terrace_step: float = 3.0
	var terrace_strength: float = 1.0
	var terrace_phase: float = 0.0
	var terrace_coverage: float = 0.5
	## The surface's character, rolled from the seed by roll_surface or set by hand (applied in
	## _sample_open_terrain_height). The height noise is read at a point pushed by a slower
	## noise pair, surface_warp metres at most, so the round blobs of plain noise stretch into
	## curved ridges and bays; mixed toward its ridged form by surface_ridge (0 round tops, 1
	## sharp crests along the noise's zero lines); and redistributed by surface_power (above 1
	## the valleys flatten into plains and the hills grow fewer and taller, below 1 plateaus).
	## 0 m, 0 and 1 leave the plain noise. Every seed drawing from one distribution is what
	## makes generated ground feel predictable; rolling these makes seeds differ in kind.
	var surface_warp: float = 0.0
	var surface_ridge: float = 0.0
	var surface_power: float = 1.0
	## Regions: a very slow noise (one swell 500 to 900 m across, so a 512 m map holds one or
	## two) says where the lowlands and the highlands are, and the surface changes with it:
	## the amplitude falls to region_lowland of itself where the mask is lowest, the highlands
	## are mixed toward ridged noise by region_ridge and carry a finer detail noise at
	## region_detail of the amplitude (craggy where it is high, smooth where it is low), and
	## the warp grows with the mask. region_strength 0 is no regions: the same hills
	## everywhere. Rolled by roll_regions, or set by hand.
	var region_strength: float = 0.0
	var region_lowland: float = 0.2
	var region_ridge: float = 0.0
	var region_detail: float = 0.0
	## The height curve, applied to the unit height (0 the lowest the noise goes, 1 the
	## highest) before the amplitude: a hard floor the valleys fill up to, like sediment, so
	## the low ground is flat (curve_floor, 0 for none), and a cliff band that puts
	## curve_cliff of the height into a steep span curve_cliff_width wide about
	## curve_cliff_at, leaving flat spans below and above it (plains, a plateau and the
	## climb between; 0 for none). Rolled by roll_curve, or set by hand.
	var curve_floor: float = 0.0
	var curve_cliff: float = 0.0
	var curve_cliff_at: float = 0.5
	var curve_cliff_width: float = 0.15
	## Relief: 3D noise added to the density within relief_band metres of the surface on the
	## steep faces, so a cliff gets lips, undercuts and overhangs instead of the smooth slope
	## a height can only give. The noise is relief_amplitude metres at most, fades to nothing
	## at the band's edge and on gentle ground (surface_slope), so the ground is never
	## hollowed and nothing floats in the air. Rolled by roll_relief, or set by hand (0 none).
	var relief_amplitude: float = 0.0
	var relief_band: float = 0.0
	## Flat spots: landings the surface is blended toward a level within a radius, each
	## (x, z, inner radius, outer radius) in world metres, flat inside the inner radius and
	## fading to the natural ground at the outer one. Set by roll_flat_spots or by hand, then
	## prepare_flat_spots() reads the level each spot sits at.
	var flat_spots: Array[Vector4] = []
	## Carves tunnels, caverns and bedrock under a solid-filled open terrain (null: none).
	var caves: CaveCarver = null
	## Land biomes: the map is cut into patches land_patch_size metres across (BiomePatches)
	## and each draws its kind from land_weights, one weight per LandBiome in order, so the
	## weights are the biomes' likelihoods; the surface takes the biome's tint half-blended
	## over the shader's own lawn and rock. One weight alone is that biome everywhere; all
	## zero is meadow.
	var land_weights: PackedFloat32Array = [6.0, 2.0, 1.0, 1.0]
	var land_patch_size: float = 400.0:
		set(value):
			land_patch_size = maxf(value, 1.0)
			_land_warp = null
	## Solid ground a map builder adds on top of the shape: the soil in a garden's raised beds,
	## the footings under structures. Each is a stadium (a box with rounded ends) standing on
	## its centre, see stadium_sdf; "tint" is the vertex colour its surface carries (alpha 0:
	## the ground shader draws that colour instead of the map's own ground). It is natural
	## ground otherwise: dirt when dug, unless "ground" is true (a footing), when it digs as
	## the map's own ground, stone and veins and all.
	var solids: Array[Dictionary] = []:
		set(value):
			solids = value
			_region_solids = value
			_region_solid_count = value.size()
	var terrain_edits: TerrainEdits = null
	## Seeds which element each ore pocket is (with the vein and ore noises, the map's seed).
	var ore_seed: int = 0

	var _flat_spot_heights: PackedFloat32Array = PackedFloat32Array()
	var _flat_spot_count: int = 0
	var _region_noise: FastNoiseLite
	var _detail_noise: FastNoiseLite
	var _relief_noise: FastNoiseLite
	var _land_warp: FastNoiseLite
	var _land_seed: int = 0
	var _vein_noise: FastNoiseLite
	var _ore_noise: FastNoiseLite

	var _macro_noise: FastNoiseLite
	var _height_noise: FastNoiseLite
	var _terrace_noise: FastNoiseLite
	var _warp_noise_x: FastNoiseLite
	var _warp_noise_z: FastNoiseLite
	var _heightmap_image: Image
	var _noise: FastNoiseLite
	## The solids that can reach the region being sampled (see prepare_for_region), and how
	## many: a chunk field asks every sample, so the solids it cannot touch are dropped first.
	var _region_solids: Array[Dictionary] = []
	var _region_solid_count: int = 0

	## Signed distance to a solid: negative inside. The stadium stands on "center" (its
	## bottom), runs "half_length" along x (or z when "along_z") with ends of "radius", and is
	## "height" tall.
	static func stadium_sdf(world_pos: Vector3, solid: Dictionary) -> float:
		var local: Vector3 = world_pos - (solid["center"] as Vector3)
		var along: float = local.z if bool(solid["along_z"]) else local.x
		var across: float = local.x if bool(solid["along_z"]) else local.z
		var radius: float = float(solid["radius"])
		var straight: float = maxf(absf(along) - (float(solid["half_length"]) - radius), 0.0)
		var sideways: float = Vector2(straight, across).length() - radius
		var height: float = float(solid["height"])
		var vertical: float = absf(local.y - height * 0.5) - height * 0.5
		return maxf(sideways, vertical)

	## Keeps only the solids that can reach a region (a chunk's samples plus the halo the
	## normals read). Every sample of the region is then tested against those alone.
	## Whether a region whose lowest samples sit at bottom_y, over ground no higher than
	## highest_surface, holds nothing but air: the surface is below it, no placed solid was
	## prepared for the region, and no edit lies in it. The caves only take ground away, so
	## nothing else can put ground above the surface.
	func is_sky(highest_surface: float, bottom_y: float, region: AABB) -> bool:
		if not open_terrain_enabled or highest_surface >= bottom_y or _region_solid_count > 0:
			return false
		if terrain_edits != null and terrain_edits.get_override_count() > 0:
			return not terrain_edits.get_all_bounds().intersects(region)
		return true

	func prepare_for_region(region: AABB) -> void:
		_region_solids = []
		for solid: Dictionary in solids:
			if region.intersects(solid_bounds(solid)):
				_region_solids.append(solid)
		_region_solid_count = _region_solids.size()
		if caves != null and caves.systems != null:
			caves.systems.prepare_region(region)

	static func solid_bounds(solid: Dictionary) -> AABB:
		var center: Vector3 = solid["center"]
		var half_length: float = float(solid["half_length"])
		var radius: float = float(solid["radius"])
		var half: Vector3 = (
			Vector3(radius, 0.0, half_length)
			if bool(solid["along_z"])
			else Vector3(half_length, 0.0, radius)
		)
		return AABB(center - half, Vector3(half.x * 2.0, float(solid["height"]), half.z * 2.0))

	func _solids_sdf(world_pos: Vector3) -> float:
		var nearest: float = INF
		for solid: Dictionary in _region_solids:
			nearest = minf(nearest, stadium_sdf(world_pos, solid))
		return nearest

	## The solid a point lies in, or an empty dictionary. Among the prepared region's solids:
	## the mesher only asks about its chunk's own samples and the vertices between them.
	func solid_at(world_pos: Vector3) -> Dictionary:
		for solid: Dictionary in _region_solids:
			if stadium_sdf(world_pos, solid) <= 0.0:
				return solid
		return {}

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
		if _region_solid_count > 0:
			var solid: Dictionary = solid_at(world_position)
			if not solid.is_empty() and not bool(solid.get("ground", false)):
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

	## natural_material with the depth read from the map's surface instead of the density
	## value: what the mesher colours a dug face with and the pickaxe pays out. The density is
	## not a depth: under a solid fill it is the distance to the nearest air, a cave's wall as
	## much as the surface, and under a sponge it is the 3D noise; read as a depth it painted
	## the ground wrong.
	func ground_material(world_position: Vector3, density_value: float) -> TerrainMaterials.Kind:
		return natural_material(world_position, -depth_below_surface(world_position, density_value))

	## Metres below the map's surface at a point (negative above it): for an open terrain the
	## surface height over the point less the point's height; for a world with no surface of
	## its own the density, which is the shape there (negative inside).
	func depth_below_surface(world_position: Vector3, density_value: float) -> float:
		if open_terrain_enabled:
			var surface: float = _sample_open_terrain_height(world_position.x, world_position.z)
			return surface - world_position.y
		return -density_value

	## The vertex colour of natural ground here (alpha 1: the terrain shader draws its own
	## ground, tinted by it). Plain white unless the point lies in a placed solid, which
	## carries its own tint (alpha 0: a flat colour, the soil in a raised bed).
	func natural_tint(world_position: Vector3, density_value: float) -> Color:
		if _region_solid_count > 0:
			var solid: Dictionary = solid_at(world_position)
			if not solid.is_empty():
				return solid.get("tint", TerrainMaterials.NATURAL_VERTEX_COLOR) as Color
		# A wall well under the surface is a cave's, and takes its biome's tint; the ground on
		# top takes the land's.
		if open_terrain_enabled:
			var depth: float = depth_below_surface(world_position, density_value)
			if depth > 1.5:
				if caves != null:
					return CaveCarver.biome_tint(caves.biome(world_position, depth))
			else:
				return land_tint(land_biome(world_position.x, world_position.z))
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
		_land_seed = noise_seed + 1313
		_land_warp = null

	## The land biome of the patch at a column.
	func land_biome(world_x: float, world_z: float) -> LandBiome:
		if _land_warp == null:
			_land_warp = BiomePatches.make_warp(_land_seed, land_patch_size)
		var pick: int = BiomePatches.pick(
			world_x, world_z, _land_seed, land_patch_size, _land_warp, land_weights
		)
		return LandBiome.MEADOW if pick < 0 else pick as LandBiome

	## The vertex tint of the surface in a land biome: half-blended over the ground shader's
	## own lawn and rock (alpha 0.5), or the plain natural colour where the biome adds nothing.
	static func land_tint(kind: LandBiome) -> Color:
		match kind:
			LandBiome.DRYLAND:
				return Color(0.74, 0.64, 0.38, 0.5)
			LandBiome.MARSH:
				return Color(0.2, 0.38, 0.2, 0.5)
			LandBiome.BARRENS:
				return Color(0.52, 0.5, 0.46, 0.5)
		return TerrainMaterials.NATURAL_VERTEX_COLOR

	func land_summary() -> String:
		return "land %s" % BiomePatches.shares(LAND_BIOME_NAMES, land_weights)

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

	func _evaluate_boxed_in_terrain(world_pos: Vector3, with_edits: bool) -> float:
		var value: float = _sample_boxed_in_terrain_noise(world_pos)
		if boxed_in_edges_enabled:
			value = maxf(
				value,
				DensitySampler.boxed_in_terrain_box_sdf(
					world_pos, bounds_center, bounds_half, bounds_clip_inset
				)
			)
		if _region_solid_count > 0:
			value = minf(value, _solids_sdf(world_pos))
		if with_edits and terrain_edits != null:
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
		var height: float
		if _heightmap_image != null and not _heightmap_image.is_empty():
			height = (
				DensitySampler.sample_heightmap_image(
					_heightmap_image, world_x, world_z, bounds_center, bounds_half, noise_amplitude
				)
				+ surface_height_offset
			)
		elif not noise_enabled or _height_noise == null:
			height = bounds_center.y + surface_height_offset
		else:
			# The region mask, 0 in the lowlands and 1 in the highlands.
			var mask: float = 0.0
			if region_strength > 0.0 and _region_noise != null:
				mask = smoothstep(-0.45, 0.45, _region_noise.get_noise_2d(world_x, world_z))
			var sample_x: float = world_x
			var sample_z: float = world_z
			if surface_warp > 0.0 and _warp_noise_x != null:
				var warp: float = surface_warp
				if region_strength > 0.0:
					warp *= lerpf(1.0, lerpf(0.5, 1.5, mask), region_strength)
				sample_x += _warp_noise_x.get_noise_2d(world_x, world_z) * warp
				sample_z += _warp_noise_z.get_noise_2d(world_x, world_z) * warp
			var noise_value: float = _height_noise.get_noise_2d(sample_x, sample_z)
			var ridge: float = surface_ridge
			if region_ridge > 0.0:
				ridge = maxf(ridge, region_ridge * mask * region_strength)
			if ridge > 0.0:
				noise_value = lerpf(noise_value, 1.0 - 2.0 * absf(noise_value), ridge)
			if region_detail > 0.0 and mask > 0.0 and _detail_noise != null:
				noise_value += (
					_detail_noise.get_noise_2d(world_x, world_z)
					* region_detail
					* mask
					* region_strength
				)
			var unit: float = clampf((noise_value + 1.0) * 0.5, 0.0, 1.0)
			if not is_equal_approx(surface_power, 1.0):
				unit = pow(unit, surface_power)
			unit = curve_height(unit)
			var amplitude: float = noise_amplitude
			if region_strength > 0.0:
				amplitude *= lerpf(1.0, lerpf(region_lowland, 1.0, mask), region_strength)
			height = bounds_center.y + (unit * 2.0 - 1.0) * amplitude + surface_height_offset
		if terrace_enabled:
			height = terrace_height(height, world_x, world_z)
		if _flat_spot_count > 0:
			height = flat_spot_height(height, world_x, world_z)
		return height

	## The unit height (0 to 1) through the height curve: the valleys filled up to the floor
	## (a smooth maximum, so the ground stays continuous and never dips), then the cliff
	## band, a smoothstep across it mixed in by curve_cliff. Both keep the height rising
	## with its input, so a hill is still a hill, only reshaped.
	func curve_height(unit: float) -> float:
		if curve_floor > 0.0:
			var blend: float = clampf(
				0.5 + 0.5 * (unit - curve_floor) / CURVE_FLOOR_SOFTNESS, 0.0, 1.0
			)
			unit = (lerpf(curve_floor, unit, blend) + CURVE_FLOOR_SOFTNESS * blend * (1.0 - blend))
		if curve_cliff > 0.0:
			var steep: float = smoothstep(
				curve_cliff_at - curve_cliff_width, curve_cliff_at + curve_cliff_width, unit
			)
			unit = lerpf(unit, steep, curve_cliff)
		return unit

	## The surface's slope at a column, rise over run (0 flat, 1 a 45 degree face), from the
	## heights a metre along x and z when the column's own height is known.
	func surface_slope(world_x: float, world_z: float, height: float) -> float:
		var along_x: float = _sample_open_terrain_height(world_x + 1.0, world_z) - height
		var along_z: float = _sample_open_terrain_height(world_x, world_z + 1.0) - height
		return sqrt(along_x * along_x + along_z * along_z)

	## The height blended toward the level of every flat spot in reach: all the way inside the
	## inner radius (less FLAT_SPOT_BLEND, so a landing keeps a trace of the ground), fading
	## to the natural ground at the outer one.
	func flat_spot_height(height: float, world_x: float, world_z: float) -> float:
		for index: int in _flat_spot_count:
			var spot: Vector4 = flat_spots[index]
			var distance: float = Vector2(world_x - spot.x, world_z - spot.y).length()
			if distance >= spot.w:
				continue
			var weight: float = smoothstep(spot.w, spot.z, distance) * FLAT_SPOT_BLEND
			height = lerpf(height, _flat_spot_heights[index], weight)
		return height

	## Reads the level each flat spot sits at (the natural ground at its centre) and switches
	## the spots on. Call after flat_spots is set by hand; roll_flat_spots calls it.
	func prepare_flat_spots() -> void:
		_flat_spot_count = 0
		_flat_spot_heights.resize(flat_spots.size())
		for index: int in flat_spots.size():
			var spot: Vector4 = flat_spots[index]
			_flat_spot_heights[index] = _sample_open_terrain_height(spot.x, spot.y)
		_flat_spot_count = flat_spots.size()

	## The flat spots as points on the surface, for whatever wants level ground (nests).
	func flat_spot_points() -> Array[Vector3]:
		var points: Array[Vector3] = []
		for index: int in _flat_spot_count:
			var spot: Vector4 = flat_spots[index]
			points.append(Vector3(spot.x, _flat_spot_heights[index], spot.y))
		return points

	## The surface height stepped into shelves. The height is read as a position along the
	## treads (terrace_step metres each, from terrace_phase) and pushed toward the nearest
	## tread: terrace_strength 1 leaves a riser a few percent of the tread wide, 0 only an
	## S-curve across the whole tread, so the ground stays continuous whatever the strength.
	## The terrace noise then says how much of the shelf shows here: all of it where the noise
	## runs above the coverage's threshold, none below, blended across the band between.
	func terrace_height(height: float, world_x: float, world_z: float) -> float:
		if terrace_step <= 0.0:
			return height
		var level: float = (height - terrace_phase) / terrace_step
		var tread: float = floorf(level)
		var along: float = level - tread
		var riser: float = lerpf(0.5, 0.06, clampf(terrace_strength, 0.0, 1.0))
		var stepped: float = tread + smoothstep(0.5 - riser, 0.5 + riser, along)
		var shelved: float = terrace_phase + stepped * terrace_step
		var share: float = 1.0
		if _terrace_noise != null:
			# Noise runs in [-1, 1]: coverage 0 puts the threshold's whole band above it, 1 below.
			var threshold: float = lerpf(1.2, -1.2, clampf(terrace_coverage, 0.0, 1.0))
			share = smoothstep(
				threshold - 0.2, threshold + 0.2, _terrace_noise.get_noise_2d(world_x, world_z)
			)
		return lerpf(height, shelved, share)

	## Rolls the terraces a seed gives: whether there are any (at this chance, or always when
	## forced), the tread height and the strength from their ranges, the phase, and the slow
	## noise that says where they show, with this share of the ground terraced. Every number
	## is drawn whether or not the roll says yes, so forcing terraces on in the terrain lab
	## shows the very terraces the seed would have had.
	func roll_terraces(
		terrain_seed: int,
		chance: float,
		step_range: Vector2,
		strength_range: Vector2,
		coverage: float,
		force: bool = false
	) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector2i(terrain_seed, 3301))
		var rolled: float = rng.randf()
		terrace_step = rng.randf_range(
			minf(step_range.x, step_range.y), maxf(step_range.x, step_range.y)
		)
		terrace_strength = rng.randf_range(
			minf(strength_range.x, strength_range.y), maxf(strength_range.x, strength_range.y)
		)
		terrace_phase = rng.randf_range(0.0, terrace_step)
		terrace_coverage = coverage
		terrace_enabled = force or rolled < chance
		_terrace_noise = FastNoiseLite.new()
		_terrace_noise.seed = terrain_seed + 909
		_terrace_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_terrace_noise.frequency = 1.0 / 90.0
		_terrace_noise.fractal_type = FastNoiseLite.FRACTAL_NONE

	## Rolls the surface's character a seed gives: a redistribution power from its range, a
	## warp from its range on warp_chance of seeds (else none), a ridged mix from its range on
	## ridge_chance of them (else none). Every number is drawn whether or not its roll says
	## yes, so a chance of 1 in the lab shows the very trait the seed would have had.
	func roll_surface(
		terrain_seed: int,
		power_range: Vector2,
		warp_chance: float,
		warp_range: Vector2,
		ridge_chance: float,
		ridge_range: Vector2
	) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector2i(terrain_seed, 4409))
		surface_power = rng.randf_range(
			minf(power_range.x, power_range.y), maxf(power_range.x, power_range.y)
		)
		var warp_rolled: float = rng.randf()
		var warp: float = rng.randf_range(
			minf(warp_range.x, warp_range.y), maxf(warp_range.x, warp_range.y)
		)
		surface_warp = warp if warp_rolled < warp_chance else 0.0
		var ridge_rolled: float = rng.randf()
		var ridge: float = rng.randf_range(
			minf(ridge_range.x, ridge_range.y), maxf(ridge_range.x, ridge_range.y)
		)
		surface_ridge = ridge if ridge_rolled < ridge_chance else 0.0
		init_warp_noise(terrain_seed)

	## The slow noise pair the warp reads, at half the height noise's frequency (so a push
	## spans a hill or two): needed whenever surface_warp is set by hand.
	func init_warp_noise(terrain_seed: int) -> void:
		var frequency: float = 0.004
		if _height_noise != null:
			frequency = _height_noise.frequency * 0.5
		_warp_noise_x = FastNoiseLite.new()
		_warp_noise_x.seed = terrain_seed + 808
		_warp_noise_x.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_warp_noise_x.frequency = frequency
		_warp_noise_x.fractal_type = FastNoiseLite.FRACTAL_FBM
		_warp_noise_x.fractal_octaves = 2
		_warp_noise_z = FastNoiseLite.new()
		_warp_noise_z.seed = terrain_seed + 809
		_warp_noise_z.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_warp_noise_z.frequency = frequency
		_warp_noise_z.fractal_type = FastNoiseLite.FRACTAL_FBM
		_warp_noise_z.fractal_octaves = 2

	## "warp 23 m, ridges 0.35, power 1.6" (the traits present), or "plain surface".
	func surface_summary() -> String:
		var traits: PackedStringArray = PackedStringArray()
		if surface_warp > 0.0:
			traits.append("warp %d m" % roundi(surface_warp))
		if surface_ridge > 0.0:
			traits.append("ridges %.2f" % surface_ridge)
		if not is_equal_approx(surface_power, 1.0):
			traits.append("power %.1f" % surface_power)
		if traits.is_empty():
			return "plain surface"
		return ", ".join(traits)

	## "terraces every 3.2 m, strength 0.8, over 50% of the ground", or "no terraces".
	func terrace_summary() -> String:
		if not terrace_enabled:
			return "no terraces"
		return (
			"terraces every %.1f m, strength %.2f, over %d%% of the ground"
			% [terrace_step, terrace_strength, roundi(terrace_coverage * 100.0)]
		)

	## Rolls the regions a seed gives: on region_chance of seeds, a mask noise one swell of
	## size_range metres across, the lowlands' share of the amplitude, the highlands' ridged
	## mix and detail from their ranges; no regions otherwise. Every number is drawn whether
	## or not the roll says yes, so a chance of 1 in the lab shows the seed's own regions.
	func roll_regions(
		terrain_seed: int,
		chance: float,
		size_range: Vector2,
		lowland_range: Vector2,
		ridge_range: Vector2,
		detail_range: Vector2
	) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector2i(terrain_seed, 5501))
		var rolled: float = rng.randf()
		var size: float = maxf(_draw(rng, size_range), 1.0)
		region_lowland = clampf(_draw(rng, lowland_range), 0.0, 1.0)
		region_ridge = clampf(_draw(rng, ridge_range), 0.0, 1.0)
		region_detail = maxf(_draw(rng, detail_range), 0.0)
		region_strength = 1.0 if rolled < chance else 0.0
		init_region_noise(terrain_seed, 1.0 / size)

	## The slow mask noise and the highlands' detail noise (four times the height noise's
	## frequency, two octaves): needed whenever region_strength is set by hand.
	func init_region_noise(terrain_seed: int, mask_frequency: float = 1.0 / 700.0) -> void:
		_region_noise = FastNoiseLite.new()
		_region_noise.seed = terrain_seed + 1010
		_region_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_region_noise.frequency = mask_frequency
		_region_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
		_detail_noise = FastNoiseLite.new()
		_detail_noise.seed = terrain_seed + 1011
		_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_detail_noise.frequency = (
			_height_noise.frequency * 4.0 if _height_noise != null else 0.032
		)
		_detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_detail_noise.fractal_octaves = 2

	## The share of the map's ground the region mask calls highland (above a half), from a
	## coarse grid over the bounds; 0 without regions.
	func highland_share() -> float:
		if region_strength <= 0.0 or _region_noise == null:
			return 0.0
		var highland: int = 0
		var steps: int = 16
		for step_x: int in steps:
			for step_z: int in steps:
				var world_x: float = (
					bounds_center.x
					+ ((float(step_x) + 0.5) / float(steps) - 0.5) * 2.0 * bounds_half.x
				)
				var world_z: float = (
					bounds_center.z
					+ ((float(step_z) + 0.5) / float(steps) - 0.5) * 2.0 * bounds_half.z
				)
				if _region_noise.get_noise_2d(world_x, world_z) > 0.0:
					highland += 1
		return float(highland) / float(steps * steps)

	## "highland over 38% (lowlands at 0.2 of the height, ridges 0.6, detail 0.2)", or
	## "no regions".
	func region_summary() -> String:
		if region_strength <= 0.0:
			return "no regions"
		return (
			"highland over %d%% (lowlands at %.2f of the height, ridges %.2f, detail %.2f)"
			% [roundi(highland_share() * 100.0), region_lowland, region_ridge, region_detail]
		)

	## Rolls the height curve a seed gives: a floor from its range on floor_chance of seeds,
	## and on cliff_chance of them a cliff band of strength, level and width from theirs.
	## Every number is drawn whether or not its roll says yes.
	func roll_curve(
		terrain_seed: int,
		floor_chance: float,
		floor_range: Vector2,
		cliff_chance: float,
		cliff_range: Vector2,
		level_range: Vector2,
		width_range: Vector2
	) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector2i(terrain_seed, 5502))
		var floor_rolled: float = rng.randf()
		var floor_level: float = clampf(_draw(rng, floor_range), 0.0, 1.0)
		curve_floor = floor_level if floor_rolled < floor_chance else 0.0
		var cliff_rolled: float = rng.randf()
		var cliff: float = clampf(_draw(rng, cliff_range), 0.0, 1.0)
		curve_cliff_at = clampf(_draw(rng, level_range), 0.0, 1.0)
		curve_cliff_width = maxf(_draw(rng, width_range), 0.01)
		curve_cliff = cliff if cliff_rolled < cliff_chance else 0.0

	## "floor at 0.30, cliffs 0.6 at 0.50" (what is present), or "no height curve".
	func curve_summary() -> String:
		var parts: PackedStringArray = PackedStringArray()
		if curve_floor > 0.0:
			parts.append("floor at %.2f" % curve_floor)
		if curve_cliff > 0.0:
			parts.append("cliffs %.1f at %.2f" % [curve_cliff, curve_cliff_at])
		if parts.is_empty():
			return "no height curve"
		return ", ".join(parts)

	## Rolls the relief a seed gives: on this chance of seeds, an amplitude from its range;
	## none otherwise. The number is drawn whether or not the roll says yes.
	func roll_relief(terrain_seed: int, chance: float, amplitude_range: Vector2) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector2i(terrain_seed, 5504))
		var rolled: float = rng.randf()
		var amplitude: float = maxf(_draw(rng, amplitude_range), 0.0)
		set_relief(amplitude if rolled < chance else 0.0, terrain_seed)

	## Relief of this amplitude (0 none) with its 3D noise, a lump every six metres or so.
	func set_relief(amplitude: float, terrain_seed: int) -> void:
		relief_amplitude = amplitude
		relief_band = amplitude * 2.0
		if amplitude <= 0.0:
			_relief_noise = null
			return
		_relief_noise = FastNoiseLite.new()
		_relief_noise.seed = terrain_seed + 1212
		_relief_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_relief_noise.frequency = 1.0 / 6.0
		_relief_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_relief_noise.fractal_octaves = 2

	## Metres above the surface the relief can put solid ground (0 without relief): a sky
	## chunk must clear it.
	func relief_reach() -> float:
		return relief_band if relief_amplitude > 0.0 else 0.0

	## "relief 2.4 m" or "no relief".
	func relief_summary() -> String:
		if relief_amplitude <= 0.0:
			return "no relief"
		return "relief %.1f m" % relief_amplitude

	## Rolls the flat spots a seed gives: a count from its range, each an inner radius from
	## its range (the outer one FLAT_SPOT_FADE further out), placed inside the bounds with
	## the fade kept off the edge and spots kept apart (a few tries each).
	func roll_flat_spots(terrain_seed: int, count_range: Vector2i, radius_range: Vector2) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector2i(terrain_seed, 5505))
		var count: int = rng.randi_range(
			mini(count_range.x, count_range.y), maxi(count_range.x, count_range.y)
		)
		flat_spots = []
		for _index: int in maxi(count, 0):
			var inner: float = maxf(_draw(rng, radius_range), 1.0)
			var outer: float = inner + FLAT_SPOT_FADE
			var reach_x: float = maxf(bounds_half.x - outer, 0.0)
			var reach_z: float = maxf(bounds_half.z - outer, 0.0)
			var spot := Vector4(bounds_center.x, bounds_center.z, inner, outer)
			for _attempt: int in 8:
				spot.x = bounds_center.x + rng.randf_range(-reach_x, reach_x)
				spot.y = bounds_center.z + rng.randf_range(-reach_z, reach_z)
				var apart: bool = true
				for other: Vector4 in flat_spots:
					if Vector2(spot.x - other.x, spot.y - other.y).length() < outer + other.w:
						apart = false
						break
				if apart:
					break
			flat_spots.append(spot)
		prepare_flat_spots()

	## "3 flat spots" or "no flat spots".
	func flat_spot_summary() -> String:
		if _flat_spot_count == 0:
			return "no flat spots"
		if _flat_spot_count == 1:
			return "1 flat spot"
		return "%d flat spots" % _flat_spot_count

	static func _draw(rng: RandomNumberGenerator, value_range: Vector2) -> float:
		return rng.randf_range(
			minf(value_range.x, value_range.y), maxf(value_range.x, value_range.y)
		)

	func sample_open_terrain_height(world_x: float, world_z: float) -> float:
		return _sample_open_terrain_height(world_x, world_z)

	func _evaluate_open_terrain(world_pos: Vector3, with_edits: bool) -> float:
		var surface_height: float = _sample_open_terrain_height(world_pos.x, world_pos.z)
		return evaluate_open_terrain_with_surface(world_pos, surface_height, with_edits)

	## Open-terrain density when the column's surface height is already known (field builds
	## sample one height per XZ column instead of per voxel).
	func evaluate_open_terrain_with_surface(
		world_pos: Vector3, surface_height: float, with_edits: bool = true, slope: float = -1.0
	) -> float:
		var above_surface: float = world_pos.y - surface_height
		var value: float
		if open_terrain_solid_fill:
			value = above_surface
			if relief_amplitude > 0.0 and absf(above_surface) < relief_band:
				# The relief: the surface's slope says how much shows (steep faces only), the
				# distance from the surface fades it out, and the 3D noise pushes the face in
				# and out by what is left. slope is the column's when the caller knows it.
				if slope < 0.0:
					slope = surface_slope(world_pos.x, world_pos.z, surface_height)
				var steep: float = smoothstep(RELIEF_SLOPE_START, RELIEF_SLOPE_END, slope)
				if steep > 0.0:
					value += (
						_relief_noise.get_noise_3dv(world_pos)
						* relief_amplitude
						* steep
						* (1.0 - absf(above_surface) / relief_band)
					)
			if caves != null:
				# The caves open on steep faces, so near the surface they want the slope.
				if slope < 0.0 and above_surface > -(caves.tunnel_depth + caves.fade):
					slope = surface_slope(world_pos.x, world_pos.z, surface_height)
				value = caves.carve(value, world_pos, surface_height, maxf(slope, 0.0))
		elif above_surface >= OPEN_TERRAIN_NOISE_SKIP_HEIGHT:
			# The scaled noise stays within the skip height, so the max() is exactly above_surface.
			value = above_surface
		else:
			# Same 3D noise field as boxed-in terrain, in metres. The air is the union of the
			# air above the surface and the noise's holes, so the density is the greater of the
			# two distances on both sides of the surface: above it the surface clips the noise,
			# below it a sample in solid noise reads how deep it lies, and the mesher puts the
			# surface where the height says. Taking the noise alone below the surface changed no
			# shape (the zero crossings are the same) but left the hills stair-stepped.
			value = maxf(
				_sample_boxed_in_terrain_noise(world_pos) * SPONGE_NOISE_METRES, above_surface
			)
		if open_terrain_edges_enabled:
			value = maxf(
				value,
				DensitySampler.open_terrain_box_sdf(
					world_pos, bounds_center, bounds_half, bounds_clip_inset
				)
			)
		if _region_solid_count > 0:
			value = minf(value, _solids_sdf(world_pos))
		if with_edits and terrain_edits != null:
			value = terrain_edits.apply_to_density(value, world_pos)
		return value

	## The density here: the map's own shape with the edits (digging, building) on top. With
	## with_edits false, the density the map was generated with: about zero on the original
	## surface, negative inside the original ground. The mesher reads that at a dug face to
	## tell how deep into the ground the digging reached (topsoil, stone or a vein).
	func evaluate(world_pos: Vector3, with_edits: bool = true) -> float:
		if open_terrain_enabled:
			return _evaluate_open_terrain(world_pos, with_edits)
		if boxed_in_terrain_enabled:
			return _evaluate_boxed_in_terrain(world_pos, with_edits)
		# No shape of its own: solid where the 3D noise runs high, with the edits on top.
		var value := 1.0
		if noise_enabled:
			value -= (
				DensitySampler.fbm_noise_3d(
					_noise, world_pos, noise_octaves, noise_lacunarity, noise_gain
				)
				* noise_amplitude
			)
		if _region_solid_count > 0:
			value = minf(value, _solids_sdf(world_pos))
		if with_edits and terrain_edits != null:
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
