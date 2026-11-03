class_name DayCycle
extends Node
## Day and night over a loaded map. The clock runs on every machine (the host's snapshot keeps
## them together); the map's sun swings from dawn to dusk, and the sky, the ambient light and a
## plain-colour background dim with it. After dark a faint moon lights the ground from the other
## side. Modes read daylight() and hear dusk and dawn.
##
## The map's own resources are left alone: the environment, its sky and the sky material are
## duplicated before anything is changed, so the main menu's sky stays bright.

signal dusk
signal dawn

## Seconds of daylight, then of night, in one cycle.
const DAY_SECONDS: float = 300.0
const NIGHT_SECONDS: float = 180.0
const CYCLE_SECONDS: float = DAY_SECONDS + NIGHT_SECONDS
## Ambient light and the sky fade over this long either side of dusk and dawn.
const TWILIGHT_SECONDS: float = 30.0
## The sun (and the moon) are at full strength this high above the horizon (sine of elevation).
const HORIZON_FADE: float = 0.2
const MOON_ENERGY: float = 0.07
const MOON_COLOR := Color(0.55, 0.65, 0.95)
## How dark ambient light and a plain background get at the bottom of the night.
const NIGHT_AMBIENT: float = 0.3
const NIGHT_BACKGROUND: float = 0.18
const NIGHT_SKY := Color(0.03, 0.04, 0.09)
const SKY_COLOR_PARAMETERS: Array[String] = [
	"sky_top_color", "sky_horizon_color", "ground_glow_color"
]

## Runs the clock faster (headless smoke tests); 1 is real time.
static var speed: float = 1.0

## Seconds into the cycle: 0 is dawn, DAY_SECONDS is dusk.
var time: float = DAY_SECONDS * 0.25
var running: bool = true

var _sun: DirectionalLight3D
## A sun that is a body in the sky (the celestial map's) keeps its aim and only dims.
var _sun_rotates: bool = true
var _sun_energy: float = 1.0
var _sun_color: Color = Color.WHITE
var _sun_east: Vector3 = Vector3.RIGHT
var _sun_north: Vector3 = Vector3.FORWARD
var _environment: Environment
var _ambient_energy: float = 1.0
var _background: Color = Color.BLACK
var _sky_material: ShaderMaterial
var _sky_colors: Dictionary = {}
var _was_night: bool = false


func _process(delta: float) -> void:
	if running:
		advance(delta * speed)
	_apply()


# --- The clock -----------------------------------------------------------------------------------


## Moves the clock on and reports what it crossed: 1 for dusk, 2 for dawn, 0 for neither.
func advance(seconds: float) -> int:
	time = fposmod(time + seconds, CYCLE_SECONDS)
	var night: bool = is_night()
	var crossed: int = 0
	if night and not _was_night:
		crossed = 1
		dusk.emit()
	elif _was_night and not night:
		crossed = 2
		dawn.emit()
	_was_night = night
	return crossed


## Sets the clock (a saved world, a host's snapshot) without ringing dusk or dawn.
func set_time(seconds: float) -> void:
	time = fposmod(seconds, CYCLE_SECONDS)
	_was_night = is_night()


func is_night() -> bool:
	return is_night_at(time)


func daylight() -> float:
	return daylight_at(time)


static func is_night_at(seconds: float) -> bool:
	return fposmod(seconds, CYCLE_SECONDS) >= DAY_SECONDS


## 1 by day, 0 by night, eased through the twilight around dusk and dawn.
static func daylight_at(seconds: float) -> float:
	var t: float = fposmod(seconds, CYCLE_SECONDS)
	var half: float = TWILIGHT_SECONDS * 0.5
	var after_dusk: float = smoothstep(DAY_SECONDS - half, DAY_SECONDS + half, t)
	# Dawn sits at both ends of the cycle: past midnight, t counts down to it from below zero.
	var midnight: float = DAY_SECONDS + NIGHT_SECONDS * 0.5
	var since_dawn: float = t if t < midnight else t - CYCLE_SECONDS
	var after_dawn: float = smoothstep(-half, half, since_dawn)
	return minf(1.0 - after_dusk, after_dawn)


## Seconds until the next dusk (by day) or dawn (by night).
static func seconds_to_change_at(seconds: float) -> float:
	var t: float = fposmod(seconds, CYCLE_SECONDS)
	return (DAY_SECONDS - t) if t < DAY_SECONDS else (CYCLE_SECONDS - t)


## "4:05": minutes and seconds.
static func clock_text(seconds: float) -> String:
	var whole: int = maxi(ceili(seconds), 0)
	return "%d:%02d" % [floori(whole / 60.0), whole % 60]


## Where the sun is from the ground (unit vector): on the east horizon at dawn, overhead at
## midday, on the west horizon at dusk and below the ground through the night.
static func sun_direction_at(seconds: float, east: Vector3, north: Vector3) -> Vector3:
	var t: float = fposmod(seconds, CYCLE_SECONDS)
	var angle: float
	if t < DAY_SECONDS:
		angle = PI * t / DAY_SECONDS
	else:
		angle = PI + PI * (t - DAY_SECONDS) / NIGHT_SECONDS
	# A touch of north keeps the sun off the zenith, so the light always has a horizontal
	# component to aim along.
	return (east * cos(angle) + Vector3.UP * sin(angle) + north * 0.3).normalized()


# --- The map -------------------------------------------------------------------------------------


## Finds the map's sun and environment and takes copies of what the cycle will change.
func attach(scene_root: Node) -> void:
	for node: Node in scene_root.find_children("*", "DirectionalLight3D", true, false):
		var light: DirectionalLight3D = node as DirectionalLight3D
		if _sun == null or light.get_parent() == scene_root:
			_sun = light
	if _sun != null:
		_sun_rotates = not (_sun.get_parent() is SunBody)
		_sun_energy = _sun.light_energy
		_sun_color = _sun.light_color
		var toward_sun: Vector3 = _sun.global_basis.z
		var flat: Vector3 = Vector3(toward_sun.x, 0.0, toward_sun.z)
		_sun_east = flat.normalized() if flat.length() > 0.01 else Vector3.RIGHT
		_sun_north = _sun_east.cross(Vector3.UP).normalized()
	var environments: Array[Node] = scene_root.find_children("*", "WorldEnvironment", true, false)
	if environments.is_empty() or (environments[0] as WorldEnvironment).environment == null:
		return
	var world_environment: WorldEnvironment = environments[0] as WorldEnvironment
	_environment = world_environment.environment.duplicate() as Environment
	world_environment.environment = _environment
	_ambient_energy = _environment.ambient_light_energy
	_background = _environment.background_color
	if _environment.sky != null and _environment.sky.sky_material is ShaderMaterial:
		var sky: Sky = _environment.sky.duplicate() as Sky
		_sky_material = sky.sky_material.duplicate() as ShaderMaterial
		sky.sky_material = _sky_material
		_environment.sky = sky
		for parameter: String in SKY_COLOR_PARAMETERS:
			var value: Variant = _sky_material.get_shader_parameter(parameter)
			if value is Color:
				_sky_colors[parameter] = value


func _apply() -> void:
	var light: float = daylight()
	var sun_direction: Vector3 = sun_direction_at(time, _sun_east, _sun_north)
	if _sun != null and is_instance_valid(_sun):
		var sun_up: float = clampf(sun_direction.y / HORIZON_FADE, 0.0, 1.0)
		var moon_up: float = clampf(-sun_direction.y / HORIZON_FADE, 0.0, 1.0)
		if _sun_rotates:
			var toward: Vector3 = sun_direction if sun_direction.y >= 0.0 else -sun_direction
			_sun.look_at(_sun.global_position - toward, Vector3.UP)
			_sun.light_energy = _sun_energy * sun_up + MOON_ENERGY * moon_up
			_sun.light_color = _sun_color.lerp(MOON_COLOR, moon_up)
		else:
			_sun.light_energy = (
				_sun_energy * lerpf(MOON_ENERGY / maxf(_sun_energy, 0.01), 1.0, light)
			)
	if _environment != null:
		_environment.ambient_light_energy = _ambient_energy * lerpf(NIGHT_AMBIENT, 1.0, light)
		if _environment.background_mode == Environment.BG_COLOR:
			_environment.background_color = _background * lerpf(NIGHT_BACKGROUND, 1.0, light)
	if _sky_material != null:
		_sky_material.set_shader_parameter("sun_direction", sun_direction)
		for parameter: String in _sky_colors:
			var day_color: Color = _sky_colors[parameter]
			_sky_material.set_shader_parameter(parameter, NIGHT_SKY.lerp(day_color, light))
