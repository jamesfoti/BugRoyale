class_name CarryItem
extends Area3D
## Something a bug carries for a mode: a colony's egg, the sugar cube, a fallen bug's antenna, a
## seed. On the ground it bobs and spins and reports who walks into it (the mode decides what
## that means); carried, it floats over the carrier's head so everyone can see who has it.

## A bug in play walked into the item while it lay on the ground.
signal touched(item: CarryItem, body: FighterBody)

enum Kind { EGG, SUGAR, ANTENNA, SEED }

const GROUP: StringName = &"carry_item"
const PICKUP_RADIUS: float = 1.2
const CARRY_HEIGHT: float = 2.0

var kind: Kind = Kind.EGG
## The team the item belongs to (an egg's colony), or -1.
var team: int = -1
var home: Vector3 = Vector3.ZERO
var color: Color = Color.WHITE
var up: Vector3 = Vector3.UP
## Whoever carries it; null on the ground.
var carrier: Fighter
## How long it has lain where it is (for returning a dropped egg).
var on_ground_seconds: float = 0.0

var _mesh: MeshInstance3D
var _time: float = 0.0


## Puts an item on the ground at a point; its home is where it was placed.
static func spawn(
	parent: Node, at: Vector3, item_kind: Kind, item_team: int, item_color: Color, up_here: Vector3
) -> CarryItem:
	var item := CarryItem.new()
	item.kind = item_kind
	item.team = item_team
	item.color = item_color
	item.up = up_here
	item.home = at
	item._time = randf() * TAU
	parent.add_child(item)
	item.global_position = at
	return item


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(group_for(kind))
	collision_layer = 0
	collision_mask = MapInfo.FIGHTER_LAYER
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PICKUP_RADIUS
	shape.shape = sphere
	add_child(shape)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _make_mesh()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	if is_carried():
		global_position = carrier.get_position() + up * (CARRY_HEIGHT + 0.1 * sin(_time * 3.0))
		_mesh.position = Vector3.ZERO
	else:
		on_ground_seconds += delta
		_mesh.position = up * (0.3 + 0.12 * sin(_time * 2.5))
	_mesh.global_rotate(up, delta * 1.5)


## The scene group for items of a kind ("egg", "sugar", "antenna", "seed"), for bots to find.
static func group_for(item_kind: Kind) -> StringName:
	match item_kind:
		Kind.SUGAR:
			return &"sugar"
		Kind.ANTENNA:
			return &"antenna"
		Kind.SEED:
			return &"seed"
	return &"egg"


func is_carried() -> bool:
	return carrier != null and carrier.is_valid()


func pick_up(fighter: Fighter) -> void:
	carrier = fighter
	set_deferred("monitoring", false)


## Back on the ground at a point.
func drop(at: Vector3) -> void:
	carrier = null
	global_position = at
	on_ground_seconds = 0.0
	set_deferred("monitoring", true)


func return_home() -> void:
	drop(home)


func is_at_home() -> bool:
	return not is_carried() and global_position.distance_to(home) < 2.0


func _on_body_entered(body: Node3D) -> void:
	if is_carried():
		return
	var fighter_body: FighterBody = body as FighterBody
	if fighter_body == null or not fighter_body.is_in_play():
		return
	touched.emit(self, fighter_body)


func _make_mesh() -> Mesh:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.6
	match kind:
		Kind.SUGAR:
			var cube := BoxMesh.new()
			cube.size = Vector3.ONE * 0.7
			material.roughness = 0.3
			cube.material = material
			return cube
		Kind.ANTENNA:
			var antenna := CapsuleMesh.new()
			antenna.radius = 0.08
			antenna.height = 1.0
			material.roughness = 0.6
			antenna.material = material
			return antenna
		Kind.SEED:
			var seed_mesh := CapsuleMesh.new()
			seed_mesh.radius = 0.22
			seed_mesh.height = 0.8
			material.roughness = 0.8
			seed_mesh.material = material
			return seed_mesh
	var egg := SphereMesh.new()
	egg.radius = 0.45
	egg.height = 1.2
	material.roughness = 0.4
	egg.material = material
	return egg
