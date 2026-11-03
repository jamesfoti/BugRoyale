extends GutTest
## The pickaxe stock: digging pays out by material (only with the pickaxe: a blast's crater is
## free), building spends, the map's own ground is dirt, the stock never goes negative, and a
## build the stock cannot cover is refused.

var _stock: MaterialStock


func before_each() -> void:
	_stock = MaterialStock.new()
	watch_signals(_stock)


func test_starts_empty_for_every_placeable_kind() -> void:
	for kind: TerrainMaterials.Kind in TerrainMaterials.PLACEABLE:
		if kind != TerrainMaterials.Kind.NATURAL:
			assert_eq(_stock.count(kind), 0, TerrainMaterials.display_name(kind))
	assert_eq(_stock.text(), "Nothing dug yet")


func test_a_carve_pays_out_what_it_removed() -> void:
	(
		_stock
		. on_edit_applied(
			{
				"add": false,
				"tool": TerrainBrush.PICKAXE_TOOL,
				"removed": {TerrainMaterials.Kind.DIRT: 7, TerrainMaterials.Kind.STONE: 2},
			}
		)
	)
	assert_eq(_stock.count(TerrainMaterials.Kind.DIRT), 7)
	assert_eq(_stock.count(TerrainMaterials.Kind.STONE), 2)
	assert_eq(_stock.text(), "Dirt 7, Stone 2")
	assert_signal_emitted(_stock, "changed")


func test_a_blast_pays_nothing() -> void:
	_stock.on_edit_applied({"add": false, "removed": {TerrainMaterials.Kind.DIRT: 7}})
	assert_eq(_stock.count(TerrainMaterials.Kind.DIRT), 0, "no tool: a shot")
	assert_signal_not_emitted(_stock, "changed")


func test_building_spends_the_brush_material() -> void:
	_stock.add(TerrainMaterials.Kind.STONE, 10)
	_stock.on_edit_applied({"add": true, "material": TerrainMaterials.Kind.STONE, "added": 4})
	assert_eq(_stock.count(TerrainMaterials.Kind.STONE), 6)


func test_the_maps_own_ground_costs_dirt() -> void:
	assert_eq(MaterialStock.cost_kind(TerrainMaterials.Kind.NATURAL), TerrainMaterials.Kind.DIRT)
	_stock.add(TerrainMaterials.Kind.DIRT, 10)
	_stock.on_edit_applied({"add": true, "material": TerrainMaterials.Kind.NATURAL, "added": 4})
	assert_eq(_stock.count(TerrainMaterials.Kind.DIRT), 6)
	assert_eq(_stock.count(TerrainMaterials.Kind.NATURAL), 6, "asking for ground reads dirt")


func test_the_stock_never_goes_negative() -> void:
	_stock.add(TerrainMaterials.Kind.DIRT, 2)
	_stock.on_edit_applied({"add": true, "material": TerrainMaterials.Kind.DIRT, "added": 5})
	assert_eq(_stock.count(TerrainMaterials.Kind.DIRT), 0)


func test_a_build_needs_half_its_voxels_in_hand() -> void:
	# A box two voxels on a side covers eight voxels: four must be affordable.
	var block: Dictionary = ChunkedTerrainWorld.box_edit(
		Vector3.ZERO, Vector3.ONE, true, TerrainMaterials.Kind.STONE
	)
	assert_false(_stock.affordable(block, 1.0), "nothing in hand")
	_stock.add(TerrainMaterials.Kind.STONE, 3)
	assert_false(_stock.affordable(block, 1.0), "three is one short")
	_stock.add(TerrainMaterials.Kind.STONE, 1)
	assert_true(_stock.affordable(block, 1.0))


func test_carving_is_always_allowed() -> void:
	var carve: Dictionary = ChunkedTerrainWorld.sphere_edit(
		Vector3.ZERO, 3.0, false, TerrainMaterials.Kind.NATURAL
	)
	assert_true(_stock.affordable(carve, 1.0))
	assert_true(_stock.can_afford(carve), "no terrain attached: nothing is gated")


func test_counts_round_trip() -> void:
	_stock.add(TerrainMaterials.Kind.DIRT, 3)
	_stock.add(TerrainMaterials.Kind.CLAY, 5)
	var other: MaterialStock = MaterialStock.new()
	other.import_counts(_stock.export_counts())
	assert_eq(other.counts, _stock.counts)
