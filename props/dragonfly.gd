class_name Dragonfly
extends Node3D
## The squad's transport in Forage: a dragonfly the size of a bus that flies in from the edge of
## the map, hovers over a landing zone while bugs drop off or climb aboard, and flies out again.
## It has no physics. It follows the ground at a set height and stays under any lid or ceiling,
## so it works on every map: radial up on the celestial body, under the terrarium glass, beneath
## a crawlspace's joists. The model is built from primitives here; the wings beat in _process.

## On station over the landing zone (hovering).
signal arrived
## Gone: it reached its exit point and hid itself.
signal departed

enum State { IDLE, INBOUND, DESCENDING, HOVERING, ASCENDING, OUTBOUND }

const WING_FLAP_HZ: float = 22.0
const WING_FLAP_RADIANS: float = 0.4
const WING_SPAN: float = 4.4
const HOVER_BOB: float = 0.3
## Below the belly, where riders hang (and the local rider's camera orbits).
const SEAT_DROP: float = 3.0

var map: MapInfo
var cruise_speed: float = 24.0
var climb_speed: float = 9.0
## Heights above the ground: en route, and while on station.
var cruise_height: float = 18.0
var hover_height: float = 4.5
var state: State = State.IDLE

## Ground point under the landing zone, and the sky point to leave through.
var _landing: Vector3 = Vector3.ZERO
var _exit: Vector3 = Vector3.ZERO
var _heading: Vector3 = Vector3.FORWARD
var _hover_origin: Vector3 = Vector3.ZERO
var _time: float = 0.0
var _wing_pivots: Array[Node3D] = []


func _ready() -> void:
	_build_model()
	visible = false


func _process(delta: float) -> void:
	_time += delta
	var flap: float = sin(_time * TAU * WING_FLAP_HZ) * WING_FLAP_RADIANS
	for index: int in _wing_pivots.size():
		var side: float = 1.0 if index % 2 == 0 else -1.0
		_wing_pivots[index].rotation.z = flap * side


func _physics_process(delta: float) -> void:
	if state == State.IDLE or map == null:
		return
	var up: Vector3 = map.up_at(global_position)
	match state:
		State.INBOUND:
			if _cruise_toward(_landing, up, delta):
				state = State.DESCENDING
		State.DESCENDING:
			if _change_altitude(hover_height, up, delta):
				state = State.HOVERING
				_hover_origin = global_position
				arrived.emit()
		State.HOVERING:
			global_position = _hover_origin + up * (sin(_time * 2.0) * HOVER_BOB)
		State.ASCENDING:
			if _change_altitude(cruise_height, up, delta):
				state = State.OUTBOUND
		State.OUTBOUND:
			if _cruise_toward(_exit, up, delta):
				state = State.IDLE
				visible = false
				departed.emit()
	_face(up)


# --- Flying ------------------------------------------------------------------------------------


## Appears at a sky point and flies to hover over a ground point.
func fly_in(from: Vector3, landing: Vector3) -> void:
	_landing = landing
	global_position = _at_height(from, cruise_height)
	_heading = (landing - from).slide(map.up_at(from)).normalized()
	visible = true
	state = State.INBOUND


## Climbs off station and leaves through a sky point, then hides.
func fly_out(exit_point: Vector3) -> void:
	_exit = exit_point
	state = State.ASCENDING


func is_on_station() -> bool:
	return state == State.HOVERING


## Where a rider hangs: under the belly.
func seat_point() -> Vector3:
	return global_position - map.up_at(global_position) * SEAT_DROP


## Flies level toward the point above a ground point, keeping cruise height over whatever is
## below. True once it is over the point.
func _cruise_toward(ground_point: Vector3, up: Vector3, delta: float) -> bool:
	var to_target: Vector3 = (ground_point - global_position).slide(up)
	var distance: float = to_target.length()
	if distance < 1.0:
		return true
	var step: float = minf(cruise_speed * delta, distance)
	_heading = to_target / distance
	global_position += _heading * step
	_change_altitude(cruise_height, up, delta)
	return false


## Moves the body toward a height above the ground. True once it is there.
func _change_altitude(height: float, up: Vector3, delta: float) -> bool:
	var altitude: float = map.altitude(global_position)
	var wanted: float = _allowed_height(global_position, height)
	var change: float = clampf(wanted - altitude, -climb_speed * delta, climb_speed * delta)
	global_position = map.clamp_to_bounds(global_position + up * change)
	return absf(wanted - altitude) < 0.25


## A point lifted to a height above the ground under it (within the map's lid and ceiling).
func _at_height(point: Vector3, height: float) -> Vector3:
	var up: Vector3 = map.up_at(point)
	var lifted: Vector3 = point + up * (_allowed_height(point, height) - map.altitude(point))
	return map.clamp_to_bounds(lifted)


## The height to fly at over a point: the wanted one, lowered to fit under a terrarium lid or a
## crawlspace ceiling.
func _allowed_height(point: Vector3, height: float) -> float:
	if map.kind == MapInfo.Kind.CELESTIAL_BODY:
		return height
	var ground_y: float = point.y - map.altitude(point)
	var room: float = map.bounds.end.y - 1.5 - ground_y
	if map.ceiling_y < INF:
		room = minf(room, map.ceiling_y - 2.5 - ground_y)
	return clampf(height, 2.0, maxf(room, 2.0))


func _face(up: Vector3) -> void:
	var forward: Vector3 = _heading.slide(up)
	if forward.length_squared() < 0.0001:
		forward = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD)
	global_basis = Basis.looking_at(forward.normalized(), up)


# --- Model -------------------------------------------------------------------------------------


func _build_model() -> void:
	var shell: StandardMaterial3D = _material(Color(0.1, 0.5, 0.62), 0.55, 0.3)
	var dark: StandardMaterial3D = _material(Color(0.07, 0.2, 0.26), 0.4, 0.45)
	var eye: StandardMaterial3D = _material(Color(0.12, 0.1, 0.2), 0.8, 0.15)
	var wing := StandardMaterial3D.new()
	wing.albedo_color = Color(0.75, 0.9, 1.0, 0.3)
	wing.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wing.cull_mode = BaseMaterial3D.CULL_DISABLED
	wing.roughness = 0.2
	wing.metallic = 0.3

	# Thorax at the origin, head toward -Z (the way it flies), abdomen trailing behind.
	var thorax := SphereMesh.new()
	thorax.radius = 0.7
	thorax.height = 1.4
	_add_part(thorax, dark, Vector3.ZERO, Vector3(1.0, 0.9, 1.3))

	var abdomen := CapsuleMesh.new()
	abdomen.radius = 0.3
	abdomen.height = 4.6
	var lying := Basis(Vector3.RIGHT, PI * 0.5)
	_add_part(abdomen, shell, Vector3(0.0, 0.05, 2.9), Vector3.ONE, lying)

	var head := SphereMesh.new()
	head.radius = 0.55
	head.height = 1.1
	_add_part(head, dark, Vector3(0.0, 0.1, -1.1))
	var eyeball := SphereMesh.new()
	eyeball.radius = 0.32
	eyeball.height = 0.64
	_add_part(eyeball, eye, Vector3(0.32, 0.25, -1.35))
	_add_part(eyeball, eye, Vector3(-0.32, 0.25, -1.35))

	var leg := CylinderMesh.new()
	leg.top_radius = 0.045
	leg.bottom_radius = 0.03
	leg.height = 1.3
	for pair: int in 3:
		for side: float in [-1.0, 1.0]:
			var splay := Basis(Vector3.FORWARD, side * 0.35)
			_add_part(leg, dark, Vector3(side * 0.45, -0.8, -0.5 + pair * 0.5), Vector3.ONE, splay)

	var blade := BoxMesh.new()
	blade.size = Vector3(WING_SPAN, 0.02, 0.9)
	for row: int in 2:
		for side: float in [1.0, -1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(side * 0.35, 0.55, -0.35 + row * 0.75)
			add_child(pivot)
			var mesh := MeshInstance3D.new()
			mesh.mesh = blade
			mesh.material_override = wing
			mesh.position = Vector3(side * WING_SPAN * 0.5, 0.0, 0.0)
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pivot.add_child(mesh)
			_wing_pivots.append(pivot)


func _add_part(
	mesh: Mesh,
	material: Material,
	at: Vector3,
	scale_by: Vector3 = Vector3.ONE,
	orientation: Basis = Basis.IDENTITY
) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.transform = Transform3D(orientation.scaled(scale_by), at)
	add_child(part)


static func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material
