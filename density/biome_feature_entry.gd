@tool
class_name BiomeFeatureEntry
extends Resource
## One line of a biome's Features list: a feature and how often it shows in that biome.

@export var feature: BiomeFeature
## How often, from 0 (never) to 1 (as often as the feature allows). For termite mounds it is
## the share of mound sites (one in every 64 m square) where a mound stands.
@export_range(0.0, 1.0, 0.01) var density: float = 0.5


## The feature's data with this biome's density, and the feature itself as `source` so the
## terrain can leave out features its map does not list (it drops `source` before any worker
## thread sees the data). Empty when the entry has no feature.
func to_data() -> Dictionary:
	if feature == null:
		return {}
	var data: Dictionary = feature.to_data()
	data["density"] = density
	data["source"] = feature
	return data
