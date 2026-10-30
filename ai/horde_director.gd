class_name HordeDirector
extends Node
## The pressure in a co-op mode, inspired by Left 4 Dead. Hornet nests hold their patches of
## ground. A noise meter listens to the squad (shots, blasts, digging, sprinting; a squadmate
## bot's gun counts for a fraction) and sends a horde when it fills, another after a long lull,
## and one on a timer during a finale. The mode announces what goes out; the director keeps the
## flocks, the meter and the horde count, and snapshots the two numbers a client shows.
##
## Every flock is built by make_flock, which reads the map's flight band and flying obstacles,
## so a mode never has to know which map it is on.

## A horde went out (the mode announces it).
signal horde_sent(count: int, reason: Reason)

enum Reason { NOISE, LULL, FINALE }

const NOISE_MAX: float = 100.0

## What feeds the meter, and how it fades.
var noise_shot: float = 4.0
var noise_blast: float = 18.0
var noise_dig: float = 7.0
var noise_run_per_second: float = 3.0
var noise_decay_per_second: float = 7.0
var noise_after_horde: float = 30.0
## How much of a squadmate bot's noise counts (the director watches the players).
var bot_noise_share: float = 0.2
var horde_cooldown_seconds: float = 25.0
## A horde comes anyway after this long without one, and this often during a finale.
var lull_seconds: float = 80.0
var finale_seconds: float = 12.0
var horde_base: int = 8
var horde_growth: int = 3
var horde_max: int = 40

var map: MapInfo
## Where the flocks go (the map scene's root).
var world_root: Node
var prey_group: StringName = &"player"
var enemy_team: int = Damageable.NO_TEAM
var noise: float = 0.0
var hordes: int = 0
var finale: bool = false

var _horde_flock: BirdFlock
var _nests: Array[BirdFlock] = []
var _cooldown: float = 0.0
var _lull: float = 0.0
var _finale_timer: float = 0.0


## Points the director at a map and the group it hunts. Call before building flocks.
func setup(map_info: MapInfo, world: Node, prey: StringName, team: int) -> void:
	map = map_info
	world_root = world
	prey_group = prey
	enemy_team = team


# --- Flocks ------------------------------------------------------------------------------------


## A flock of hornets hunting the prey group, flying in the map's band and around its obstacles.
static func make_flock(
	parent: Node, map_info: MapInfo, prey: StringName, team: int, flock_name: String
) -> BirdFlock:
	var flock := BirdFlock.new()
	flock.name = flock_name
	flock.auto_build = false
	flock.map = map_info
	flock.target_group = prey
	flock.hornet_team = team
	var band: Vector2 = map_info.flight_band()
	flock.min_height = band.x
	flock.max_height = band.y
	flock.obstacles = map_info.flying_obstacles()
	parent.add_child(flock)
	return flock


## A nest: hornets that patrol a patch of ground and attack what comes near.
func add_nest(center: Vector3, count: int, patrol_radius: float = 10.0) -> BirdFlock:
	var nest: BirdFlock = make_flock(
		world_root, map, prey_group, enemy_team, "HornetNest%d" % _nests.size()
	)
	nest.follow_targets = false
	nest.spawn_radius = patrol_radius
	nest.attack_detection_radius = 20.0
	nest.global_position = center + map.up_at(center) * 5.0
	nest.spawn_wave(count)
	_nests.append(nest)
	return nest


## The flock hordes arrive in: it chases the squad wherever it goes.
func build_horde_flock() -> void:
	_horde_flock = make_flock(world_root, map, prey_group, enemy_team, "Horde")
	_horde_flock.follow_targets = true
	_horde_flock.spawn_radius = 45.0
	_horde_flock.attack_detection_radius = 60.0
	_horde_flock.max_speed = 13.0
	_horde_flock.max_attack_speed = 19.0
	_horde_flock.attack_damage = 8.0


# --- Listening ---------------------------------------------------------------------------------


## Hears a squad member's gun; a bot's counts for a fraction.
func listen_to(fighter: Fighter) -> void:
	var shooter: Node = fighter.body.get_node_or_null("ShooterTest")
	if shooter != null and shooter.has_signal("fired"):
		shooter.connect("fired", _on_fired.bind(fighter.is_human))


## Hears the pickaxe: any terrain edit on the map.
func listen_to_terrain() -> void:
	var terrain: ChunkedTerrainWorld = (
		get_tree().get_first_node_in_group("terrain_world") as ChunkedTerrainWorld
	)
	if terrain != null:
		terrain.edit_applied.connect(func(_edit: Dictionary) -> void: hear(noise_dig))


func hear(amount: float) -> void:
	noise = clampf(noise + amount, 0.0, NOISE_MAX)


func _on_fired(explosion_radius: float, human: bool) -> void:
	var loudness: float = noise_blast if explosion_radius > 0.6 else noise_shot
	hear(loudness if human else loudness * bot_noise_share)


# --- Deciding ----------------------------------------------------------------------------------


## Once per frame on the host: fades the meter, hears the squad sprinting, and sends hordes.
func tick(delta: float, squad: Array[Fighter]) -> void:
	_cooldown -= delta
	_lull += delta
	for fighter: Fighter in squad:
		if not fighter.is_alive():
			continue
		if fighter.body.get_input().run and fighter.body.velocity.length() > 4.0:
			hear(noise_run_per_second * delta)
	# The full-meter check comes before the fade: a meter that just reached the top must fire,
	# not slip under it by a frame's decay.
	if noise >= NOISE_MAX and _cooldown <= 0.0:
		noise = noise_after_horde
		send_horde(Reason.NOISE)
	elif _lull >= lull_seconds:
		send_horde(Reason.LULL)
	noise = clampf(noise - noise_decay_per_second * delta, 0.0, NOISE_MAX)
	if finale:
		_finale_timer -= delta
		if _finale_timer <= 0.0:
			_finale_timer = finale_seconds
			send_horde(Reason.FINALE)


func send_horde(reason: Reason) -> void:
	_cooldown = horde_cooldown_seconds
	_lull = 0.0
	var count: int = mini(horde_base + hordes * horde_growth, horde_max)
	if _horde_flock != null:
		_horde_flock.spawn_wave(count)
	hordes += 1
	horde_sent.emit(count, reason)


## Hordes on a timer from now on (the first one soon), on top of the meter.
func start_finale() -> void:
	finale = true
	_finale_timer = finale_seconds * 0.5


func stop_finale() -> void:
	finale = false


# --- Showing -----------------------------------------------------------------------------------


## The meter as a bar of `cells` characters.
static func noise_bar(noise_now: float, cells: int) -> String:
	var filled: int = clampi(ceili(noise_now / NOISE_MAX * cells), 0, cells)
	return "#".repeat(filled) + ".".repeat(cells - filled)


func snapshot() -> Dictionary:
	return {"noise": noise, "hordes": hordes}


func apply(state: Dictionary) -> void:
	noise = float(state.get("noise", noise))
	hordes = int(state.get("hordes", hordes))
