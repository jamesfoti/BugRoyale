extends Node
class_name ShooterTest
## Weapon fire: a projectile visual, direct and splash damage on impact, and a crater in the
## terrain for the explosive weapons only ("digs" in the profile: grenade launcher, rocket
## launcher, short cannon). Bullets, pellets and blades leave the ground alone.
##
## The local player's trigger and aim come from the mouse and the camera. Any other pilot (a
## bot's brain, later a network peer) hands its FighterInput to handle_input each physics frame:
## the trigger edge or hold, and the ray the shot follows.

const SHOOT_ACTION: StringName = &"shoot"
const ShootProjectileVisualScene: PackedScene = preload("res://combat/shoot_projectile_visual.tscn")

const WEAPON_FIRE_PROFILE: Dictionary = {
	PlayerItems.Item.WEAPON_AK: {
		"cooldown": 0.11, "damage": 8.0, "radius": 1.4, "projectile_speed": 180.0, "projectile_radius": 0.1,
		"spread": 1.4, "bloom": 0.35, "auto": true,
	},
	PlayerItems.Item.WEAPON_GRENADE_LAUNCHER: {
		"cooldown": 0.65, "damage": 20.0, "radius": 3.8, "projectile_speed": 70.0, "projectile_radius": 0.22,
		"spread": 1.5, "bloom": 0.8, "digs": true,
	},
	PlayerItems.Item.WEAPON_KNIFE_1: {
		"cooldown": 0.25, "damage": 4.0, "radius": 0.8, "projectile_speed": 120.0, "projectile_radius": 0.08,
		"spread": 0.0, "bloom": 0.0,
	},
	PlayerItems.Item.WEAPON_KNIFE_2: {
		"cooldown": 0.25, "damage": 4.0, "radius": 0.8, "projectile_speed": 120.0, "projectile_radius": 0.08,
		"spread": 0.0, "bloom": 0.0,
	},
	PlayerItems.Item.WEAPON_PISTOL: {
		"cooldown": 0.2, "damage": 10.0, "radius": 1.1, "projectile_speed": 165.0, "projectile_radius": 0.09,
		"spread": 1.1, "bloom": 0.5,
	},
	PlayerItems.Item.WEAPON_REVOLVER: {
		"cooldown": 0.3, "damage": 14.0, "radius": 1.6, "projectile_speed": 155.0, "projectile_radius": 0.1,
		"spread": 0.9, "bloom": 0.9,
	},
	PlayerItems.Item.WEAPON_REVOLVER_SMALL: {
		"cooldown": 0.26, "damage": 11.0, "radius": 1.3, "projectile_speed": 160.0, "projectile_radius": 0.09,
		"spread": 1.2, "bloom": 0.6,
	},
	PlayerItems.Item.WEAPON_ROCKET_LAUNCHER: {
		"cooldown": 0.9, "damage": 28.0, "radius": 4.6, "projectile_speed": 55.0, "projectile_radius": 0.28,
		"spread": 0.8, "bloom": 1.0, "digs": true,
	},
	PlayerItems.Item.WEAPON_SHORT_CANNON: {
		"cooldown": 0.75, "damage": 24.0, "radius": 3.4, "projectile_speed": 65.0, "projectile_radius": 0.24,
		"spread": 2.0, "bloom": 1.2, "digs": true,
	},
	PlayerItems.Item.WEAPON_SHOTGUN: {
		"cooldown": 0.45, "damage": 16.0, "radius": 2.3, "projectile_speed": 145.0, "projectile_radius": 0.12,
		"spread": 4.5, "bloom": 1.5,
	},
	PlayerItems.Item.WEAPON_SHOVEL: {
		"cooldown": 0.35, "damage": 6.0, "radius": 1.0, "projectile_speed": 95.0, "projectile_radius": 0.1,
		"spread": 0.0, "bloom": 0.0,
	},
	PlayerItems.Item.WEAPON_SMG: {
		"cooldown": 0.08, "damage": 6.0, "radius": 1.0, "projectile_speed": 190.0, "projectile_radius": 0.08,
		"spread": 2.2, "bloom": 0.3, "auto": true,
	},
	PlayerItems.Item.WEAPON_SNIPER: {
		"cooldown": 0.55, "damage": 22.0, "radius": 2.0, "projectile_speed": 220.0, "projectile_radius": 0.11,
		"spread": 3.0, "bloom": 1.5,
	},
	PlayerItems.Item.WEAPON_SNIPER_2: {
		"cooldown": 0.6, "damage": 24.0, "radius": 2.2, "projectile_speed": 225.0, "projectile_radius": 0.11,
		"spread": 3.0, "bloom": 1.5,
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
## Shot cone, in degrees: each weapon's base spread, plus bloom that every shot adds and that
## fades at this rate, plus extra for running and for being off the ground. Aiming tightens the
## whole cone; a scope removes it.
@export var bloom_decay_per_second: float = 5.0
@export var max_bloom_degrees: float = 4.0
@export var move_spread_degrees: float = 1.2
@export var airborne_spread_degrees: float = 2.0
@export_range(0.0, 1.0, 0.05) var aim_spread_scale: float = 0.4
## How long after the last shot the body keeps squaring up to the camera. Longer than any
## weapon's cooldown, so the stance holds steady through a burst instead of flickering between
## shots (which twists the body, and the camera with it, when strafing).
@export var stance_hold_seconds: float = 1.0
## Bots: no craters and no impact effects (dozens of bots would wreck the map and the frame
## rate); their spread is their brain's, not the gun's.
@export var lightweight_impacts: bool = false

## Shots fired since the body spawned (the smoke test reads it).
var shots_fired: int = 0

var _camera: Camera3D
var _cooldown_left_seconds: float = 0.0
var _shoot_visual_timer_seconds: float = 0.0
var _stance_timer_seconds: float = 0.0
var _bloom_degrees: float = 0.0


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
	_stance_timer_seconds = maxf(0.0, _stance_timer_seconds - delta)
	_bloom_degrees = maxf(0.0, _bloom_degrees - bloom_decay_per_second * delta)
	# Automatic weapons keep firing while the button is held.
	if _is_local_pilot() and Input.is_action_pressed(SHOOT_ACTION) and _can_accept_shoot_input():
		var fire_profile: Dictionary = WEAPON_FIRE_PROFILE.get(_get_equipped_weapon_item(), {})
		if fire_profile.get("auto", false):
			_try_shoot()
	_update_skin_shooting_state()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_pilot() or not _can_accept_shoot_input():
		return
	if event.is_action_pressed(SHOOT_ACTION):
		_try_shoot()


## A non-local pilot's trigger for this physics frame (the body calls this after sampling).
func handle_input(input: FighterInput) -> void:
	if _is_local_pilot() or not _can_accept_shoot_input():
		return
	if input.shoot_pressed:
		_try_shoot()
	elif input.shoot_held:
		var fire_profile: Dictionary = WEAPON_FIRE_PROFILE.get(_get_equipped_weapon_item(), {})
		if fire_profile.get("auto", false):
			_try_shoot()


func _is_local_pilot() -> bool:
	var body: FighterBody = get_parent() as FighterBody
	return body == null or body.is_local


## True while the trigger is held and for a while after the last shot: the body faces the camera.
## Deliberately sticky, not per shot, so it never drops out between shots of a burst.
func is_firing() -> bool:
	if not PlayerItems.is_weapon(_get_equipped_weapon_item()):
		return false
	if _stance_timer_seconds > 0.0:
		return true
	if not _is_local_pilot():
		var body: FighterBody = get_parent() as FighterBody
		return body.get_input().shoot_held
	return Input.is_action_pressed(SHOOT_ACTION) and _can_accept_shoot_input()


## Half-angle of the cone the next shot can land in, in degrees (what the crosshair shows).
func get_spread_degrees() -> float:
	var equipped_weapon_item: PlayerItems.Item = _get_equipped_weapon_item()
	if not PlayerItems.is_weapon(equipped_weapon_item):
		return 0.0
	var orbit_camera: OrbitCamera = get_node_or_null(orbit_camera_path) as OrbitCamera
	if orbit_camera != null and orbit_camera.is_scoped():
		return 0.0
	var fire_profile: Dictionary = WEAPON_FIRE_PROFILE.get(equipped_weapon_item, {})
	var spread: float = float(fire_profile.get("spread", 1.0)) + _bloom_degrees
	var body: CharacterBody3D = get_parent() as CharacterBody3D
	if body != null:
		spread += move_spread_degrees * clampf(body.velocity.length() / 6.0, 0.0, 1.0)
		if not body.is_on_floor():
			spread += airborne_spread_degrees
	if orbit_camera != null and orbit_camera.is_aiming():
		spread *= aim_spread_scale
	return spread


## Scatters a direction within the current spread cone.
func _apply_spread(direction: Vector3) -> Vector3:
	if lightweight_impacts:
		return direction
	var spread: float = get_spread_degrees()
	if spread <= 0.0:
		return direction
	var side: Vector3 = direction.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	var axis: Vector3 = side.rotated(direction, randf() * TAU)
	# Even density over the cone's disc, not bunched at the center.
	var angle: float = deg_to_rad(spread) * sqrt(randf())
	return direction.rotated(axis, angle).normalized()


## Where the shot visibly leaves from: the weapon in hand, or the camera when scoped (the body
## is hidden then) or when no weapon mesh is around.
func _get_muzzle_position(fallback: Vector3) -> Vector3:
	var orbit_camera: OrbitCamera = get_node_or_null(orbit_camera_path) as OrbitCamera
	if orbit_camera != null and orbit_camera.is_scoped():
		return fallback
	var skin_node: Node = _get_skin_node()
	if skin_node == null:
		return fallback
	var weapon_mesh: Node3D = skin_node.find_child("WeaponMesh", true, false) as Node3D
	if weapon_mesh == null or not weapon_mesh.visible:
		return fallback
	return weapon_mesh.global_position


func _try_shoot() -> void:
	if _cooldown_left_seconds > 0.0:
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
	var digs: bool = fire_profile.get("digs", false) and not lightweight_impacts

	var ray_origin: Vector3
	var ray_direction: Vector3
	var aim_ray: Dictionary = _get_aim_ray()
	ray_origin = aim_ray["origin"]
	ray_direction = aim_ray["direction"]
	if ray_direction.length_squared() <= 0.0001:
		return
	ray_direction = _apply_spread(ray_direction.normalized())
	_bloom_degrees = minf(_bloom_degrees + float(fire_profile.get("bloom", 0.5)), max_bloom_degrees)

	var ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_direction * max_shoot_distance
	)
	var shooter_body: CollisionObject3D = get_parent() as CollisionObject3D
	if shooter_body != null:
		ray_query.exclude = [shooter_body.get_rid()]
	var space: PhysicsDirectSpaceState3D = get_viewport().get_world_3d().direct_space_state
	var raycast_hit: Dictionary = space.intersect_ray(ray_query)
	if raycast_hit.is_empty():
		return
	shots_fired += 1

	var hit_position: Vector3 = raycast_hit.position
	_spawn_projectile_visual(
		_get_muzzle_position(ray_origin),
		hit_position,
		projectile_speed,
		projectile_radius,
		raycast_hit,
		hit_damage,
		explosion_radius,
		digs
	)

	_cooldown_left_seconds = cooldown_seconds
	_shoot_visual_timer_seconds = maxf(cooldown_seconds * 0.8, 0.06)
	_stance_timer_seconds = maxf(stance_hold_seconds, cooldown_seconds + 0.1)
	_update_skin_shooting_state()


func _spawn_projectile_visual(
	start_position: Vector3,
	target_position: Vector3,
	projectile_speed: float,
	projectile_radius: float,
	raycast_hit: Dictionary,
	hit_damage: float,
	explosion_radius: float,
	digs: bool
) -> void:
	var projectile_visual: ShootProjectileVisual = (
		ShootProjectileVisualScene.instantiate() as ShootProjectileVisual
	)
	if projectile_visual == null:
		_apply_shot_impact(raycast_hit, hit_damage, target_position, explosion_radius, digs)
		return

	var world_root: Node = get_tree().current_scene
	if world_root == null:
		projectile_visual.free()
		_apply_shot_impact(raycast_hit, hit_damage, target_position, explosion_radius, digs)
		return

	world_root.add_child(projectile_visual)
	projectile_visual.travel_speed = projectile_speed
	projectile_visual.launch(start_position, target_position, projectile_radius)
	projectile_visual.arrived.connect(
		_apply_shot_impact.bind(raycast_hit, hit_damage, target_position, explosion_radius, digs)
	)


func _apply_shot_impact(
	raycast_hit: Dictionary,
	hit_damage: float,
	hit_position: Vector3,
	explosion_radius: float,
	digs: bool
) -> void:
	var direct_hit: Damageable = _apply_damage_at_hit(raycast_hit, hit_damage)
	_apply_splash_damage(hit_position, explosion_radius, hit_damage, direct_hit)
	if digs:
		_apply_terrain_explosion(hit_position, explosion_radius)
	if not lightweight_impacts:
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
	var player_node: Node = get_parent()
	if player_node == null:
		return false
	if not _is_local_pilot():
		return true
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
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
	if not _is_local_pilot():
		var input: FighterInput = (get_parent() as FighterBody).get_input()
		if input.has_aim:
			return {"origin": input.aim_origin, "direction": input.aim_direction}
		return {"origin": Vector3.ZERO, "direction": Vector3.ZERO}
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
