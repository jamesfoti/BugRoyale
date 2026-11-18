@tool
class_name PlantFeature
extends BiomeFeature
## Something that grows on a biome's ground (or lies on it, as boulders do), drawn as fields of
## meshes by BiomePlants: the map is cut into cells `spacing` metres across, each with one
## jittered spot, and a spot grows one when its hash falls under the density the biome there
## gives the plant, the ground is not too steep, and it is open ground (not a termite mound's
## side or a ledge). Looks only: nothing collides with a plant.

enum Shape { GRASS, TALL_GRASS, FLOWERS, FERN, SHRUB, BOULDER, REEDS, CACTUS, TREE, MUSHROOM }

## The built-in mesh it grows as (PlantMeshes), unless Mesh is set.
@export var shape: Shape = Shape.GRASS
## Its main colour (leaves, petals, stone); trunks and stems keep their own.
@export var color: Color = Color(0.42, 0.62, 0.26)
## A mesh of its own instead of the shape, 1 m tall with its foot at the origin.
@export var mesh: Mesh
## How tall, in metres, shortest to tallest.
@export var height: Vector2 = Vector2(1.5, 3.0)
## How wide for its height (1 keeps the mesh's own shape).
@export_range(0.2, 4.0, 0.05) var girth: float = 1.0
## The cell size of its grid in metres: at density 1, one plant every this many metres.
@export_range(0.5, 64.0, 0.5) var spacing: float = 3.0
## The steepest ground it grows on.
@export_range(0.0, 90.0, 1.0) var max_slope_degrees: float = 35.0
## The deepest water it grows under (reeds stand in the shallows; most plants keep to dry land).
@export_range(0.0, 10.0, 0.1) var max_water_depth: float = 0.0
## How much each plant's colour strays from the next.
@export_range(0.0, 0.5, 0.01) var color_variation: float = 0.1
## How far it leans with the ground (0 upright, 1 square to the slope).
@export_range(0.0, 1.0, 0.05) var follow_slope: float = 0.3
@export var cast_shadows: bool = false
## Beyond this many metres from the camera it is not drawn.
@export_range(10.0, 3000.0, 10.0) var draw_distance: float = 150.0


func _init() -> void:
	feature_name = "plant"


func to_data() -> Dictionary:
	var data: Dictionary = super.to_data()
	data["type"] = "plant"
	return data
