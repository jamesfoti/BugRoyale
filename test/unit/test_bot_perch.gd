extends GutTest
## A bot that lands on another bug (a worker dropping off a raised bed after its leader) steps
## off its back instead of standing there for good because the leader is "close enough".

const _CAPSULE_RADIUS: float = 0.3
const _CAPSULE_HEIGHT: float = 1.2
const _GRAVITY: float = 9.8
const _SETTLE_FRAMES: int = 40

var _leader: FighterBody
var _bot: FighterBody
var _brain: BotBrain


func before_each() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = MapInfo.TERRAIN_LAYER
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	floor_shape.shape = box
	floor_shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(floor_shape)
	add_child_autofree(floor_body)
	_leader = _make_fighter(Vector3(0.0, _CAPSULE_HEIGHT * 0.5, 0.0))


func test_a_bot_dropped_on_a_fighter_walks_off() -> void:
	_bot = _make_fighter(Vector3(0.05, _CAPSULE_HEIGHT * 1.5 + 0.4, 0.0))
	_attach_brain()
	await _settle()
	assert_true(_bot.is_on_floor(), "landed on something")
	assert_gt(_bot.global_position.y, _CAPSULE_HEIGHT, "on the leader's back, not the ground")
	var input: FighterInput = _brain.sample(_bot, 1.0 / 60.0)
	assert_gt(input.move.length(), 0.5, "steps off instead of standing still")


func test_a_bot_beside_its_leader_stays_put() -> void:
	_bot = _make_fighter(Vector3(2.0, _CAPSULE_HEIGHT * 0.5 + 0.2, 0.0))
	_attach_brain()
	await _settle()
	assert_true(_bot.is_on_floor(), "on the ground")
	assert_lt(_bot.global_position.y, _CAPSULE_HEIGHT, "beside the leader, not on it")
	var input: FighterInput = _brain.sample(_bot, 1.0 / 60.0)
	assert_eq(input.move, Vector2.ZERO, "within reach of the leader: no need to move")


func _make_fighter(at: Vector3) -> FighterBody:
	var body := FighterBody.new()
	body.use_bot_skin = true
	body.skin_override_path = CharacterSkin.BLACK_ANT_BOT_SCENE_PATH
	body.collision_layer = MapInfo.FIGHTER_LAYER
	body.collision_mask = MapInfo.TERRAIN_LAYER | MapInfo.FIGHTER_LAYER
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = _CAPSULE_RADIUS
	capsule.height = _CAPSULE_HEIGHT
	shape.shape = capsule
	body.add_child(shape)
	var visual_root := Node3D.new()
	visual_root.name = "VisualRoot"
	body.add_child(visual_root)
	var health := Damageable.new()
	health.name = "Damageable"
	health.team = 1
	body.add_child(health)
	body.position = at
	add_child_autofree(body)
	return body


func _attach_brain() -> void:
	_brain = BotBrain.new()
	_brain.name = "BotBrain"
	_brain.map = MapInfo.new()
	_brain.leader = _leader
	_brain.detection_range = 0.0
	_bot.add_child(_brain)


## Lets both bodies fall under gravity until they rest (the test bodies have no mover of their
## own: FighterBody leaves movement to its subclass).
func _settle() -> void:
	for _frame: int in _SETTLE_FRAMES:
		await wait_physics_frames(1)
		for body: FighterBody in [_leader, _bot]:
			body.velocity += Vector3.DOWN * _GRAVITY / 60.0
			body.move_and_slide()
