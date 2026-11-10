class_name CaveCarver
extends RefCounted
## The underground of a fixed map, drawn from its seed: worm tunnels where two 3D noises both
## run near zero, rounded caverns deeper down where a slower noise runs high, a few sinkholes
## that open tunnels to the sky, on half the seeds ravines cut down into the surface from the
## sky, and bedrock a couple of metres above the bottom of the chunk grid so nothing digs out
## of the world. Every noise is read at a point pushed by a slow warp, so the tunnels bend
## and the ravines wander (the ropey look of GPU Gems 3's terrains) instead of following
## the noise's own lines. The surface is the map's own (a garden's heightmap, a
## crawlspace's dirt); this only carves what lies under it, so every seed gives a known map a
## new underworld, the way Terraria's worlds share a shape and differ below.
##
## Noise alone is the same everywhere, an even sponge of identical holes, so over it the seed
## lays structure. Regions: a very slow noise says where the rock is riddled and where it is
## nearly solid. Depth bands, Terraria's layers: burrow ground, then tunnels, then caverns,
## then a deep band of bigger rooms, with seams of near-solid rock between them that undulate
## like beds. A thickness noise swells the tunnels into chambers and pinches them to crawls
## (Minecraft's spaghetti thickness). The caverns are wider than they are tall and, on most
## seeds, cut by bedding floors. Halls: one or two chambers a world in the deep band, far
## bigger than any cavern. Shafts: a few vertical pits, picked by a map, that cross the seams
## and tie the bands together.
##
## Depth is metres below the surface of the column. Tunnels start at tunnel_depth, caverns at
## cavern_depth, and both widen with depth: the ground near the surface is for burrows, the
## middle is tunnels, the bottom is rooms. Measured on the noises used here, a band of 0.16
## shared by two noises is about 13% of the ground, a cutoff of 0.5 about 12%.

## Tunnels and caverns narrow to nothing over this many metres above their start depth.
const FADE: float = 3.0
## Metres over which the deep band takes over from the cavern band.
const BAND_FADE: float = 10.0
## Metres of bedrock above the bottom of the chunk grid.
const FLOOR_MARGIN: float = 2.5
## Nothing is carved this close above bedrock (a floor to stand on in the lowest rooms).
const FLOOR_CLEARANCE: float = 1.5
## How much wider (as a share of the band) tunnels and caverns get per metre of depth, and
## the most they widen: reached 50 m down, where the maps' lowest layer already is, so a deep
## world's lower layers are that dense and no denser (unchecked, 350 m down the tunnel band was
## three times its width and the cavern cutoff near zero).
const WIDEN_PER_METRE: float = 0.006
const WIDEN_MAX: float = 1.3
## The share of seeds that cut ravines, and the share whose caverns have bedding floors.
const RAVINE_CHANCE: float = 0.5
## Metres over which one feature's air blends into another's where they meet, so a tunnel
## running into a room or through a floor joins it in a rounded mouth instead of leaving
## a sliver of wall thinner than a voxel between them (the floating pieces those make).
const BLEND: float = 2.0
const FLOOR_CHANCE: float = 0.6
## The region mask goes from lean to rich over this span of the region noise, about its bias.
const REGION_EDGE: float = 0.3

var world_seed: int = 0
## Tunnel noise frequency (1 / metres between tunnels) and the half-width of the band around
## zero that both tunnel noises must be inside, in noise units; the depth tunnels start at.
var tunnel_frequency: float = 0.035
var tunnel_threshold: float = 0.17
var tunnel_depth: float = 6.0
## Caverns: a slower noise, air wherever it runs above the cutoff (rounded rooms); deeper.
## Read with its height squeezed by cavern_squash, so the rooms are wider than they are tall.
var cavern_frequency: float = 0.016
var cavern_cutoff: float = 0.5
var cavern_depth: float = 22.0
var cavern_squash: float = 1.6
## How much of the surface opens into sinkholes (the sinkhole noise above this is open).
var sinkhole_threshold: float = 0.42
## Ravines: open gorges along the zero lines of a slow noise, air where the noise sits inside
## a band around zero (ravine_width, in noise units, 0.05 to 0.08 opening a tenth to a sixth of
## the surface; 0 is no ravines) that narrows to nothing
## ravine_depth metres below the surface, a rounded floor. The noise is read in 3D with its
## height squeezed by ravine_lean, so the walls lean and wander with depth into overhangs,
## and now and then a bridge: the look the 3D-noise sponge had where it cut the surface.
var ravine_frequency: float = 0.015
var ravine_width: float = 0.0
var ravine_depth: float = 12.0
var ravine_lean: float = 0.4
## Warp: metres a slow noise pushes every cave read sideways, and that noise's frequency
## (one bend per 100 to 200 m). 0 m reads the noises where they lie.
var warp_metres: float = 0.0
var warp_frequency: float = 0.007
## Regions: a 3D noise region_size metres across scales the tunnel band and the cavern
## cutoff between region_lean (where it runs low; 0 is solid rock) and region_rich (where
## it runs high; above 1 is riddled). region_bias shifts the noise before the mask, so a
## seed with a low bias is mostly rich and one with a high bias mostly solid.
var region_size: float = 250.0
var region_lean: float = 1.0
var region_rich: float = 1.0
var region_bias: float = 0.0
## Thickness: a 3D noise thickness_size metres across multiplies the tunnel band along its
## length, from thickness_thin (a crawl) to thickness_thick (a chamber).
var thickness_size: float = 60.0
var thickness_thin: float = 1.0
var thickness_thick: float = 1.0
## The deep band: below deep_depth the tunnel band shrinks to deep_tunnels of itself and the
## rooms grow (the cavern cutoff divided by deep_rooms). Seams of near-solid rock seam_width
## metres each side of cavern_depth and deep_depth, seam_strength of the way to solid (1 is
## solid rock there; 0 is no seams). The band edges and the floors are bent by a slow noise
## of band_wave metres, so they undulate like beds instead of running dead level.
var deep_depth: float = 180.0
var deep_tunnels: float = 1.0
var deep_rooms: float = 1.0
var seam_width: float = 6.0
var seam_strength: float = 0.0
var band_wave: float = 0.0
## Bedding floors: slabs of rock floor_thickness metres thick every floor_spacing metres of
## depth, cutting the caverns (not the tunnels, halls or shafts) so the rooms have floors to
## stand on and ceilings over them. 0 thickness is no floors.
var floor_spacing: float = 32.0
var floor_thickness: float = 0.0
## Halls: a very slow noise hall_size metres across, air above hall_cutoff in the deep band
## only, so a world holds a chamber or two far bigger than any cavern (2 is no halls).
var hall_size: float = 150.0
var hall_cutoff: float = 2.0
## Shafts: vertical pits where two more noises, read with their height squeezed by
## shaft_lean, both run inside shaft_width of zero, within the spots a 2D map opens (the
## map's noise above shaft_share; 0 width is no shafts). They start at tunnel_depth, ignore
## the regions and seams, and run to bedrock.
var shaft_frequency: float = 0.012
var shaft_width: float = 0.0
var shaft_lean: float = 0.12
var shaft_share: float = 0.45
## World Y below which everything is solid.
var floor_y: float = -INF

var _tunnel_noise: FastNoiseLite
var _tunnel_noise_b: FastNoiseLite
var _cavern_noise: FastNoiseLite
var _sinkhole_noise: FastNoiseLite
var _ravine_noise: FastNoiseLite
var _warp_noise: FastNoiseLite
var _region_noise: FastNoiseLite
var _thickness_noise: FastNoiseLite
var _wave_noise: FastNoiseLite
var _hall_noise: FastNoiseLite
var _shaft_noise: FastNoiseLite
var _shaft_noise_b: FastNoiseLite
var _shaft_map: FastNoiseLite


## The underworld one seed draws, with bedrock at floor_y.
static func from_seed(value: int, bedrock_y: float) -> CaveCarver:
	var carver := CaveCarver.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(value, 7919))
	carver.world_seed = value
	carver.floor_y = bedrock_y
	carver.tunnel_frequency = rng.randf_range(0.022, 0.05)
	carver.tunnel_threshold = rng.randf_range(0.12, 0.22)
	carver.tunnel_depth = rng.randf_range(4.0, 8.0)
	carver.cavern_frequency = rng.randf_range(0.009, 0.022)
	carver.cavern_cutoff = rng.randf_range(0.38, 0.6)
	carver.cavern_depth = rng.randf_range(16.0, 26.0)
	carver.sinkhole_threshold = rng.randf_range(0.36, 0.5)
	carver.warp_metres = rng.randf_range(4.0, 10.0)
	carver.warp_frequency = rng.randf_range(0.005, 0.01)
	if rng.randf() < RAVINE_CHANCE:
		carver.ravine_width = rng.randf_range(0.05, 0.08)
		carver.ravine_frequency = rng.randf_range(0.01, 0.02)
		carver.ravine_depth = rng.randf_range(8.0, 18.0)
		carver.ravine_lean = rng.randf_range(0.25, 0.6)
	carver.cavern_squash = rng.randf_range(1.2, 2.2)
	carver.region_size = rng.randf_range(150.0, 400.0)
	# Lean rock is solid on half the seeds and sparse on the rest: between the two the
	# tunnels would be hair-thin worms, dust at any voxel size.
	carver.region_lean = rng.randf_range(0.5, 0.8) if rng.randf() < 0.5 else 0.0
	carver.region_rich = rng.randf_range(1.0, 1.25)
	carver.region_bias = rng.randf_range(-0.2, 0.2)
	carver.thickness_size = rng.randf_range(40.0, 80.0)
	carver.thickness_thin = rng.randf_range(0.5, 0.7)
	carver.thickness_thick = rng.randf_range(1.2, 1.5)
	carver.deep_depth = rng.randf_range(120.0, 260.0)
	carver.deep_tunnels = rng.randf_range(0.3, 0.7)
	carver.deep_rooms = rng.randf_range(1.2, 1.6)
	carver.seam_width = rng.randf_range(3.0, 8.0)
	carver.seam_strength = rng.randf_range(0.5, 1.0)
	carver.band_wave = rng.randf_range(5.0, 20.0)
	if rng.randf() < FLOOR_CHANCE:
		carver.floor_spacing = rng.randf_range(24.0, 48.0)
		carver.floor_thickness = rng.randf_range(2.0, 4.0)
	carver.hall_size = rng.randf_range(120.0, 200.0)
	carver.hall_cutoff = rng.randf_range(0.55, 0.7)
	carver.shaft_frequency = rng.randf_range(0.009, 0.015)
	carver.shaft_width = rng.randf_range(0.12, 0.2)
	carver.shaft_lean = rng.randf_range(0.08, 0.2)
	carver.shaft_share = rng.randf_range(0.35, 0.55)
	carver._make_noises()
	return carver


## The carver for a terrain's settings: bedrock FLOOR_MARGIN above the bottom of the grid,
## and the Cave Roll sliders' values over the roll when the terrain fixes them.
static func for_settings(settings: ChunkedTerrainWorld.SettingsSnapshot) -> CaveCarver:
	var carver: CaveCarver = from_seed(
		settings.noise_seed,
		bedrock_y(settings.world_origin.y, settings.chunks_y, settings.chunk_world_size)
	)
	if settings.open_terrain_cave_roll == OpenTerrain.CaveRoll.FIXED:
		carver.apply(settings.open_terrain_cave_values)
	return carver


## Sets these fields (by name) over the roll and remakes the noises, so a changed
## frequency or size takes. The noises still come from the seed, so the same seed with
## the same values carves the same caves.
func apply(values: Dictionary) -> void:
	for field: String in values:
		set(field, values[field])
	_make_noises()


## World Y of bedrock for a grid this many chunks tall about this origin: FLOOR_MARGIN above
## its bottom. A terrain's footings stand on it too (ChunkedTerrainWorld.get_bedrock_y).
static func bedrock_y(origin_y: float, chunks_y: int, chunk_world_size: float) -> float:
	return origin_y - float(chunks_y) * chunk_world_size * 0.5 + FLOOR_MARGIN


## Solid ground's density (metres below the surface, negative) with the caves carved out of it
## and bedrock under it: the value a solid-filled open terrain has before its edges and edits.
## The caves' air is a distance too (metres, negative outside a cave), so the ground stays a
## distance everywhere: the mesher places a surface vertex by interpolating between two
## samples, which is only right when both sides are metres. Held at a constant inside, the
## ground pulled every slope vertex toward its grid column and the hills came out terraced.
## Carved right up to the surface, so a sinkhole or ravine opens to the sky with no skin.
func carve(value: float, world_pos: Vector3, surface_height: float) -> float:
	var depth: float = surface_height - world_pos.y
	if depth > 0.0 and world_pos.y > floor_y + FLOOR_CLEARANCE:
		value = maxf(value, air(world_pos, depth))
	return minf(value, world_pos.y - floor_y)


## Metres of air the caves put at a point: positive inside a cave, negative metres to the
## nearest one outside it, and -INF where no cave can reach yet (above the tunnels' start
## with no sinkhole over it). The deepest of the tunnel's, the cavern's, the hall's, the
## shaft's and the ravine's reach. A tunnel runs where both tunnel noises sit inside the band
## around zero (two bands cross in worms, one alone would be sheets); a cavern where the
## cavern noise runs above its cutoff. Each narrows to nothing above its start depth, and a
## sinkhole lets a tunnel reach the sky. A ravine is the other way up: widest at the surface,
## pinching out at its depth.
func air(world_pos: Vector3, depth: float) -> float:
	var widen: float = minf(1.0 + depth * WIDEN_PER_METRE, WIDEN_MAX)
	# Where the 3D noises are read: pushed sideways by the warp (two reads of one slow
	# noise, offset for the second axis). The sinkhole read stays put, it is a map, not
	# a shape.
	var read_pos: Vector3 = world_pos
	if warp_metres > 0.0 and _warp_noise != null:
		read_pos.x += _warp_noise.get_noise_3dv(world_pos) * warp_metres
		read_pos.z += (
			_warp_noise.get_noise_3d(world_pos.x + 97.0, world_pos.y + 41.0, world_pos.z + 31.0)
			* warp_metres
		)
	# The depth the bands and floors go by, bent so their edges undulate like beds.
	var bed: float = depth
	if band_wave > 0.0 and _wave_noise != null:
		bed += _wave_noise.get_noise_2d(world_pos.x, world_pos.z) * band_wave
	var deep: float = smoothstep(deep_depth - BAND_FADE, deep_depth + BAND_FADE, bed)
	var richness: float = region_richness(world_pos) * seam(bed)
	var opening: float = smoothstep(
		sinkhole_threshold - 0.1,
		sinkhole_threshold + 0.1,
		_sinkhole_noise.get_noise_2d(world_pos.x, world_pos.z)
	)
	var tunnel_mask: float = (
		maxf(smoothstep(tunnel_depth - FADE, tunnel_depth + FADE, depth), opening)
		* richness
		* lerpf(1.0, deep_tunnels, deep)
	)
	var best: float = -INF
	if tunnel_mask > 0.0:
		var tunnel: float = (
			tunnel_threshold * widen * tunnel_mask * thickness(read_pos)
			- maxf(
				absf(_tunnel_noise.get_noise_3dv(read_pos)),
				absf(_tunnel_noise_b.get_noise_3dv(read_pos))
			)
		)
		best = tunnel / (2.0 * tunnel_frequency)
	var cavern_mask: float = smoothstep(cavern_depth - FADE, cavern_depth + FADE, bed) * richness
	if cavern_mask > 0.0:
		var grow: float = widen * lerpf(1.0, deep_rooms, deep)
		var cutoff: float = lerpf(1.0, cavern_cutoff / grow, cavern_mask)
		var cavern: float = (
			_cavern_noise.get_noise_3d(read_pos.x, read_pos.y * cavern_squash, read_pos.z) - cutoff
		)
		best = _blend(best, minf(cavern / (2.0 * cavern_frequency), floor_slab(bed)))
	if hall_cutoff < 1.0 and deep > 0.0:
		var hall_edge: float = lerpf(1.0, hall_cutoff, deep)
		var hall: float = (
			_hall_noise.get_noise_3d(read_pos.x, read_pos.y * cavern_squash, read_pos.z) - hall_edge
		)
		best = _blend(best, hall * hall_size / 2.0)
	if shaft_width > 0.0:
		var shaft_mask: float = (
			smoothstep(tunnel_depth - FADE, tunnel_depth + FADE, depth)
			* smoothstep(
				shaft_share - 0.1,
				shaft_share + 0.1,
				_shaft_map.get_noise_2d(world_pos.x, world_pos.z)
			)
		)
		if shaft_mask > 0.0:
			var lean_y: float = read_pos.y * shaft_lean
			var shaft: float = (
				shaft_width * shaft_mask
				- maxf(
					absf(_shaft_noise.get_noise_3d(read_pos.x, lean_y, read_pos.z)),
					absf(_shaft_noise_b.get_noise_3d(read_pos.x, lean_y, read_pos.z))
				)
			)
			best = _blend(best, shaft / (2.0 * shaft_frequency))
	if ravine_width > 0.0 and depth < ravine_depth:
		var pinch: float = sqrt(1.0 - maxf(depth, 0.0) / ravine_depth)
		var gash: float = (
			ravine_width * pinch
			- absf(_ravine_noise.get_noise_3d(read_pos.x, read_pos.y * ravine_lean, read_pos.z))
		)
		best = _blend(best, gash / (2.0 * ravine_frequency))
	return best


## How riddled the rock is here: region_lean where the region noise runs low, region_rich
## where it runs high, the tunnel band and the cavern cutoff scaled by it.
func region_richness(world_pos: Vector3) -> float:
	if _region_noise == null or is_equal_approx(region_lean, region_rich):
		return region_rich
	var mask: float = smoothstep(
		-REGION_EDGE, REGION_EDGE, _region_noise.get_noise_3dv(world_pos) - region_bias
	)
	return lerpf(region_lean, region_rich, mask)


## How much of the way to solid rock the seams go at this (bent) depth: 1 clear of them,
## 1 - seam_strength at the middle of a seam.
func seam(bed: float) -> float:
	if seam_strength <= 0.0:
		return 1.0
	var nearest: float = minf(absf(bed - cavern_depth), absf(bed - deep_depth))
	return 1.0 - seam_strength * (1.0 - smoothstep(0.0, seam_width, nearest))


## The tunnel band's multiplier here: thin to thick along the tunnel's length.
func thickness(read_pos: Vector3) -> float:
	if _thickness_noise == null or is_equal_approx(thickness_thin, thickness_thick):
		return thickness_thick
	return lerpf(
		thickness_thin, thickness_thick, 0.5 + 0.5 * _thickness_noise.get_noise_3dv(read_pos)
	)


## Metres to the nearest bedding floor at this (bent) depth: negative inside a slab, so a
## cavern's air capped by it stops at the floor; INF with no floors.
func floor_slab(bed: float) -> float:
	if floor_thickness <= 0.0:
		return INF
	var into: float = fposmod(bed, floor_spacing)
	if into < floor_thickness:
		return -minf(into, floor_thickness - into)
	return minf(into - floor_thickness, floor_spacing - into)


## True where a point lies inside a cave (air carved from solid ground).
func is_cave(world_pos: Vector3, surface_height: float) -> bool:
	var depth: float = surface_height - world_pos.y
	return depth > 0.0 and world_pos.y > floor_y + FLOOR_CLEARANCE and air(world_pos, depth) > 0.0


func summary() -> String:
	var ravines: String = "no ravines"
	if ravine_width > 0.0:
		ravines = "ravines %.2f to %d m down" % [ravine_width, roundi(ravine_depth)]
	var floors: String = "no floors"
	if floor_thickness > 0.0:
		floors = "floors every %d m" % roundi(floor_spacing)
	return (
		(
			"tunnels %.2f from %d m down, caverns %.2f from %d m down, deep from %d m, "
			+ "regions %d m (%.1f to %.1f), seams %d m, %s, halls %.2f, shafts %.2f, %s, "
			+ "warp %d m, bedrock at %d m"
		)
		% [
			tunnel_threshold,
			roundi(tunnel_depth),
			cavern_cutoff,
			roundi(cavern_depth),
			roundi(deep_depth),
			roundi(region_size),
			region_lean,
			region_rich,
			roundi(seam_width),
			floors,
			hall_cutoff,
			shaft_width,
			ravines,
			roundi(warp_metres),
			roundi(floor_y)
		]
	)


func _make_noises() -> void:
	_tunnel_noise = _noise(world_seed + 404, tunnel_frequency, 2)
	_tunnel_noise_b = _noise(world_seed + 405, tunnel_frequency, 2)
	_cavern_noise = _noise(world_seed + 606, cavern_frequency, 1)
	_sinkhole_noise = _noise(world_seed + 505, 1.0 / 70.0, 1)
	_ravine_noise = _noise(world_seed + 707, ravine_frequency, 2)
	_warp_noise = _noise(world_seed + 808, warp_frequency, 1)
	_region_noise = _noise(world_seed + 909, 1.0 / region_size, 1)
	_thickness_noise = _noise(world_seed + 910, 1.0 / thickness_size, 1)
	_wave_noise = _noise(world_seed + 911, 1.0 / 140.0, 1)
	_hall_noise = _noise(world_seed + 912, 1.0 / hall_size, 1)
	_shaft_noise = _noise(world_seed + 913, shaft_frequency, 1)
	_shaft_noise_b = _noise(world_seed + 914, shaft_frequency, 1)
	_shaft_map = _noise(world_seed + 915, 1.0 / 150.0, 1)


## The deeper of two features' air, blended over BLEND metres where they are within it of
## each other (a polynomial smooth maximum): the union's wall fillets instead of creasing.
static func _blend(a: float, b: float) -> float:
	var overlap: float = maxf(BLEND - absf(a - b), 0.0) / BLEND
	return maxf(a, b) + overlap * overlap * BLEND * 0.25


static func _noise(noise_seed: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = frequency
	if octaves > 1:
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = octaves
	else:
		noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	return noise
