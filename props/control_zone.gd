class_name ControlZone
extends Node3D
## A patch of ground a team can hold: a hill, a nest, a territory. The mode tells it who is
## standing in it each frame (occupants by team) and it keeps the owner and the capture progress:
## one team alone inside for capture_seconds takes it, two teams inside freeze it (contested),
## and a locked zone (Land Grab) never changes hands again. Drawn as a ring on the ground and a
## beam in the owner's colour, with the beam fading toward the colour of whoever is taking it.

## The zone changed hands.
signal captured(zone: ControlZone, team: int)

const NEUTRAL: int = -1
const NEUTRAL_COLOR: Color = Color(0.7, 0.7, 0.7)

var radius: float = 6.0
var capture_seconds: float = 4.0
var owner_team: int = NEUTRAL
## 0..1 toward progress_team taking the zone.
var progress: float = 0.0
var progress_team: int = NEUTRAL
var contested: bool = false
var locked: bool = false
## Colour of a team (int -> Color), from the mode.
var color_for: Callable
var map: MapInfo

var _ring_material: StandardMaterial3D
var _beam_material: StandardMaterial3D


## Puts a zone in the map at a ground point.
static func place(
	parent: Node, map_info: MapInfo, point: Vector3, radius_m: float, colors: Callable
) -> ControlZone:
	var zone := ControlZone.new()
	zone.radius = radius_m
	zone.color_for = colors
	zone.map = map_info
	parent.add_child(zone)
	zone._build()
	zone.move_to(point)
	return zone


func move_to(point: Vector3) -> void:
	var up: Vector3 = map.up_at(point)
	var side: Vector3 = (
		up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	)
	global_transform = Transform3D(Basis(side, up, side.cross(up).normalized()), point)


## Whether a point stands in the zone (flat distance, with a little height tolerance).
func contains(point: Vector3) -> bool:
	var offset: Vector3 = point - global_position
	var up: Vector3 = global_basis.y
	return offset.slide(up).length() <= radius and absf(offset.dot(up)) <= 5.0


## Back to neutral, nothing in progress, open again.
func reset() -> void:
	owner_team = NEUTRAL
	progress = 0.0
	progress_team = NEUTRAL
	contested = false
	locked = false
	_refresh_colors()


## One frame of holding: occupants is team -> how many of them stand inside (zero counts left
## out). One team alone makes progress; two freeze it; the owner alone keeps it secure.
func update(occupants: Dictionary, delta: float) -> void:
	if locked:
		return
	var present: Array = []
	for team: int in occupants:
		if int(occupants[team]) > 0:
			present.append(team)
	contested = present.size() > 1
	if contested or present.is_empty():
		_refresh_colors()
		return
	var team: int = present[0]
	if team == owner_team:
		progress = 0.0
		progress_team = NEUTRAL
		_refresh_colors()
		return
	if progress_team != team:
		progress_team = team
		progress = 0.0
	progress = minf(progress + delta / capture_seconds, 1.0)
	if progress >= 1.0:
		owner_team = team
		progress = 0.0
		progress_team = NEUTRAL
		captured.emit(self, team)
	_refresh_colors()


func color_of(team: int) -> Color:
	if team == NEUTRAL or not color_for.is_valid():
		return NEUTRAL_COLOR
	return color_for.call(team)


func _build() -> void:
	var ring := CylinderMesh.new()
	ring.top_radius = radius
	ring.bottom_radius = radius
	ring.height = 0.25
	_ring_material = _translucent(0.3)
	ring.material = _ring_material
	var ring_mesh := MeshInstance3D.new()
	ring_mesh.mesh = ring
	ring_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring_mesh)

	var beam := CylinderMesh.new()
	beam.top_radius = 0.6
	beam.bottom_radius = 0.6
	beam.height = 30.0
	_beam_material = _translucent(0.25)
	beam.material = _beam_material
	var beam_mesh := MeshInstance3D.new()
	beam_mesh.mesh = beam
	beam_mesh.position = Vector3(0.0, 15.0, 0.0)
	beam_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam_mesh)
	_refresh_colors()


static func _translucent(alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission_energy_multiplier = 1.2
	material.albedo_color = Color(1.0, 1.0, 1.0, alpha)
	return material


func _refresh_colors() -> void:
	if _ring_material == null:
		return
	var owner_color: Color = color_of(owner_team)
	var beam_color: Color = owner_color
	if progress_team != NEUTRAL:
		beam_color = owner_color.lerp(color_of(progress_team), progress)
	if contested:
		beam_color = Color(1.0, 0.9, 0.3)
	_ring_material.albedo_color = Color(owner_color.r, owner_color.g, owner_color.b, 0.3)
	_ring_material.emission = owner_color
	_beam_material.albedo_color = Color(beam_color.r, beam_color.g, beam_color.b, 0.25)
	_beam_material.emission = beam_color
