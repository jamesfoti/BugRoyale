extends GutTest
## The elements in the ground: the table lists every one once with a symbol, a number, a depth
## and a colour; the ground under the topsoil is stone with pockets of ore, each element only
## from its own depth down and the pockets a share of the stone, not all of it; a seed always
## draws the same ore; and a dug element lands in the stock like any other material.

const SEED: int = 4242
const OTHER_SEED: int = 99


func _ground(noise_seed: int = SEED) -> DensitySampler.WorldDensity:
	return DensitySampler.create_open_terrain_world_density(
		noise_seed, 0.01, 3.0, 3, 2.0, 0.5, Vector3.ZERO, Vector3(256.0, 48.0, 256.0)
	)


## What the ground is at a grid of points, this many metres down: Kind -> how many points.
func _tally(ground: DensitySampler.WorldDensity, depth: float, steps: int = 40) -> Dictionary:
	var counts: Dictionary = {}
	for step_x: int in steps:
		for step_z: int in steps:
			var position := Vector3(
				float(step_x) * 5.0 - 100.0, -depth, float(step_z) * 5.0 - 100.0
			)
			var kind: TerrainMaterials.Kind = ground.natural_material(position, -depth)
			counts[kind] = int(counts.get(kind, 0)) + 1
	return counts


func test_every_element_is_in_the_table_once() -> void:
	assert_eq(TerrainMaterials.ELEMENT_KINDS.size(), TerrainMaterials.ELEMENTS.size())
	var symbols: Dictionary = {}
	var last_number: int = 0
	for kind: TerrainMaterials.Kind in TerrainMaterials.ELEMENT_KINDS:
		var name: String = TerrainMaterials.display_name(kind)
		assert_true(TerrainMaterials.is_element(kind), name)
		var symbol: String = TerrainMaterials.symbol(kind)
		assert_false(symbols.has(symbol), "%s: symbol %s twice" % [name, symbol])
		symbols[symbol] = true
		var number: int = TerrainMaterials.atomic_number(kind)
		assert_gt(number, last_number, "%s: the table runs by atomic number" % name)
		last_number = number
		assert_gt(TerrainMaterials.ore_weight(kind), 0, name)
		assert_gte(
			TerrainMaterials.ore_depth(kind),
			DensitySampler.WorldDensity.TOPSOIL_DEPTH,
			"%s lies under the topsoil" % name
		)
		assert_ne(TerrainMaterials.color(kind), Color.WHITE, "%s has a colour" % name)
		assert_eq(TerrainMaterials.vertex_color(kind).a, 0.0, "%s draws as placed" % name)


func test_placeable_is_the_grounds_then_the_elements() -> void:
	assert_eq(
		TerrainMaterials.PLACEABLE.size(),
		TerrainMaterials.GROUNDS.size() + TerrainMaterials.ELEMENT_KINDS.size()
	)
	assert_eq(TerrainMaterials.PLACEABLE[0], TerrainMaterials.Kind.NATURAL)
	assert_eq(
		TerrainMaterials.PLACEABLE[TerrainMaterials.GROUNDS.size()], TerrainMaterials.Kind.LITHIUM
	)
	assert_eq(TerrainMaterials.PLACEABLE[-1], TerrainMaterials.Kind.URANIUM)


func test_names_symbols_and_numbers() -> void:
	assert_eq(TerrainMaterials.display_name(TerrainMaterials.Kind.IRON), "Iron")
	assert_eq(TerrainMaterials.display_name(TerrainMaterials.Kind.ALUMINIUM), "Aluminium")
	assert_eq(TerrainMaterials.symbol(TerrainMaterials.Kind.IRON), "Fe")
	assert_eq(TerrainMaterials.atomic_number(TerrainMaterials.Kind.GOLD), 79)
	assert_eq(TerrainMaterials.atomic_number(TerrainMaterials.Kind.URANIUM), 92)
	assert_false(TerrainMaterials.is_element(TerrainMaterials.Kind.STONE))
	assert_eq(TerrainMaterials.symbol(TerrainMaterials.Kind.STONE), "")
	assert_eq(TerrainMaterials.ore_depth(TerrainMaterials.Kind.STONE), INF, "stone is never an ore")
	assert_eq(TerrainMaterials.display_name(TerrainMaterials.Kind.STONE), "Stone")
	assert_eq(StockPanel.row_name(TerrainMaterials.Kind.IRON), "Fe Iron")
	assert_eq(StockPanel.row_name(TerrainMaterials.Kind.STONE), "Stone")


func test_the_topsoil_is_the_maps_own_ground() -> void:
	var ground: DensitySampler.WorldDensity = _ground()
	var counts: Dictionary = _tally(ground, 1.0, 10)
	assert_eq(counts.keys(), [TerrainMaterials.Kind.NATURAL])


func test_no_element_lies_above_its_depth() -> void:
	var ground: DensitySampler.WorldDensity = _ground()
	var elements_found: int = 0
	for depth: float in [1.8, 2.0, 4.0, 7.0, 10.0, 14.0, 17.0, 20.0, 26.0]:
		var counts: Dictionary = _tally(ground, depth, 25)
		for kind: TerrainMaterials.Kind in counts:
			if not TerrainMaterials.is_element(kind):
				continue
			elements_found += int(counts[kind])
			assert_lte(
				TerrainMaterials.ore_depth(kind),
				depth,
				"%s at %.1f m" % [TerrainMaterials.display_name(kind), depth]
			)
	assert_gt(elements_found, 0)
	assert_false(
		_tally(ground, 1.8, 25).keys().any(TerrainMaterials.is_element),
		"nothing between the topsoil and the shallowest ore"
	)


func test_ore_is_a_share_of_the_stone_and_the_deep_ground_has_many_elements() -> void:
	var ground: DensitySampler.WorldDensity = _ground()
	var counts: Dictionary = _tally(ground, 25.0)
	var stone: int = int(counts.get(TerrainMaterials.Kind.STONE, 0))
	var ore: int = 0
	var distinct: int = 0
	for kind: TerrainMaterials.Kind in counts:
		if TerrainMaterials.is_element(kind):
			ore += int(counts[kind])
			distinct += 1
	var share: float = float(ore) / float(stone + ore)
	assert_between(share, 0.02, 0.25, "ore share of the stone: %.3f" % share)
	assert_gte(distinct, 10, "elements found at 25 m: %d" % distinct)
	assert_true(
		counts.has(TerrainMaterials.Kind.SAND) or counts.has(TerrainMaterials.Kind.CLAY),
		"the veins are still there"
	)


func test_the_same_seed_draws_the_same_ore_and_another_seed_differs() -> void:
	var first: Dictionary = _tally(_ground(), 12.0)
	var again: Dictionary = _tally(_ground(), 12.0)
	var other: Dictionary = _tally(_ground(OTHER_SEED), 12.0)
	assert_eq(first, again)
	assert_ne(first, other)


func gold_everywhere(_world_position: Vector3, _density: float) -> TerrainMaterials.Kind:
	return TerrainMaterials.Kind.GOLD


func flat_ground(world_position: Vector3) -> float:
	return world_position.y


func test_a_dug_element_lands_in_the_stock_and_builds() -> void:
	var edits: TerrainEdits = TerrainEdits.new()
	edits.set_voxel_size(1.0)
	edits.add_brush(
		Vector3(0, -3, 0),
		1.5,
		false,
		Callable(self, "flat_ground"),
		TerrainMaterials.Kind.NATURAL,
		Callable(self, "gold_everywhere")
	)
	var dug: int = int(edits.last_removed.get(TerrainMaterials.Kind.GOLD, 0))
	assert_gt(dug, 0, "the gold comes out as gold")
	var stock: MaterialStock = MaterialStock.new()
	stock.on_edit_applied(
		{"add": false, "tool": TerrainBrush.PICKAXE_TOOL, "removed": edits.last_removed}
	)
	assert_eq(stock.count(TerrainMaterials.Kind.GOLD), dug)
	assert_eq(stock.text(), "Gold %d" % dug)
	var block: Dictionary = ChunkedTerrainWorld.box_edit(
		Vector3.ZERO, Vector3.ONE, true, TerrainMaterials.Kind.GOLD
	)
	assert_true(stock.affordable(block, 1.0), "enough gold for a two-voxel block")
	stock.on_edit_applied({"add": true, "material": TerrainMaterials.Kind.GOLD, "added": dug})
	assert_eq(stock.count(TerrainMaterials.Kind.GOLD), 0)
	assert_false(stock.affordable(block, 1.0))
