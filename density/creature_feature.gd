@tool
class_name CreatureFeature
extends BiomeFeature
## Creatures that live in a biome: groups of a class of bug that wander near home, neutral to
## everyone until hurt. The one hurt and its kin near it then turn on the attacker for a while
## (BiomeCreatures spawns them once the terrain is built, CreatureBrain drives each). With a
## Home feature (termite mounds) a group lives at each of that feature's sites in the biomes
## that list this creature, the biome's density the share of sites with a group; without one, a
## group stands at that share of the sites of a 64 m grid over those biomes.

## The team every creature of any kind is on: they never hurt each other, and nothing counts
## them for a mode's teams.
const TEAM: int = 900
## The group every creature body joins; bots of a mode leave them out of their hunt.
const GROUP: StringName = &"neutral_creature"

## The class of bug, for its body, skin and health.
@export var character: LoadingScreen.PlayerCharacter = LoadingScreen.PlayerCharacter.TERMITE_SOLDIER
## A skin other than the class's bot skin (empty for that).
@export_file("*.tscn") var skin_path: String = ""
## The feature whose sites are home; none for anywhere in the biome.
@export var home: BiomeFeature
## How many in a group, fewest to most.
@export var group_size: Vector2i = Vector2i(2, 4)
## How far from home a creature wanders, in metres.
@export_range(2.0, 80.0, 1.0) var wander_radius: float = 18.0
## The bite: damage, seconds between bites and reach in metres.
@export_range(0.0, 100.0, 1.0) var bite_damage: float = 12.0
@export_range(0.1, 5.0, 0.1) var bite_cooldown: float = 1.0
@export_range(1.0, 6.0, 0.1) var bite_reach: float = 2.6
## How long a hurt creature hunts its attacker, and how near its kin must be to join in.
@export_range(1.0, 120.0, 1.0) var anger_seconds: float = 20.0
@export_range(0.0, 80.0, 1.0) var call_radius: float = 20.0
## The most of them on a map, so a big map stays cheap.
@export_range(0, 200, 1) var max_count: int = 30


func _init() -> void:
	feature_name = "creatures"


func to_data() -> Dictionary:
	var data: Dictionary = super.to_data()
	data["type"] = "creature"
	return data


## The bite as a bot weapon (BotBrain.weapon).
func bite() -> Dictionary:
	return {
		"damage": bite_damage,
		"cooldown": bite_cooldown,
		"range": bite_reach,
		"spread_degrees": 0.0,
		"melee": true,
	}
