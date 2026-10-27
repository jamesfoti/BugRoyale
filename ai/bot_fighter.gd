extends CharacterBody3D
class_name BotFighter
## AI stand-in for another player. Walks the map like a player (any map: uses MapInfo's up, so the
## celestial body's gravity works too), hunts the nearest enemy, keeps to its weapon's preferred range,
## strafes, and shoots with spread. Modes can make it follow a squad leader or flee rising water.
## Bot shots never dig into the terrain (dozens of bots would wreck the map and the frame rate).

const ShootProjectileVisualScene: PackedScene = preload("res://combat/shoot_projectile_visual.tscn")
const _EYE_HEIGHT: float = 0.9
const _CAPSULE_RADIUS: float = 0.35
const _CAPSULE_HEIGHT: float = 1.2
const _RETARGET_SECONDS: float = 0.4
const _REACTION_SECONDS: float = 0.55
const _PROJECTILE_SPEED: float = 130.0
const _VISUAL_REST_BASIS: Basis = Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))
## A husk's bite: melee, so no projectile, just a short reach.
const HUSK_WEAPON: Dictionary = {"damage": 9.0, "cooldown": 0.8, "range": 2.4, "spread_degrees": 0.0, "pellets": 1, "melee": true}
## How far inside the spore cloud's edge a clean bot likes to stay.
const _STORM_MARGIN: float = 6.0

## Group whose members this bot hunts: "fighter" (players and bots of other teams) or "bird".
var target_group: StringName = &"fighter"
## Optional squad leader to stay near when nothing is in range (Attack of the Hornets).
var leader: Node3D
## Head for high ground when rising water gets close (Battle Royale).
var avoid_water: bool = false
## Spore cloud (Cordyceps Royale): a clean bot keeps inside this circle, planar. INF = no cloud.
var storm_center: Vector3 = Vector3.INF
var storm_radius: float = INF
## Taken by the fungus: slow, unarmed, bites anything clean, and walks straight through the
## spores and the water.
var husk: bool = false
var detection_range: float = 70.0
var character: LoadingScreen.PlayerCharacter = LoadingScreen.PlayerCharacter.ANT_WARRIOR
var map: MapInfo
var damageable: Damageable
var skin: CharacterSkin

var _visual_root: Node3D
var _move_speed: float = 5.0
var _jump_velocity: float = 4.5
var _weapon: Dictionary = {}
var _weapon_item: PlayerItems.Item = PlayerItems.Item.WEAPON_AK
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _active: bool = true
var _target: Node3D
## Whether the current target was visible at the last check (hills, or the celestial body's curve, hide it).
var _target_in_sight: bool = false
var _retarget_timer: float = 0.0
var _reaction_timer: float = 0.0
var _cooldown: float = 0.0
var _wander_point: Vector3 = Vector3.INF
var _wander_timer: float = 0.0
## A path through the map's ductwork, followed point by point whenever the bot and its goal are
## on different sides of the sheet metal (or the bot just feels like wandering the ducts).
var _route: PackedVector3Array = PackedVector3Array()
var _route_index: int = 0
var _route_destination: Vector3 = Vector3.INF
var _route_check_timer: float = 0.0
var _route_check_position: Vector3 = Vector3.ZERO
## After abandoning a stuck route, no duct wandering for a while.
var _duct_cooldown: float = 0.0
var _duct_network: DuctNetwork
var _duct_network_checked: bool = false
var _strafe_sign: float = 1.0
var _strafe_timer: float = 0.0
var _anim_state: String = ""


## Builds a ready-to-add bot for a class and team. skin_path overrides the class's bot skin.
static func create(
	bot_character: LoadingScreen.PlayerCharacter, bot_team: int, map_info: MapInfo, skin_path: String = ""
) -> BotFighter:
	var bot := BotFighter.new()
	bot.name = "Bot"
	bot.character = bot_character
	bot.map = map_info
	bot.collision_layer = MapInfo.FIGHTER_LAYER
	bot.collision_mask = MapInfo.TERRAIN_LAYER | MapInfo.FIGHTER_LAYER | MapInfo.STRUCTURE_LAYER
	bot.floor_snap_length = 0.3

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = _CAPSULE_RADIUS
	capsule.height = _CAPSULE_HEIGHT
	shape.shape = capsule
	shape.position = Vector3(0.0, _CAPSULE_HEIGHT * 0.5, 0.0)
	bot.add_child(shape)

	bot._visual_root = Node3D.new()
	bot._visual_root.name = "VisualRoot"
	bot._visual_root.basis = _VISUAL_REST_BASIS
	bot.add_child(bot._visual_root)
	var scene: PackedScene = load(skin_path if not skin_path.is_empty() else CharacterSkin.bot_scene_path_for(bot_character)) as PackedScene
	bot.skin = scene.instantiate() as CharacterSkin
	bot._visual_root.add_child(bot.skin)

	var stats: Dictionary = CharacterSkin.stats_for(bot_character)
	bot.damageable = Damageable.new()
	bot.damageable.name = "Damageable"
	bot.damageable.max_health = stats.get("max_health", 100.0)
	bot.damageable.team = bot_team
	bot.add_child(bot.damageable)
	bot._move_speed = 5.0 * float(stats.get("speed", 1.0))
	bot._jump_velocity = 4.5 * float(stats.get("jump", 1.0))
	bot._weapon = CharacterSkin.bot_weapon_for(bot_character)
	bot._weapon_item = CharacterSkin.weapon_for(bot_character)
	bot.add_to_group("fighter")
	return bot


func _ready() -> void:
	skin.set_equipped_weapon_from_item(_weapon_item)
	_strafe_sign = 1.0 if randf() < 0.5 else -1.0


## Stops the bot firing for a while (e.g. a royale's drop-in grace period).
func hold_fire(seconds: float) -> void:
	_cooldown = maxf(_cooldown, seconds)


func is_active() -> bool:
	return _active


## Removes the bot from play (dead): hidden, not collidable, not thinking.
func deactivate() -> void:
	_active = false
	visible = false
	collision_layer = 0
	velocity = Vector3.ZERO
	_target = null
	set_physics_process(false)


## Puts the bot back into play at a position with full health.
func respawn_at(position_on_map: Vector3) -> void:
	global_position = position_on_map
	velocity = Vector3.ZERO
	_align_to_up(map.up_at(position_on_map), 1.0)
	visible = true
	collision_layer = MapInfo.FIGHTER_LAYER
	damageable.revive()
	_target = null
	_wander_point = Vector3.INF
	_active = true
	set_physics_process(true)


## The fungus takes the bot (Cordyceps Royale): it rises again on the fungus team at a fraction of
## its speed, drops its gun for a bite, forgets the storm and the water, and senses the clean
## from far off. Works on a bot that just died as well as a live one.
func become_husk(fungus_team: int, speed_scale: float) -> void:
	husk = true
	damageable.team = fungus_team
	damageable.revive()
	_weapon = HUSK_WEAPON
	_weapon_item = PlayerItems.Item.NONE
	skin.set_equipped_weapon_from_item(PlayerItems.Item.NONE)
	_move_speed *= speed_scale
	avoid_water = false
	leader = null
	storm_center = Vector3.INF
	storm_radius = INF
	detection_range = maxf(detection_range, 60.0)
	_target = null
	_wander_point = Vector3.INF
	_clear_route()
	# A moment of stillness as it gets back up.
	_cooldown = maxf(_cooldown, 1.5)
	add_to_group("husk")
	visible = true
	collision_layer = MapInfo.FIGHTER_LAYER
	_active = true
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not _active or map == null:
		return
	var up: Vector3 = map.up_at(global_position)
	up_direction = up
	_align_to_up(up, minf(1.0, 8.0 * delta))
	if map.is_out_of_bounds(global_position):
		damageable.apply_damage(damageable.max_health * 10.0)
		return

	_retarget_timer -= delta
	_reaction_timer -= delta
	_cooldown -= delta
	_strafe_timer -= delta
	_wander_timer -= delta
	_duct_cooldown -= delta
	_watch_route_progress(delta)
	if _retarget_timer <= 0.0:
		_retarget_timer = _RETARGET_SECONDS
		var previous: Node3D = _target
		_target = _find_target()
		_target_in_sight = _target != null and _can_see(_target)
		if _target != previous:
			_reaction_timer = _REACTION_SECONDS
	if _target != null and not _is_valid_target(_target):
		_target = null

	var goal: Vector3 = _choose_goal(up)
	var to_goal: Vector3 = goal - global_position
	var planar: Vector3 = to_goal.slide(up)
	var move_direction: Vector3 = Vector3.ZERO
	if to_goal.length() > 0.6:
		# Walk along the ground toward the goal. On the celestial body a goal far around the curve projects
		# to a tiny (or zero, if straight through) ground vector, so only its direction is used.
		if planar.length_squared() < 0.0001:
			planar = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD)
		move_direction = planar.normalized()
	if avoid_water and move_direction != Vector3.ZERO and _step_leads_into_water(move_direction):
		move_direction = Vector3.ZERO
	var vertical_speed: float = velocity.dot(up)
	if is_on_floor() and vertical_speed < 0.0:
		vertical_speed = 0.0
	velocity = move_direction * _move_speed + up * vertical_speed
	if not is_on_floor():
		velocity -= up * _gravity * delta
	elif move_direction != Vector3.ZERO and is_on_wall():
		velocity += up * _jump_velocity

	var facing: Vector3 = move_direction
	if _target != null:
		facing = (_target.global_position - global_position).slide(up)
	_face(facing, delta)
	move_and_slide()
	_try_shoot(up)
	_update_animation(move_direction, up)


# --- Targeting --------------------------------------------------------------------------------

func _find_target() -> Node3D:
	var best: Node3D = null
	var best_distance: float = detection_range
	for node: Node in get_tree().get_nodes_in_group(target_group):
		var candidate: Node3D = node as Node3D
		if candidate == null or not _is_valid_target(candidate):
			continue
		var distance: float = global_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


func _is_valid_target(candidate: Node3D) -> bool:
	if candidate == self or not is_instance_valid(candidate) or not candidate.is_inside_tree():
		return false
	if candidate is BotFighter and not (candidate as BotFighter).is_active():
		return false
	var health: Damageable = candidate.get_node_or_null("Damageable") as Damageable
	if health == null or not health.is_alive():
		return false
	return damageable.team == Damageable.NO_TEAM or health.team != damageable.team


# --- Movement ---------------------------------------------------------------------------------

func _choose_goal(up: Vector3) -> Vector3:
	var position_now: Vector3 = global_position
	if avoid_water and map.water != null and position_now.y < map.water_surface_y() + 3.0:
		return _wander_goal(map.water_surface_y() + 4.0)
	# In (or nearly in) the spore cloud: nothing matters but getting back inside the circle.
	if _fears_storm() and _storm_depth(position_now) > -_STORM_MARGIN:
		return _via_ducts(_storm_refuge(up))
	var target_too_low: bool = avoid_water and _target != null and map.water != null and _target.global_position.y < map.water_surface_y() + 2.0
	# No chasing a husk into the spores.
	var target_in_storm: bool = _fears_storm() and _target != null and _storm_depth(_target.global_position) > 1.0
	if _target != null and not target_too_low and not target_in_storm:
		var to_target: Vector3 = (_target.global_position - position_now).slide(up)
		var distance: float = to_target.length()
		var melee: bool = bool(_weapon.get("melee", false))
		var preferred: float = (
			float(_weapon.get("range", 2.0)) * 0.6 if melee
			else clampf(float(_weapon.get("range", 40.0)) * 0.45, 6.0, 25.0)
		)
		if distance > preferred * 1.3 or not _target_in_sight:
			return _via_ducts(_target.global_position)
		if melee:
			# Keep pressing in; a bite has no standoff range.
			return _target.global_position
		if distance < preferred * 0.6:
			return position_now - to_target
		if _strafe_timer <= 0.0:
			_strafe_timer = randf_range(1.2, 2.8)
			_strafe_sign = -_strafe_sign
		return position_now + to_target.cross(up).normalized() * 4.0 * _strafe_sign
	if leader != null and is_instance_valid(leader) and leader.visible:
		# "Close enough" only counts on the same side of the ductwork; 5 m through sheet metal
		# is not with the leader.
		if position_now.distance_to(leader.global_position) > 7.0 or _separated_by_ducts(leader.global_position):
			return _via_ducts(leader.global_position)
		return position_now
	return _wander_goal(-INF)


## Clean bots mind the spore cloud; husks walk through it.
func _fears_storm() -> bool:
	return not husk and storm_radius < INF and storm_center != Vector3.INF


## How far into the spores a point is: positive outside the safe circle, negative inside.
func _storm_depth(point: Vector3) -> float:
	return Vector2(point.x - storm_center.x, point.z - storm_center.z).length() - storm_radius


## A spot well inside the safe circle, straight in from where the bot stands.
func _storm_refuge(up: Vector3) -> Vector3:
	var outward: Vector3 = (global_position - storm_center).slide(up)
	if outward.length_squared() < 0.01:
		outward = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD)
	var inside: float = maxf(storm_radius - _STORM_MARGIN * 2.0, 0.0)
	var refuge: Vector3 = storm_center + outward.normalized() * inside
	refuge.y = global_position.y
	return refuge


## A random ground point, the best of several at staying inside the spore cloud's safe circle.
func _random_point(min_height: float) -> Vector3:
	if not _fears_storm():
		return map.random_surface_point(0.0, 0.0, min_height)
	var best: Vector3 = Vector3.INF
	var best_depth: float = INF
	for _attempt: int in 6:
		var candidate: Vector3 = map.random_surface_point(0.0, 0.0, min_height)
		var candidate_depth: float = _storm_depth(candidate)
		if candidate_depth < best_depth:
			best_depth = candidate_depth
			best = candidate
		if candidate_depth < -_STORM_MARGIN * 2.0:
			break
	return best


## True when the bot and a point are on different sides of the ductwork (one inside, one out).
func _separated_by_ducts(point: Vector3) -> bool:
	var network: DuctNetwork = _find_duct_network()
	if network == null:
		return false
	var probe: Vector3 = Vector3.UP * 0.6
	return network.is_inside(global_position + probe) != network.is_inside(point + probe)


## The way to a destination: straight at it when neither end is inside the ductwork, otherwise
## along a route through the ducts' waypoint graph (recomputed when the destination moves).
func _via_ducts(destination: Vector3) -> Vector3:
	var network: DuctNetwork = _find_duct_network()
	if network == null:
		return destination
	var probe: Vector3 = Vector3.UP * 0.6
	if not network.is_inside(global_position + probe) and not network.is_inside(destination + probe):
		_clear_route()
		return destination
	if _route.is_empty() or _route_destination.distance_to(destination) > 4.0:
		_start_route(network.route(global_position, destination), destination)
		if _route.is_empty():
			return destination
	return _follow_route()


func _start_route(route: PackedVector3Array, destination: Vector3) -> void:
	_route = route
	_route_index = 0
	_route_destination = destination
	_route_check_timer = 0.0
	_route_check_position = global_position


func _clear_route() -> void:
	_route = PackedVector3Array()
	_route_destination = Vector3.INF


## A route that makes no progress for a few seconds is abandoned (something is in the way).
func _watch_route_progress(delta: float) -> void:
	if _route.is_empty():
		return
	_route_check_timer += delta
	if _route_check_timer < 2.5:
		return
	_route_check_timer = 0.0
	if global_position.distance_to(_route_check_position) < 1.0:
		_clear_route()
		_wander_point = Vector3.INF
		_duct_cooldown = 12.0
	_route_check_position = global_position


func _wander_goal(min_height: float) -> Vector3:
	if not _route.is_empty():
		return _follow_route()
	var reached: bool = _wander_point != Vector3.INF and global_position.distance_to(_wander_point) < 2.0
	var too_low: bool = _wander_point != Vector3.INF and _wander_point.y < min_height
	if _wander_point == Vector3.INF or reached or too_low or _wander_timer <= 0.0:
		var network: DuctNetwork = _find_duct_network()
		# Now and then, wander into the ductwork instead (not while fleeing water, and not through
		# a flooded entry).
		if network != null and min_height == -INF and _duct_cooldown <= 0.0 and randf() < 0.35:
			var inside_spot: Vector3 = network.random_interior_point()
			var in_storm: bool = inside_spot != Vector3.INF and _fears_storm() and _storm_depth(inside_spot) > -_STORM_MARGIN
			if inside_spot != Vector3.INF and not in_storm:
				var route: PackedVector3Array = network.route(global_position, inside_spot)
				if not route.is_empty() and not map.is_underwater(route[0] + Vector3.UP * 0.5):
					_wander_point = inside_spot
					_wander_timer = randf_range(12.0, 20.0)
					_start_route(route, inside_spot)
					return _follow_route()
		_wander_point = _random_point(min_height)
		_wander_timer = randf_range(6.0, 11.0)
		# Leaving the ducts means walking out the way in, not through a wall.
		if network != null and network.is_inside(global_position + Vector3.UP * 0.6):
			_start_route(network.route(global_position, _wander_point), _wander_point)
	if not _route.is_empty():
		return _follow_route()
	return _wander_point


## The next route point, advancing when the bot gets close (measured flat, since waypoints sit
## at feet height on floors the bot may be above or below while climbing a ramp).
func _follow_route() -> Vector3:
	var point: Vector3 = _route[_route_index]
	if Vector2(point.x - global_position.x, point.z - global_position.z).length() < 1.3:
		_route_index += 1
		if _route_index >= _route.size():
			# Off the graph: head straight for wherever the route was taking us.
			var destination: Vector3 = _route_destination
			_clear_route()
			return destination if destination != Vector3.INF else global_position
		point = _route[_route_index]
	return point


func _find_duct_network() -> DuctNetwork:
	if not _duct_network_checked:
		_duct_network_checked = true
		_duct_network = get_tree().get_first_node_in_group("duct_network") as DuctNetwork
	return _duct_network if _duct_network != null and is_instance_valid(_duct_network) else null


func _align_to_up(up: Vector3, weight: float) -> void:
	var current_up: Vector3 = global_basis.y.normalized()
	if current_up.dot(up) > 0.9999:
		return
	var turn := Quaternion(current_up, up)
	global_basis = (Basis(Quaternion.IDENTITY.slerp(turn, weight)) * global_basis).orthonormalized()


func _face(direction: Vector3, delta: float) -> void:
	var local_direction: Vector3 = (global_basis.inverse() * direction).slide(Vector3.UP)
	if local_direction.length_squared() < 0.0001:
		return
	var target_rotation: Quaternion = (
		Basis.looking_at(local_direction.normalized(), Vector3.UP) * _VISUAL_REST_BASIS
	).get_rotation_quaternion()
	var current_rotation: Quaternion = _visual_root.basis.get_rotation_quaternion()
	if current_rotation.dot(target_rotation) < 0.0:
		target_rotation = -target_rotation
	_visual_root.basis = Basis(current_rotation.slerp(target_rotation, minf(1.0, 10.0 * delta)))


# --- Shooting ---------------------------------------------------------------------------------

func _try_shoot(up: Vector3) -> void:
	if _target == null or _cooldown > 0.0 or _reaction_timer > 0.0 or _weapon.is_empty():
		return
	var eye: Vector3 = global_position + up * _EYE_HEIGHT
	var aim_point: Vector3 = _aim_point(_target)
	var weapon_range: float = _weapon.get("range", 40.0)
	if eye.distance_to(aim_point) > weapon_range:
		return
	var sight: Dictionary = _cast(eye, aim_point)
	if not sight.is_empty() and sight.collider != _target:
		return
	_cooldown = float(_weapon.get("cooldown", 0.3)) * randf_range(0.9, 1.25)
	if bool(_weapon.get("melee", false)):
		# A bite lands straight away, no projectile.
		_apply_hit(_target, float(_weapon.get("damage", 6.0)))
		return
	var base_direction: Vector3 = (aim_point - eye).normalized()
	for _pellet: int in int(_weapon.get("pellets", 1)):
		var direction: Vector3 = _spread(base_direction, float(_weapon.get("spread_degrees", 3.0)))
		var hit: Dictionary = _cast(eye, eye + direction * weapon_range)
		var impact: Vector3 = hit.position if not hit.is_empty() else eye + direction * weapon_range
		_spawn_shot(eye + direction * 0.5, impact, hit.get("collider"))


func _spread(direction: Vector3, degrees: float) -> Vector3:
	var side: Vector3 = direction.cross(Vector3.UP if absf(direction.y) < 0.95 else Vector3.RIGHT).normalized()
	var spun: Vector3 = side.rotated(direction, randf() * TAU)
	return direction.rotated(spun, deg_to_rad(randf() * degrees)).normalized()


func _spawn_shot(from: Vector3, to: Vector3, collider: Variant) -> void:
	var world_root: Node = get_tree().current_scene
	var visual: ShootProjectileVisual = ShootProjectileVisualScene.instantiate() as ShootProjectileVisual
	world_root.add_child(visual)
	visual.travel_speed = _PROJECTILE_SPEED
	visual.launch(from, to, 0.07)
	visual.arrived.connect(_apply_hit.bind(collider, float(_weapon.get("damage", 6.0))))


func _apply_hit(collider: Variant, damage: float) -> void:
	if not is_instance_valid(collider) or not (collider is Node):
		return
	var health: Damageable = (collider as Node).get_node_or_null("Damageable") as Damageable
	if health != null:
		health.apply_damage(damage, self)


func _cast(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(query)


# --- Animation --------------------------------------------------------------------------------

func _update_animation(move_direction: Vector3, up: Vector3) -> void:
	var state: String = "idle"
	if not is_on_floor():
		state = "jump" if velocity.dot(up) > 0.05 else "fall"
	elif move_direction != Vector3.ZERO:
		state = "run" if _move_speed > 5.5 else "walk"
	if state != _anim_state:
		_anim_state = state
		skin.set_state(state)


func _aim_point(target: Node3D) -> Vector3:
	var lift: float = 0.6 if target is CharacterBody3D else 0.0
	return target.global_position + map.up_at(target.global_position) * lift


func _can_see(target: Node3D) -> bool:
	var eye: Vector3 = global_position + map.up_at(global_position) * _EYE_HEIGHT
	var sight: Dictionary = _cast(eye, _aim_point(target))
	return sight.is_empty() or sight.collider == target


## True when the ground a step ahead sits at or near the water (a drop into the flood).
func _step_leads_into_water(direction: Vector3) -> bool:
	if map.water == null:
		return false
	var ahead: Dictionary = map.ground_hit(global_position + direction * 1.5)
	var safe_height: float = map.water_surface_y() + 1.5
	return ahead.is_empty() or (ahead.position.y < safe_height and global_position.y >= safe_height)
