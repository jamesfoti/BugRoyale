class_name CrawlspaceBuilder
extends Node3D
## Builds a patch of the crawlspace of a house over an OpenTerrain dirt floor: block piers
## carrying girders, floor joists and a plywood subfloor overhead, foundation walls around the
## edge with vents (and one access hatch) letting in cool daylight, plumbing and ductwork under
## the joists, a few bare bulbs, and inorganic debris on the dirt: rocks, loose blocks, bricks
## and lumber offcuts. No plants: nothing grows where the sun never reaches. Sized from the
## terrain's extents, so the same scene works for any grid.
##
## Every size in the exports is a real-world metre; the house is built at structure_scale times
## that while the bugs stay their own size. The default 100 matches the terrarium rooms (one
## world metre is one real centimetre): a block pier is 40 m across, the joists hang 50 m
## overhead, and the whole map is a five-metre patch of a real crawlspace.
##
## Framing, piers and walls collide on MapInfo.STRUCTURE_LAYER: bugs bump into them (and can
## climb them), but ground probes (spawns, hornet altitude) look straight through to the dirt.
##
## A storm rages outside: rain streaks across every vent, water streams in over the sills and
## lightning flashes through the openings. Flood water sits dormant under the dirt until a mode
## (Battle Royale) raises it; as it climbs, bulbs it reaches short out with a shock, and
## start_sewage_backup() makes the drains vent sewage onto the surface.

@export var terrain_path: NodePath = ^"../TerrainWorld"
## World metres per real metre. 100 matches the terrarium rooms' 1:100.
@export_range(1.0, 200.0, 1.0) var structure_scale: float = 100.0
## Dirt (mean level) to the top of the joists, in real metres.
@export var clearance: float = 0.9
## Rolls the framing grid per match within realistic ranges: beam rows, pier and joist spacing,
## vent spacing, which wall has the hatch, and the clearance. Off keeps the exports exactly.
@export var randomize_structure: bool = true
@export_group("Framing")
## A 2x10 joist on 16 inch centres.
@export var joist_depth: float = 0.24
@export var joist_width: float = 0.04
@export var joist_spacing: float = 0.4
## Built-up beams under the joists, on piers: a tapered concrete block with a 4x4 post.
@export var girder_rows: int = 2
@export var girder_depth: float = 0.24
@export var girder_width: float = 0.09
@export var pier_spacing: float = 1.2
## Pier block footprint at the dirt, its top, its height, and the post on it.
@export var pier_size: float = 0.45
@export var pier_block_top: float = 0.28
@export var pier_block_height: float = 0.25
@export var pier_post_size: float = 0.09
## Sill plate on the foundation wall, under the joists.
@export var sill_thickness: float = 0.04
@export_group("Foundation")
## Block masonry (mortar joints, stacked-block piers) or poured concrete (tapered piers with
## posts). RANDOM rolls one per match; piers and walls always match each other.
@export var masonry: Masonry = Masonry.RANDOM
@export var wall_thickness: float = 0.2
@export var vent_spacing: float = 1.8
@export var vent_size: Vector2 = Vector2(0.4, 0.2)
@export_group("Debris")
## Added to the terrain seed (randomised per match by the loading screen) for everything the
## builder scatters or rolls: debris, mushrooms, duct growth, masonry style.
@export var debris_seed: int = 7
@export var rock_count: int = 120
@export var block_count: int = 18
@export var brick_count: int = 28
@export var scrap_count: int = 20
## Clusters of mushrooms on the damp dirt (fungi grow where plants can't).
@export var mushroom_clusters: int = 16

const LUMBER_COLOR := Color(0.6, 0.47, 0.3)
const PLYWOOD_COLOR := Color(0.68, 0.56, 0.37)
const CONCRETE_COLOR := Color(0.56, 0.56, 0.53)
const BRICK_COLOR := Color(0.55, 0.27, 0.2)
const ROCK_COLOR := Color(0.36, 0.34, 0.32)
## Pipe radii in real metres: 4 inch ABS drain, 3/4 inch PEX, 1 inch gas.
const DRAIN_RADIUS: float = 0.05
const PEX_RADIUS: float = 0.01
const GAS_RADIUS: float = 0.0125

var _terrain: OpenTerrain
var _center: Vector3
var _half: Vector3
## Structure scale, copied at build time.
var _s: float = 1.0
## Seed for this build, and the masonry style it rolled.
var _seed: int = 0
var _block_masonry: bool = false
## Framing grid for this build (the exports, or per-match rolls).
var _girder_rows: int = 2
var _vent_spacing: float = 1.8
var _hatch_wall: int = 3
var _clearance: float = 0.9
## Scaled framing sizes.
var _joist_depth: float
var _joist_width: float
var _joist_spacing: float
var _pier_spacing: float
var _pier_size: float
var _wall: float
## World Y of the top of the joists; the subfloor sits on it.
var _ceiling: float
var _rng := RandomNumberGenerator.new()
var _materials: Dictionary = {}
var _water: TerrariumWater
## Vent and hatch openings: glow panel, spotlight and geometry, for the storm and lightning.
var _openings: Array[Dictionary] = []
## Bare bulbs: light, mesh and position, so the flood can short them.
var _bulbs: Array[Dictionary] = []
## Each drain line's height and z, where sewage backs up into a flood.
var _drain_lines: Array[Dictionary] = []
## Pier row z positions and pier x positions, so the ductwork can thread between them.
var _pier_rows: Array = []
var _pier_xs: Array = []
## Pier volumes, handed to the ductwork's network so flyers avoid them too.
var _pier_boxes: Array[AABB] = []
## Z of every main already laid, so the next one keeps its distance.
var _main_zs: Array = []
## The ductwork, whose solid volumes (ducts, furnace, piers) debris must keep out of.
var _network: DuctNetwork
var _lightning_in: float = 4.0
var _flash_left: float = 0.0
var _flashes_queued: int = 0
var _sewage_started: bool = false


func _ready() -> void:
	add_to_group("map_ceiling")
	add_to_group("crawlspace")
	call_deferred("build")


## Masonry rolled by the matches so far this session, so the style never repeats more than
## twice in a row: a fair coin alone can run the same way four or five matches straight.
static var _last_block_roll: int = -1
static var _block_roll_streak: int = 0


func _roll_masonry() -> bool:
	var block: bool = _rng.randf() < 0.5
	if int(block) == _last_block_roll and _block_roll_streak >= 2:
		block = not block
	if int(block) == _last_block_roll:
		_block_roll_streak += 1
	else:
		_block_roll_streak = 1
	_last_block_roll = int(block)
	return block


## World Y of the joists' underside: the map's ceiling for flyers.
func get_ceiling_y() -> float:
	return _ceiling - _joist_depth


## Lightning timing, and restoring the vents after a flash.
func _process(delta: float) -> void:
	if _openings.is_empty():
		return
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_set_lightning(false)
			if _flashes_queued > 0:
				_flashes_queued -= 1
				_lightning_in = _rng.randf_range(0.08, 0.2)
		return
	_lightning_in -= delta
	if _lightning_in <= 0.0:
		_set_lightning(true)
		_flash_left = _rng.randf_range(0.08, 0.16)
		if _flashes_queued == 0 and _rng.randf() < 0.5:
			_flashes_queued = 1
		else:
			_lightning_in = _rng.randf_range(5.0, 14.0)


## Bulbs the flood reaches short out.
func _physics_process(_delta: float) -> void:
	if _water == null or _bulbs.is_empty():
		return
	var surface: float = _water.get_water_surface_y()
	for bulb: Dictionary in _bulbs:
		if not bulb["live"]:
			continue
		if surface >= bulb["position"].y - 0.03 * _s:
			_short_bulb(bulb)


func build() -> void:
	_terrain = get_node_or_null(terrain_path) as OpenTerrain
	if _terrain == null:
		push_warning("[Crawlspace] No OpenTerrain at %s; nothing built." % terrain_path)
		return
	for child: Node in get_children():
		child.queue_free()
	# The loading screen randomises the terrain seed per match; a scene run straight from the
	# editor never passes through it, so roll a fresh seed there too.
	_seed = debris_seed + int(_terrain.noise_seed)
	if LoadingScreen.last_terrain_seed == 0:
		_seed += randi() % 1000000
	_rng.seed = _seed
	_block_masonry = masonry == Masonry.BLOCK or (masonry == Masonry.RANDOM and _roll_masonry())
	_s = structure_scale
	_joist_depth = joist_depth * _s
	_joist_width = joist_width * _s
	_joist_spacing = joist_spacing * _s
	_pier_spacing = pier_spacing * _s
	_pier_size = (0.4 if _block_masonry else pier_size) * _s
	_wall = wall_thickness * _s
	_girder_rows = girder_rows
	_vent_spacing = vent_spacing
	_hatch_wall = 3
	_clearance = clearance
	if randomize_structure:
		_girder_rows = [1, 2, 2, 3][_rng.randi() % 4]
		_pier_spacing = _rng.randf_range(1.0, 1.6) * _s
		_joist_spacing = (0.4 if _rng.randf() < 0.8 else 0.3) * _s
		_vent_spacing = _rng.randf_range(1.4, 2.4)
		_hatch_wall = _rng.randi() % 4
		_clearance = _rng.randf_range(0.8, 1.0)
	var extents: Vector3 = _terrain.get_world_extents()
	_center = _terrain.global_position
	_half = extents * 0.5
	_ceiling = _center.y + _clearance * _s

	_build_subfloor_and_joists(extents)
	_build_girders_and_piers(extents)
	_build_foundation_walls(extents)
	_build_services(extents)
	_build_bulbs(extents)
	_build_debris()
	_build_mushrooms()
	_build_flood_water(extents)
	_build_storm()
	print("[Crawlspace] Built %.0fx%.0f m crawlspace at 1:%.0f, joists %.0f m up, %s masonry, %d beam rows, piers every %.1f m, joists every %.1f m, vents every %.0f m, hatch on wall %d" % [extents.x, extents.z, _s, _ceiling - _joist_depth - _center.y, "block" if _block_masonry else "poured", _girder_rows, _pier_spacing, _joist_spacing, _vent_spacing * _s, _hatch_wall])


# --- Flood and storm --------------------------------------------------------------------------

## Flood water filling the foundation box, parked under the lowest dirt until a mode raises it.
## Its height range runs from under the dirt to just below the joists, so Battle Royale's level
## fractions mean the same thing here as in the terrarium. Tinted to murky storm runoff.
func _build_flood_water(extents: Vector3) -> void:
	var floor_y: float = _center.y - 0.15 * _s
	var size := Vector3(extents.x - _wall * 2.0, (_ceiling - _joist_depth - 0.06 * _s) - floor_y, extents.z - _wall * 2.0)
	_water = TerrariumWater.create(size, 0.05)
	_water.position = Vector3(_center.x, floor_y, _center.z)
	add_child(_water)
	var surface: MeshInstance3D = _water.get_node_or_null("WaterSurface") as MeshInstance3D
	if surface != null and surface.material_override is ShaderMaterial:
		var material: ShaderMaterial = surface.material_override as ShaderMaterial
		material.set_shader_parameter("base_color", Color(0.24, 0.28, 0.18))
		material.set_shader_parameter("shine_color", Color(0.6, 0.62, 0.5))
	var volume: MeshInstance3D = _water.get_node_or_null("WaterVolume") as MeshInstance3D
	if volume != null and volume.material_override is ShaderMaterial:
		var material: ShaderMaterial = volume.material_override as ShaderMaterial
		material.set_shader_parameter("base_color", Color(0.18, 0.21, 0.13))
		material.set_shader_parameter("deep_color", Color(0.08, 0.1, 0.06))
		material.set_shader_parameter("surface_alpha", 0.5)


## Rain across every opening and water streaming in over each sill.
func _build_storm() -> void:
	var storm := Node3D.new()
	storm.name = "Storm"
	add_child(storm)
	for opening: Dictionary in _openings:
		var rain: GPUParticles3D = _make_rain(opening["width"], opening["height"])
		# Outside the wall, in front of the daylight panel, so it reads as rain beyond the vent.
		rain.position = opening["position"] + opening["outward"] * (_wall * 0.5 + 0.05 * _s) + Vector3.UP * (opening["height"] * 0.5 + 0.1 * _s)
		storm.add_child(rain)
		# Drips run down the inside face of the opening, in its plane, from the lintel to the
		# dirt below the sill.
		# Water blown in over the sill runs off its inner edge and down the inside face of the
		# wall to the dirt. (The hatch's sill is at the dirt, so it gets no drips.)
		var drip_top: Vector3 = opening["position"] - opening["outward"] * (_wall * 0.5 + 0.01 * _s) - Vector3.UP * (opening["height"] * 0.5)
		var dirt_below: float = _terrain.get_surface_height_at(drip_top)
		if drip_top.y - dirt_below < 1.0:
			continue
		var stream: GPUParticles3D = _make_stream(opening["width"], opening["outward"], drip_top.y - dirt_below)
		stream.position = drip_top
		storm.add_child(stream)


## Raindrops at bug scale: streaks a few tens of centimetres across falling fast.
func _make_rain(width: float, height: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Rain"
	particles.amount = int(clampf(width * height * 0.12, 24.0, 200.0))
	var fall_speed: float = 0.45 * _s
	particles.lifetime = maxf((height + 0.2 * _s) / fall_speed, 0.15)
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-width, -height - 0.1 * _s, -0.2 * _s), Vector3(width * 2.0, height + 0.2 * _s, 0.4 * _s))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(width * 0.5, 0.05, 0.02 * _s)
	process.direction = Vector3.DOWN
	process.spread = 3.0
	process.initial_velocity_min = fall_speed
	process.initial_velocity_max = fall_speed * 1.25
	process.gravity = Vector3.ZERO
	process.color = Color(0.5, 0.6, 0.78, 0.9)
	particles.process_material = process
	var streak := BoxMesh.new()
	streak.size = Vector3(0.003, 0.03, 0.003) * _s
	particles.draw_pass_1 = streak
	particles.material_override = _storm_material()
	return particles


## A sheet of drips the width of an opening, falling straight down its inner face (parallel to
## the wall) for `fall` metres. `outward` is the wall's normal, so the sheet lies across it.
func _make_stream(width: float, outward: Vector3, fall: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Stream"
	particles.amount = int(clampf(width * fall * 0.05, 32.0, 160.0))
	particles.lifetime = sqrt(2.0 * maxf(fall, 1.0) / 9.8) + 0.3
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-width, -fall - 1.0, -width), Vector3(width * 2.0, fall + 2.0, width * 2.0))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# Thin along the wall's normal, wide across the opening.
	var across: Vector3 = Vector3(absf(outward.z), 0.0, absf(outward.x))
	process.emission_box_extents = across * width * 0.48 + Vector3(absf(outward.x), 0.0, absf(outward.z)) * 0.01 * _s + Vector3(0.0, 0.05, 0.0)
	process.direction = Vector3.DOWN
	process.spread = 1.5
	process.initial_velocity_min = 0.01 * _s
	process.initial_velocity_max = 0.03 * _s
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.2
	process.color = Color(0.6, 0.72, 0.85)
	particles.process_material = process
	var drop := SphereMesh.new()
	drop.radius = 0.004 * _s
	drop.height = drop.radius * 2.0
	drop.radial_segments = 6
	drop.rings = 3
	particles.draw_pass_1 = drop
	particles.material_override = _storm_material()
	return particles


func _storm_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	return material


func _set_lightning(on: bool) -> void:
	for opening: Dictionary in _openings:
		var glow: StandardMaterial3D = opening["glow_material"]
		glow.albedo_color = Color(1.0, 1.0, 1.0) if on else opening["glow_color"]
		var light: SpotLight3D = opening["light"]
		if light != null:
			light.light_energy = opening["light_energy"] * (5.0 if on else 1.0)


## A flooded bulb pops: a flash, then dark, with a brief shock on the water around it.
func _short_bulb(bulb: Dictionary) -> void:
	bulb["live"] = false
	var light: OmniLight3D = bulb["light"]
	var tween: Tween = create_tween()
	tween.tween_property(light, "light_energy", 7.0, 0.08)
	tween.tween_property(light, "light_energy", 0.0, 0.25)
	var mesh: MeshInstance3D = bulb["mesh"]
	var dead := StandardMaterial3D.new()
	dead.albedo_color = Color(0.22, 0.22, 0.2)
	mesh.material_override = dead
	var shock: FluidPool = FluidPool.create(0.5 * _s, 15.0, 1.5, Color(0.7, 0.85, 1.0), true)
	shock.grow_seconds = 0.2
	shock.surface_water = _water
	add_child(shock)
	shock.global_position = Vector3(bulb["position"].x, _water.get_water_surface_y(), bulb["position"].z)


## The drains back up: sewage spreads over the flood surface along each drain line, hurting
## anyone swimming through it. Called by Battle Royale once the water is well up.
func start_sewage_backup() -> void:
	if _sewage_started or _water == null:
		return
	_sewage_started = true
	var span: float = _half.x * 2.0 - _wall * 2.0
	for line: Dictionary in _drain_lines:
		for index: int in 4:
			var x: float = _center.x - span * 0.5 + span * (index + 0.5) / 4.0 + _rng.randf_range(-0.3, 0.3) * _s
			var pool: FluidPool = FluidPool.create(0.55 * _s, 5.0, 600.0, Color(0.27, 0.3, 0.12))
			pool.grow_seconds = 12.0
			pool.surface_water = _water
			add_child(pool)
			pool.global_position = Vector3(x, _water.get_water_surface_y(), line["z"])


# --- Framing ----------------------------------------------------------------------------------

func _build_subfloor_and_joists(extents: Vector3) -> void:
	var framing := Node3D.new()
	framing.name = "Framing"
	add_child(framing)
	var subfloor: float = 0.02 * _s
	# Plywood subfloor on top of the joists.
	_box(framing, "Subfloor", Vector3(extents.x, subfloor, extents.z), Vector3(_center.x, _ceiling + subfloor * 0.5, _center.z), _material(PLYWOOD_COLOR, 0.95, Detail.WOOD, 0))
	# Joists run the full depth, drawn as one MultiMesh.
	var joist_mesh := BoxMesh.new()
	joist_mesh.size = Vector3(_joist_width, _joist_depth, extents.z)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = joist_mesh
	var count: int = int(floor((extents.x - _wall * 2.0) / _joist_spacing))
	multimesh.instance_count = count
	var first_x: float = _center.x - (count - 1) * _joist_spacing * 0.5
	for index: int in count:
		multimesh.set_instance_transform(
			index, Transform3D(Basis.IDENTITY, Vector3(first_x + index * _joist_spacing, _ceiling - _joist_depth * 0.5, _center.z))
		)
	var joists := MultiMeshInstance3D.new()
	joists.name = "Joists"
	joists.multimesh = multimesh
	joists.material_override = _wood(2)
	framing.add_child(joists)
	# Rim joists along the two long edges.
	for sign: float in [-1.0, 1.0]:
		_box(
			framing, "RimJoist", Vector3(extents.x, _joist_depth, _joist_width),
			Vector3(_center.x, _ceiling - _joist_depth * 0.5, _center.z + sign * (_half.z - _wall - _joist_width * 0.5)),
			_wood(0)
		)
	# One slab collider for the whole joist zone and subfloor, on the structure layer.
	_collider(framing, "CeilingCollider", Vector3(extents.x, _joist_depth + subfloor, extents.z), Vector3(_center.x, _ceiling - _joist_depth * 0.5 + subfloor * 0.5, _center.z), MapInfo.STRUCTURE_LAYER)


## Girders flush with the joists (the joists hang on them), each on a row of block piers.
## Built-up beams under the joists, each on a row of piers. A pier is a tapered concrete block
## set into the dirt with a 4x4 post on top, the way older houses are propped: the block's
## shoulders give bugs a ledge to climb onto.
func _build_girders_and_piers(extents: Vector3) -> void:
	var support := Node3D.new()
	support.name = "Support"
	add_child(support)
	var girder_top: float = _ceiling - _joist_depth
	var girder_bottom: float = girder_top - girder_depth * _s
	var block_base: float = _pier_size
	var block_top: float = pier_block_top * _s
	var block_height: float = pier_block_height * _s
	var post: float = pier_post_size * _s
	var block_mesh := CylinderMesh.new()
	# A four-sided cylinder is a square frustum; the radius is the corner distance.
	block_mesh.radial_segments = 4
	block_mesh.rings = 1
	block_mesh.bottom_radius = block_base * 0.5 * sqrt(2.0)
	block_mesh.top_radius = block_top * 0.5 * sqrt(2.0)
	block_mesh.height = block_height
	var block_shape: Shape3D = block_mesh.create_convex_shape(true)
	for row: int in _girder_rows:
		var z: float = _center.z - _half.z + extents.z * (row + 1) / (_girder_rows + 1)
		_box(
			support, "Girder", Vector3(extents.x - _wall * 2.0, girder_depth * _s, girder_width * _s),
			Vector3(_center.x, (girder_top + girder_bottom) * 0.5, z), _wood(0), MapInfo.STRUCTURE_LAYER
		)
		var pier_count: int = maxi(int(floor((extents.x - _wall * 2.0 - _pier_spacing) / _pier_spacing)) + 1, 2)
		var first_x: float = _center.x - (pier_count - 1) * _pier_spacing * 0.5
		_pier_rows.append(z)
		if _pier_xs.is_empty():
			for index: int in pier_count:
				_pier_xs.append(first_x + index * _pier_spacing)
		for index: int in pier_count:
			var x: float = first_x + index * _pier_spacing
			if _block_masonry:
				_build_block_pier(support, x, z, girder_bottom)
				continue
			# The block sits a little into the dirt; sample its footprint so no edge floats.
			var ground: float = _terrain.get_surface_height_at(Vector3(x, 0.0, z))
			for corner_x: float in [-1.0, 1.0]:
				for corner_z: float in [-1.0, 1.0]:
					ground = minf(ground, _terrain.get_surface_height_at(Vector3(x + corner_x * block_base * 0.5, 0.0, z + corner_z * block_base * 0.5)))
			ground -= 0.03 * _s
			var block := MeshInstance3D.new()
			block.name = "PierBlock"
			block.mesh = block_mesh
			block.material_override = _material(CONCRETE_COLOR, 0.95, Detail.CONCRETE)
			block.position = Vector3(x, ground + block_height * 0.5, z)
			block.rotation.y = PI * 0.25
			support.add_child(block)
			var body := StaticBody3D.new()
			body.collision_layer = MapInfo.STRUCTURE_LAYER
			body.collision_mask = 0
			var shape := CollisionShape3D.new()
			shape.shape = block_shape
			body.add_child(shape)
			block.add_child(body)
			var block_top_y: float = ground + block_height
			var post_height: float = maxf(girder_bottom - block_top_y, 0.02 * _s)
			_box(
				support, "PierPost", Vector3(post, post_height, post), Vector3(x, block_top_y + post_height * 0.5, z),
				_wood(1), MapInfo.STRUCTURE_LAYER
			)
			_pier_boxes.append(AABB(Vector3(x - block_base * 0.5, ground, z - block_base * 0.5), Vector3(block_base, block_height, block_base)))
			_pier_boxes.append(AABB(Vector3(x - post * 0.5, block_top_y, z - post * 0.5), Vector3(post, post_height, post)))


## A stacked-block pier: one 8x8x16 block per course, laid alternately, with a solid cap
## block under the beam. The masonry pattern draws the courses and joints.
func _build_block_pier(support: Node3D, x: float, z: float, girder_bottom: float) -> void:
	var footprint: float = 0.4 * _s
	var ground: float = _terrain.get_surface_height_at(Vector3(x, 0.0, z))
	for corner_x: float in [-1.0, 1.0]:
		for corner_z: float in [-1.0, 1.0]:
			ground = minf(ground, _terrain.get_surface_height_at(Vector3(x + corner_x * footprint * 0.5, 0.0, z + corner_z * footprint * 0.5)))
	ground -= 0.03 * _s
	var cap: float = 0.05 * _s
	# Whole courses, so the joints line up with the cap.
	var course: float = 0.2 * _s
	var height: float = floor((girder_bottom - cap - ground) / course) * course
	var cap_height: float = girder_bottom - (ground + height)
	_box(support, "PierBlocks", Vector3(footprint, height, footprint), Vector3(x, ground + height * 0.5, z), _material(CONCRETE_COLOR, 0.95, Detail.BLOCK), MapInfo.STRUCTURE_LAYER)
	_box(support, "PierCap", Vector3(footprint + 0.02 * _s, cap_height, footprint + 0.02 * _s), Vector3(x, ground + height + cap_height * 0.5, z), _material(CONCRETE_COLOR, 0.95, Detail.CONCRETE), MapInfo.STRUCTURE_LAYER)
	_pier_boxes.append(AABB(Vector3(x - footprint * 0.5, ground, z - footprint * 0.5), Vector3(footprint, height + cap_height, footprint)))


# --- Foundation -------------------------------------------------------------------------------

## Four walls from below the dirt up to the subfloor, each with vents, plus one access hatch.
func _build_foundation_walls(extents: Vector3) -> void:
	var foundation := Node3D.new()
	foundation.name = "Foundation"
	add_child(foundation)
	var bottom: float = _center.y - _half.y + 0.5
	# The wall stops under a sill plate; the joists bear on that.
	var wall_top: float = _ceiling - _joist_depth - sill_thickness * _s
	# Vents sit just under the sill, above grade.
	var vent_top: float = wall_top - 0.02 * _s
	var vent_bottom: float = vent_top - vent_size.y * _s
	var vent_width: float = vent_size.x * _s
	var spacing: float = _vent_spacing * _s
	for wall: int in 4:
		var along_x: bool = wall < 2
		var side: float = -1.0 if wall % 2 == 0 else 1.0
		var length: float = extents.x if along_x else extents.z
		var openings: Array = []
		var vent_count: int = maxi(int(floor((length - 0.8 * _s) / spacing)), 1)
		var first: float = -(vent_count - 1) * spacing * 0.5
		for index: int in vent_count:
			openings.append([first + index * spacing, vent_width, vent_bottom, vent_top, false])
		if wall == _hatch_wall:
			# Access hatch in the +Z wall: dirt level up to the joists.
			openings.append([0.0, 0.6 * _s, _terrain.get_surface_height_at(Vector3(_center.x, 0.0, _center.z + _half.z)) - 0.03 * _s, wall_top, true])
		openings.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var offset: float = side * (_half.x if not along_x else _half.z) - side * _wall * 0.5
		var cursor: float = -length * 0.5
		# Every opening glows, but only the hatch and one vent per wall cast light: each
		# spotlight is a whole extra lighting pass on an integrated GPU.
		var lit_vent: int = openings.size() / 2
		for index: int in openings.size():
			var opening: Array = openings[index]
			var left: float = maxf(opening[0] - opening[1] * 0.5, cursor)
			var right: float = left + opening[1]
			_wall_piece(foundation, along_x, offset, cursor, left, bottom, wall_top)
			# Sill and lintel around the opening.
			_wall_piece(foundation, along_x, offset, left, right, bottom, opening[2])
			_wall_piece(foundation, along_x, offset, left, right, opening[3], wall_top)
			var lit: bool = opening[4] or index == lit_vent
			_opening_light(foundation, along_x, offset, (left + right) * 0.5, opening[2], opening[3], opening[1], side, opening[4], lit)
			cursor = right
		_wall_piece(foundation, along_x, offset, cursor, length * 0.5, bottom, wall_top)
		# Sill plate along the top of the wall, with the joists resting on it.
		var sill: float = sill_thickness * _s
		var plate_size: Vector3 = Vector3(length, sill, _wall) if along_x else Vector3(_wall, sill, length)
		var plate_position: Vector3 = (
			Vector3(_center.x, wall_top + sill * 0.5, _center.z + offset) if along_x
			else Vector3(_center.x + offset, wall_top + sill * 0.5, _center.z)
		)
		_box(foundation, "SillPlate", plate_size, plate_position, _wood(0 if along_x else 2), MapInfo.STRUCTURE_LAYER)


func _wall_piece(parent: Node3D, along_x: bool, offset: float, from: float, to: float, y_bottom: float, y_top: float) -> void:
	if to - from < 0.01 or y_top - y_bottom < 0.01:
		return
	var mid: float = (from + to) * 0.5
	var size: Vector3
	var position: Vector3
	if along_x:
		size = Vector3(to - from, y_top - y_bottom, _wall)
		position = Vector3(_center.x + mid, (y_top + y_bottom) * 0.5, _center.z + offset)
	else:
		size = Vector3(_wall, y_top - y_bottom, to - from)
		position = Vector3(_center.x + offset, (y_top + y_bottom) * 0.5, _center.z + mid)
	_box(parent, "Wall", size, position, _material(CONCRETE_COLOR, 0.95, Detail.BLOCK if _block_masonry else Detail.POURED), MapInfo.STRUCTURE_LAYER)


## Daylight through an opening: a glowing panel in the wall plane and, when `lit`, a spotlight
## shining in.
func _opening_light(parent: Node3D, along_x: bool, offset: float, along: float, y_bottom: float, y_top: float, width: float, side: float, hatch: bool, lit: bool) -> void:
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
	var panel_depth: float = 0.02 * _s
	panel.size = Vector3(width, height, panel_depth) if along_x else Vector3(panel_depth, height, width)
	glow.mesh = panel
	var glow_material := StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.albedo_color = Color(0.75, 0.85, 1.0) if not hatch else Color(1.0, 0.92, 0.75)
	glow.material_override = glow_material
	# Set out past the wall so the rain can fall between the opening and the sky.
	glow.position = position + outward * (_wall * 0.5 + 0.1 * _s)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(glow)
	var light: SpotLight3D = null
	if lit:
		light = SpotLight3D.new()
		light.name = "VentLight"
		light.light_color = Color(0.8, 0.88, 1.0) if not hatch else Color(1.0, 0.93, 0.8)
		light.light_energy = 4.0 if hatch else 3.0
		light.spot_range = (2.5 if hatch else 1.8) * _s
		light.spot_angle = 55.0
		light.spot_attenuation = 1.2
		light.shadow_enabled = hatch
		light.position = position - outward * (_wall * 0.5 + 0.05 * _s)
		parent.add_child(light)
		light.look_at(light.position - outward + Vector3.DOWN * 0.35, Vector3.UP)
	_openings.append({
		"position": position, "outward": outward, "width": width, "height": height,
		"glow_material": glow_material, "glow_color": glow_material.albedo_color,
		"light": light, "light_energy": light.light_energy if light != null else 0.0,
	})


# --- Services and lights ----------------------------------------------------------------------

## Plumbing hangs just under the joists, above the ductwork: a black ABS drain main (two when
## there is room) with the bath, kitchen and laundry drains coming down to it, red/blue PEX
## mains with hot and cold branches rising to the fixtures, and a yellow gas main feeding the
## furnace, water heater, stove and dryer. Every straight piece is a destructible UtilityPipe
## section. The ductwork is grown first; the mains then pick z positions clear of the pier rows
## and of the duct risers, and the fixture columns sit beside the pier gaps so they miss the
## trunk and the piers.
func _build_services(extents: Vector3) -> void:
	var services := Node3D.new()
	services.name = "Services"
	add_child(services)
	var s: float = _s
	var joist_bottom: float = _ceiling - _joist_depth
	var span: float = extents.x - _wall * 2.0
	# Small lines tucked right under the joists; the drain lower, clearing the ducts.
	var small_y: float = joist_bottom - 0.02 * s
	var drain_y: float = joist_bottom - 0.09 * s
	var pair_gap: float = 0.04 * s
	# Fixture columns sit off the pier-gap midpoints: clear of the piers and of the ductwork's
	# runs along Z, which take the midpoints themselves.
	var gaps: Array = []
	for index: int in _pier_xs.size() - 1:
		gaps.append((float(_pier_xs[index]) + float(_pier_xs[index + 1])) * 0.5)
	if gaps.is_empty():
		gaps.append(_center.x)
	var branch_xs: Array = []
	for gap: float in gaps:
		branch_xs.append(gap + 0.32 * s)
	branch_xs.shuffle()
	_branch_x_pool = branch_xs
	_branch_x_all = branch_xs.duplicate()

	# Ductwork first; its trunk takes one of the pier gaps.
	var duct_x: float = gaps[_rng.randi() % gaps.size()]
	var network: DuctNetwork = DuctBuilder.build(
		self, _center, _half, _wall,
		func(x: float, z: float) -> float: return _terrain.get_surface_height_at(Vector3(x, 0.0, z)),
		duct_x, _pier_rows, _pier_xs, _pier_size, branch_xs.duplicate(), joist_bottom, joist_bottom - girder_depth * s, s, _rng
	) as DuctNetwork
	network.obstacles.append_array(_pier_boxes)
	_network = network
	var riser_zs: Array = network.get_meta("riser_zs")
	var furnace_top: Vector3 = network.get_meta("furnace_top")
	var furnace_size: Vector3 = network.get_meta("furnace_size")
	# The drain hangs low enough to clip the furnace cabinet, so it keeps off its footprint.
	var furnace_band: Array = [furnace_top.z - furnace_size.z * 0.5, furnace_top.z + furnace_size.z * 0.5]
	# The gaps between the walls and the pier rows, where the mains run.
	var edges: Array = [_center.z - _half.z + _wall]
	edges.append_array(_pier_rows)
	edges.append(_center.z + _half.z - _wall)
	var gap_count: int = edges.size() - 1
	var reach_min: float = 0.2 * s
	var reach_max: float = 0.4 * s
	# A branch stays inside its main's bay: the beams on the pier rows are in the way of
	# anything hanging at pipe height.
	var girder_bottom: float = joist_bottom - girder_depth * s
	var girders: Array = []
	for row_z: float in _pier_rows:
		girders.append({"z": row_z, "radius": girder_width * 0.5 * s, "bottom": girder_bottom})

	# The small lines hang at one height; every riser (drain, water or gas) must stand clear
	# of them, so their mains are chosen first.
	var water_z: float = _pick_main_z(edges, 1 % gap_count, pair_gap + PEX_RADIUS * s, riser_zs)
	var gas_z: float = _pick_main_z(edges, 2 % gap_count, GAS_RADIUS * s, riser_zs)
	var small_mains: Array = [
		{"z": water_z - pair_gap, "radius": PEX_RADIUS * s},
		{"z": water_z + pair_gap, "radius": PEX_RADIUS * s},
		{"z": gas_z, "radius": GAS_RADIUS * s},
	]
	# Each line's risers stand in their own lane beside the shared column, so risers of
	# different lines never share a spot.
	var hot_lane: float = -0.14 * s
	var cold_lane: float = -0.06 * s
	var gas_lane: float = 0.07 * s
	# Drain main(s), with the fixture drains coming down to them.
	var drain_fixtures: Array = ["BathDrain", "KitchenDrain", "LaundryDrain"]
	var drain_count: int = 2 if gap_count >= 3 else 1
	for index: int in drain_count:
		var z: float = _pick_main_z(edges, 0 if index == 0 else gap_count - 1, DRAIN_RADIUS * s, riser_zs, [furnace_band])
		_drain_lines.append({"z": z, "y": drain_y})
		_run_line(services, UtilityPipe.Fluid.SEWAGE, DRAIN_RADIUS * s, drain_y, z, span, "Drain%d" % index)
		var count: int = 2 if index == 0 else 1
		if drain_count == 1:
			count = 3
		for fixture: int in count:
			var fixture_name: String = drain_fixtures.pop_front()
			var x: float = _next_branch_x()
			var end_z: float = _clear_riser(_clamp_to_bay(z + _branch_side() * _rng.randf_range(reach_min, reach_max), z, edges, DRAIN_RADIUS * s), DRAIN_RADIUS * 0.8 * s, small_mains)
			_build_polyline(
				services, UtilityPipe.Fluid.SEWAGE, DRAIN_RADIUS * 0.8 * s,
				[Vector3(x, drain_y, z), Vector3(x, drain_y, end_z), Vector3(x, joist_bottom, end_z)], fixture_name
			)
		if index == 0:
			# A drop line down into the dirt (the cleanout), somewhere the ducts aren't.
			for _attempt: int in 12:
				var x: float = _center.x + _rng.randf_range(-_half.x * 0.6, _half.x * 0.6)
				var ground: float = _terrain.get_surface_height_at(Vector3(x, 0.0, z))
				if _column_clear(network, x, z, ground, drain_y):
					var drop: UtilityPipe = UtilityPipe.create(UtilityPipe.Fluid.SEWAGE, drain_y - ground + 0.05 * s, DRAIN_RADIUS * s, ground, _effect_scale())
					drop.name = "Cleanout"
					drop.position = Vector3(x, (drain_y + ground - 0.05 * s) * 0.5, z)
					services.add_child(drop)
					break

	# Water: hot and cold mains side by side with paired branches up to the fixtures. The small
	# lines all hang at one height, so a branch crossing another line dips under it.
	_run_line(services, UtilityPipe.Fluid.HOT_WATER, PEX_RADIUS * s, small_y, water_z - pair_gap, span, "HotWater")
	_run_line(services, UtilityPipe.Fluid.COLD_WATER, PEX_RADIUS * s, small_y, water_z + pair_gap, span, "ColdWater")
	for fixture_name: String in ["Bathroom", "Kitchen", "Laundry"]:
		var x: float = _next_branch_x()
		var side: float = _branch_side()
		var end_z: float = _clear_riser(_clamp_to_bay(water_z + side * _rng.randf_range(reach_min, reach_max), water_z, edges, pair_gap * 3.0), PEX_RADIUS * s, small_mains)
		var hot_points: Array = _z_leg(x + hot_lane, small_y, water_z - pair_gap, end_z, PEX_RADIUS * s, small_mains)
		hot_points.append(Vector3(x + hot_lane, joist_bottom, end_z))
		_build_polyline(services, UtilityPipe.Fluid.HOT_WATER, PEX_RADIUS * s, hot_points, fixture_name + "Hot")
		var cold_end_z: float = _clear_riser(_clamp_to_bay(end_z + 2.0 * pair_gap * side, water_z, edges, pair_gap), PEX_RADIUS * s, small_mains)
		var cold_points: Array = _z_leg(x + cold_lane, small_y, water_z + pair_gap, cold_end_z, PEX_RADIUS * s, small_mains)
		cold_points.append(Vector3(x + cold_lane, joist_bottom, cold_end_z))
		_build_polyline(services, UtilityPipe.Fluid.COLD_WATER, PEX_RADIUS * s, cold_points, fixture_name + "Cold")

	# Gas: one main with its own branches, and a drop onto the furnace.
	_run_line(services, UtilityPipe.Fluid.GAS, GAS_RADIUS * s, small_y, gas_z, span, "Gas")
	for fixture_name: String in ["WaterHeaterGas", "Stove", "Dryer"]:
		var x: float = _next_branch_x()
		var end_z: float = _clear_riser(_clamp_to_bay(gas_z + _branch_side() * _rng.randf_range(reach_min, reach_max), gas_z, edges, GAS_RADIUS * s), GAS_RADIUS * s, small_mains)
		var points: Array = _z_leg(x + gas_lane, small_y, gas_z, end_z, GAS_RADIUS * s, small_mains)
		points.append(Vector3(x + gas_lane, joist_bottom, end_z))
		_build_polyline(services, UtilityPipe.Fluid.GAS, GAS_RADIUS * s, points, fixture_name)
	# The furnace feed runs along the cabinet's +X face, dipping under the water mains and the
	# beams on the way, and drops to its gas valve.
	var feed_x: float = furnace_top.x + furnace_size.x * 0.5 + 0.05 * s
	var feed_points: Array = _z_leg(feed_x, small_y, gas_z, furnace_top.z, GAS_RADIUS * s, small_mains + girders)
	feed_points.append(Vector3(feed_x, furnace_top.y + 0.01 * s, furnace_top.z))
	_build_polyline(services, UtilityPipe.Fluid.GAS, GAS_RADIUS * s, feed_points, "FurnaceGas")


## Keeps a branch end inside the bay (between pier rows, or a row and a wall) that its main
## runs in, `margin` short of the beam or wall.
func _clamp_to_bay(z: float, main_z: float, edges: Array, margin: float) -> float:
	var keep_off: float = girder_width * 0.5 * _s + margin + 0.04 * _s
	for index: int in edges.size() - 1:
		var low: float = float(edges[index])
		var high: float = float(edges[index + 1])
		if main_z >= low and main_z <= high:
			return clampf(z, low + keep_off, high - keep_off)
	return z


## Nudges a riser's z off any line hanging at the small lines' height, so the riser never
## stands through a main.
func _clear_riser(z: float, pipe_radius: float, mains: Array) -> float:
	for main: Dictionary in mains:
		var main_z: float = float(main["z"])
		var clearance: float = pipe_radius + float(main["radius"]) + 0.02 * _s
		if absf(z - main_z) < clearance:
			z = main_z + clearance * (1.0 if z >= main_z else -1.0)
	return z


## A run along Z at one height, from one main out to z_to, with a dip under everything in the
## way: other lines hanging at that height, and beams, whose "bottom" sets how deep the dip
## goes (the leg's own main at z_from is not counted).
func _z_leg(x: float, y: float, z_from: float, z_to: float, pipe_radius: float, obstacles: Array) -> Array:
	var direction: float = signf(z_to - z_from)
	var crossings: Array = []
	for obstacle: Dictionary in obstacles:
		var obstacle_z: float = float(obstacle["z"])
		var clearance: float = pipe_radius + float(obstacle["radius"]) + 0.02 * _s
		if (obstacle_z - z_from) * direction > clearance and (z_to - obstacle_z) * direction > clearance:
			var underside: float = float(obstacle.get("bottom", y - float(obstacle["radius"])))
			var dip_y: float = minf(y - 0.035 * _s, underside - pipe_radius - 0.02 * _s)
			crossings.append([absf(obstacle_z - z_from), obstacle_z, clearance, dip_y])
	crossings.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var points: Array = [Vector3(x, y, z_from)]
	for crossing: Array in crossings:
		var obstacle_z: float = crossing[1]
		var clearance: float = crossing[2]
		var dip_y: float = crossing[3]
		points.append(Vector3(x, y, obstacle_z - direction * clearance))
		points.append(Vector3(x, dip_y, obstacle_z - direction * clearance))
		points.append(Vector3(x, dip_y, obstacle_z + direction * clearance))
		points.append(Vector3(x, y, obstacle_z + direction * clearance))
	points.append(Vector3(x, y, z_to))
	return points

## A z for a main in the given gap between pier rows (or walls), clear of the piers, the duct
## risers, the mains already laid and any extra [min, max] bands. Falls back to the gap's
## middle.
func _pick_main_z(edges: Array, gap_index: int, pipe_radius: float, riser_zs: Array, blocked_bands: Array = []) -> float:
	var low: float = edges[gap_index]
	var high: float = edges[gap_index + 1]
	var best: float = (low + high) * 0.5
	for fraction: float in [0.5, 0.35, 0.65, 0.25, 0.75, 0.4, 0.6, 0.2, 0.8]:
		var z: float = lerpf(low, high, fraction) + _rng.randf_range(-0.03, 0.03) * _s
		var clear: bool = true
		for row_z: float in _pier_rows:
			if absf(z - row_z) < _pier_size * 0.5 + pipe_radius + 0.03 * _s:
				clear = false
		for riser_z: float in riser_zs:
			if absf(z - riser_z) < DuctBuilder.DUCT_WIDTH * 0.5 * _s + pipe_radius + 0.03 * _s:
				clear = false
		for other_z: float in _main_zs:
			if absf(z - other_z) < 0.12 * _s + pipe_radius:
				clear = false
		for band: Array in blocked_bands:
			if z > float(band[0]) - pipe_radius - 0.03 * _s and z < float(band[1]) + pipe_radius + 0.03 * _s:
				clear = false
		if clear:
			best = z
			break
	_main_zs.append(best)
	return best


## True when a vertical line at (x, z) between two heights stays out of the ductwork.
func _column_clear(network: DuctNetwork, x: float, z: float, y_from: float, y_to: float) -> bool:
	var steps: int = 8
	for step: int in steps + 1:
		if network.is_inside(Vector3(x, lerpf(y_from, y_to, float(step) / steps), z)):
			return false
	return true


## The next column for a fixture branch; the columns are reused (on different mains) once
## every one has been taken.
var _branch_x_pool: Array = []
var _branch_x_all: Array = []
func _next_branch_x() -> float:
	if _branch_x_pool.is_empty():
		_branch_x_pool = _branch_x_all.duplicate()
		_branch_x_pool.shuffle()
	return float(_branch_x_pool.pop_front())


## Which way a branch leaves its main, alternating so fixtures spread across the space.
var _next_branch_side: float = 1.0
func _branch_side() -> float:
	_next_branch_side = -_next_branch_side
	return _next_branch_side


## Leak, pool and blast sizes grow with the square root of the scale: big enough to matter to
## a bug, not house-sized.
func _effect_scale() -> float:
	return sqrt(_s)


## A line along X made of destructible sections, with a hanger strap up to the joists at each
## joint.
func _run_line(parent: Node3D, fluid: UtilityPipe.Fluid, pipe_radius: float, y: float, z: float, span: float, line_name: String) -> void:
	var strap_material: Material = _material(Color(0.3, 0.3, 0.32), 0.5)
	var joist_bottom: float = _ceiling - _joist_depth
	var section_count: int = maxi(int(round(span / (0.8 * _s))), 1)
	var section_length: float = span / section_count
	for section: int in section_count:
		var x: float = _center.x - span * 0.5 + section_length * (section + 0.5)
		var dirt: float = _terrain.get_surface_height_at(Vector3(x, 0.0, z))
		var pipe: UtilityPipe = UtilityPipe.create(fluid, section_length, pipe_radius, dirt, _effect_scale())
		pipe.name = "%s_%d" % [line_name, section]
		pipe.position = Vector3(x, y, z)
		pipe.rotation = Vector3(0.0, 0.0, PI * 0.5)
		parent.add_child(pipe)
		_box(parent, "Hanger", Vector3(0.01 * _s, joist_bottom - y, pipe_radius * 2.0 + 0.02 * _s), Vector3(x - section_length * 0.5, (joist_bottom + y) * 0.5, z), strap_material)


## A run of pipe through a list of corners: each leg in destructible sections, a round fitting
## at every corner, and a plate where a riser meets the floor above.
func _build_polyline(parent: Node3D, fluid: UtilityPipe.Fluid, pipe_radius: float, points: Array, line_name: String) -> void:
	var fitting_material: Material = UtilityPipe.pipe_material(fluid)
	for leg: int in points.size() - 1:
		var from: Vector3 = points[leg]
		var to: Vector3 = points[leg + 1]
		var length: float = from.distance_to(to)
		if length < 0.01:
			continue
		var direction: Vector3 = (to - from) / length
		var section_count: int = maxi(int(ceil(length / (0.8 * _s))), 1)
		var section_length: float = length / section_count
		for section: int in section_count:
			var mid: Vector3 = from + direction * section_length * (section + 0.5)
			var dirt: float = _terrain.get_surface_height_at(Vector3(mid.x, 0.0, mid.z))
			var pipe: UtilityPipe = UtilityPipe.create(fluid, section_length, pipe_radius, dirt, _effect_scale())
			pipe.name = "%s_%d_%d" % [line_name, leg, section]
			pipe.position = mid
			pipe.basis = _pipe_basis(direction)
			parent.add_child(pipe)
		if leg < points.size() - 2:
			var fitting := MeshInstance3D.new()
			fitting.name = "Fitting"
			var sphere := SphereMesh.new()
			sphere.radius = pipe_radius * 1.25
			sphere.height = sphere.radius * 2.0
			sphere.radial_segments = 10
			sphere.rings = 5
			fitting.mesh = sphere
			fitting.material_override = fitting_material
			fitting.position = to
			parent.add_child(fitting)
	var last: Vector3 = points.back()
	if is_equal_approx(last.y, _ceiling - _joist_depth):
		_box(parent, "FloorPlate", Vector3(0.08, 0.01, 0.08) * _s, last - Vector3.UP * 0.005 * _s, _material(Color(0.35, 0.35, 0.37), 0.5))


## Basis whose Y axis points along `axis` (pipes run along their local Y).
func _pipe_basis(axis: Vector3) -> Basis:
	var reference: Vector3 = Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x_axis: Vector3 = axis.cross(reference).normalized()
	var z_axis: Vector3 = x_axis.cross(axis).normalized()
	return Basis(x_axis, axis, z_axis)


func _build_bulbs(extents: Vector3) -> void:
	var lights := Node3D.new()
	lights.name = "Bulbs"
	add_child(lights)
	var hang: float = _ceiling - _joist_depth - 0.08 * _s
	for x_sign: float in [-1.0, 1.0]:
		for z_sign: float in [-1.0, 1.0]:
			var position := Vector3(_center.x + x_sign * extents.x * 0.25, hang, _center.z + z_sign * extents.z * 0.25)
			_cylinder(lights, "Cord", 0.004 * _s, 0.08 * _s, position + Vector3.UP * 0.05 * _s, Vector3.ZERO, _material(Color(0.12, 0.12, 0.12)))
			var bulb := MeshInstance3D.new()
			bulb.name = "Bulb"
			var sphere := SphereMesh.new()
			sphere.radius = 0.03 * _s
			sphere.height = 0.06 * _s
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
			light.light_energy = 5.0
			light.omni_range = 2.0 * _s
			light.omni_attenuation = 1.0
			light.shadow_enabled = false
			light.position = position
			lights.add_child(light)
			_bulbs.append({"light": light, "mesh": bulb, "position": position, "live": true})


# --- Debris -----------------------------------------------------------------------------------

## Loose blocks, bricks, stones and lumber offcuts at real size: a block is a 40 cm block.
func _build_debris() -> void:
	var debris := Node3D.new()
	debris.name = "Debris"
	add_child(debris)
	var rock: Dictionary = AsteroidMeshBuilder.build(_seed, 1.0, 1, 0.35)
	var rock_mesh: Mesh = rock["mesh"]
	for _rock: int in rock_count:
		var size: float = _rng.randf_range(0.015, 0.08) * _s
		var spot: Vector3 = _ground_spot(size * 1.3)
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
		_tumbled_box(debris, "Block", Vector3(0.4, 0.2, 0.2) * _s, CONCRETE_COLOR, true, Detail.CONCRETE)
	for _brick: int in brick_count:
		_tumbled_box(debris, "Brick", Vector3(0.2, 0.065, 0.1) * _s, BRICK_COLOR, true, Detail.CONCRETE)
	for _scrap: int in scrap_count:
		_tumbled_box(debris, "Scrap", Vector3(_rng.randf_range(0.3, 1.0), 0.04, 0.09) * _s, LUMBER_COLOR, true, Detail.WOOD)


## Mushrooms in clusters, mostly at the damp foot of a pier or along a wall: pale buttons and
## ink caps with the odd toadstool, a few centimetres tall in real terms, so a few metres to a
## bug. Each species draws through one MultiMesh; the big ones get a stem and cap to climb.
func _build_mushrooms() -> void:
	var root := Node3D.new()
	root.name = "Mushrooms"
	add_child(root)
	var kinds: Array = [
		[MushroomMeshBuilder.Species.BUTTON, "ButtonMushrooms", 0.5],
		[MushroomMeshBuilder.Species.INKCAP, "InkCaps", 0.38],
		[MushroomMeshBuilder.Species.TOADSTOOL, "Toadstools", 0.12],
	]
	var patches: Dictionary = {}
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	for _cluster: int in mushroom_clusters:
		var pick: float = _rng.randf()
		var kind: Array = kinds[0] if pick < kinds[0][2] else (kinds[1] if pick < kinds[0][2] + kinds[1][2] else kinds[2])
		var key: String = "%s%d" % [kind[1], _rng.randi() % 3]
		if not patches.has(key):
			var built: Dictionary = MushroomMeshBuilder.build(hash(key) + _seed, kind[0])
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.use_colors = true
			multimesh.mesh = built["mesh"]
			var instance := MultiMeshInstance3D.new()
			instance.name = key
			instance.multimesh = multimesh
			instance.material_override = material
			root.add_child(instance)
			patches[key] = {"built": built, "instance": instance, "transforms": [], "colors": []}
		var patch: Dictionary = patches[key]
		var built: Dictionary = patch["built"]
		var center: Vector3 = _damp_spot()
		for index: int in _rng.randi_range(2, 6):
			var size: float = _rng.randf_range(0.015, 0.045) * _s
			var spot: Vector3 = center
			if index > 0:
				var angle: float = _rng.randf() * TAU
				var distance: float = _rng.randf_range(size * 1.5, size * 4.0)
				spot = center + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
				spot.y = _dirt_height(spot)
				if not _spot_clear(spot, size * float(built["cap_radius"])):
					continue
			var basis: Basis = Basis(Vector3.UP, _rng.randf() * TAU) * Basis.from_scale(Vector3(size, size * _rng.randf_range(0.9, 1.15), size))
			var transform := Transform3D(basis, spot - Vector3.UP * size * 0.04)
			patch["transforms"].append(transform)
			var tint: Color = Color.WHITE * _rng.randf_range(0.88, 1.0)
			tint.a = 1.0
			patch["colors"].append(tint)
			var cap_radius: float = float(built["cap_radius"]) * size
			if cap_radius >= 0.75:
				_mushroom_collider(root, transform, built, basis.get_scale().y)
	var total: int = 0
	for patch: Dictionary in patches.values():
		var multimesh: MultiMesh = patch["instance"].multimesh
		multimesh.instance_count = patch["transforms"].size()
		for index: int in patch["transforms"].size():
			multimesh.set_instance_transform(index, patch["transforms"][index])
			multimesh.set_instance_color(index, patch["colors"][index])
		total += patch["transforms"].size()
	print("[Crawlspace] %d mushrooms in %d kinds" % [total, patches.size()])


## Somewhere damp: the foot of a pier, the base of a wall, or anywhere on the dirt.
func _damp_spot() -> Vector3:
	var pick: float = _rng.randf()
	for _attempt: int in 12:
		var spot: Vector3
		if pick < 0.5 and not _pier_xs.is_empty():
			var x: float = float(_pier_xs[_rng.randi() % _pier_xs.size()])
			var z: float = float(_pier_rows[_rng.randi() % _pier_rows.size()])
			var angle: float = _rng.randf() * TAU
			var distance: float = _pier_size * _rng.randf_range(0.75, 1.3)
			spot = Vector3(x + cos(angle) * distance, 0.0, z + sin(angle) * distance)
		elif pick < 0.8:
			var along_x: bool = _rng.randf() < 0.5
			var side: float = -1.0 if _rng.randf() < 0.5 else 1.0
			var inset: float = _wall + _rng.randf_range(0.05, 0.2) * _s
			var along: float = _rng.randf_range(-0.8, 0.8)
			spot = (
				Vector3(_center.x + along * _half.x, 0.0, _center.z + side * (_half.z - inset)) if along_x
				else Vector3(_center.x + side * (_half.x - inset), 0.0, _center.z + along * _half.z)
			)
		else:
			return _ground_spot(0.03 * _s)
		spot.y = _dirt_height(spot)
		if _spot_clear(spot, 0.03 * _s):
			return spot
	return _ground_spot(0.03 * _s)


## A cylinder for the stem and a flat one for the cap, so bugs can climb up and stand on top.
func _mushroom_collider(parent: Node3D, transform: Transform3D, built: Dictionary, size: float) -> void:
	var body := StaticBody3D.new()
	body.name = "MushroomCollider"
	body.collision_layer = MapInfo.TERRAIN_LAYER
	body.collision_mask = 0
	body.transform = Transform3D(Basis(transform.basis.get_rotation_quaternion()), transform.origin)
	var stem := CylinderShape3D.new()
	stem.radius = maxf(float(built["stem_radius"]) * size, 0.15)
	stem.height = float(built["cap_y"]) * size
	var stem_shape := CollisionShape3D.new()
	stem_shape.shape = stem
	stem_shape.position = Vector3(0.0, stem.height * 0.5, 0.0)
	body.add_child(stem_shape)
	var cap := CylinderShape3D.new()
	cap.radius = float(built["cap_radius"]) * size * 0.9
	cap.height = maxf(float(built["cap_height"]) * size * 0.6, 0.2)
	var cap_shape := CollisionShape3D.new()
	cap_shape.shape = cap
	cap_shape.position = Vector3(0.0, (float(built["cap_y"]) + float(built["cap_height"]) * 0.3) * size, 0.0)
	body.add_child(cap_shape)
	parent.add_child(body)


## A box lying on the dirt at a random spot and yaw, sometimes tipped on its side. The dirt is
## not flat under something this big, so the box is tilted to the slope fitted through the
## ground under its four corners and sunk a little, which keeps every corner touching.
func _tumbled_box(parent: Node3D, box_name: String, size: Vector3, color: Color, collide: bool, detail: Detail = Detail.NONE) -> void:
	var tipped: bool = _rng.randf() < 0.3
	var yaw: float = _rng.randf() * TAU
	var right: Vector3 = Basis(Vector3.UP, yaw).x
	var forward: Vector3 = Basis(Vector3.UP, yaw).z
	# Footprint on the dirt: tipping swaps the box's height for its depth.
	var half_right: float = size.x * 0.5
	var half_forward: float = (size.y if tipped else size.z) * 0.5
	var rest_height: float = (size.z if tipped else size.y) * 0.5
	# A long offcut is checked along its own length, not as a square the size of its length,
	# or it would find no room between the duct runs.
	var spot: Vector3 = _ground_spot_along(right, half_right, half_forward)
	if spot == Vector3.INF:
		return
	var height_right_plus: float = _dirt_height(spot + right * half_right)
	var height_right_minus: float = _dirt_height(spot - right * half_right)
	var height_forward_plus: float = _dirt_height(spot + forward * half_forward)
	var height_forward_minus: float = _dirt_height(spot - forward * half_forward)
	var slope_right: float = (height_right_plus - height_right_minus) / (2.0 * half_right)
	var slope_forward: float = (height_forward_plus - height_forward_minus) / (2.0 * half_forward)
	var up: Vector3 = (Vector3.UP - right * slope_right - forward * slope_forward).normalized()
	var seat: float = (height_right_plus + height_right_minus + height_forward_plus + height_forward_minus + spot.y) / 5.0
	var basis: Basis = Basis(Vector3.UP, yaw)
	var tilt_axis: Vector3 = Vector3.UP.cross(up)
	if tilt_axis.length_squared() > 0.000001:
		basis = Basis(tilt_axis.normalized(), Vector3.UP.angle_to(up)) * basis
	if tipped:
		basis = basis * Basis(Vector3.RIGHT, PI * 0.5)
	var sink: float = 0.3 + 0.02 * _s
	var position: Vector3 = Vector3(spot.x, seat, spot.z) + up * (rest_height - sink)
	var box := _box(parent, box_name, size, position, _material(color * _rng.randf_range(0.85, 1.1), 0.95, detail, 0), MapInfo.TERRAIN_LAYER if collide else 0)
	box.basis = basis
	if collide:
		(box.get_child(0) as Node3D).basis = Basis.IDENTITY


func _dirt_height(point: Vector3) -> float:
	return _terrain.get_surface_height_at(Vector3(point.x, 0.0, point.z))


## A random spot on the dirt inside the walls where something `reach` metres across won't poke
## into a duct, the furnace or a pier (the last try is used if nothing clear turns up).
func _ground_spot(reach: float = 0.0) -> Vector3:
	var margin: float = _wall + 0.2 * _s
	var spot: Vector3 = _center
	for _attempt: int in 24:
		var x: float = _center.x + _rng.randf_range(-_half.x + margin, _half.x - margin)
		var z: float = _center.z + _rng.randf_range(-_half.z + margin, _half.z - margin)
		spot = Vector3(x, _terrain.get_surface_height_at(Vector3(x, 0.0, z)), z)
		if _network == null or _spot_clear(spot, reach):
			break
	return spot


## A random spot on the dirt where a box `half_along` long (along `along`) and `half_across`
## wide fits clear of the ducts, furnace and piers, or Vector3.INF when none turns up.
func _ground_spot_along(along: Vector3, half_along: float, half_across: float) -> Vector3:
	var margin: float = _wall + 0.2 * _s + half_along
	var spot: Vector3 = Vector3.INF
	for _attempt: int in 40:
		var x: float = _center.x + _rng.randf_range(-_half.x + margin, _half.x - margin)
		var z: float = _center.z + _rng.randf_range(-_half.z + margin, _half.z - margin)
		spot = Vector3(x, _terrain.get_surface_height_at(Vector3(x, 0.0, z)), z)
		if _network == null or _span_clear(spot, along, half_along, half_across):
			return spot
	# No room found: the caller leaves this piece out rather than jamming it into something.
	return Vector3.INF


func _span_clear(spot: Vector3, along: Vector3, half_along: float, half_across: float) -> bool:
	var steps: int = maxi(int(ceil(half_along / maxf(half_across, 1.0))) * 2, 2)
	for step: int in steps + 1:
		var point: Vector3 = spot + along * lerpf(-half_along, half_along, float(step) / steps) + Vector3.UP * half_across
		for box: AABB in _network.obstacles:
			if box.grow(half_across + 0.5).has_point(point):
				return false
	return true


func _spot_clear(spot: Vector3, reach: float) -> bool:
	var footprint := AABB(spot - Vector3(reach, 0.5, reach), Vector3(reach * 2.0, reach * 2.0 + 0.5, reach * 2.0))
	for box: AABB in _network.obstacles:
		if box.intersects(footprint):
			return false
	return true


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


## Surface detail the toon shader paints on: see toon_detail.gdshaderinc.
enum Detail { NONE, WOOD, CONCRETE, BLOCK, BRICK, POURED }
enum Masonry { RANDOM, BLOCK, POURED }


## A shared material per colour, roughness and detail. `grain_axis` is the object axis the
## wood runs along (0 x, 1 y, 2 z) for Detail.WOOD.
func _material(color: Color, roughness: float = 0.95, detail: Detail = Detail.NONE, grain_axis: int = 0) -> StandardMaterial3D:
	var key: String = "%s|%.2f|%d|%d" % [color.to_html(), roughness, detail, grain_axis]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if detail != Detail.NONE:
		material.set_meta(&"toon_detail", int(detail))
		material.set_meta(&"toon_detail_scale", _s)
		material.set_meta(&"toon_grain_axis", grain_axis)
	_materials[key] = material
	return material


func _wood(along_axis: int) -> StandardMaterial3D:
	return _material(LUMBER_COLOR, 0.95, Detail.WOOD, along_axis)
