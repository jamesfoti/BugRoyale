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
## Depth is metres below the surface of the column. Tunnels start at tunnel_depth, caverns at
## cavern_depth, and both widen with depth: the ground near the surface is for burrows, the
## middle is tunnels, the bottom is rooms. Measured on the noises used here, a band of 0.16
## shared by two noises is about 13% of the ground, a cutoff of 0.5 about 12%.

## Tunnels and caverns narrow to nothing over this many metres above their start depth.
const FADE: float = 3.0
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
## The share of seeds that cut ravines.
const RAVINE_CHANCE: float = 0.5

var world_seed: int = 0
## Tunnel noise frequency (1 / metres between tunnels) and the half-width of the band around
## zero that both tunnel noises must be inside, in noise units; the depth tunnels start at.
var tunnel_frequency: float = 0.035
var tunnel_threshold: float = 0.17
var tunnel_depth: float = 6.0
## Caverns: a slower noise, air wherever it runs above the cutoff (rounded rooms); deeper.
var cavern_frequency: float = 0.016
var cavern_cutoff: float = 0.5
var cavern_depth: float = 22.0
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
## World Y below which everything is solid.
var floor_y: float = -INF

var _tunnel_noise: FastNoiseLite
var _tunnel_noise_b: FastNoiseLite
var _cavern_noise: FastNoiseLite
var _sinkhole_noise: FastNoiseLite
var _ravine_noise: FastNoiseLite
var _warp_noise: FastNoiseLite


## The underworld one seed draws, with bedrock at floor_y.
static func from_seed(value: int, bedrock_y: float) -> CaveCarver:
	var carver := CaveCarver.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(value, 7919))
	carver.world_seed = value
	carver.floor_y = bedrock_y
	carver.tunnel_frequency = rng.randf_range(0.028, 0.045)
	carver.tunnel_threshold = rng.randf_range(0.14, 0.2)
	carver.tunnel_depth = rng.randf_range(4.0, 8.0)
	carver.cavern_frequency = rng.randf_range(0.012, 0.02)
	carver.cavern_cutoff = rng.randf_range(0.42, 0.55)
	carver.cavern_depth = rng.randf_range(16.0, 26.0)
	carver.sinkhole_threshold = rng.randf_range(0.36, 0.5)
	carver.warp_metres = rng.randf_range(4.0, 10.0)
	carver.warp_frequency = rng.randf_range(0.005, 0.01)
	if rng.randf() < RAVINE_CHANCE:
		carver.ravine_width = rng.randf_range(0.05, 0.08)
		carver.ravine_frequency = rng.randf_range(0.01, 0.02)
		carver.ravine_depth = rng.randf_range(8.0, 18.0)
		carver.ravine_lean = rng.randf_range(0.25, 0.6)
	carver._tunnel_noise = _noise(value + 404, carver.tunnel_frequency, 2)
	carver._tunnel_noise_b = _noise(value + 405, carver.tunnel_frequency, 2)
	carver._cavern_noise = _noise(value + 606, carver.cavern_frequency, 1)
	carver._sinkhole_noise = _noise(value + 505, 1.0 / 70.0, 1)
	carver._ravine_noise = _noise(value + 707, carver.ravine_frequency, 2)
	carver._warp_noise = _noise(value + 808, carver.warp_frequency, 1)
	return carver


## The carver for a terrain's settings: bedrock FLOOR_MARGIN above the bottom of the grid.
static func for_settings(settings: ChunkedTerrainWorld.SettingsSnapshot) -> CaveCarver:
	return from_seed(
		settings.noise_seed,
		bedrock_y(settings.world_origin.y, settings.chunks_y, settings.chunk_world_size)
	)


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
## with no sinkhole over it). The deeper of the tunnel's and the cavern's reach. A tunnel runs
## where both tunnel noises sit inside the band around zero (two bands cross in worms, one
## alone would be sheets); a cavern where the cavern noise runs above its cutoff. Each narrows
## to nothing above its start depth, and a sinkhole lets a tunnel reach the sky. A ravine is
## the other way up: widest at the surface, pinching out at its depth.
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
	var opening: float = smoothstep(
		sinkhole_threshold - 0.1,
		sinkhole_threshold + 0.1,
		_sinkhole_noise.get_noise_2d(world_pos.x, world_pos.z)
	)
	var tunnel_mask: float = maxf(
		smoothstep(tunnel_depth - FADE, tunnel_depth + FADE, depth), opening
	)
	var best: float = -INF
	if tunnel_mask > 0.0:
		var tunnel: float = (
			tunnel_threshold * widen * tunnel_mask
			- maxf(
				absf(_tunnel_noise.get_noise_3dv(read_pos)),
				absf(_tunnel_noise_b.get_noise_3dv(read_pos))
			)
		)
		best = tunnel / (2.0 * tunnel_frequency)
	var cavern_mask: float = smoothstep(cavern_depth - FADE, cavern_depth + FADE, depth)
	if cavern_mask > 0.0:
		var cutoff: float = lerpf(1.0, cavern_cutoff / widen, cavern_mask)
		var cavern: float = _cavern_noise.get_noise_3dv(read_pos) - cutoff
		best = maxf(best, cavern / (2.0 * cavern_frequency))
	if ravine_width > 0.0 and depth < ravine_depth:
		var pinch: float = sqrt(1.0 - maxf(depth, 0.0) / ravine_depth)
		var gash: float = (
			ravine_width * pinch
			- absf(_ravine_noise.get_noise_3d(read_pos.x, read_pos.y * ravine_lean, read_pos.z))
		)
		best = maxf(best, gash / (2.0 * ravine_frequency))
	return best


## True where a point lies inside a cave (air carved from solid ground).
func is_cave(world_pos: Vector3, surface_height: float) -> bool:
	var depth: float = surface_height - world_pos.y
	return depth > 0.0 and world_pos.y > floor_y + FLOOR_CLEARANCE and air(world_pos, depth) > 0.0


func summary() -> String:
	var ravines: String = "no ravines"
	if ravine_width > 0.0:
		ravines = "ravines %.2f to %d m down" % [ravine_width, roundi(ravine_depth)]
	return (
		"tunnels %.2f from %d m down, caverns %.2f from %d m down, %s, warp %d m, bedrock at %d m"
		% [
			tunnel_threshold,
			roundi(tunnel_depth),
			cavern_cutoff,
			roundi(cavern_depth),
			ravines,
			roundi(warp_metres),
			roundi(floor_y)
		]
	)


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
