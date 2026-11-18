@tool
class_name BiomeFeature
extends Resource
## Something that stands, grows or lives in a biome: termite mounds, a kind of plant, a kind of
## creature. One resource in features/ holds what the thing is; a biome's Features list says
## how often it shows there (BiomeFeatureEntry), so the same feature can be in many biomes at
## different densities. A map raises only the features its terrain's Biome Features lists.

## Shown in the rebuild line and the inspector.
@export var feature_name: String = "feature"


## The feature as plain values, which the chunks' worker threads read instead of the resource.
## `type` says which builder raises it; `path` lets a script load the resource back.
func to_data() -> Dictionary:
	return {"type": "", "name": feature_name, "path": resource_path}
