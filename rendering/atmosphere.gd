class_name Atmosphere
extends Node
## The air the player sees through. Above ground the air is clear once the map is built (the
## whole surface stands, so there is nothing to hide); while it still builds, a haze in the
## map's own colour closes in to hide where the built ground ends
## (ChunkedTerrainWorld.get_built_reach), opening as the build spreads and gone once it is
## done. Underground, under a roof of rock, it is dark: a black fog that closes in by
## DARK_END metres, short of the chunks streamed round the player
## (ChunkedTerrainWorld.STREAM_VIEW), so no cavern shows an end that is not built, and the
## ambient light drops. The camera is underground when the terrain stands over it and it is
## below the surface's height there (an open ravine is daylit); the look blends between the
## two over a second or so. A scene whose environment has a fog of its own (the crawlspace's
## dim air under the house) keeps it above ground as designed, with no haze over it; the
## dark underground thickens that fog instead (DARK_DENSITY). Runs on a copy of the scene's
## environment, in the game only: the editor's view of a map is untouched. Something else may
## put its own copy in (Burrow's DayCycle does, after this one): the atmosphere follows
## whichever environment the scene shows, and runs after everything else each frame
## (process_priority), dimming the ambient light the day cycle set rather than overwriting it.

## While the map builds: the haze's farthest reach (where it has thinned to nothing once the
## built edge is past it), and where it begins at most.
const HAZE_BEGIN: float = 100.0
const HAZE_END: float = 600.0
## The haze over a map drawn under a sky, a little paler than the sky's horizon.
const SKY_HAZE := Color(0.74, 0.83, 0.94)
## While the map builds: metres short of the built ground's edge the haze is total, the
## nearest it closes to, and how fast it follows the edge (metres a second).
const EDGE_MARGIN: float = 8.0
const EDGE_NEAREST: float = 60.0
const EDGE_RATE: float = 400.0
## Physics-free frames between looks at how far the built ground reaches.
const EDGE_EVERY: int = 10
## Underground: where the dark begins and where it is total, its colour, and how much of the
## ambient light is left. Total inside the 48 m the underground stands round the player, less
## the camera's arm behind it.
const DARK_BEGIN: float = 4.0
const DARK_END: float = 40.0
const DARK_COLOR := Color(0.008, 0.008, 0.01)
const DARK_AMBIENT: float = 0.3
## Underground in a scene with a fog of its own: the exponential fog's density there, all but
## total by DARK_END metres.
const DARK_DENSITY: float = 0.1
## Metres below the surface's height the camera must be, and the most terrain over it a ray
## up looks for, to count as underground.
const UNDER_DEPTH: float = 4.0
const ROOF_REACH: float = 300.0
## How fast the look follows the camera in or out of the ground, in full blends a second.
const BLEND_RATE: float = 1.2

var _world_environment: WorldEnvironment
var _environment: Environment
var _haze_color: Color
## The ambient light as the scene (or the day cycle, frame by frame) sets it, before the dark
## dims it, and the value last written over it.
var _ambient_energy: float = 1.0
var _ambient_written: float = -1.0
var _blend: float = 0.0
## The scene's own fog (exponential, as the scene set it): kept above ground instead of the
## haze. Its density, colour and sky share as the scene had them.
var _own_fog: bool = false
var _own_density: float = 0.0
var _own_color: Color = Color.BLACK
var _own_sky_affect: float = 0.0
## How far the built ground reaches round the camera (HAZE_END once the map is built, and the
## haze gone), and the frames since the edge was last looked at.
var _edge: float = HAZE_END
var _edge_target: float = HAZE_END
var _edge_tick: int = 0


## Gives a scene's game view its atmosphere (the PlayerSpawner adds it with the player).
static func attach(scene_root: Node) -> Atmosphere:
	var atmosphere := Atmosphere.new()
	atmosphere.name = "Atmosphere"
	atmosphere.process_priority = 100
	scene_root.add_child(atmosphere)
	return atmosphere


func _ready() -> void:
	var found: Array[Node] = get_parent().find_children("*", "WorldEnvironment", true, false)
	_world_environment = found.front() as WorldEnvironment if not found.is_empty() else null
	if _world_environment == null or _world_environment.environment == null:
		set_process(false)
		return
	_environment = _world_environment.environment.duplicate() as Environment
	_world_environment.environment = _environment
	_ambient_energy = _environment.ambient_light_energy
	_own_fog = (
		_environment.fog_enabled and _environment.fog_mode == Environment.FOG_MODE_EXPONENTIAL
	)
	if _own_fog:
		_own_density = _environment.fog_density
		_own_color = _environment.fog_light_color
		_own_sky_affect = _environment.fog_sky_affect
		_apply()
		return
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
	var adopted: bool = _follow_environment()
	_edge_tick += 1
	if not _own_fog and _edge_tick % EDGE_EVERY == 1:
		_edge_target = _built_edge()
	var target: float = 1.0 if _underground() else 0.0
	var settled: bool = is_equal_approx(target, _blend) and is_equal_approx(_edge, _edge_target)
	if not settled:
		_blend = move_toward(_blend, target, delta * BLEND_RATE)
		# Closing in is at once (no unbuilt edge shows); opening is gradual.
		if _edge_target < _edge:
			_edge = _edge_target
		else:
			_edge = move_toward(_edge, _edge_target, delta * EDGE_RATE)
	if not settled or adopted or _environment.ambient_light_energy != _ambient_written:
		_apply()


## Takes up the environment the scene shows now when something put another copy in (it is
## that one's own copy, already the game's, so it is worked on as it is). True when it did.
func _follow_environment() -> bool:
	var shown: Environment = _world_environment.environment
	if shown == null or shown == _environment:
		return false
	_environment = shown
	return true


## How far the haze may reach: HAZE_END, or short of the nearest ground the map's build has
## not laid yet.
func _built_edge() -> float:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return HAZE_END
	var reach: float = INF
	for terrain: ChunkedTerrainWorld in MapInfo.terrain_worlds(get_tree()):
		reach = minf(reach, terrain.get_built_reach(camera.global_position))
	return clampf(reach - EDGE_MARGIN, EDGE_NEAREST, HAZE_END)


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


## Sets the environment to the blend between the air above ground and the dark under it.
## Above ground the haze is total at the built edge while that is near, thins as the edge
## moves out past half of HAZE_END, and is gone at HAZE_END (the map built).
func _apply() -> void:
	var t: float = smoothstep(0.0, 1.0, _blend)
	if _environment.ambient_light_energy != _ambient_written:
		# Set by someone else since (the day cycle): that is the light to dim now.
		_ambient_energy = _environment.ambient_light_energy
	_environment.ambient_light_energy = _ambient_energy * lerpf(1.0, DARK_AMBIENT, t)
	_ambient_written = _environment.ambient_light_energy
	if _own_fog:
		_environment.fog_light_color = _own_color.lerp(DARK_COLOR, t)
		_environment.fog_density = lerpf(_own_density, DARK_DENSITY, t)
		_environment.fog_sky_affect = lerpf(_own_sky_affect, 1.0, t)
		return
	var haze_end: float = minf(HAZE_END, _edge)
	var haze_begin: float = minf(HAZE_BEGIN, haze_end * 0.4)
	var haze_density: float = clampf(2.0 - 2.0 * haze_end / HAZE_END, 0.0, 1.0)
	_environment.fog_light_color = _haze_color.lerp(DARK_COLOR, t)
	_environment.fog_depth_begin = lerpf(haze_begin, DARK_BEGIN, t)
	_environment.fog_depth_end = lerpf(haze_end, DARK_END, t)
	_environment.fog_density = lerpf(haze_density, 1.0, t)
	_environment.fog_sky_affect = t
	# Clear air: no fog at all, not a fog of no density.
	_environment.fog_enabled = _environment.fog_density > 0.0
