extends GutTest
## What a dug face shows and what the pickaxe pays out, read from how deep the digging went:
## the depth comes from the map's surface, not the density (under a solid fill the caves hold
## the density at a metre of depth, so read as a depth it made the whole underground topsoil);
## the topsoil is dirt on a dug face, the colour the stock panel shows for it, while the lawn
## around the hole stays the map's own; and a dig below the topsoil shows the stone or vein it
## reached.

const SEED: int = 7
const BEDROCK_Y: float = -45.5
const VOXEL: float = 2.0
const CELLS: int = 16
## The chunk's first sample: the chunk spans 32 m from here.
const ORIGIN: Vector3 = Vector3(-16.0, -24.0, -16.0)
## A flat map's surface sits this far above the sample row at y = 0, so that row is topsoil
## and the next one down is under it.
const FLAT_SURFACE: float = 1.0


## A solid-filled open terrain with caves carved under it, as the garden has: rolling with
## the amplitude, flat at FLAT_SURFACE without.
func _ground(amplitude: float = 3.0) -> DensitySampler.WorldDensity:
	var density: DensitySampler.WorldDensity = DensitySampler.create_open_terrain_world_density(
		SEED,
		0.01,
		amplitude,
		3,
		2.0,
		0.5,
		Vector3.ZERO,
		Vector3(256.0, 48.0, 256.0),
		0.5,
		false,
		null,
		FLAT_SURFACE if amplitude == 0.0 else 0.0,
		true
	)
	density.caves = CaveCarver.from_seed(SEED, BEDROCK_Y)
	density.caves.ravine_width = 0.0  # digging wants ground to dig; the ravines have their own test
	density.caves.biome_fixed = CaveCarver.Biome.PLAIN  # the colours here are the digging's
	density.land_weights = [1.0, 0.0, 0.0, 0.0]  # meadow alone, for the same reason
	return density


## The chunk's mesh, with the edits on the ground (null: none).
func _mesh(
	ground: DensitySampler.WorldDensity, edits: TerrainEdits
) -> FlyingEdgesMesher.MeshResult:
	ground.terrain_edits = edits
	var field: SignedDensityField = DensitySampler.build_chunk_field(
		ground, Vector3i.ONE * (CELLS + 1), ORIGIN, Vector3i.ZERO, VOXEL
	)
	var extent: float = VOXEL * float(CELLS)
	return FlyingEdgesMesher.build_mesh(
		field, extent, 0.0, Vector3i.ZERO, ORIGIN, ORIGIN + Vector3.ONE * extent * 0.5, ground
	)


## Carves a sphere, as the pickaxe does; last_removed on the result is what came loose.
func _dig(ground: DensitySampler.WorldDensity, center: Vector3, radius: float) -> TerrainEdits:
	var edits := TerrainEdits.new()
	edits.set_voxel_size(VOXEL)
	edits.set_grid_origin(ORIGIN)
	edits.add_brush(
		center,
		radius,
		false,
		Callable(ground, "evaluate"),
		TerrainMaterials.Kind.NATURAL,
		Callable(ground, "ground_material")
	)
	return edits


func _color_counts(mesh: FlyingEdgesMesher.MeshResult) -> Dictionary:
	var counts: Dictionary = {}
	for color: Color in mesh.colors:
		counts[color] = int(counts.get(color, 0)) + 1
	return counts


func test_the_depth_is_read_from_the_surface_not_the_density() -> void:
	var ground: DensitySampler.WorldDensity = _ground()
	var deep: int = 0
	var topsoil: int = 0
	for step: int in 40:
		var x: float = float(step) * 7.0 - 140.0
		var z: float = float(step) * -5.0 + 100.0
		var surface: float = ground.sample_open_terrain_height(x, z)
		var below := Vector3(x, surface - 6.0, z)
		if ground.caves.is_cave(below, surface):
			continue
		var value: float = ground.evaluate(below, false)
		assert_lt(value, 0.0, "6 m down is ground")
		assert_almost_eq(ground.depth_below_surface(below, value), 6.0, 0.01)
		if ground.ground_material(below, value) != TerrainMaterials.Kind.NATURAL:
			deep += 1
		var shallow := Vector3(x, surface - 0.5, z)
		if (
			ground.ground_material(shallow, ground.evaluate(shallow, false))
			== (TerrainMaterials.Kind.NATURAL)
		):
			topsoil += 1
	assert_gt(deep, 30, "6 m down lies stone, a vein or ore, not topsoil")
	assert_gt(topsoil, 30, "half a metre down is still the topsoil")


func test_an_undug_lawn_carries_no_colour_of_its_own() -> void:
	var counts: Dictionary = _color_counts(_mesh(_ground(0.0), null))
	assert_eq(counts.keys(), [TerrainMaterials.NATURAL_VERTEX_COLOR])


func test_a_shallow_dig_shows_dirt_and_pays_dirt() -> void:
	var ground: DensitySampler.WorldDensity = _ground(0.0)
	# From the surface, 1.3 m down: the sample a metre under it comes out, the floor is topsoil.
	var edits: TerrainEdits = _dig(ground, Vector3(0.0, FLAT_SURFACE, 0.0), 1.3)
	assert_eq(edits.last_removed, {TerrainMaterials.Kind.DIRT: 1}, "one voxel of dirt dug")
	var counts: Dictionary = _color_counts(_mesh(ground, edits))
	var dirt: Color = TerrainMaterials.vertex_color(TerrainMaterials.Kind.DIRT)
	assert_true(counts.has(dirt), "the hole's faces show dirt")
	assert_true(counts.has(TerrainMaterials.NATURAL_VERTEX_COLOR), "the lawn around it stays")
	for color: Color in counts:
		assert_true(
			color == dirt or color == TerrainMaterials.NATURAL_VERTEX_COLOR,
			"only dirt and lawn: %s" % str(color)
		)
	# The brush thins the samples in a shell round the hole without digging them out; the
	# lawn over that shell is still the lawn, so the hole has no ring of dirt round it.
	var shell := Vector3(2.0, 0.0, 0.0)
	assert_true(edits.is_overridden_at(shell), "the shell sample was written")
	assert_lt(edits.apply_to_density(ground.evaluate(shell, false), shell), 0.0, "and stays solid")
	assert_lt(float(counts[dirt]), float(counts[TerrainMaterials.NATURAL_VERTEX_COLOR]) / 10.0)


func test_a_deep_dig_reaches_the_stone() -> void:
	var ground: DensitySampler.WorldDensity = _ground(0.0)
	var edits: TerrainEdits = _dig(ground, Vector3(0.0, FLAT_SURFACE - 4.0, 0.0), 5.0)
	var removed: Dictionary = edits.last_removed
	assert_true(removed.has(TerrainMaterials.Kind.DIRT), "the topsoil came out as dirt")
	var below_topsoil: int = 0
	for kind: TerrainMaterials.Kind in removed:
		if kind != TerrainMaterials.Kind.DIRT:
			below_topsoil += int(removed[kind])
	assert_gt(below_topsoil, 0, "and the ground under it as stone, a vein or ore")
	var counts: Dictionary = _color_counts(_mesh(ground, edits))
	var dirt: Color = TerrainMaterials.vertex_color(TerrainMaterials.Kind.DIRT)
	var deeper: int = 0
	for color: Color in counts:
		if color != dirt and color != TerrainMaterials.NATURAL_VERTEX_COLOR:
			deeper += int(counts[color])
	assert_gt(deeper, 0, "the hole's lower faces show what lies under the topsoil")
