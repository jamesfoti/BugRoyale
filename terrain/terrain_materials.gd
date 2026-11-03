class_name TerrainMaterials
extends RefCounted
## The stuff the pickaxe digs and builds with. NATURAL is the map's own ground (whatever its
## terrain shader draws); every other kind is baked into the mesh as a vertex colour that the
## terrain shaders show instead of the procedural ground. The first five are the common grounds
## (dirt under the topsoil, stone below it, veins of sand, clay and gravel); after them come the
## elements, one per chemical element that is dug out of the Earth's crust as an ore or found
## native in it (so no gases, nothing made only in a reactor, nothing only ever refined as a
## by-product of another ore). Each element lies in pockets within the stone from a depth of
## its own, the common ones near the surface and the precious ones at the bottom, and is built
## with like any other material once in hand. Order matters: kinds are saved to disk as their
## number, so new kinds go on the end.

enum Kind {
	NATURAL,
	DIRT,
	STONE,
	SAND,
	CLAY,
	GRAVEL,
	LITHIUM,
	BERYLLIUM,
	BORON,
	CARBON,
	FLUORINE,
	SODIUM,
	MAGNESIUM,
	ALUMINIUM,
	SILICON,
	PHOSPHORUS,
	SULFUR,
	POTASSIUM,
	CALCIUM,
	TITANIUM,
	VANADIUM,
	CHROMIUM,
	MANGANESE,
	IRON,
	COBALT,
	NICKEL,
	COPPER,
	ZINC,
	ARSENIC,
	STRONTIUM,
	ZIRCONIUM,
	NIOBIUM,
	MOLYBDENUM,
	SILVER,
	TIN,
	ANTIMONY,
	BARIUM,
	CERIUM,
	NEODYMIUM,
	TANTALUM,
	TUNGSTEN,
	PLATINUM,
	GOLD,
	MERCURY,
	LEAD,
	BISMUTH,
	THORIUM,
	URANIUM,
}

## The common grounds, in inventory order; NATURAL first so "add terrain" keeps working.
const GROUNDS: Array[Kind] = [
	Kind.NATURAL,
	Kind.DIRT,
	Kind.STONE,
	Kind.SAND,
	Kind.CLAY,
	Kind.GRAVEL,
]

## Every element, in atomic-number order (the order of the periodic table).
const ELEMENT_KINDS: Array[Kind] = [
	Kind.LITHIUM,
	Kind.BERYLLIUM,
	Kind.BORON,
	Kind.CARBON,
	Kind.FLUORINE,
	Kind.SODIUM,
	Kind.MAGNESIUM,
	Kind.ALUMINIUM,
	Kind.SILICON,
	Kind.PHOSPHORUS,
	Kind.SULFUR,
	Kind.POTASSIUM,
	Kind.CALCIUM,
	Kind.TITANIUM,
	Kind.VANADIUM,
	Kind.CHROMIUM,
	Kind.MANGANESE,
	Kind.IRON,
	Kind.COBALT,
	Kind.NICKEL,
	Kind.COPPER,
	Kind.ZINC,
	Kind.ARSENIC,
	Kind.STRONTIUM,
	Kind.ZIRCONIUM,
	Kind.NIOBIUM,
	Kind.MOLYBDENUM,
	Kind.SILVER,
	Kind.TIN,
	Kind.ANTIMONY,
	Kind.BARIUM,
	Kind.CERIUM,
	Kind.NEODYMIUM,
	Kind.TANTALUM,
	Kind.TUNGSTEN,
	Kind.PLATINUM,
	Kind.GOLD,
	Kind.MERCURY,
	Kind.LEAD,
	Kind.BISMUTH,
	Kind.THORIUM,
	Kind.URANIUM,
]

## Placeable kinds in inventory order: the grounds, then the elements (untyped: joining two
## typed arrays yields an Array[int], which a typed constant refuses).
const PLACEABLE: Array = GROUNDS + ELEMENT_KINDS

## Where in the ground each element lies, as metres below the surface it starts at. The depths
## are the four bands of a map three chunks (about thirty metres) deep: the topsoil's floor,
## the worm tunnels, the caverns and the bedrock's doorstep.
const SHALLOW_DEPTH: float = 2.0
const MID_DEPTH: float = 7.0
const DEEP_DEPTH: float = 14.0
const DEEPEST_DEPTH: float = 20.0

## Kind -> the element: its symbol, atomic number, the depth it starts at, its weight (its share
## of the ore pockets it is a candidate for, against the other elements in reach at that depth:
## the commoner the ore on Earth, the heavier) and the colour of its ore in the ground.
const ELEMENTS: Dictionary = {
	Kind.LITHIUM:
	{
		"symbol": "Li",
		"number": 3,
		"depth": SHALLOW_DEPTH,
		"weight": 2,
		"color": Color(0.80, 0.72, 0.78)
	},
	Kind.BERYLLIUM:
	{
		"symbol": "Be",
		"number": 4,
		"depth": MID_DEPTH,
		"weight": 1,
		"color": Color(0.55, 0.78, 0.65)
	},
	Kind.BORON:
	{
		"symbol": "B",
		"number": 5,
		"depth": SHALLOW_DEPTH,
		"weight": 2,
		"color": Color(0.86, 0.86, 0.80)
	},
	Kind.CARBON:
	{
		"symbol": "C",
		"number": 6,
		"depth": SHALLOW_DEPTH,
		"weight": 8,
		"color": Color(0.12, 0.12, 0.13)
	},
	Kind.FLUORINE:
	{
		"symbol": "F",
		"number": 9,
		"depth": SHALLOW_DEPTH,
		"weight": 3,
		"color": Color(0.55, 0.35, 0.70)
	},
	Kind.SODIUM:
	{
		"symbol": "Na",
		"number": 11,
		"depth": SHALLOW_DEPTH,
		"weight": 5,
		"color": Color(0.92, 0.88, 0.86)
	},
	Kind.MAGNESIUM:
	{
		"symbol": "Mg",
		"number": 12,
		"depth": SHALLOW_DEPTH,
		"weight": 5,
		"color": Color(0.78, 0.82, 0.76)
	},
	Kind.ALUMINIUM:
	{
		"symbol": "Al",
		"number": 13,
		"depth": SHALLOW_DEPTH,
		"weight": 6,
		"color": Color(0.80, 0.52, 0.38)
	},
	Kind.SILICON:
	{
		"symbol": "Si",
		"number": 14,
		"depth": SHALLOW_DEPTH,
		"weight": 8,
		"color": Color(0.90, 0.90, 0.94)
	},
	Kind.PHOSPHORUS:
	{
		"symbol": "P",
		"number": 15,
		"depth": SHALLOW_DEPTH,
		"weight": 4,
		"color": Color(0.60, 0.66, 0.54)
	},
	Kind.SULFUR:
	{
		"symbol": "S",
		"number": 16,
		"depth": SHALLOW_DEPTH,
		"weight": 4,
		"color": Color(0.92, 0.85, 0.25)
	},
	Kind.POTASSIUM:
	{
		"symbol": "K",
		"number": 19,
		"depth": SHALLOW_DEPTH,
		"weight": 4,
		"color": Color(0.88, 0.62, 0.52)
	},
	Kind.CALCIUM:
	{
		"symbol": "Ca",
		"number": 20,
		"depth": SHALLOW_DEPTH,
		"weight": 8,
		"color": Color(0.88, 0.86, 0.76)
	},
	Kind.TITANIUM:
	{
		"symbol": "Ti",
		"number": 22,
		"depth": MID_DEPTH,
		"weight": 4,
		"color": Color(0.30, 0.32, 0.36)
	},
	Kind.VANADIUM:
	{
		"symbol": "V",
		"number": 23,
		"depth": MID_DEPTH,
		"weight": 2,
		"color": Color(0.80, 0.35, 0.15)
	},
	Kind.CHROMIUM:
	{
		"symbol": "Cr",
		"number": 24,
		"depth": MID_DEPTH,
		"weight": 3,
		"color": Color(0.28, 0.25, 0.22)
	},
	Kind.MANGANESE:
	{
		"symbol": "Mn",
		"number": 25,
		"depth": MID_DEPTH,
		"weight": 4,
		"color": Color(0.22, 0.24, 0.30)
	},
	Kind.IRON:
	{
		"symbol": "Fe",
		"number": 26,
		"depth": MID_DEPTH,
		"weight": 8,
		"color": Color(0.55, 0.25, 0.18)
	},
	Kind.COBALT:
	{
		"symbol": "Co",
		"number": 27,
		"depth": MID_DEPTH,
		"weight": 2,
		"color": Color(0.25, 0.35, 0.70)
	},
	Kind.NICKEL:
	{
		"symbol": "Ni",
		"number": 28,
		"depth": MID_DEPTH,
		"weight": 3,
		"color": Color(0.65, 0.55, 0.35)
	},
	Kind.COPPER:
	{
		"symbol": "Cu",
		"number": 29,
		"depth": MID_DEPTH,
		"weight": 5,
		"color": Color(0.85, 0.50, 0.20)
	},
	Kind.ZINC:
	{
		"symbol": "Zn",
		"number": 30,
		"depth": MID_DEPTH,
		"weight": 4,
		"color": Color(0.45, 0.38, 0.22)
	},
	Kind.ARSENIC:
	{
		"symbol": "As",
		"number": 33,
		"depth": MID_DEPTH,
		"weight": 2,
		"color": Color(0.70, 0.72, 0.70)
	},
	Kind.STRONTIUM:
	{
		"symbol": "Sr",
		"number": 38,
		"depth": SHALLOW_DEPTH,
		"weight": 2,
		"color": Color(0.65, 0.78, 0.90)
	},
	Kind.ZIRCONIUM:
	{
		"symbol": "Zr",
		"number": 40,
		"depth": MID_DEPTH,
		"weight": 2,
		"color": Color(0.62, 0.36, 0.40)
	},
	Kind.NIOBIUM:
	{
		"symbol": "Nb",
		"number": 41,
		"depth": DEEP_DEPTH,
		"weight": 1,
		"color": Color(0.20, 0.16, 0.14)
	},
	Kind.MOLYBDENUM:
	{
		"symbol": "Mo",
		"number": 42,
		"depth": MID_DEPTH,
		"weight": 2,
		"color": Color(0.40, 0.44, 0.50)
	},
	Kind.SILVER:
	{
		"symbol": "Ag",
		"number": 47,
		"depth": DEEP_DEPTH,
		"weight": 2,
		"color": Color(0.82, 0.84, 0.86)
	},
	Kind.TIN:
	{
		"symbol": "Sn",
		"number": 50,
		"depth": MID_DEPTH,
		"weight": 3,
		"color": Color(0.26, 0.20, 0.16)
	},
	Kind.ANTIMONY:
	{
		"symbol": "Sb",
		"number": 51,
		"depth": MID_DEPTH,
		"weight": 2,
		"color": Color(0.42, 0.46, 0.52)
	},
	Kind.BARIUM:
	{
		"symbol": "Ba",
		"number": 56,
		"depth": SHALLOW_DEPTH,
		"weight": 3,
		"color": Color(0.74, 0.80, 0.84)
	},
	Kind.CERIUM:
	{
		"symbol": "Ce",
		"number": 58,
		"depth": DEEP_DEPTH,
		"weight": 2,
		"color": Color(0.80, 0.65, 0.30)
	},
	Kind.NEODYMIUM:
	{
		"symbol": "Nd",
		"number": 60,
		"depth": DEEP_DEPTH,
		"weight": 2,
		"color": Color(0.65, 0.50, 0.70)
	},
	Kind.TANTALUM:
	{
		"symbol": "Ta",
		"number": 73,
		"depth": DEEP_DEPTH,
		"weight": 1,
		"color": Color(0.16, 0.16, 0.18)
	},
	Kind.TUNGSTEN:
	{
		"symbol": "W",
		"number": 74,
		"depth": DEEP_DEPTH,
		"weight": 2,
		"color": Color(0.30, 0.24, 0.22)
	},
	Kind.PLATINUM:
	{
		"symbol": "Pt",
		"number": 78,
		"depth": DEEPEST_DEPTH,
		"weight": 1,
		"color": Color(0.88, 0.88, 0.84)
	},
	Kind.GOLD:
	{
		"symbol": "Au",
		"number": 79,
		"depth": DEEPEST_DEPTH,
		"weight": 1,
		"color": Color(0.95, 0.78, 0.22)
	},
	Kind.MERCURY:
	{
		"symbol": "Hg",
		"number": 80,
		"depth": MID_DEPTH,
		"weight": 1,
		"color": Color(0.78, 0.15, 0.12)
	},
	Kind.LEAD:
	{
		"symbol": "Pb",
		"number": 82,
		"depth": MID_DEPTH,
		"weight": 4,
		"color": Color(0.30, 0.30, 0.34)
	},
	Kind.BISMUTH:
	{
		"symbol": "Bi",
		"number": 83,
		"depth": MID_DEPTH,
		"weight": 1,
		"color": Color(0.80, 0.60, 0.65)
	},
	Kind.THORIUM:
	{
		"symbol": "Th",
		"number": 90,
		"depth": DEEP_DEPTH,
		"weight": 1,
		"color": Color(0.35, 0.30, 0.25)
	},
	Kind.URANIUM:
	{
		"symbol": "U",
		"number": 92,
		"depth": DEEPEST_DEPTH,
		"weight": 1,
		"color": Color(0.65, 0.80, 0.25)
	},
}

## Vertex colour meaning "draw the map's own ground". It is Godot's default vertex colour, so a
## mesh with no colour array draws the same as one that is all natural, and it leaves materials
## that multiply by vertex colour unchanged. Placed materials carry alpha 0 instead.
const NATURAL_VERTEX_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)

const _NAMES: Dictionary = {
	Kind.NATURAL: "Terrain",
	Kind.DIRT: "Dirt",
	Kind.STONE: "Stone",
	Kind.SAND: "Sand",
	Kind.CLAY: "Clay",
	Kind.GRAVEL: "Gravel",
}

const _COLORS: Dictionary = {
	Kind.DIRT: Color(0.42, 0.30, 0.18),
	Kind.STONE: Color(0.50, 0.51, 0.53),
	Kind.SAND: Color(0.86, 0.78, 0.54),
	Kind.CLAY: Color(0.72, 0.42, 0.30),
	Kind.GRAVEL: Color(0.58, 0.55, 0.50),
}


## "Iron", "Gold", "Stone"; the enum name in title case for an element.
static func display_name(kind: Kind) -> String:
	if _NAMES.has(kind):
		return String(_NAMES[kind])
	if is_element(kind):
		return String(Kind.keys()[kind]).capitalize()
	return "Terrain"


## True for the kinds that are chemical elements rather than common ground.
static func is_element(kind: Kind) -> bool:
	return ELEMENTS.has(kind)


## The element's symbol ("Fe"); empty for a ground.
static func symbol(kind: Kind) -> String:
	return String(_element(kind).get("symbol", ""))


## The element's atomic number; 0 for a ground.
static func atomic_number(kind: Kind) -> int:
	return int(_element(kind).get("number", 0))


## Metres below the surface the element's pockets start at; INF for a ground (never an ore).
static func ore_depth(kind: Kind) -> float:
	return float(_element(kind).get("depth", INF))


## The element's share of the pockets it is in reach of; 0 for a ground.
static func ore_weight(kind: Kind) -> int:
	return int(_element(kind).get("weight", 0))


## Flat colour of a placed material; NATURAL has none (the shader draws the ground).
static func color(kind: Kind) -> Color:
	if _COLORS.has(kind):
		return _COLORS[kind] as Color
	return _element(kind).get("color", Color.WHITE) as Color


## What the mesher writes for a surface vertex whose solid side is this kind.
static func vertex_color(kind: Kind) -> Color:
	if kind == Kind.NATURAL or not (_COLORS.has(kind) or is_element(kind)):
		return NATURAL_VERTEX_COLOR
	var placed: Color = color(kind)
	placed.a = 0.0
	return placed


static func _element(kind: Kind) -> Dictionary:
	return ELEMENTS.get(kind, {}) as Dictionary
