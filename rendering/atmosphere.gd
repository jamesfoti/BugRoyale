class_name Atmosphere
extends Node
## The air the player sees through. Above ground, a haze in the map's own colour fades the far
## ground out (from HAZE_BEGIN to HAZE_END metres). Underground, under a roof of rock, it is
## dark: a black fog that closes in by DARK_END metres, short of the coarse chunks streamed
## round the player (ChunkedTerrainWorld.STREAM_ROUGH), so no cavern shows an end that is not
## built, and the ambient light drops. The camera is underground when the terrain stands over
## it and it is below the surface's height there (an open ravine is daylit); the look blends
## between the two over a second or so. Runs on a copy of the scene's environment, in the
## game only: the editor's view of a map is untouched.

## Metres from the camera where the haze above ground begins and where it is thickest, and
## how thick that is (1 hides the ground there).
const HAZE_BEGIN: float = 100.0
const HAZE_END: float = 600.0
const HAZE_DENSITY: float = 0.7
## The haze over a map drawn under a sky, a little paler than the sky's horizon.
const SKY_HAZE := Color(0.74, 0.83, 0.94)
## Underground: where the dark begins and where it is total, its colour, and how much of the
## ambient light is left.
const DARK_BEGIN: float = 6.0
const DARK_END: float = 90.0
const DARK_COLOR := Color(0.008, 0.008, 0.01)
const DARK_AMBIENT: float = 0.3
## Metres below the surface's height the camera must be, and the most terrain over it a ray
## up looks for, to count as underground.
const UNDER_DEPTH: float = 4.0
const ROOF_REACH: float = 300.0
## How fast the look follows the camera in or out of the ground, in full blends a second.
const BLEND_RATE: float = 1.2

var _environment: Environment
var _haze_color: Color
var _ambient_energy: float = 1.0
var _blend: float = 0.0


## Gives a scene's game view its atmosphere (the PlayerSpawner adds it with the player).
static func attach(scene_root: Node) -> Atmosphere:
	var atmosphere := Atmosphere.new()
	atmosphere.name = "Atmosphere"
	scene_root.add_child(atmosphere)
	return atmosphere


func _ready() -> void:
	var found: Array[Node] = get_parent().find_children("*", "WorldEnvironment", true, false)
	var world_environment: WorldEnvironment = (
		found.front() as WorldEnvironment if not found.is_empty() else null
	)
	if world_environment == null or world_environment.environment == null:
		set_process(false)
		return
	_environment = world_environment.environment.duplicate() as Environment
	world_environment.environment = _environment
	_ambient_energy = _environment.ambient_light_energy
	# Under a sky the haze is the sky's own; in a room or under a house, its dark.
	_haze_color = (
		SKY_HAZE
		if _environment.background_mode == Environment.BG_SKY
		else _environment.background_color
	)
	_environment.fog_enabled = true
	_environment.fog_mode = Environment.FOG_MODE_DEPTH
	_environment.fog_depth_curve = 1.0
	_environment.fog_light_energy = 1.0
	_environment.fog_sun_scatter = 0.0
	_apply()


func _process(delta: float) -> void:
	var target: float = 1.0 if _underground() else 0.0
	if is_equal_approx(target, _blend):
		return
	_blend = move_toward(_blend, target, delta * BLEND_RATE)
	_apply()


## Whether the camera is in the ground: below the surface's height by UNDER_DEPTH and under
## terrain.
func _underground() -> bool:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return false
	var at: Vector3 = camera.global_position
	var worlds: Array[ChunkedTerrainWorld] = MapInfo.terrain_worlds(get_tree())
	if worlds.is_empty():
		return false
	var terrain: ChunkedTerrainWorld = worlds[0]
	if not terrain.has_method("get_surface_height_at"):
		return false
	if at.y > float(terrain.call("get_surface_height_at", at)) - UNDER_DEPTH:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		at, at + Vector3.UP * ROOF_REACH, MapInfo.TERRAIN_LAYER
	)
	return not camera.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Sets the environment to the blend between the haze above ground and the dark under it.
func _apply() -> void:
	var t: float = smoothstep(0.0, 1.0, _blend)
	_environment.fog_light_color = _haze_color.lerp(DARK_COLOR, t)
	_environment.fog_depth_begin = lerpf(HAZE_BEGIN, DARK_BEGIN, t)
	_environment.fog_depth_end = lerpf(HAZE_END, DARK_END, t)
	_environment.fog_density = lerpf(HAZE_DENSITY, 1.0, t)
	_environment.fog_sky_affect = t
	_environment.ambient_light_energy = _ambient_energy * lerpf(1.0, DARK_AMBIENT, t)
