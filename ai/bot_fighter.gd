extends CharacterBody3D
class_name BotFighter
## AI stand-in for another player. Walks the map like a player (any map: uses MapInfo's up, so the
## planet's gravity works too), hunts the nearest enemy, keeps to its weapon's preferred range,
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

## Group whose members this bot hunts: "fighter" (players and bots of other teams) or "bird".
var target_group: StringName = &"fighter"
## Optional squad leader to stay near when nothing is in range (Attack of the Hornets).
var leader: Node3D
## Head for high ground when rising water gets close (Battle Royale).
var avoid_water: bool = false
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
## Whether the current target was visible at the last check (hills, or the planet's curve, hide it).
var _target_in_sight: bool = false
var _retarget_timer: float = 0.0
var _reaction_timer: float = 0.0
var _cooldown: float = 0.0
var _wander_point: Vector3 = Vector3.INF
var _wander_timer: float = 0.0
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
	bot.collision_mask = MapInfo.TERRAIN_LAYER | MapInfo.FIGHTER_LAYER
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
		# Walk along the ground toward the goal. On the planet a goal far around the curve projects
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
	var target_too_low: bool = avoid_water and _target != null and map.water != null and _target.global_position.y < map.water_surface_y() + 2.0
	if _target != null and not target_too_low:
		var to_target: Vector3 = (_target.global_position - position_now).slide(up)
		var distance: float = to_target.length()
		var preferred: float = clampf(float(_weapon.get("range", 40.0)) * 0.45, 6.0, 25.0)
		if distance > preferred * 1.3 or not _target_in_sight:
			return _target.global_position
		if distance < preferred * 0.6:
			return position_now - to_target
		if _strafe_timer <= 0.0:
			_strafe_timer = randf_range(1.2, 2.8)
			_strafe_sign = -_strafe_sign
		return position_now + to_target.cross(up).normalized() * 4.0 * _strafe_sign
	if leader != null and is_instance_valid(leader) and leader.visible:
		if position_now.distance_to(leader.global_position) > 7.0:
			return leader.global_position
		return position_now
	return _wander_goal(-INF)


func _wander_goal(min_height: float) -> Vector3:
	var reached: bool = _wander_point != Vector3.INF and global_position.distance_to(_wander_point) < 2.0
	var too_low: bool = _wander_point != Vector3.INF and _wander_point.y < min_height
	if _wander_point == Vector3.INF or reached or too_low or _wander_timer <= 0.0:
		_wander_point = map.random_surface_point(0.0, 0.0, min_height)
		_wander_timer = randf_range(6.0, 11.0)
	return _wander_point


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
