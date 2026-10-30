class_name ForageMaterial
extends Area3D
## Something worth carrying home in Forage: a crumb, a grain of sugar or a seed lying on the
## ground. Any bug in play that walks into it reports the pickup; the mode (the host) decides
## whether it counts and takes the material off the map.

signal picked_up(material: ForageMaterial, body: FighterBody)

enum Kind { CRUMB, SUGAR, SEED }

const GROUP: StringName = &"forage_material"
const PICKUP_RADIUS: float = 1.1

var kind: Kind = Kind.CRUMB
## Up at this spot (radial on the celestial body), for the bob and the spin.
var up: Vector3 = Vector3.UP

var _mesh: MeshInstance3D
var _time: float = 0.0
var _taken: bool = false


## Puts a material on the map at a position (parent must be in the tree).
static func spawn(parent: Node, at: Vector3, kind: Kind, up_here: Vector3) -> ForageMaterial:
	var material := ForageMaterial.new()
	material.kind = kind
	material.up = up_here
	material._time = randf() * TAU
	parent.add_child(material)
	material.global_position = at
	return material


func _ready() -> void:
	add_to_group(GROUP)
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
	_mesh.position = up * (0.25 + 0.12 * sin(_time * 2.5))
	_mesh.global_rotate(up, delta * 1.2)


func is_taken() -> bool:
	return _taken


## Off the map; the pickup is done.
func take() -> void:
	if _taken:
		return
	_taken = true
	queue_free()


func _on_body_entered(body: Node3D) -> void:
	if _taken:
		return
	var fighter_body: FighterBody = body as FighterBody
	if fighter_body == null or not fighter_body.is_in_play():
		return
	picked_up.emit(self, fighter_body)


func _make_mesh() -> Mesh:
	var material := StandardMaterial3D.new()
	material.emission_enabled = true
	material.emission_energy_multiplier = 0.5
	match kind:
		Kind.SUGAR:
			var cube := BoxMesh.new()
			cube.size = Vector3.ONE * 0.5
			material.albedo_color = Color(0.95, 0.95, 1.0)
			material.emission = Color(0.6, 0.6, 0.8)
			material.roughness = 0.35
			cube.material = material
			return cube
		Kind.SEED:
			var seed_mesh := CapsuleMesh.new()
			seed_mesh.radius = 0.2
			seed_mesh.height = 0.75
			material.albedo_color = Color(0.45, 0.28, 0.12)
			material.emission = Color(0.3, 0.18, 0.05)
			material.roughness = 0.8
			seed_mesh.material = material
			return seed_mesh
	var crumb := SphereMesh.new()
	crumb.radius = 0.36
	crumb.height = 0.5
	material.albedo_color = Color(0.85, 0.62, 0.25)
	material.emission = Color(0.5, 0.35, 0.1)
	material.roughness = 0.9
	crumb.material = material
	return crumb
