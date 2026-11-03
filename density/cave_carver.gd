class_name CaveCarver
extends RefCounted
## The underground of a fixed map, drawn from its seed: worm tunnels where two 3D noises both
## run near zero, rounded caverns deeper down where a slower noise runs high, a few sinkholes
## that open tunnels to the sky, and bedrock a couple of metres above the bottom of the chunk
## grid so nothing digs out of the world. The surface is the map's own (a garden's heightmap, a
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
## How much wider (as a share of the band) tunnels and caverns get per metre of depth.
const WIDEN_PER_METRE: float = 0.006

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
## World Y below which everything is solid.
var floor_y: float = -INF

var _tunnel_noise: FastNoiseLite
var _tunnel_noise_b: FastNoiseLite
var _cavern_noise: FastNoiseLite
var _sinkhole_noise: FastNoiseLite


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
	carver._tunnel_noise = _noise(value + 404, carver.tunnel_frequency, 2)
	carver._tunnel_noise_b = _noise(value + 405, carver.tunnel_frequency, 2)
	carver._cavern_noise = _noise(value + 606, carver.cavern_frequency, 1)
	carver._sinkhole_noise = _noise(value + 505, 1.0 / 70.0, 1)
	return carver


## The carver for a terrain's settings: bedrock FLOOR_MARGIN above the bottom of the grid.
static func for_settings(settings: ChunkedTerrainWorld.SettingsSnapshot) -> CaveCarver:
	return from_seed(
		settings.noise_seed,
		(
			settings.world_origin.y
			- float(settings.chunks_y) * settings.chunk_world_size * 0.5
			+ FLOOR_MARGIN
		)
	)


## Solid ground's density (metres below the surface, negative) with the caves carved out of it
## and bedrock under it: the value a solid-filled open terrain has before its edges and edits.
func carve(value: float, world_pos: Vector3, surface_height: float) -> float:
	var depth: float = surface_height - world_pos.y
	if depth > 0.5 and world_pos.y > floor_y + FLOOR_CLEARANCE:
		value = maxf(value, air(world_pos, depth))
	return minf(value, world_pos.y - floor_y)


## Metres of air the caves put at a point (negative outside any): the deeper of the tunnel's
## and the cavern's reach. A tunnel runs where both tunnel noises sit inside the band around
## zero (two bands cross in worms, one alone would be sheets); a cavern where the cavern noise
## runs above its cutoff. Each narrows to nothing above its start depth, and a sinkhole lets a
## tunnel reach the sky.
func air(world_pos: Vector3, depth: float) -> float:
	var widen: float = 1.0 + depth * WIDEN_PER_METRE
	var opening: float = smoothstep(
		sinkhole_threshold - 0.1,
		sinkhole_threshold + 0.1,
		_sinkhole_noise.get_noise_2d(world_pos.x, world_pos.z)
	)
	var tunnel_mask: float = maxf(
		smoothstep(tunnel_depth - FADE, tunnel_depth + FADE, depth), opening
	)
	var best: float = -1.0
	if tunnel_mask > 0.0:
		var tunnel: float = (
			tunnel_threshold * widen * tunnel_mask
			- maxf(
				absf(_tunnel_noise.get_noise_3dv(world_pos)),
				absf(_tunnel_noise_b.get_noise_3dv(world_pos))
			)
		)
		if tunnel > 0.0:
			best = tunnel / (2.0 * tunnel_frequency)
	var cavern_mask: float = smoothstep(cavern_depth - FADE, cavern_depth + FADE, depth)
	if cavern_mask > 0.0:
		var cutoff: float = lerpf(1.0, cavern_cutoff / widen, cavern_mask)
		var cavern: float = _cavern_noise.get_noise_3dv(world_pos) - cutoff
		if cavern > 0.0:
			best = maxf(best, cavern / (2.0 * cavern_frequency))
	return best


## True where a point lies inside a cave (air carved from solid ground).
func is_cave(world_pos: Vector3, surface_height: float) -> bool:
	var depth: float = surface_height - world_pos.y
	return depth > 0.5 and world_pos.y > floor_y + FLOOR_CLEARANCE and air(world_pos, depth) > 0.0


func summary() -> String:
	return (
		"tunnels %.2f from %d m down, caverns %.2f from %d m down, bedrock at %d m"
		% [
			tunnel_threshold,
			roundi(tunnel_depth),
			cavern_cutoff,
			roundi(cavern_depth),
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
