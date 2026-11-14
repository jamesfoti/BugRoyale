class_name QueenAnt
extends Node3D
## The queen: the colony's one life. Burrow opens with her still in her egg, a big pale egg
## wearing a little gold crown, riding on the player's back; the player fights as usual with it
## there. Wherever the player sets it down for good (found_colony, G), on level ground, it
## waits to be fed; the mode hatches it at a dawn once it has had its food (it rocks on the
## ground when it has), and the queen comes out on that spot to lay. Dropped when its bearer
## falls, the egg lies on the ground until a bug picks it up again. Out in the
## open, egg or queen, she is prey (hornets go for her); with ground standing over her (a
## burrow the player dug) she is out of their reach, and the queen mends there. If she dies
## the colony is over. The mode moves her: who carries the egg, when it is set down, whether
## she is sheltered.

## She has hatched where the egg was set down: from now on she lays.
signal hatched

enum State { CARRIED, DOWN, HATCHING, SETTLED }

const GROUP: StringName = &"queen"
const MAX_HEALTH: float = 160.0
## The egg on its bearer's back: this high over the bearer's position and this far behind.
const CARRY_HEIGHT: float = 0.4
const CARRY_BEHIND: float = 0.6
## How fast the queen mends once out and sheltered.
const MEND_PER_SECOND: float = 4.0
const BODY_COLOR := Color(0.93, 0.82, 0.58)
const EYE_COLOR := Color(0.12, 0.08, 0.05)
## The egg: bigger than a worker's egg (AntEgg), and its crown.
const EGG_RADIUS: float = 0.27
const EGG_STRETCH: float = 1.35
const SHELL_COLOR := Color(0.98, 0.95, 0.86)
const CROWN_COLOR := Color(1.0, 0.78, 0.2)
const GEM_COLOR := Color(0.85, 0.1, 0.15)
const CROWN_POINTS: int = 5

var state: State = State.CARRIED
var up: Vector3 = Vector3.UP
var health: Damageable
## Whoever carries the egg (the mode keeps this current); it rides on their back.
var bearer: Fighter
## Ground stands over her (the mode decides, every so often): out of the hornets' reach, and
## a hatched queen mends there.
var sheltered: bool = false
## The set-down egg has had its food (the mode keeps this current): it rocks, ready to hatch at
## dawn.
var fed: bool = false

var _time: float = 0.0
## The egg (shell and crown) and the queen's body, one shown at a time.
var _egg: Node3D
var _body: Node3D


## Puts the queen's egg on the map at a point, on a team (so the colony's own shots never hurt
## it).
static func spawn(parent: Node, at: Vector3, up_here: Vector3, team: int) -> QueenAnt:
	var queen := QueenAnt.new()
	queen.name = "Queen"
	queen.up = up_here
	queen._time = randf() * TAU
	parent.add_child(queen)
	queen.global_position = at
	queen.health.team = team
	return queen


func _ready() -> void:
	add_to_group(GROUP)
	health = Damageable.new()
	health.name = "Damageable"
	health.max_health = MAX_HEALTH
	add_child(health)
	_egg = _build_egg()
	_body = _build_body()
	_show_hatched(false)


func _process(delta: float) -> void:
	_time += delta
	match state:
		State.CARRIED:
			if bearer != null and bearer.is_alive():
				global_position = _on_back_of(bearer)
		State.HATCHING:
			# Fed, the shell rocks now and then: something inside is ready.
			var shake: float = 0.12 * maxf(sin(_time * 1.3), 0.0) if fed else 0.0
			_egg.rotation = Vector3(sin(_time * 21.0), 0.0, cos(_time * 17.0)) * shake
		State.SETTLED:
			if sheltered and health.is_alive():
				health.heal(MEND_PER_SECOND * delta)


# --- What the mode does with her -------------------------------------------------------------


## The egg rides on a bug's back.
func carried_by(fighter: Fighter) -> void:
	bearer = fighter
	state = State.CARRIED
	_egg.rotation = Vector3.ZERO
	if fighter != null and fighter.is_alive():
		global_position = _on_back_of(fighter)


## The egg lies on the ground at a point, for a bug to pick up.
func set_down(at: Vector3) -> void:
	bearer = null
	state = State.DOWN
	_egg.rotation = Vector3.ZERO
	global_position = at


## The egg is set down for good at a point, to wait there until it hatches.
func place(at: Vector3) -> void:
	bearer = null
	state = State.HATCHING
	global_position = at


## The set-down egg cracks open and the queen comes out (hatched, once).
func hatch() -> void:
	if state != State.HATCHING:
		return
	state = State.SETTLED
	_egg.rotation = Vector3.ZERO
	_show_hatched(true)
	hatched.emit()


## Already hatched (a saved colony): the queen at her spot.
func rest_at(at: Vector3) -> void:
	bearer = null
	state = State.SETTLED
	global_position = at
	_show_hatched(true)


func is_egg() -> bool:
	return state != State.SETTLED


func is_alive() -> bool:
	return health != null and health.is_alive()


func _show_hatched(out: bool) -> void:
	_egg.visible = not out
	_body.visible = out


## Over a bug's back: above it and behind the way it looks, with a little bob.
func _on_back_of(fighter: Fighter) -> Vector3:
	var behind: Vector3 = -fighter.body.get_view_flat_forward() * CARRY_BEHIND
	return fighter.get_position() + behind + up * (CARRY_HEIGHT + 0.04 * sin(_time * 6.0))


# --- Looks --------------------------------------------------------------------------------------


## The way she stands: across, up and forward along the map's up here.
func _frame() -> Basis:
	var side: Vector3 = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD)
	side = side.normalized()
	var forward: Vector3 = side.cross(up).normalized()
	return Basis(side, up, forward)


## A big pale egg standing on its end, a gold crown on its top: a band with CROWN_POINTS
## points round the rim and a red gem on the front, sitting a little askew.
func _build_egg() -> Node3D:
	var egg := Node3D.new()
	egg.name = "Egg"
	add_child(egg)
	var frame: Basis = _frame()
	var shell := _material(SHELL_COLOR, 0.4, 0.2)
	var gold := _material(CROWN_COLOR, 0.25, 0.35)
	gold.metallic = 0.9
	var gem := _material(GEM_COLOR, 0.15, 0.5)
	var height: float = EGG_RADIUS * EGG_STRETCH
	_add_part(egg, _sphere(EGG_RADIUS, shell), frame, up * height, Vector3(1.0, EGG_STRETCH, 1.0))

	var crown := Node3D.new()
	crown.name = "Crown"
	egg.add_child(crown)
	crown.transform = Transform3D(
		frame * Basis(Vector3.FORWARD, deg_to_rad(12.0)), up * (height * 2.0 - 0.06)
	)
	var band := CylinderMesh.new()
	band.top_radius = 0.17
	band.bottom_radius = 0.15
	band.height = 0.09
	band.material = gold
	_add_part(crown, band, Basis(), Vector3.UP * 0.045, Vector3.ONE)
	for point: int in CROWN_POINTS:
		var angle: float = TAU * float(point) / float(CROWN_POINTS)
		var spike := CylinderMesh.new()
		spike.top_radius = 0.0
		spike.bottom_radius = 0.05
		spike.height = 0.13
		spike.radial_segments = 4
		spike.material = gold
		var rim := Vector3(sin(angle), 0.0, cos(angle)) * 0.15
		_add_part(crown, spike, Basis(), rim + Vector3.UP * 0.15, Vector3.ONE)
		_add_part(crown, _sphere(0.022, gold), Basis(), rim + Vector3.UP * 0.225, Vector3.ONE)
	_add_part(
		crown, _sphere(0.035, gem), Basis(), Vector3(0.0, 0.045, 0.165), Vector3(1.0, 1.0, 0.6)
	)
	return egg


## A pale, heavy ant: a long abdomen, a thorax, a head with two dark eyes and antennae, all
## standing along the map's up here.
func _build_body() -> Node3D:
	var body := Node3D.new()
	body.name = "Body"
	add_child(body)
	var skin := _material(BODY_COLOR, 0.55, 0.15)
	var dark := _material(EYE_COLOR, 0.3, 0.0)
	var frame: Basis = _frame()
	var side: Vector3 = frame.x
	var forward: Vector3 = frame.z
	var lift: Vector3 = up * 0.45

	_add_part(body, _sphere(0.5, skin), frame, lift - forward * 0.6, Vector3(1.0, 0.85, 1.7))
	_add_part(body, _sphere(0.32, skin), frame, lift + forward * 0.25, Vector3(1.0, 0.9, 1.1))
	_add_part(body, _sphere(0.26, skin), frame, lift + forward * 0.75 + up * 0.05, Vector3.ONE)
	for mirror: float in [-1.0, 1.0]:
		_add_part(
			body,
			_sphere(0.06, dark),
			frame,
			lift + forward * 0.95 + side * 0.14 * mirror + up * 0.1,
			Vector3.ONE
		)
		var antenna := CapsuleMesh.new()
		antenna.radius = 0.025
		antenna.height = 0.6
		antenna.material = dark
		var piece: MeshInstance3D = _add_part(
			body,
			antenna,
			frame,
			lift + forward * 1.05 + side * 0.12 * mirror + up * 0.35,
			Vector3.ONE
		)
		piece.rotate_object_local(Vector3.RIGHT, deg_to_rad(-50.0))
		piece.rotate_object_local(Vector3.FORWARD, deg_to_rad(25.0 * mirror))
	return body


func _material(color: Color, roughness: float, glow: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	return material


func _sphere(radius: float, material: Material) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.material = material
	return mesh


func _add_part(
	parent: Node3D, mesh: Mesh, frame: Basis, offset: Vector3, stretch: Vector3
) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.transform = Transform3D(frame * Basis.from_scale(stretch), offset)
	parent.add_child(part)
	return part
