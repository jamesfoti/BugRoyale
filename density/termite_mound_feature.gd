@tool
class_name TermiteMoundFeature
extends BiomeFeature
## Termite mounds: earth towers that are part of the ground (dug like any other), each hollow
## inside with holes round its foot, a chimney up a spire or a hollow heart in a dome, and a
## shaft down to a honeycomb nest under the ground. The terrain (`TermiteMounds` in the
## extension) builds them; the sizes here are ranges each mound draws from with its own hash.

## The share of mounds that are tall leaning spires; the rest are low lumpy domes.
@export_range(0.0, 1.0, 0.05) var spire_share: float = 0.5
## A spire's height and foot radius in metres, smallest to largest.
@export var spire_height: Vector2 = Vector2(20.0, 34.0)
@export var spire_radius: Vector2 = Vector2(6.0, 9.0)
## A dome's height and foot radius in metres, smallest to largest.
@export var dome_height: Vector2 = Vector2(10.0, 18.0)
@export var dome_radius: Vector2 = Vector2(9.0, 13.0)
## How far under the ground the nest's middle lies, and the nest's radius, in metres.
@export var nest_depth: Vector2 = Vector2(8.0, 12.0)
@export var nest_radius: Vector2 = Vector2(5.5, 8.0)


func _init() -> void:
	feature_name = "termite mounds"


func to_data() -> Dictionary:
	var data: Dictionary = super.to_data()
	data["type"] = "termite_mounds"
	data["spire_share"] = spire_share
	data["spire_height"] = spire_height
	data["spire_radius"] = spire_radius
	data["dome_height"] = dome_height
	data["dome_radius"] = dome_radius
	data["nest_depth"] = nest_depth
	data["nest_radius"] = nest_radius
	return data
