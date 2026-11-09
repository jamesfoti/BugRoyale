class_name ModeCatalog
extends RefCounted
## Game modes, the formats they are played in (how many teams, how big) and the maps they fit.
## The main menu builds its Play flow from this, and the loading screen adds the chosen mode's
## script to the loaded map.

const MAPS: Dictionary = {
	"battlefield":
	{"name": "Backyard Garden", "scene": "res://scenes/garden.tscn", "size": "large"},
	"terrarium": {"name": "Terrarium", "scene": "res://scenes/terrarium.tscn", "size": "large"},
	"crawlspace": {"name": "Crawlspace", "scene": "res://scenes/crawlspace.tscn", "size": "large"},
}

const SIZE_RANK: Dictionary = {"small": 0, "medium": 1, "large": 2}

## How a competitive mode is played: solo (every bug for itself) or two colonies of a size. A
## format wants a map at least as big as map_size. Co-op modes have no format: a squad of four.
const FORMATS: Dictionary = {
	"solo": {"name": "Solo", "short": "FFA", "teams": 0, "fighters": 10, "map_size": "small"},
	"skirmish":
	{"name": "Skirmish", "short": "4v4", "teams": 2, "team_size": 4, "map_size": "small"},
	"colony":
	{"name": "Colony", "short": "12v12", "teams": 2, "team_size": 12, "map_size": "large"},
	"big_colony":
	{"name": "Big Colony", "short": "24v24", "teams": 2, "team_size": 24, "map_size": "large"},
}

const ALL_MAPS: Array = ["battlefield", "terrarium", "crawlspace"]
const EVERY_FORMAT: Array = ["solo", "skirmish", "colony", "big_colony"]

## scene: the mode's scene, a single node carrying the mode script; its exported numbers
## are the mode's tuning, changed from the editor.
## forced_character: the class every player uses in a colony match (the class picker is skipped).
## persistent: the world is saved per map (WorldSave) and comes back, seed and all, next time.
const MODES: Dictionary = {
	"burrow":
	{
		"name": "Burrow",
		"description":
		(
			"Survival. Your workers carry the queen: lead them to good ground and found the "
			+ "colony. Dig by day, hold the burrow after dark. The map keeps it, saved as you go."
		),
		"scene": "res://modes/burrow.tscn",
		"maps": ALL_MAPS,
		"persistent": true,
	},
	"hold_out":
	{
		"name": "Hold Out",
		"description":
		(
			"You and 3 AI squadmates hold a spot against waves of hornets, husks and enemy "
			+ "ants. Between waves, dig: what you carve is what you build with."
		),
		"scene": "res://modes/hold_out.tscn",
		"maps": ALL_MAPS,
	},
	"slayer":
	{
		"name": "Slayer",
		"description":
		(
			"Deathmatch. Solo, every bug for itself; in colonies, Red soldier ants against "
			+ "Black ants. First to the kill limit."
		),
		"scene": "res://modes/slayer.tscn",
		"maps": ALL_MAPS,
		"formats": EVERY_FORMAT,
		"default_format": "skirmish",
		"forced_character": LoadingScreen.PlayerCharacter.ANT_WARRIOR,
	},
}


static func mode(mode_id: String) -> Dictionary:
	return MODES.get(mode_id, {})


## The modes on the menu, in menu order.
static func front_door() -> Array:
	return MODES.keys()


static func map_scene(map_id: String) -> String:
	return MAPS.get(map_id, {}).get("scene", "")


static func map_name(map_id: String) -> String:
	return MAPS.get(map_id, {}).get("name", map_id)


## The map id whose scene is at a path ("" if none).
static func map_id_for_scene(scene_path: String) -> String:
	for map_id: String in MAPS:
		if MAPS[map_id].get("scene", "") == scene_path:
			return map_id
	return ""


static func format(format_id: String) -> Dictionary:
	return FORMATS.get(format_id, {})


## The formats a mode can be played in (empty for a co-op or fixed mode).
static func formats_for(mode_id: String) -> Array:
	return mode(mode_id).get("formats", [])


static func default_format(mode_id: String) -> String:
	var info: Dictionary = mode(mode_id)
	var formats: Array = info.get("formats", [])
	return str(info.get("default_format", formats.front() if not formats.is_empty() else ""))


## The mode's maps big enough for a format (all of them without a format).
static func maps_for(mode_id: String, format_id: String) -> Array:
	var maps: Array = mode(mode_id).get("maps", [])
	var wanted: int = int(SIZE_RANK.get(format(format_id).get("map_size", "small"), 0))
	var result: Array = []
	for map_id: String in maps:
		if int(SIZE_RANK.get(MAPS.get(map_id, {}).get("size", "small"), 0)) >= wanted:
			result.append(map_id)
	return result
