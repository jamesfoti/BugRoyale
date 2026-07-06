class_name OpenTerrainPreset
extends RefCounted
## Shared open-terrain noise defaults (matches scenes/battlefield_terrain_test.tscn).


const NOISE_SEED: int = 81
const NOISE_FREQUENCY: float = 0.02
const NOISE_AMPLITUDE: float = 6.0
const NOISE_OCTAVES: int = 4
const NOISE_LACUNARITY: float = 2.0
const NOISE_GAIN: float = 0.5
const CHUNK_SIZE: float = 8.0
const SURFACE_HEIGHT_OFFSET: float = 0.0
const BOXED_EDGES_ENABLED: bool = true


static func apply_to(terrain: OpenTerrain) -> void:
	terrain.noise_seed = NOISE_SEED
	terrain.noise_frequency = NOISE_FREQUENCY
	terrain.noise_amplitude = NOISE_AMPLITUDE
	terrain.noise_octaves = NOISE_OCTAVES
	terrain.noise_lacunarity = NOISE_LACUNARITY
	terrain.noise_gain = NOISE_GAIN
	terrain.surface_height_offset = SURFACE_HEIGHT_OFFSET
	terrain.boxed_edges_enabled = BOXED_EDGES_ENABLED
	terrain.bounds_falloff_enabled = false
