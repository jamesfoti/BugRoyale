class_name PlayerItems
extends RefCounted
## Hand-item ids and mapping to torch / terrain-edit behavior.

enum Item {
	NONE,
	TORCH,
	PICKAXE_DESTROY,
	PICKAXE_ADD,
	WEAPON_AK,
	WEAPON_GRENADE_LAUNCHER,
	WEAPON_PISTOL,
	WEAPON_ROCKET_LAUNCHER,
	WEAPON_SNIPER,
}

const WEAPON_ITEMS: Array[Item] = [
	Item.WEAPON_AK,
	Item.WEAPON_GRENADE_LAUNCHER,
	Item.WEAPON_PISTOL,
	Item.WEAPON_ROCKET_LAUNCHER,
	Item.WEAPON_SNIPER,
]

## Weapons that aim through a scope: the zoom ladder (fields of view in degrees, widest first;
## the scope key and the wheel step through them) and the reticle drawn over the view.
## Everything else aims over the shoulder only.
const WEAPON_SCOPES: Dictionary = {
	Item.WEAPON_SNIPER: {"fovs": [18.0, 9.0], "style": "sniper"},
	# The AK carries a 2.5x optic: the scoped assault rifle, one step only.
	Item.WEAPON_AK: {"fovs": [28.0], "style": "holo"},
}


static func item_from_edit_mode(mode: TerrainBrush.EditMode) -> Item:
	match mode:
		TerrainBrush.EditMode.DESTROY:
			return Item.PICKAXE_DESTROY
		TerrainBrush.EditMode.ADD:
			return Item.PICKAXE_ADD
	return Item.NONE


static func edit_mode_from_item(item: Item) -> TerrainBrush.EditMode:
	match item:
		Item.PICKAXE_DESTROY:
			return TerrainBrush.EditMode.DESTROY
		Item.PICKAXE_ADD:
			return TerrainBrush.EditMode.ADD
	return TerrainBrush.EditMode.OFF


static func is_weapon(item: Item) -> bool:
	return item in WEAPON_ITEMS


## Scoped fields of view in degrees, widest first; empty for a weapon without a scope.
static func scope_fovs(item: Item) -> PackedFloat32Array:
	return PackedFloat32Array(WEAPON_SCOPES.get(item, {}).get("fovs", []))


## Field of view of one zoom step (1 = first), or 0 for a weapon without a scope.
static func scope_fov(item: Item, level: int = 1) -> float:
	var fovs: PackedFloat32Array = scope_fovs(item)
	if fovs.is_empty():
		return 0.0
	return fovs[clampi(level, 1, fovs.size()) - 1]


## "sniper" (crosshair with range marks) or "holo" (ring and dot); "" without a scope.
static func scope_style(item: Item) -> String:
	return String(WEAPON_SCOPES.get(item, {}).get("style", ""))


static func weapon_mesh_name(item: Item) -> String:
	match item:
		Item.WEAPON_AK:
			return "AK"
		Item.WEAPON_GRENADE_LAUNCHER:
			return "GrenadeLauncher"
		Item.WEAPON_PISTOL:
			return "Pistol"
		Item.WEAPON_ROCKET_LAUNCHER:
			return "RocketLauncher"
		Item.WEAPON_SNIPER:
			return "Sniper"
	return ""


static func weapon_display_name(item: Item) -> String:
	match item:
		Item.WEAPON_AK:
			return "AK"
		Item.WEAPON_GRENADE_LAUNCHER:
			return "Grenade Launcher"
		Item.WEAPON_PISTOL:
			return "Pistol"
		Item.WEAPON_ROCKET_LAUNCHER:
			return "Rocket Launcher"
		Item.WEAPON_SNIPER:
			return "Sniper"
	return ""


static func apply_weapon_visual(skin: Node, item: Item) -> void:
	if skin != null and skin.has_method("set_equipped_weapon_from_item"):
		skin.call("set_equipped_weapon_from_item", item)
