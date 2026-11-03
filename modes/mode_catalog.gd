class_name ModeCatalog
extends RefCounted
## Game modes, the formats they are played in (how many teams, how big) and the maps they fit.
## The main menu builds its Play flow from this, and the loading screen adds the chosen mode's
## script to the loaded map.

const MAPS: Dictionary = {
	"battlefield":
	{"name": "Backyard Garden", "scene": "res://scenes/garden_test.tscn", "size": "large"},
	"celestial_body":
	{"name": "Celestial Body", "scene": "res://scenes/celestial_body_test.tscn", "size": "small"},
	"terrarium":
	{"name": "Terrarium", "scene": "res://scenes/terrarium_test.tscn", "size": "small"},
	"fishbowl": {"name": "Fish Bowl", "scene": "res://scenes/fishbowl_test.tscn", "size": "small"},
	"crawlspace":
	{"name": "Crawlspace", "scene": "res://scenes/crawlspace_test.tscn", "size": "large"},
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

const ALL_MAPS: Array = ["battlefield", "celestial_body", "terrarium", "fishbowl", "crawlspace"]
const TEAM_FORMATS: Array = ["skirmish", "colony", "big_colony"]
const EVERY_FORMAT: Array = ["solo", "skirmish", "colony", "big_colony"]

## forced_character: the class every player uses in a colony match (the class picker is skipped).
## persistent: the world is saved per map (WorldSave) and comes back, seed and all, next time.
## shelved: finished and tested but off the menu for now. The front door is three modes (the
## order below) so players are not spread across seven queues; a shelved mode still loads by
## id, so the smoke test and the tests keep it working for the day it comes back.
const MODES: Dictionary = {
	"burrow":
	{
		"name": "Burrow",
		"description":
		(
			"Survival. Your workers carry the queen: lead them to good ground and found the "
			+ "colony. Dig by day, hold the burrow after dark. The map keeps it, saved as you go."
		),
		"script": "res://modes/burrow.gd",
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
		"script": "res://modes/hold_out.gd",
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
		"script": "res://modes/slayer.gd",
		"maps": ALL_MAPS,
		"formats": EVERY_FORMAT,
		"default_format": "skirmish",
		"forced_character": LoadingScreen.PlayerCharacter.ANT_WARRIOR,
	},
	"capture_the_egg":
	{
		"name": "Capture the Egg",
		"description":
		(
			"Carry the enemy colony's egg home while yours is on the nest. A fallen carrier "
			+ "drops it. First to 3."
		),
		"script": "res://modes/capture_the_egg.gd",
		"maps": ALL_MAPS,
		"formats": TEAM_FORMATS,
		"default_format": "skirmish",
		"forced_character": LoadingScreen.PlayerCharacter.ANT_WARRIOR,
		"shelved": true,
	},
	"king_of_the_anthill":
	{
		"name": "King of the Anthill",
		"description": "Hold the hill to score a point a second. The hill moves every minute.",
		"script": "res://modes/king_of_the_anthill.gd",
		"maps": ALL_MAPS,
		"formats": ["solo", "skirmish", "colony"],
		"default_format": "skirmish",
		"forced_character": LoadingScreen.PlayerCharacter.ANT_WARRIOR,
		"shelved": true,
	},
	"forage":
	{
		"name": "Forage",
		"description":
		(
			"Extraction. A dragonfly drops your squad of 4 on hostile ground. Gather the quota, "
			+ "stay quiet (noise brings the horde) and ride the dragonfly out from the beacon."
		),
		"script": "res://modes/forage.gd",
		"maps": ALL_MAPS,
		"shelved": true,
	},
	"cordyceps_royale":
	{
		"name": "Cordyceps Royale",
		"description":
		(
			"12 bugs, no respawns, and the storm is a cloud of Cordyceps spores. "
			+ "Bugs it takes come back as husks and hunt the clean. Last clean bug wins."
		),
		"script": "res://modes/cordyceps_royale.gd",
		"maps": ["battlefield", "terrarium", "fishbowl", "crawlspace"],
		"shelved": true,
	},
}


static func mode(mode_id: String) -> Dictionary:
	return MODES.get(mode_id, {})


## The modes on the menu, in menu order: every mode that is not shelved.
static func front_door() -> Array:
	var result: Array = []
	for mode_id: String in MODES:
		if not bool(MODES[mode_id].get("shelved", false)):
			result.append(mode_id)
	return result


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
