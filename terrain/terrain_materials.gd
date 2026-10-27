class_name TerrainMaterials
extends RefCounted
## The stuff the pickaxe can build with. NATURAL is the map's own ground (whatever its terrain
## shader draws); every other kind is baked into the mesh as a vertex colour that the terrain
## shaders show instead of the procedural ground. For now any amount of any kind can be placed;
## mining it first is a later step.


enum Kind {
	NATURAL,
	DIRT,
	STONE,
	SAND,
	CLAY,
	GRAVEL,
}

## Placeable kinds in inventory order; NATURAL first so "add terrain" keeps working as before.
const PLACEABLE: Array[Kind] = [
	Kind.NATURAL,
	Kind.DIRT,
	Kind.STONE,
	Kind.SAND,
	Kind.CLAY,
	Kind.GRAVEL,
]

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

## Vertex colour meaning "draw the map's own ground". It is Godot's default vertex colour, so a
## mesh with no colour array draws the same as one that is all natural, and it leaves materials
## that multiply by vertex colour unchanged. Placed materials carry alpha 0 instead.
const NATURAL_VERTEX_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)


static func display_name(kind: Kind) -> String:
	return String(_NAMES.get(kind, "Terrain"))


## Flat colour of a placed material; NATURAL has none (the shader draws the ground).
static func color(kind: Kind) -> Color:
	return _COLORS.get(kind, Color.WHITE) as Color


## What the mesher writes for a surface vertex whose solid side is this kind.
static func vertex_color(kind: Kind) -> Color:
	if kind == Kind.NATURAL or not _COLORS.has(kind):
		return NATURAL_VERTEX_COLOR
	var placed: Color = _COLORS[kind] as Color
	placed.a = 0.0
	return placed
