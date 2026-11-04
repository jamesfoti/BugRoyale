class_name AntEgg
extends Node3D
## An egg the queen laid, lying on the chamber floor until dawn hatches it. It can be hurt
## (a Damageable on the colony's team) so anything that gets down the shaft can end it; the
## mode listens for that and counts the loss. Pale, a little longer than it is wide, standing
## along the map's up here.

const GROUP: StringName = &"ant_egg"
const MAX_HEALTH: float = 30.0
const SHELL_COLOR := Color(0.97, 0.94, 0.86)
const RADIUS: float = 0.28

var health: Damageable
var up: Vector3 = Vector3.UP


## Puts an egg on the map at a point, on a team (the colony's own shots never hurt it).
static func spawn(parent: Node, at: Vector3, up_here: Vector3, team: int) -> AntEgg:
	var egg := AntEgg.new()
	egg.name = "Egg"
	egg.up = up_here
	parent.add_child(egg)
	egg.global_position = at
	egg.health.team = team
	return egg


func _ready() -> void:
	add_to_group(GROUP)
	health = Damageable.new()
	health.name = "Damageable"
	health.max_health = MAX_HEALTH
	add_child(health)
	var shell := StandardMaterial3D.new()
	shell.albedo_color = SHELL_COLOR
	shell.roughness = 0.4
	shell.emission_enabled = true
	shell.emission = SHELL_COLOR
	shell.emission_energy_multiplier = 0.2
	var mesh := SphereMesh.new()
	mesh.radius = RADIUS
	mesh.height = RADIUS * 2.0
	mesh.material = shell
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var side: Vector3 = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD)
	side = side.normalized()
	var forward: Vector3 = side.cross(up).normalized()
	part.transform = Transform3D(
		Basis(side, up, forward) * Basis.from_scale(Vector3(1.0, 1.35, 1.0)), up * RADIUS * 1.35
	)
	add_child(part)


func is_alive() -> bool:
	return health != null and health.is_alive()
