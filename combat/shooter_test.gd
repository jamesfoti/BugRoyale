extends Node
class_name ShooterTest
## Weapon test fire: projectile visual with explosive terrain carving on impact.

const SHOOT_ACTION: StringName = &"shoot"
const ShootProjectileVisualScene: PackedScene = preload("res://combat/shoot_projectile_visual.tscn")

const WEAPON_FIRE_PROFILE: Dictionary = {
	PlayerItems.Item.WEAPON_AK: {
		"cooldown": 0.11, "damage": 8.0, "radius": 1.4, "projectile_speed": 180.0, "projectile_radius": 0.1,
	},
	PlayerItems.Item.WEAPON_GRENADE_LAUNCHER: {
		"cooldown": 0.65, "damage": 20.0, "radius": 3.8, "projectile_speed": 70.0, "projectile_radius": 0.22,
	},
	PlayerItems.Item.WEAPON_KNIFE_1: {
		"cooldown": 0.25, "damage": 4.0, "radius": 0.8, "projectile_speed": 120.0, "projectile_radius": 0.08,
	},
	PlayerItems.Item.WEAPON_KNIFE_2: {
		"cooldown": 0.25, "damage": 4.0, "radius": 0.8, "projectile_speed": 120.0, "projectile_radius": 0.08,
	},
	PlayerItems.Item.WEAPON_PISTOL: {
		"cooldown": 0.2, "damage": 10.0, "radius": 1.1, "projectile_speed": 165.0, "projectile_radius": 0.09,
	},
	PlayerItems.Item.WEAPON_REVOLVER: {
		"cooldown": 0.3, "damage": 14.0, "radius": 1.6, "projectile_speed": 155.0, "projectile_radius": 0.1,
	},
	PlayerItems.Item.WEAPON_REVOLVER_SMALL: {
		"cooldown": 0.26, "damage": 11.0, "radius": 1.3, "projectile_speed": 160.0, "projectile_radius": 0.09,
	},
	PlayerItems.Item.WEAPON_ROCKET_LAUNCHER: {
		"cooldown": 0.9, "damage": 28.0, "radius": 4.6, "projectile_speed": 55.0, "projectile_radius": 0.28,
	},
	PlayerItems.Item.WEAPON_SHORT_CANNON: {
		"cooldown": 0.75, "damage": 24.0, "radius": 3.4, "projectile_speed": 65.0, "projectile_radius": 0.24,
	},
	PlayerItems.Item.WEAPON_SHOTGUN: {
		"cooldown": 0.45, "damage": 16.0, "radius": 2.3, "projectile_speed": 145.0, "projectile_radius": 0.12,
	},
	PlayerItems.Item.WEAPON_SHOVEL: {
		"cooldown": 0.35, "damage": 6.0, "radius": 1.0, "projectile_speed": 95.0, "projectile_radius": 0.1,
	},
	PlayerItems.Item.WEAPON_SMG: {
		"cooldown": 0.08, "damage": 6.0, "radius": 1.0, "projectile_speed": 190.0, "projectile_radius": 0.08,
	},
	PlayerItems.Item.WEAPON_SNIPER: {
		"cooldown": 0.55, "damage": 22.0, "radius": 2.0, "projectile_speed": 220.0, "projectile_radius": 0.11,
	},
	PlayerItems.Item.WEAPON_SNIPER_2: {
		"cooldown": 0.6, "damage": 24.0, "radius": 2.2, "projectile_speed": 225.0, "projectile_radius": 0.11,
	},
}

@export var camera_path: NodePath = ^"../OrbitCamera/Camera3D"
@export var orbit_camera_path: NodePath = ^"../OrbitCamera"
@export var max_shoot_distance: float = 650.0
@export var default_cooldown_seconds: float = 0.2
@export var default_damage: float = 8.0
@export var default_explosion_radius: float = 1.2
@export var default_projectile_speed: float = 140.0
@export var default_projectile_radius: float = 0.1
## Splash damage at the edge of the explosion radius, as a fraction of the shot's damage
## (full damage at the center, falling off linearly).
@export_range(0.0, 1.0, 0.05) var splash_edge_damage_fraction: float = 0.25

var _camera: Camera3D
var _cooldown_left_seconds: float = 0.0
var _shoot_visual_timer_seconds: float = 0.0


func _ready() -> void:
	if not InputMap.has_action(SHOOT_ACTION):
		push_error(
			"Missing InputMap action '%s'. Add it under Project > Project Settings > Input Map."
			% SHOOT_ACTION
		)
	_camera = get_node_or_null(camera_path) as Camera3D


func _process(delta: float) -> void:
	_cooldown_left_seconds = maxf(0.0, _cooldown_left_seconds - delta)
	_shoot_visual_timer_seconds = maxf(0.0, _shoot_visual_timer_seconds - delta)
	_update_skin_shooting_state()


func _unhandled_input(event: InputEvent) -> void:
	if not _can_accept_shoot_input():
		return
	if event.is_action_pressed(SHOOT_ACTION):
		_try_shoot()


func _try_shoot() -> void:
	if _camera == null or _cooldown_left_seconds > 0.0:
		return
	var equipped_weapon_item = _get_equipped_weapon_item()
	if not PlayerItems.is_weapon(equipped_weapon_item):
		return

	var fire_profile: Dictionary = WEAPON_FIRE_PROFILE.get(equipped_weapon_item, {})
	var cooldown_seconds: float = fire_profile.get("cooldown", default_cooldown_seconds)
	var hit_damage: float = fire_profile.get("damage", default_damage)
	var explosion_radius: float = fire_profile.get("radius", default_explosion_radius)
	var projectile_speed: float = fire_profile.get("projectile_speed", default_projectile_speed)
	var projectile_radius: float = fire_profile.get("projectile_radius", default_projectile_radius)

	var ray_origin: Vector3
	var ray_direction: Vector3
	var aim_ray: Dictionary = _get_aim_ray()
	ray_origin = aim_ray["origin"]
	ray_direction = aim_ray["direction"]
	if ray_direction.length_squared() <= 0.0001:
		return
	ray_direction = ray_direction.normalized()

	var ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_direction * max_shoot_distance
	)
	ray_query.exclude = [get_parent()]
	var space: PhysicsDirectSpaceState3D = get_viewport().get_world_3d().direct_space_state
	var raycast_hit: Dictionary = space.intersect_ray(ray_query)
	if raycast_hit.is_empty():
		return

	var hit_position: Vector3 = raycast_hit.position
	_spawn_projectile_visual(
		ray_origin,
		hit_position,
		projectile_speed,
		projectile_radius,
		raycast_hit,
		hit_damage,
		explosion_radius
	)

	_cooldown_left_seconds = cooldown_seconds
	_shoot_visual_timer_seconds = maxf(cooldown_seconds * 0.8, 0.06)
	_update_skin_shooting_state()


func _spawn_projectile_visual(
	start_position: Vector3,
	target_position: Vector3,
	projectile_speed: float,
	projectile_radius: float,
	raycast_hit: Dictionary,
	hit_damage: float,
	explosion_radius: float
) -> void:
	var projectile_visual: ShootProjectileVisual = (
		ShootProjectileVisualScene.instantiate() as ShootProjectileVisual
	)
	if projectile_visual == null:
		_apply_shot_impact(raycast_hit, hit_damage, target_position, explosion_radius)
		return

	var world_root: Node = get_tree().current_scene
	if world_root == null:
		projectile_visual.free()
		_apply_shot_impact(raycast_hit, hit_damage, target_position, explosion_radius)
		return

	world_root.add_child(projectile_visual)
	projectile_visual.travel_speed = projectile_speed
	projectile_visual.launch(start_position, target_position, projectile_radius)
	projectile_visual.arrived.connect(
		_apply_shot_impact.bind(raycast_hit, hit_damage, target_position, explosion_radius)
	)


func _apply_shot_impact(
	raycast_hit: Dictionary,
	hit_damage: float,
	hit_position: Vector3,
	explosion_radius: float
) -> void:
	var direct_hit: Damageable = _apply_damage_at_hit(raycast_hit, hit_damage)
	_apply_splash_damage(hit_position, explosion_radius, hit_damage, direct_hit)
	_apply_terrain_explosion(hit_position, explosion_radius)
	_spawn_explosion_effect(hit_position, explosion_radius)


## Damages whatever the shot hit directly and returns its Damageable (null if none).
func _apply_damage_at_hit(raycast_hit: Dictionary, hit_damage: float) -> Damageable:
	# The hit was recorded when the shot fired; by the time the projectile arrives the collider
	# may be gone (e.g. a terrain chunk's collision rebuilt by an earlier explosion).
	var hit_collider_variant: Variant = raycast_hit.get("collider")
	if not is_instance_valid(hit_collider_variant):
		return null
	var hit_collider: Node = hit_collider_variant as Node
	if hit_collider == null:
		return null
	var damageable: Damageable = _resolve_damageable(hit_collider)
	if damageable == null:
		return null
	damageable.apply_damage(hit_damage, get_parent())
	return damageable


## Explosion splash: every other damageable within the radius takes damage that falls off from
## full at the center to splash_edge_damage_fraction at the edge. Skips the direct hit (already
## damaged) and the shooter's own player.
func _apply_splash_damage(
	explosion_position: Vector3,
	explosion_radius: float,
	hit_damage: float,
	direct_hit: Damageable
) -> void:
	if explosion_radius <= 0.0:
		return
	var shooter_owner: Node = get_parent()
	for node: Node in get_tree().get_nodes_in_group("damageable"):
		var damageable: Damageable = node as Damageable
		if damageable == null or damageable == direct_hit or not damageable.is_alive():
			continue
		var target: Node3D = damageable.get_parent() as Node3D
		if target == null or target == shooter_owner:
			continue
		var distance: float = target.global_position.distance_to(explosion_position)
		if distance > explosion_radius:
			continue
		var falloff: float = lerpf(1.0, splash_edge_damage_fraction, distance / explosion_radius)
		damageable.apply_damage(hit_damage * falloff, shooter_owner)


func _apply_terrain_explosion(hit_position: Vector3, explosion_radius: float) -> void:
	var terrain_world: ChunkedTerrainWorld = _resolve_terrain_world()
	if terrain_world == null:
		return
	terrain_world.apply_brush(hit_position, explosion_radius, false)


func _spawn_explosion_effect(hit_position: Vector3, explosion_radius: float) -> void:
	var world_root: Node = get_tree().current_scene
	if world_root == null:
		return
	WeaponExplosionEffect.spawn(world_root, hit_position, explosion_radius)


func _resolve_terrain_world() -> ChunkedTerrainWorld:
	var terrain_world: ChunkedTerrainWorld = get_tree().get_first_node_in_group("terrain_world") as ChunkedTerrainWorld
	if terrain_world != null:
		return terrain_world
	terrain_world = get_tree().get_first_node_in_group("open_terrain") as ChunkedTerrainWorld
	if terrain_world != null:
		return terrain_world
	terrain_world = get_tree().get_first_node_in_group("boxed_in_terrain") as ChunkedTerrainWorld
	return terrain_world


func _resolve_damageable(target: Node) -> Damageable:
	if target is Damageable:
		return target as Damageable
	var direct_damageable: Damageable = target.get_node_or_null("Damageable") as Damageable
	if direct_damageable != null:
		return direct_damageable
	var parent_node: Node = target.get_parent()
	if parent_node == null:
		return null
	if parent_node is Damageable:
		return parent_node as Damageable
	return parent_node.get_node_or_null("Damageable") as Damageable


func _can_accept_shoot_input() -> bool:
	if get_tree().paused:
		return false
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return false
	var player_node: Node = get_parent()
	if player_node == null:
		return false
	if player_node.has_method("is_terrain_focus_active") and player_node.call("is_terrain_focus_active"):
		return false
	if player_node.has_method("_is_item_menu_open") and player_node.call("_is_item_menu_open"):
		return false
	return true


func _update_skin_shooting_state() -> void:
	var skin_node: Node = _get_skin_node()
	if skin_node == null or not skin_node.has_method("set_shooting"):
		return
	var is_shooting: bool = _shoot_visual_timer_seconds > 0.0 and PlayerItems.is_weapon(_get_equipped_weapon_item())
	skin_node.call("set_shooting", is_shooting)


func _get_equipped_weapon_item():
	var skin_node: Node = _get_skin_node()
	if skin_node == null or not skin_node.has_method("get_equipped_weapon_item"):
		return PlayerItems.Item.NONE
	return skin_node.call("get_equipped_weapon_item")


func _get_skin_node() -> Node:
	var player_node: Node = get_parent()
	if player_node == null:
		return null
	var visual_root: Node = player_node.get_node_or_null("VisualRoot")
	if visual_root == null or visual_root.get_child_count() == 0:
		return null
	return visual_root.get_child(0)


func _get_aim_ray() -> Dictionary:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var screen_position: Vector2 = viewport_size * 0.5
	var orbit_camera: OrbitCamera = get_node_or_null(orbit_camera_path) as OrbitCamera
	if orbit_camera != null:
		screen_position = orbit_camera.get_crosshair_screen_position(viewport_size)
	if _camera == null:
		return {"origin": Vector3.ZERO, "direction": Vector3.FORWARD}
	return {
		"origin": _camera.project_ray_origin(screen_position),
		"direction": _camera.project_ray_normal(screen_position),
	}
