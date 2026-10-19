extends RefCounted
class_name ModeCatalog
## Game modes and the maps they can be played on. The main menu builds its Play flow from this,
## and the loading screen adds the chosen mode's script to the loaded map.

const MAPS: Dictionary = {
	"battlefield": {"name": "Open Battlefield", "scene": "res://scenes/battlefield_terrain_test.tscn"},
	"celestial_body": {"name": "Celestial Body", "scene": "res://scenes/celestial_body_test.tscn"},
	"terrarium": {"name": "Terrarium", "scene": "res://scenes/terrarium_test.tscn"},
	"fishbowl": {"name": "Fish Bowl", "scene": "res://scenes/fishbowl_test.tscn"},
	"crawlspace": {"name": "Crawlspace", "scene": "res://scenes/crawlspace_test.tscn"},
}

## forced_character: the class every player uses in that mode (the class picker is skipped).
const MODES: Dictionary = {
	"hornets": {
		"name": "Attack of the Hornets",
		"description": "You and 3 AI squadmates hold out against ever-bigger hornet waves. Fallen squadmates return each wave.",
		"script": "res://modes/attack_of_the_hornets.gd",
		"maps": ["battlefield", "celestial_body", "terrarium", "fishbowl", "crawlspace"],
	},
	"ants_vs_ants": {
		"name": "Ants vs Ants",
		"description": "10 vs 10 team deathmatch: your Red colony against the Black colony. First to 40 kills wins.",
		"script": "res://modes/ants_vs_ants.gd",
		"maps": ["battlefield", "celestial_body", "terrarium", "fishbowl", "crawlspace"],
		"forced_character": LoadingScreen.PlayerCharacter.ANT_WARRIOR,
	},
	"battle_royale": {
		"name": "Battle Royale",
		"description": "12 bugs, one survivor. The terrarium floods in stages, so keep to high ground. No respawns.",
		"script": "res://modes/battle_royale.gd",
		"maps": ["terrarium", "fishbowl"],
	},
	"explore": {
		"name": "Explore",
		"description": "Walk any map with no enemies or AI: try the movement, climbing, flight, water and digging.",
		"script": "res://modes/explore.gd",
		"maps": ["battlefield", "celestial_body", "terrarium", "fishbowl", "crawlspace"],
	},
}


static func mode(mode_id: String) -> Dictionary:
	return MODES.get(mode_id, {})


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
