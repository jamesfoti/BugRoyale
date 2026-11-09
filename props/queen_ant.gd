class_name QueenAnt
extends Node3D
## The queen: the colony's one life. At the start of Burrow the workers carry her over the
## ground and she rides on their backs; the player decides where she is set down, and the
## workers dig her chamber under that spot. On the surface she is prey (hornets go for her);
## settled underground she is out of their reach and mends. If she dies the colony is over.
## The mode moves her: who carries her, when she is set down, and the path she takes below.

enum State { CARRIED, DOWN, SETTLING, SETTLED }

const GROUP: StringName = &"queen"
const MAX_HEALTH: float = 160.0
## How high over the carriers' backs she rides, and how she rests on the ground.
const CARRY_HEIGHT: float = 1.0
const REST_HEIGHT: float = 0.45
## How fast she goes down the shaft once it is dug (m/s), and how fast she mends once settled.
const SETTLE_SPEED: float = 2.0
const MEND_PER_SECOND: float = 4.0
const BODY_COLOR := Color(0.93, 0.82, 0.58)
const EYE_COLOR := Color(0.12, 0.08, 0.05)
## The nest the workers dig for her: a shaft sloping down and away from the entrance, one carve
## per step, then the chamber. The radii were sized to the maps' old 2 m voxels (a 1.9 m carve
## was sure to take a voxel out); at 1 m they dig the same shaft, finer, wide enough for a bug
## to walk down.
const SHAFT_STEPS: int = 5
const SHAFT_STEP: float = 1.2
const SHAFT_RADIUS: float = 1.9
const CHAMBER_RADIUS: float = 3.2
const CHAMBER_DEPTH: float = 7.0

var state: State = State.CARRIED
var up: Vector3 = Vector3.UP
var health: Damageable
## Whoever carries her this frame (the mode keeps this current); she rides over their backs.
var bearers: Array[Fighter] = []

var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
var _time: float = 0.0


## Puts a queen on the map at a point, on a team (so the colony's own shots never hurt her).
static func spawn(parent: Node, at: Vector3, up_here: Vector3, team: int) -> QueenAnt:
	var queen := QueenAnt.new()
	queen.name = "Queen"
	queen.up = up_here
	queen._time = randf() * TAU
	parent.add_child(queen)
	queen.global_position = at
	queen.health.team = team
	return queen


## The carves that dig her nest: the shaft steps from the entrance, then the chamber. Pure
## geometry, so it can be tested without a map. Every carve is the pickaxe's (the dirt pays into
## the colony's stock).
static func nest_plan(entrance: Vector3, up_here: Vector3, direction: Vector3) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	var along: Vector3 = _tangent(direction, up_here)
	for step: int in SHAFT_STEPS + 1:
		var reach: float = SHAFT_STEP * float(step)
		var center: Vector3 = entrance + along * reach - up_here * reach * 0.9
		var carve: Dictionary = ChunkedTerrainWorld.sphere_edit(
			center, SHAFT_RADIUS, false, TerrainMaterials.Kind.NATURAL
		)
		carve["tool"] = TerrainBrush.PICKAXE_TOOL
		plan.append(carve)
	var chamber: Dictionary = ChunkedTerrainWorld.sphere_edit(
		chamber_center(entrance, up_here, direction),
		CHAMBER_RADIUS,
		false,
		TerrainMaterials.Kind.NATURAL
	)
	chamber["tool"] = TerrainBrush.PICKAXE_TOOL
	plan.append(chamber)
	return plan


static func chamber_center(entrance: Vector3, up_here: Vector3, direction: Vector3) -> Vector3:
	var along: Vector3 = _tangent(direction, up_here)
	return entrance + along * SHAFT_STEP * float(SHAFT_STEPS) - up_here * CHAMBER_DEPTH


## The way she goes below once the nest is dug: down the shaft to the chamber floor.
static func settle_path(
	entrance: Vector3, up_here: Vector3, direction: Vector3
) -> PackedVector3Array:
	var path := PackedVector3Array()
	for carve: Dictionary in nest_plan(entrance, up_here, direction):
		path.append(carve["position"])
	var floor_point: Vector3 = (
		chamber_center(entrance, up_here, direction) - up_here * (CHAMBER_RADIUS - 1.0)
	)
	path[path.size() - 1] = floor_point
	return path


## A unit vector along the ground from a wished direction (any direction when it has none).
static func _tangent(direction: Vector3, up_here: Vector3) -> Vector3:
	var along: Vector3 = direction.slide(up_here)
	if along.length_squared() < 0.0001:
		along = up_here.cross(Vector3.RIGHT if absf(up_here.x) < 0.9 else Vector3.FORWARD)
	return along.normalized()


func _ready() -> void:
	add_to_group(GROUP)
	health = Damageable.new()
	health.name = "Damageable"
	health.max_health = MAX_HEALTH
	add_child(health)
	_build_body()


func _process(delta: float) -> void:
	_time += delta
	match state:
		State.CARRIED:
			var centre: Vector3 = _bearers_centre()
			if centre != Vector3.INF:
				global_position = centre + up * (CARRY_HEIGHT + 0.08 * sin(_time * 4.0))
		State.DOWN:
			pass
		State.SETTLING:
			_descend(delta)
		State.SETTLED:
			if health.is_alive():
				health.heal(MEND_PER_SECOND * delta)


# --- What the mode does with her -------------------------------------------------------------


func carried_by(fighters: Array[Fighter]) -> void:
	bearers = fighters
	state = State.CARRIED


## Set down on the ground at a point.
func set_down(at: Vector3) -> void:
	bearers = []
	state = State.DOWN
	global_position = at + up * REST_HEIGHT


## Goes below along a path (the dug shaft) and settles at its end.
func settle_along(path: PackedVector3Array) -> void:
	bearers = []
	_path = path
	_path_index = 0
	state = State.SETTLING if not path.is_empty() else State.SETTLED


## Already below (a saved colony): straight to the chamber floor.
func rest_below(at: Vector3) -> void:
	bearers = []
	state = State.SETTLED
	global_position = at


func is_on_surface() -> bool:
	return state != State.SETTLED


func is_alive() -> bool:
	return health != null and health.is_alive()


func _descend(delta: float) -> void:
	var target: Vector3 = _path[_path_index]
	var step: float = SETTLE_SPEED * delta
	if global_position.distance_to(target) <= step:
		global_position = target
		_path_index += 1
		if _path_index >= _path.size():
			state = State.SETTLED
		return
	global_position += (target - global_position).normalized() * step


func _bearers_centre() -> Vector3:
	var total: Vector3 = Vector3.ZERO
	var count: int = 0
	for bearer: Fighter in bearers:
		if bearer.is_alive():
			total += bearer.get_position()
			count += 1
	return total / float(count) if count > 0 else Vector3.INF


# --- Looks --------------------------------------------------------------------------------------


## A pale, heavy ant: a long abdomen, a thorax, a head with two dark eyes and antennae, all
## standing along the map's up here.
func _build_body() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = BODY_COLOR
	skin.roughness = 0.55
	skin.emission_enabled = true
	skin.emission = BODY_COLOR
	skin.emission_energy_multiplier = 0.15
	var dark := StandardMaterial3D.new()
	dark.albedo_color = EYE_COLOR
	dark.roughness = 0.3
	var side: Vector3 = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD)
	side = side.normalized()
	var forward: Vector3 = side.cross(up).normalized()
	var frame := Basis(side, up, forward)

	_add_part(_sphere(0.5, skin), frame, -forward * 0.6, Vector3(1.0, 0.85, 1.7))
	_add_part(_sphere(0.32, skin), frame, forward * 0.25, Vector3(1.0, 0.9, 1.1))
	_add_part(_sphere(0.26, skin), frame, forward * 0.75 + up * 0.05, Vector3.ONE)
	for mirror: float in [-1.0, 1.0]:
		_add_part(
			_sphere(0.06, dark),
			frame,
			forward * 0.95 + side * 0.14 * mirror + up * 0.1,
			Vector3.ONE
		)
		var antenna := CapsuleMesh.new()
		antenna.radius = 0.025
		antenna.height = 0.6
		antenna.material = dark
		var piece: MeshInstance3D = _add_part(
			antenna, frame, forward * 1.05 + side * 0.12 * mirror + up * 0.35, Vector3.ONE
		)
		piece.rotate_object_local(Vector3.RIGHT, deg_to_rad(-50.0))
		piece.rotate_object_local(Vector3.FORWARD, deg_to_rad(25.0 * mirror))


func _sphere(radius: float, material: Material) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.material = material
	return mesh


func _add_part(mesh: Mesh, frame: Basis, offset: Vector3, stretch: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.transform = Transform3D(frame * Basis.from_scale(stretch), offset)
	add_child(part)
	return part
