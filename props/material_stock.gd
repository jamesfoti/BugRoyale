class_name MaterialStock
extends RefCounted
## What a bug has dug and not yet built with, by TerrainMaterials.Kind, and the rules that tie
## the stock to the pickaxe: a pickaxe carve pays out what it removed (the map's own ground
## counts as dirt; a crater blasted by a shot or an asteroid pays nothing), building spends the
## stock of the brush's material, and a build the stock cannot cover is refused through the
## terrain's edit gate. Hold Out and Burrow share it.

## The counts changed (a dig, a build, a bonus).
signal changed

## Of the voxels a build shape covers, the share that must be affordable (most are already solid).
const COST_ESTIMATE_SHARE: float = 0.5

## TerrainMaterials.Kind -> voxels in hand (every placeable kind is listed, at 0 to begin with).
var counts: Dictionary = {}

var _terrain: ChunkedTerrainWorld


func _init() -> void:
	for kind: int in TerrainMaterials.Kind.values():
		if kind != TerrainMaterials.Kind.NATURAL:
			counts[kind] = 0


## Gates a terrain's builds and hears its edits from now on (null leaves the stock passive).
func attach(terrain: ChunkedTerrainWorld) -> void:
	_terrain = terrain
	if _terrain == null:
		return
	_terrain.edit_gate = can_afford
	_terrain.edit_applied.connect(on_edit_applied)


## Voxels in hand of a kind (the map's own ground reads as dirt).
func count(kind: int) -> int:
	return int(counts.get(cost_kind(kind), 0))


## Pays in (or, negative, spends) voxels of a kind; the stock never goes below zero.
func add(kind: int, voxels: int) -> void:
	var paid: int = cost_kind(kind)
	counts[paid] = maxi(int(counts.get(paid, 0)) + voxels, 0)
	changed.emit()


## Building spends the stock of its material; a pickaxe carve pays out what came loose.
func on_edit_applied(edit: Dictionary) -> void:
	if bool(edit.get("add", false)):
		add(int(edit.get("material", TerrainMaterials.Kind.NATURAL)), -int(edit.get("added", 0)))
		return
	if str(edit.get("tool", "")) != TerrainBrush.PICKAXE_TOOL:
		return
	var removed: Dictionary = edit.get("removed", {})
	for kind: int in removed:
		add(kind, int(removed[kind]))


## The terrain's edit gate: a build goes through when the stock covers its estimated cost.
func can_afford(edit: Dictionary) -> bool:
	if _terrain == null:
		return true
	return affordable(edit, _terrain.get_voxel_size())


## can_afford with the voxel size given, so the rule can be checked without a terrain.
func affordable(edit: Dictionary, voxel_size: float) -> bool:
	if not bool(edit.get("add", false)):
		return true
	var needed: int = ceili(
		ChunkedTerrainWorld.estimate_voxels(edit, voxel_size) * COST_ESTIMATE_SHARE
	)
	return count(int(edit.get("material", TerrainMaterials.Kind.NATURAL))) >= needed


## The kind a build is paid for in: the map's own ground costs dirt.
static func cost_kind(kind: int) -> int:
	return TerrainMaterials.Kind.DIRT if kind == TerrainMaterials.Kind.NATURAL else kind


## The materials in hand, those with any: "Dirt 42, Stone 8".
func text() -> String:
	var parts: Array[String] = []
	for kind: int in counts:
		if int(counts[kind]) > 0:
			parts.append(
				(
					"%s %d"
					% [TerrainMaterials.display_name(kind as TerrainMaterials.Kind), counts[kind]]
				)
			)
	return ", ".join(parts) if not parts.is_empty() else "Nothing dug yet"


## The kinds with anything in hand (a fresh stock exports {}).
func export_counts() -> Dictionary:
	var result: Dictionary = {}
	for kind: int in counts:
		if int(counts[kind]) > 0:
			result[kind] = int(counts[kind])
	return result


func import_counts(state: Dictionary) -> void:
	for kind: Variant in state:
		counts[int(kind)] = int(state[kind])
	changed.emit()
