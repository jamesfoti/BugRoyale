class_name CrawlspaceBuilder
extends Node3D
## Builds the crawlspace of a house over an OpenTerrain dirt floor: block piers carrying girders,
## floor joists and a plywood subfloor overhead, foundation walls around the edge with vents (and
## one access hatch) letting in cool daylight, drain pipes and a duct under the joists, a few bare
## bulbs, and inorganic debris on the dirt: rocks, loose blocks, bricks and lumber offcuts. No
## plants: nothing grows where the sun never reaches. Sized from the terrain's extents, so the
## same scene works for any grid.
##
## The joists and subfloor collide on MapInfo.STRUCTURE_LAYER: bugs bump into them, but ground
## probes (spawns, hornet altitude) look straight through to the dirt.

@export var terrain_path: NodePath = ^"../TerrainWorld"
@export_group("Framing")
@export var joist_depth: float = 1.0
@export var joist_width: float = 0.25
@export var joist_spacing: float = 1.8
@export var girder_rows: int = 3
@export var pier_spacing: float = 12.0
@export var pier_size: float = 1.6
@export_group("Foundation")
@export var wall_thickness: float = 1.2
@export var vent_spacing: float = 16.0
@export var vent_size: Vector2 = Vector2(3.0, 1.4)
@export_group("Debris")
@export var debris_seed: int = 7
@export var rock_count: int = 40
@export var block_count: int = 14
@export var brick_count: int = 18
@export var scrap_count: int = 16

const LUMBER_COLOR := Color(0.6, 0.47, 0.3)
const PLYWOOD_COLOR := Color(0.68, 0.56, 0.37)
const CONCRETE_COLOR := Color(0.56, 0.56, 0.53)
const BRICK_COLOR := Color(0.55, 0.27, 0.2)
const PVC_COLOR := Color(0.9, 0.9, 0.88)
const DUCT_COLOR := Color(0.6, 0.62, 0.66)
const ROCK_COLOR := Color(0.36, 0.34, 0.32)

var _terrain: OpenTerrain
var _center: Vector3
var _half: Vector3
## World Y of the top of the joists; the subfloor sits on it. Matches MapInfo's flat-map
## bounds top so hornets are clamped beneath it.
var _ceiling: float
var _rng := RandomNumberGenerator.new()
var _materials: Dictionary = {}


func _ready() -> void:
	add_to_group("map_ceiling")
	call_deferred("build")


func build() -> void:
	_terrain = get_node_or_null(terrain_path) as OpenTerrain
	if _terrain == null:
		push_warning("[Crawlspace] No OpenTerrain at %s; nothing built." % terrain_path)
		return
	for child: Node in get_children():
		child.queue_free()
	_rng.seed = debris_seed
	var extents: Vector3 = _terrain.get_world_extents()
	_center = _terrain.global_position
	_half = extents * 0.5
	_ceiling = _center.y + _half.y - 1.0

	_build_subfloor_and_joists(extents)
	_build_girders_and_piers(extents)
	_build_foundation_walls(extents)
	_build_services(extents)
	_build_bulbs(extents)
	_build_debris()
	print("[Crawlspace] Built %.0fx%.0f m crawlspace, ceiling at y=%.1f" % [extents.x, extents.z, _ceiling])


# --- Framing ----------------------------------------------------------------------------------

func _build_subfloor_and_joists(extents: Vector3) -> void:
	var framing := Node3D.new()
	framing.name = "Framing"
	add_child(framing)
	# Plywood subfloor on top of the joists.
	_box(framing, "Subfloor", Vector3(extents.x, 0.3, extents.z), Vector3(_center.x, _ceiling + 0.15, _center.z), _material(PLYWOOD_COLOR))
	# Joists run the full depth, drawn as one MultiMesh.
	var joist_mesh := BoxMesh.new()
	joist_mesh.size = Vector3(joist_width, joist_depth, extents.z)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = joist_mesh
	var count: int = int(floor((extents.x - wall_thickness * 2.0) / joist_spacing))
	multimesh.instance_count = count
	var first_x: float = _center.x - (count - 1) * joist_spacing * 0.5
	for index: int in count:
		multimesh.set_instance_transform(
			index, Transform3D(Basis.IDENTITY, Vector3(first_x + index * joist_spacing, _ceiling - joist_depth * 0.5, _center.z))
		)
	var joists := MultiMeshInstance3D.new()
	joists.name = "Joists"
	joists.multimesh = multimesh
	joists.material_override = _material(LUMBER_COLOR)
	framing.add_child(joists)
	# Rim joists along the two long edges.
	for sign: float in [-1.0, 1.0]:
		_box(
			framing, "RimJoist", Vector3(extents.x, joist_depth, joist_width),
			Vector3(_center.x, _ceiling - joist_depth * 0.5, _center.z + sign * (_half.z - wall_thickness - joist_width * 0.5)),
			_material(LUMBER_COLOR)
		)
	# One slab collider for the whole joist zone and subfloor, on the ceiling layer.
	_collider(framing, "CeilingCollider", Vector3(extents.x, joist_depth + 0.3, extents.z), Vector3(_center.x, _ceiling - joist_depth * 0.5 + 0.15, _center.z), MapInfo.STRUCTURE_LAYER)


func _build_girders_and_piers(extents: Vector3) -> void:
	var support := Node3D.new()
	support.name = "Support"
	add_child(support)
	var girder_depth: float = 1.2
	var girder_width: float = 0.4
	var girder_bottom: float = _ceiling - joist_depth - girder_depth
	for row: int in girder_rows:
		var z: float = _center.z - _half.z + extents.z * (row + 1) / (girder_rows + 1)
		_box(
			support, "Girder", Vector3(extents.x - wall_thickness * 2.0, girder_depth, girder_width),
			Vector3(_center.x, girder_bottom + girder_depth * 0.5, z), _material(LUMBER_COLOR), MapInfo.STRUCTURE_LAYER
		)
		var pier_count: int = int(floor((extents.x - wall_thickness * 2.0 - pier_spacing) / pier_spacing)) + 1
		var first_x: float = _center.x - (pier_count - 1) * pier_spacing * 0.5
		for index: int in pier_count:
			var x: float = first_x + index * pier_spacing
			var ground: float = _terrain.get_surface_height_at(Vector3(x, 0.0, z)) - 0.8
			var height: float = girder_bottom - ground
			_box(
				support, "Pier", Vector3(pier_size, height, pier_size), Vector3(x, ground + height * 0.5, z),
				_material(CONCRETE_COLOR), MapInfo.STRUCTURE_LAYER
			)
			# A wood cap plate between the block pier and the girder.
			_box(support, "PierCap", Vector3(pier_size + 0.2, 0.15, pier_size + 0.2), Vector3(x, girder_bottom - 0.075, z), _material(LUMBER_COLOR))


# --- Foundation -------------------------------------------------------------------------------

## Four walls from below the dirt up to the subfloor, each with vents, plus one access hatch.
func _build_foundation_walls(extents: Vector3) -> void:
	var foundation := Node3D.new()
	foundation.name = "Foundation"
	add_child(foundation)
	var bottom: float = _center.y - _half.y + 0.5
	var vent_bottom: float = _ceiling - joist_depth - 2.4
	var vent_top: float = vent_bottom + vent_size.y
	for wall: int in 4:
		var along_x: bool = wall < 2
		var side: float = -1.0 if wall % 2 == 0 else 1.0
		var length: float = extents.x if along_x else extents.z
		var openings: Array = []
		var vent_count: int = int(floor((length - 8.0) / vent_spacing))
		var first: float = -(vent_count - 1) * vent_spacing * 0.5
		for index: int in vent_count:
			openings.append([first + index * vent_spacing, vent_size.x, vent_bottom, vent_top, false])
		if wall == 3:
			# Access hatch in the +Z wall: dirt level up to the joists.
			openings.append([0.0, 4.5, _terrain.get_surface_height_at(Vector3(_center.x, 0.0, _center.z + _half.z)) - 0.3, _ceiling - joist_depth - 0.4, true])
		openings.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var offset: float = side * (_half.x if not along_x else _half.z) - side * wall_thickness * 0.5
		var cursor: float = -length * 0.5
		for opening: Array in openings:
			var left: float = opening[0] - opening[1] * 0.5
			_wall_piece(foundation, along_x, offset, cursor, left, bottom, _ceiling)
			# Sill and lintel around the opening.
			_wall_piece(foundation, along_x, offset, left, left + opening[1], bottom, opening[2])
			_wall_piece(foundation, along_x, offset, left, left + opening[1], opening[3], _ceiling)
			_opening_light(foundation, along_x, offset, opening[0], opening[2], opening[3], opening[1], side, opening[4])
			cursor = left + opening[1]
		_wall_piece(foundation, along_x, offset, cursor, length * 0.5, bottom, _ceiling)


func _wall_piece(parent: Node3D, along_x: bool, offset: float, from: float, to: float, y_bottom: float, y_top: float) -> void:
	if to - from < 0.01 or y_top - y_bottom < 0.01:
		return
	var mid: float = (from + to) * 0.5
	var size: Vector3
	var position: Vector3
	if along_x:
		size = Vector3(to - from, y_top - y_bottom, wall_thickness)
		position = Vector3(_center.x + mid, (y_top + y_bottom) * 0.5, _center.z + offset)
	else:
		size = Vector3(wall_thickness, y_top - y_bottom, to - from)
		position = Vector3(_center.x + offset, (y_top + y_bottom) * 0.5, _center.z + mid)
	_box(parent, "Wall", size, position, _material(CONCRETE_COLOR), MapInfo.STRUCTURE_LAYER)


## Daylight through an opening: a glowing panel in the wall plane and a spotlight shining in.
func _opening_light(parent: Node3D, along_x: bool, offset: float, along: float, y_bottom: float, y_top: float, width: float, side: float, hatch: bool) -> void:
	var height: float = y_top - y_bottom
	var center_y: float = (y_bottom + y_top) * 0.5
	var outward: Vector3 = Vector3(0.0, 0.0, side) if along_x else Vector3(side, 0.0, 0.0)
	var position: Vector3 = (
		Vector3(_center.x + along, center_y, _center.z + offset) if along_x
		else Vector3(_center.x + offset, center_y, _center.z + along)
	)
	var glow := MeshInstance3D.new()
	glow.name = "HatchGlow" if hatch else "VentGlow"
	var panel := BoxMesh.new()
	panel.size = Vector3(width, height, 0.1) if along_x else Vector3(0.1, height, width)
	glow.mesh = panel
	var glow_material := StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.albedo_color = Color(0.75, 0.85, 1.0) if not hatch else Color(1.0, 0.92, 0.75)
	glow.material_override = glow_material
	glow.position = position + outward * (wall_thickness * 0.5 - 0.05)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(glow)
	var light := SpotLight3D.new()
	light.name = "VentLight"
	light.light_color = Color(0.8, 0.88, 1.0) if not hatch else Color(1.0, 0.93, 0.8)
	light.light_energy = 4.0 if hatch else 2.5
	light.spot_range = 36.0 if hatch else 26.0
	light.spot_angle = 55.0
	light.spot_attenuation = 1.2
	light.shadow_enabled = hatch
	light.position = position - outward * (wall_thickness * 0.5 + 0.3)
	parent.add_child(light)
	light.look_at(light.position - outward + Vector3.DOWN * 0.35, Vector3.UP)


# --- Services and lights ----------------------------------------------------------------------

## Plumbing hangs below the girders (between the pier rows, so nothing runs through the
## framing): two black ABS drain lines along X in destructible sections, one with a drop to the
## dirt, red and blue PEX water lines running as hot/cold pairs, plus an indestructible round
## duct along Z threaded between the piers.
func _build_services(extents: Vector3) -> void:
	var services := Node3D.new()
	services.name = "Services"
	add_child(services)
	var girder_bottom: float = _ceiling - joist_depth - 1.2
	var row_gap: float = extents.z / (girder_rows + 1)
	var span: float = extents.x - wall_thickness * 2.0
	# Drains in the first and third gaps between pier rows.
	for index: int in 2:
		var z: float = _center.z - _half.z + row_gap * (0.5 + index * 2.0 + _rng.randf_range(-0.3, 0.3))
		var drain_y: float = girder_bottom - 0.8
		_run_line(services, UtilityPipe.Fluid.SEWAGE, 0.3, drain_y, z, span, "Drain%d" % index)
		if index == 0:
			# A drop line down into the dirt, in its own section.
			var x: float = _center.x + _rng.randf_range(-_half.x * 0.5, _half.x * 0.5)
			var ground: float = _terrain.get_surface_height_at(Vector3(x, 0.0, z))
			var drop: UtilityPipe = UtilityPipe.create(UtilityPipe.Fluid.SEWAGE, drain_y - ground + 0.5, 0.3, ground)
			drop.name = "DropPipe"
			drop.position = Vector3(x, (drain_y + ground - 0.5) * 0.5, z)
			services.add_child(drop)
	# PEX hot/cold pairs in the second and fourth gaps, hot on one side, cold 0.7 m over, with a
	# yellow gas line a little further along.
	for index: int in 2:
		var z: float = _center.z - _half.z + row_gap * (1.5 + index * 2.0 + _rng.randf_range(-0.3, 0.3))
		var water_y: float = girder_bottom - 0.5
		_run_line(services, UtilityPipe.Fluid.HOT_WATER, 0.15, water_y, z - 0.35, span, "HotWater%d" % index)
		_run_line(services, UtilityPipe.Fluid.COLD_WATER, 0.15, water_y, z + 0.35, span, "ColdWater%d" % index)
		_run_line(services, UtilityPipe.Fluid.GAS, 0.12, water_y - 0.4, z + 1.6, span, "Gas%d" % index)
	# A round duct along Z, halfway between two piers so it threads past every row.
	var duct_x: float = _center.x + pier_spacing * 0.5 + pier_spacing * float(_rng.randi_range(-2, 1))
	_cylinder(services, "Duct", 1.0, extents.z - wall_thickness * 2.0, Vector3(duct_x, girder_bottom - 1.4, _center.z), Vector3(PI * 0.5, 0.0, 0.0), _material(DUCT_COLOR, 0.3))


## A line along X made of destructible sections, with a hanger strap up to the joists at each
## joint.
func _run_line(parent: Node3D, fluid: UtilityPipe.Fluid, pipe_radius: float, y: float, z: float, span: float, line_name: String) -> void:
	var strap_material: Material = _material(Color(0.3, 0.3, 0.32), 0.5)
	var joist_bottom: float = _ceiling - joist_depth
	var section_count: int = maxi(int(round(span / 8.0)), 1)
	var section_length: float = span / section_count
	for section: int in section_count:
		var x: float = _center.x - span * 0.5 + section_length * (section + 0.5)
		var dirt: float = _terrain.get_surface_height_at(Vector3(x, 0.0, z))
		var pipe: UtilityPipe = UtilityPipe.create(fluid, section_length, pipe_radius, dirt)
		pipe.name = "%s_%d" % [line_name, section]
		pipe.position = Vector3(x, y, z)
		pipe.rotation = Vector3(0.0, 0.0, PI * 0.5)
		parent.add_child(pipe)
		_box(parent, "Hanger", Vector3(0.06, joist_bottom - y, pipe_radius * 2.0 + 0.1), Vector3(x - section_length * 0.5, (joist_bottom + y) * 0.5, z), strap_material)


func _build_bulbs(extents: Vector3) -> void:
	var lights := Node3D.new()
	lights.name = "Bulbs"
	add_child(lights)
	var hang: float = _ceiling - joist_depth - 0.6
	for x_sign: float in [-1.0, 1.0]:
		for z_sign: float in [-1.0, 1.0]:
			var position := Vector3(_center.x + x_sign * extents.x * 0.25, hang, _center.z + z_sign * extents.z * 0.25)
			_cylinder(lights, "Cord", 0.03, 0.6, position + Vector3.UP * 0.4, Vector3.ZERO, _material(Color(0.12, 0.12, 0.12)))
			var bulb := MeshInstance3D.new()
			bulb.name = "Bulb"
			var sphere := SphereMesh.new()
			sphere.radius = 0.22
			sphere.height = 0.44
			bulb.mesh = sphere
			var glow := StandardMaterial3D.new()
			glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			glow.albedo_color = Color(1.0, 0.92, 0.7)
			bulb.material_override = glow
			bulb.position = position
			bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lights.add_child(bulb)
			var light := OmniLight3D.new()
			light.name = "BulbLight"
			light.light_color = Color(1.0, 0.85, 0.6)
			light.light_energy = 3.0
			light.omni_range = 36.0
			light.omni_attenuation = 1.3
			light.shadow_enabled = true
			light.position = position
			lights.add_child(light)


# --- Debris -----------------------------------------------------------------------------------

func _build_debris() -> void:
	var debris := Node3D.new()
	debris.name = "Debris"
	add_child(debris)
	var rock: Dictionary = AsteroidMeshBuilder.build(debris_seed, 1.0, 1, 0.35)
	var rock_mesh: Mesh = rock["mesh"]
	for _rock: int in rock_count:
		var spot: Vector3 = _ground_spot()
		var size: float = _rng.randf_range(0.35, 1.5)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Rock"
		mesh_instance.mesh = rock_mesh
		mesh_instance.material_override = _material(ROCK_COLOR * _rng.randf_range(0.8, 1.15))
		mesh_instance.scale = Vector3(size * _rng.randf_range(0.8, 1.3), size * _rng.randf_range(0.6, 1.0), size * _rng.randf_range(0.8, 1.3))
		mesh_instance.position = spot - Vector3.UP * size * 0.3
		mesh_instance.rotation.y = _rng.randf() * TAU
		debris.add_child(mesh_instance)
		if size > 0.9:
			var body := StaticBody3D.new()
			body.collision_layer = MapInfo.TERRAIN_LAYER
			body.collision_mask = 0
			var shape := CollisionShape3D.new()
			shape.shape = rock["shape"]
			body.add_child(shape)
			mesh_instance.add_child(body)
	for _block: int in block_count:
		_tumbled_box(debris, "Block", Vector3(1.6, 0.8, 0.8), CONCRETE_COLOR, true)
	for _brick: int in brick_count:
		_tumbled_box(debris, "Brick", Vector3(0.8, 0.25, 0.4), BRICK_COLOR, false)
	for _scrap: int in scrap_count:
		_tumbled_box(debris, "Scrap", Vector3(_rng.randf_range(1.5, 5.0), 0.15, 0.35), LUMBER_COLOR, false)


## A box lying on the dirt at a random spot and yaw, sometimes tipped on its side.
func _tumbled_box(parent: Node3D, box_name: String, size: Vector3, color: Color, collide: bool) -> void:
	var spot: Vector3 = _ground_spot()
	var tipped: bool = _rng.randf() < 0.3
	var basis: Basis = Basis(Vector3.UP, _rng.randf() * TAU)
	if tipped:
		basis = basis * Basis(Vector3.RIGHT, PI * 0.5)
	var rest_height: float = (size.z if tipped else size.y) * 0.5 - 0.05
	var box := _box(parent, box_name, size, spot + Vector3.UP * rest_height, _material(color * _rng.randf_range(0.85, 1.1)), MapInfo.TERRAIN_LAYER if collide else 0)
	box.basis = basis
	if collide:
		(box.get_child(0) as Node3D).basis = Basis.IDENTITY


func _ground_spot() -> Vector3:
	var margin: float = wall_thickness + 2.0
	var x: float = _center.x + _rng.randf_range(-_half.x + margin, _half.x - margin)
	var z: float = _center.z + _rng.randf_range(-_half.z + margin, _half.z - margin)
	return Vector3(x, _terrain.get_surface_height_at(Vector3(x, 0.0, z)), z)


# --- Helpers ----------------------------------------------------------------------------------

func _box(parent: Node3D, box_name: String, size: Vector3, position: Vector3, material: Material, collision_layer: int = 0) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = box_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.position = position
	parent.add_child(mesh_instance)
	if collision_layer != 0:
		var body := StaticBody3D.new()
		body.collision_layer = collision_layer
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
		mesh_instance.add_child(body)
	return mesh_instance


func _collider(parent: Node3D, body_name: String, size: Vector3, position: Vector3, collision_layer: int) -> void:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = collision_layer
	body.collision_mask = 0
	body.position = position
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	parent.add_child(body)


## A cylinder whose own axis is Y; rotation turns it to lie along X or Z.
func _cylinder(parent: Node3D, cylinder_name: String, radius: float, length: float, position: Vector3, rotation_radians: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = cylinder_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 14
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.position = position
	mesh_instance.rotation = rotation_radians
	parent.add_child(mesh_instance)


func _material(color: Color, roughness: float = 0.95) -> StandardMaterial3D:
	var key: String = "%s|%.2f" % [color.to_html(), roughness]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	_materials[key] = material
	return material
