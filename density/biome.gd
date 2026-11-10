class_name Biome
extends Resource
## One kind of ground on top or of cave below, as data: its weight against the other kinds in
## its list (BiomePatches draws each patch by weight), the tint its surfaces carry, the depths
## it holds at, and what the carver does in it. A new kind is a new resource in biomes/, no
## code; the lists on the terrain node say which kinds a map draws from.

## Shown in the rebuild line's shares.
@export var biome_name: String = "biome"
## How likely a patch is this kind against the others in its list: 3 against 1 is three
## patches in four, 0 is never, and one kind alone is everywhere.
@export_range(0.0, 10.0, 0.5) var weight: float = 1.0
## The vertex tint of its surfaces: white at alpha 1 is the ground as the shader draws it,
## any colour at alpha 0.5 is blended half over that, and alpha 0 replaces it.
@export var tint: Color = Color(1.0, 1.0, 1.0, 1.0)
## Caves only: the metres below the surface between which the kind holds. Where a patch's
## kind does not hold, the first kind in the list that does stands in.
@export var depth_range: Vector2 = Vector2(0.0, 100000.0)
## Caves only: rooms stand on pillars where the pillar map runs high.
@export var pillars: bool = false
## Caves only: the seed's ceiling jag and floor rubble, scaled (0 smooth).
@export_range(0.0, 3.0, 0.1) var ceiling_jag: float = 1.0
@export_range(0.0, 3.0, 0.1) var rubble: float = 1.0


## The kind as plain values, which the chunks' worker threads read instead of the resource.
func to_data() -> Dictionary:
	return {
		"name": biome_name,
		"weight": weight,
		"tint": tint,
		"depth_min": depth_range.x,
		"depth_max": depth_range.y,
		"pillars": pillars,
		"ceiling_jag": ceiling_jag,
		"rubble": rubble,
	}


## The data of a list of kinds, skipping empty slots (and a list that is not one at all, as
## a scene saved by an editor running an older script can hold).
static func data_of(biomes: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (biomes is Array):
		return out
	for biome: Variant in biomes as Array:
		if biome is Biome:
			out.append((biome as Biome).to_data())
	return out


static func weights_of(data: Array[Dictionary]) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	for kind: Dictionary in data:
		out.append(float(kind.get("weight", 0.0)))
	return out


static func names_of(data: Array[Dictionary]) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for kind: Dictionary in data:
		out.append(str(kind.get("name", "")))
	return out


## The tint of a kind's surfaces; the ground's own where there is no kind.
static func tint_of(kind: Dictionary) -> Color:
	return kind.get("tint", TerrainMaterials.NATURAL_VERTEX_COLOR) as Color


## Whether a kind holds this many metres below the surface.
static func holds(kind: Dictionary, depth: float) -> bool:
	return depth >= float(kind.get("depth_min", 0.0)) and depth < float(kind.get("depth_max", INF))
