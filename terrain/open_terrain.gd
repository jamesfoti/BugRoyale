@tool
class_name OpenTerrain
extends ChunkedTerrainWorld
## Boxed-in style 3D noise clipped by a heightmap surface (open top, side/bottom walls), or
## solid ground under the surface with a seeded underworld carved out of it (caves_enabled).
## The surface is layered from the seed: its noise may be rolled from ranges (Noise Roll),
## it takes a character (Character: warped, ridged, redistributed), regions of lowland and
## highland with a height curve of flat floors and cliff bands (Regions), relief on the
## steep faces and flat landings (Relief), and terraces (Terraces). Each group has a Plain
## or None to switch it off and a chance and ranges to roll from.

## Whether the surface is stepped into terraces: rolled from the seed at terrace_chance, or
## forced on (to see a seed's terraces in the lab) or off.
enum Terraces { SEEDED, ALWAYS, NEVER }
## Whether the surface's character (warp, ridges, redistribution) is rolled from the seed, or
## the surface is the plain height noise as the sliders set it.
enum Character { SEEDED, PLAIN }
## Whether the Noise sliders are used as set (Fixed) or a seed draws its own noise from the
## Noise Roll ranges (Seeded), so seeds differ in hill size, height and roughness.
enum NoiseRoll { FIXED, SEEDED }
## Whether the seed rolls regions (lowlands and highlands) and a height curve, or the
## surface is the same everywhere with the noise's own bell-shaped heights.
enum Regions { SEEDED, PLAIN }
## Whether the seed rolls relief (overhangs on the steep faces) and flat spots, or none.
enum Relief { SEEDED, NONE }

@export_group("Open Terrain Grid")
@export_range(1, 64, 1) var chunks_x: int = 5:
	set(value):
		chunks_x = maxi(value, 1)
		_request_rebuild()
@export_range(1, 32, 1) var chunks_y: int = 3:
	set(value):
		chunks_y = maxi(value, 1)
		_request_rebuild()
@export_range(1, 64, 1) var chunks_z: int = 5:
	set(value):
		chunks_z = maxi(value, 1)
		_request_rebuild()

@export_group("Heightmap")
## Optional grayscale heightmap texture. When unset, procedural 2D noise is used.
@export var heightmap: Texture2D:
	set(value):
		heightmap = value
		_heightmap_image_cache = null
		_request_rebuild()
## Which chunk layer from the top the surface sits in: 0 keeps it at the box's centre (the
## maps, half the box sky and half ground), 1 and above put it in the middle of that
## layer counted from the top, so the chunks below are all ground (a deep world). The hills
## need headroom: amplitude plus offset must stay under the layers above the surface, half
## a chunk for layer 1, a chunk and a half for layer 2.
@export_range(0, 32, 1) var surface_layer: int = 0:
	set(value):
		surface_layer = maxi(value, 0)
		_request_rebuild()
## Raises or lowers the ground surface in meters (relative to this node's Y).
@export_range(-8.0, 8.0, 0.5) var surface_height_offset: float = 0.0:
	set(value):
		surface_height_offset = value
		_request_rebuild()

@export_group("Terraces")
## Terraces: the surface stepped into shelves on some seeds, in some places (see
## DensitySampler.WorldDensity.terrace_height). Seeded rolls them from the seed at
## terrace_chance; Always and Never override the roll. The tread height and the strength (0 a
## soft benching, 1 flat treads and steep risers) are drawn from their ranges, and
## terrace_coverage is the share of the ground they appear on, a slow noise picking where.
@export var terraces: Terraces = Terraces.SEEDED:
	set(value):
		terraces = value
		_request_rebuild()
## The chance a seed is terraced at all, when Terraces is Seeded. 0 never, 1 always.
@export_range(0.0, 1.0, 0.05) var terrace_chance: float = 0.4:
	set(value):
		terrace_chance = value
		_request_rebuild()
## Tread height in metres, least and most.
@export var terrace_step: Vector2 = Vector2(1.5, 5.0):
	set(value):
		terrace_step = value
		_request_rebuild()
## Strength, least and most, 0 to 1.
@export var terrace_strength: Vector2 = Vector2(0.35, 1.0):
	set(value):
		terrace_strength = value
		_request_rebuild()
## The share of the ground the terraces appear on, 0 to 1; a slow noise picks where.
@export_range(0.0, 1.0, 0.05) var terrace_coverage: float = 0.5:
	set(value):
		terrace_coverage = value
		_request_rebuild()

# The surface's character, rolled from the seed (DensitySampler.WorldDensity.roll_surface),
# so seeds differ in kind and not only in where the hills are: a redistribution power, a
# domain warp on some seeds and a ridged mix on some. To force one trait in the lab, set
# its chance to 1 and narrow its range to one value.
@export_group("Character")
## Seeded rolls the surface's character from the seed: a redistribution power for every
## seed, a domain warp on some and a ridged mix on some. Plain is the bare noise.
@export var character: Character = Character.SEEDED:
	set(value):
		character = value
		_request_rebuild()
## Redistribution power, least and most, drawn for every seed. 1 leaves the noise alone.
## Above 1 the valleys flatten into plains and the hills grow fewer and taller; below 1
## the ground rises into plateaus with narrow valleys between.
@export var character_power: Vector2 = Vector2(0.7, 1.6):
	set(value):
		character_power = value
		_request_rebuild()
## The chance a seed is domain warped. 0 never, 1 always.
@export_range(0.0, 1.0, 0.05) var character_warp_chance: float = 0.5:
	set(value):
		character_warp_chance = value
		_request_rebuild()
## Domain warp in metres, least and most: how far a slower noise pushes each column before
## the height noise is read there, so round blobs stretch into curved ridges and bays.
@export var character_warp: Vector2 = Vector2(10.0, 40.0):
	set(value):
		character_warp = value
		_request_rebuild()
## The chance a seed is ridged. 0 never, 1 always.
@export_range(0.0, 1.0, 0.05) var character_ridge_chance: float = 0.35:
	set(value):
		character_ridge_chance = value
		_request_rebuild()
## Ridged mix, least and most, 0 to 1: how much of the height comes from ridged noise, which
## has sharp crests along lines instead of round hilltops. 0 is round hills, 1 all crests.
@export var character_ridge: Vector2 = Vector2(0.2, 0.5):
	set(value):
		character_ridge = value
		_request_rebuild()

@export_group("Noise Roll")
## Fixed uses the Noise sliders as set. Seeded ignores them and draws the frequency,
## amplitude, octaves, lacunarity and gain from the ranges below for every seed, so one
## seed's hills are 250 m across and smooth and another's 100 m and craggy.
@export var noise_roll: NoiseRoll = NoiseRoll.FIXED:
	set(value):
		noise_roll = value
		_request_rebuild()
## Frequency, least and most: 0.004 is hills 250 m across, 0.01 hills 100 m across.
@export var roll_frequency: Vector2 = Vector2(0.004, 0.01):
	set(value):
		roll_frequency = value
		_request_rebuild()
## Amplitude in metres, least and most. The surface sits at the box's centre and nothing
## is built above the top chunk, so keep the most under half the box height.
@export var roll_amplitude: Vector2 = Vector2(8.0, 40.0):
	set(value):
		roll_amplitude = value
		_request_rebuild()
## Octaves, least and most: 1 is one smooth swell, 5 has detail down to a few metres.
@export var roll_octaves: Vector2i = Vector2i(2, 5):
	set(value):
		roll_octaves = value
		_request_rebuild()
## Lacunarity, least and most: how much finer each octave is than the last.
@export var roll_lacunarity: Vector2 = Vector2(1.8, 2.6):
	set(value):
		roll_lacunarity = value
		_request_rebuild()
## Gain, least and most: 0.3 is smooth swells, 0.65 craggy detail.
@export var roll_gain: Vector2 = Vector2(0.3, 0.65):
	set(value):
		roll_gain = value
		_request_rebuild()

@export_group("Regions")
## Seeded rolls regions from the seed: a very slow noise says where the lowlands and the
## highlands are, the lowlands keep only a share of the amplitude, the highlands turn
## ridged and craggy, and a height curve fills the valleys flat and puts the climb into a
## cliff band. Plain is the same hills everywhere with the noise's own heights.
@export var regions: Regions = Regions.SEEDED:
	set(value):
		regions = value
		_request_rebuild()
## The chance a seed has regions at all. 0 never, 1 always.
@export_range(0.0, 1.0, 0.05) var region_chance: float = 0.7:
	set(value):
		region_chance = value
		_request_rebuild()
## Metres across one swell of the region mask, least and most: a 512 m map holds one or
## two regions at 500 to 900.
@export var region_size: Vector2 = Vector2(500.0, 900.0):
	set(value):
		region_size = value
		_request_rebuild()
## The share of the amplitude the lowlands keep, least and most: 0.1 is plains with a
## metre or two of relief, 1 is no difference from the highlands.
@export var region_lowland: Vector2 = Vector2(0.1, 0.35):
	set(value):
		region_lowland = value
		_request_rebuild()
## The ridged mix in the highlands, least and most: 0 round hills, 1 all sharp crests
## along lines. The lowlands keep the seed's own Character ridge.
@export var region_ridge: Vector2 = Vector2(0.3, 0.8):
	set(value):
		region_ridge = value
		_request_rebuild()
## Finer detail noise added in the highlands as a share of the amplitude, least and most,
## so they are craggy where the lowlands are smooth.
@export var region_detail: Vector2 = Vector2(0.1, 0.3):
	set(value):
		region_detail = value
		_request_rebuild()
## The chance a seed has a hard floor: the valleys fill up to a level like sediment, so
## the low ground is flat. 0 never, 1 always.
@export_range(0.0, 1.0, 0.05) var floor_chance: float = 0.6:
	set(value):
		floor_chance = value
		_request_rebuild()
## The floor's level, least and most, as a share of the height range: 0 the lowest the
## noise goes, 1 the highest. 0.3 fills the bottom third of the valleys.
@export var floor_level: Vector2 = Vector2(0.2, 0.45):
	set(value):
		floor_level = value
		_request_rebuild()
## The chance a seed has a cliff band: a steep span in the height curve with flat spans
## below and above it, plains and a plateau and the climb between. 0 never, 1 always.
@export_range(0.0, 1.0, 0.05) var cliff_chance: float = 0.5:
	set(value):
		cliff_chance = value
		_request_rebuild()
## How much of the height goes through the cliff band, least and most: 0 none, 1 all of
## it (the plains and the plateau are dead flat).
@export var cliff_strength: Vector2 = Vector2(0.4, 0.8):
	set(value):
		cliff_strength = value
		_request_rebuild()
## Where the cliff band sits, least and most, as a share of the height range: 0.5 is
## halfway up.
@export var cliff_level: Vector2 = Vector2(0.4, 0.6):
	set(value):
		cliff_level = value
		_request_rebuild()
## How much of the height range the cliff band spans, least and most: narrow is sheer.
@export var cliff_width: Vector2 = Vector2(0.08, 0.2):
	set(value):
		cliff_width = value
		_request_rebuild()

@export_group("Relief")
## Seeded rolls relief and flat spots from the seed: 3D noise on the steep faces, so
## cliffs get lips, undercuts and overhangs, and a few landings of level ground. None
## leaves the surface as the height made it.
@export var relief: Relief = Relief.SEEDED:
	set(value):
		relief = value
		_request_rebuild()
## The chance a seed has relief. 0 never, 1 always.
@export_range(0.0, 1.0, 0.05) var relief_chance: float = 0.6:
	set(value):
		relief_chance = value
		_request_rebuild()
## How far the relief pushes a steep face in and out, in metres, least and most. It
## shows on faces steeper than about 30 degrees and is full at 45.
@export var relief_amplitude: Vector2 = Vector2(1.5, 3.5):
	set(value):
		relief_amplitude = value
		_request_rebuild()
## How many flat spots a seed places, least and most: landings of level ground the
## colony nests go on. 0 and 0 for none.
@export var flat_spot_count: Vector2i = Vector2i(2, 4):
	set(value):
		flat_spot_count = value
		_request_rebuild()
## A flat spot's radius in metres, least and most. The ground is level inside it and
## fades into the land over the 10 m beyond.
@export var flat_spot_radius: Vector2 = Vector2(8.0, 14.0):
	set(value):
		flat_spot_radius = value
		_request_rebuild()

@export_group("Edges")
## Clip terrain to world bounds on X, Z, and bottom Y. Top remains open.
@export var boxed_edges_enabled: bool = true:
	set(value):
		boxed_edges_enabled = value
		_request_rebuild()
## Fills solid ground below the heightmap surface instead of 3D cave noise.
@export var solid_underside: bool = false:
	set(value):
		solid_underside = value
		_request_rebuild()

## Private copy of the heightmap's image, shared read-only by every settings snapshot and
## worker thread instead of being duplicated per snapshot.
var _heightmap_image_cache: Image


func _register_playable_groups() -> void:
	add_to_group("open_terrain")


func _get_grid_dimensions() -> Vector3i:
	return Vector3i(chunks_x, chunks_y, chunks_z)


func _get_world_log_name() -> String:
	return "OpenTerrain"


func get_surface_height_at(world_position: Vector3) -> float:
	var density: DensitySampler.WorldDensity = _get_bake_density()
	if density.open_terrain_enabled:
		return density.sample_open_terrain_height(world_position.x, world_position.z)
	return global_position.y


func _apply_world_specific_settings(settings: ChunkedTerrainWorld.SettingsSnapshot) -> void:
	settings.boxed_in_terrain_enabled = false
	settings.open_terrain_enabled = true
	settings.open_terrain_edges_enabled = boxed_edges_enabled
	settings.open_terrain_solid_fill = solid_underside
	settings.open_terrain_heightmap_image = _duplicate_heightmap_image()
	settings.open_terrain_surface_offset = surface_height_offset
	if surface_layer > 0:
		# From the box's centre up to the middle of the chosen layer, counted from the top.
		settings.open_terrain_surface_offset += (
			settings.bounds_half.y - (float(surface_layer) - 0.5) * settings.chunk_world_size
		)
	settings.open_terrain_terraces = terraces
	settings.open_terrain_terrace_chance = terrace_chance
	settings.open_terrain_terrace_step = terrace_step
	settings.open_terrain_terrace_strength = terrace_strength
	settings.open_terrain_terrace_coverage = terrace_coverage
	settings.open_terrain_character = character
	settings.open_terrain_character_power = character_power
	settings.open_terrain_character_warp_chance = character_warp_chance
	settings.open_terrain_character_warp = character_warp
	settings.open_terrain_character_ridge_chance = character_ridge_chance
	settings.open_terrain_character_ridge = character_ridge
	settings.open_terrain_noise_roll = noise_roll
	settings.open_terrain_roll_frequency = roll_frequency
	settings.open_terrain_roll_amplitude = roll_amplitude
	settings.open_terrain_roll_octaves = roll_octaves
	settings.open_terrain_roll_lacunarity = roll_lacunarity
	settings.open_terrain_roll_gain = roll_gain
	settings.open_terrain_regions = regions
	settings.open_terrain_region_chance = region_chance
	settings.open_terrain_region_size = region_size
	settings.open_terrain_region_lowland = region_lowland
	settings.open_terrain_region_ridge = region_ridge
	settings.open_terrain_region_detail = region_detail
	settings.open_terrain_floor_chance = floor_chance
	settings.open_terrain_floor_level = floor_level
	settings.open_terrain_cliff_chance = cliff_chance
	settings.open_terrain_cliff_strength = cliff_strength
	settings.open_terrain_cliff_level = cliff_level
	settings.open_terrain_cliff_width = cliff_width
	settings.open_terrain_relief = relief
	settings.open_terrain_relief_chance = relief_chance
	settings.open_terrain_relief_amplitude = relief_amplitude
	settings.open_terrain_flat_spot_count = flat_spot_count
	settings.open_terrain_flat_spot_radius = flat_spot_radius


## The noise a seed builds with: the sliders' values as set (the snapshot's), or with the
## roll on, its own draw from the Noise Roll ranges. Keys: frequency, amplitude, octaves,
## lacunarity, gain.
static func rolled_noise(settings: ChunkedTerrainWorld.SettingsSnapshot) -> Dictionary:
	if settings.open_terrain_noise_roll != NoiseRoll.SEEDED:
		return {
			"frequency": settings.noise_frequency,
			"amplitude": settings.noise_amplitude,
			"octaves": settings.noise_octaves,
			"lacunarity": settings.noise_lacunarity,
			"gain": settings.noise_gain,
		}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(settings.noise_seed, 5503))
	var frequency: Vector2 = settings.open_terrain_roll_frequency
	var amplitude: Vector2 = settings.open_terrain_roll_amplitude
	var octaves: Vector2i = settings.open_terrain_roll_octaves
	var lacunarity: Vector2 = settings.open_terrain_roll_lacunarity
	var gain: Vector2 = settings.open_terrain_roll_gain
	return {
		"frequency":
		maxf(
			rng.randf_range(minf(frequency.x, frequency.y), maxf(frequency.x, frequency.y)), 0.001
		),
		"amplitude":
		maxf(rng.randf_range(minf(amplitude.x, amplitude.y), maxf(amplitude.x, amplitude.y)), 0.0),
		"octaves": rng.randi_range(mini(octaves.x, octaves.y), maxi(octaves.x, octaves.y)),
		"lacunarity":
		rng.randf_range(minf(lacunarity.x, lacunarity.y), maxf(lacunarity.x, lacunarity.y)),
		"gain": rng.randf_range(minf(gain.x, gain.y), maxf(gain.x, gain.y)),
	}


## "hills 170 m across, 28 m tall, 4 octaves, lacunarity 2.1, gain 0.52".
static func noise_summary(noise: Dictionary) -> String:
	return (
		"hills %d m across, %d m tall, %d octaves, lacunarity %.1f, gain %.2f"
		% [
			roundi(1.0 / maxf(float(noise["frequency"]), 0.001)),
			roundi(float(noise["amplitude"])),
			int(noise["octaves"]),
			float(noise["lacunarity"]),
			float(noise["gain"])
		]
	)


func _build_world_density(
	settings: ChunkedTerrainWorld.SettingsSnapshot
) -> DensitySampler.WorldDensity:
	var noise: Dictionary = rolled_noise(settings)
	var density: DensitySampler.WorldDensity = DensitySampler.create_open_terrain_world_density(
		settings.noise_seed,
		float(noise["frequency"]),
		float(noise["amplitude"]),
		int(noise["octaves"]),
		float(noise["lacunarity"]),
		float(noise["gain"]),
		settings.bounds_center,
		settings.bounds_half,
		settings.bounds_clip_inset,
		settings.open_terrain_edges_enabled,
		settings.open_terrain_heightmap_image,
		settings.open_terrain_surface_offset,
		settings.open_terrain_solid_fill
	)
	if settings.caves_enabled and settings.open_terrain_solid_fill:
		density.caves = CaveCarver.for_settings(settings)
	if settings.open_terrain_character == Character.SEEDED:
		density.roll_surface(
			settings.noise_seed,
			settings.open_terrain_character_power,
			settings.open_terrain_character_warp_chance,
			settings.open_terrain_character_warp,
			settings.open_terrain_character_ridge_chance,
			settings.open_terrain_character_ridge
		)
	if settings.open_terrain_regions == Regions.SEEDED:
		density.roll_regions(
			settings.noise_seed,
			settings.open_terrain_region_chance,
			settings.open_terrain_region_size,
			settings.open_terrain_region_lowland,
			settings.open_terrain_region_ridge,
			settings.open_terrain_region_detail
		)
		density.roll_curve(
			settings.noise_seed,
			settings.open_terrain_floor_chance,
			settings.open_terrain_floor_level,
			settings.open_terrain_cliff_chance,
			settings.open_terrain_cliff_strength,
			settings.open_terrain_cliff_level,
			settings.open_terrain_cliff_width
		)
	if settings.open_terrain_relief == Relief.SEEDED:
		if settings.open_terrain_solid_fill:
			density.roll_relief(
				settings.noise_seed,
				settings.open_terrain_relief_chance,
				settings.open_terrain_relief_amplitude
			)
	if settings.open_terrain_terraces != Terraces.NEVER:
		density.roll_terraces(
			settings.noise_seed,
			settings.open_terrain_terrace_chance,
			settings.open_terrain_terrace_step,
			settings.open_terrain_terrace_strength,
			settings.open_terrain_terrace_coverage,
			settings.open_terrain_terraces == Terraces.ALWAYS
		)
	# Last, so a landing is level whatever the terraces and the character did there.
	if settings.open_terrain_relief == Relief.SEEDED:
		density.roll_flat_spots(
			settings.noise_seed,
			settings.open_terrain_flat_spot_count,
			settings.open_terrain_flat_spot_radius
		)
	return density


## The seed's flat spots as points on the surface (empty without any): level landings for
## nests and the like.
func get_flat_spots() -> Array[Vector3]:
	var density: DensitySampler.WorldDensity = _get_bake_density()
	if density == null:
		return []
	return density.flat_spot_points()


func _world_summary(settings: ChunkedTerrainWorld.SettingsSnapshot) -> String:
	var density: DensitySampler.WorldDensity = _build_world_density(settings)
	var summary: String = ", seed %d: " % settings.noise_seed
	if settings.open_terrain_noise_roll == NoiseRoll.SEEDED:
		summary += noise_summary(rolled_noise(settings)) + ", "
	summary += (
		", "
		. join(
			[
				density.surface_summary(),
				density.region_summary(),
				density.curve_summary(),
				density.relief_summary(),
				density.flat_spot_summary(),
				density.terrace_summary(),
			]
		)
	)
	if density.caves != null:
		summary += ", " + density.caves.summary()
	return summary


func _duplicate_heightmap_image() -> Image:
	if heightmap == null:
		return null
	if _heightmap_image_cache != null:
		return _heightmap_image_cache
	var image: Image = heightmap.get_image()
	if image == null or image.is_empty():
		return null
	_heightmap_image_cache = image.duplicate()
	return _heightmap_image_cache
