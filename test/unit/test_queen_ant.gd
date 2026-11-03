extends GutTest
## The queen's nest, as pure geometry: the workers' carves step down and away from the entrance
## and end in a chamber well below it, every carve is the pickaxe's (so the dirt pays into the
## colony's stock), and the way the queen goes down ends on the chamber floor. Checked flat and
## on a curved map (any up).

const ENTRANCE := Vector3(10.0, 2.0, -4.0)


func test_the_plan_steps_down_and_away_then_the_chamber() -> void:
	var plan: Array[Dictionary] = QueenAnt.nest_plan(ENTRANCE, Vector3.UP, Vector3.RIGHT)
	assert_eq(
		plan.size(), QueenAnt.SHAFT_STEPS + 2, "the shaft's steps, the entrance and the chamber"
	)
	assert_eq(plan[0]["position"], ENTRANCE, "the first carve is the entrance itself")
	var previous: Vector3 = ENTRANCE
	for index: int in range(1, plan.size()):
		var center: Vector3 = plan[index]["position"]
		assert_lt(center.y, previous.y, "each carve is deeper than the last")
		assert_gt(center.x, previous.x - 0.001, "and no nearer the entrance along the ground")
		assert_almost_eq(center.z, ENTRANCE.z, 0.001, "the shaft keeps its line")
		previous = center
	var chamber: Dictionary = plan.back()
	assert_almost_eq(float(chamber["radius"]), QueenAnt.CHAMBER_RADIUS, 0.001)
	assert_almost_eq(chamber["position"].y, ENTRANCE.y - QueenAnt.CHAMBER_DEPTH, 0.001)
	for carve: Dictionary in plan:
		assert_false(bool(carve["add"]), "the workers only dig")
		assert_eq(str(carve["tool"]), TerrainBrush.PICKAXE_TOOL, "dug, so the dirt is the colony's")


func test_the_way_down_follows_the_shaft_to_the_chamber_floor() -> void:
	var path: PackedVector3Array = QueenAnt.settle_path(ENTRANCE, Vector3.UP, Vector3.FORWARD)
	var plan: Array[Dictionary] = QueenAnt.nest_plan(ENTRANCE, Vector3.UP, Vector3.FORWARD)
	assert_eq(path.size(), plan.size())
	for index: int in path.size() - 1:
		assert_eq(path[index], plan[index]["position"], "down the shaft carve by carve")
	var chamber: Vector3 = plan.back()["position"]
	assert_lt(path[path.size() - 1].y, chamber.y, "ending below the chamber's centre, on its floor")
	assert_gt(
		path[path.size() - 1].y, chamber.y - QueenAnt.CHAMBER_RADIUS, "but inside the chamber"
	)


func test_a_wish_with_no_ground_direction_still_gets_a_shaft() -> void:
	var plan: Array[Dictionary] = QueenAnt.nest_plan(ENTRANCE, Vector3.UP, Vector3.UP)
	var last: Vector3 = plan[plan.size() - 2]["position"]
	var flat: float = Vector2(last.x - ENTRANCE.x, last.z - ENTRANCE.z).length()
	assert_almost_eq(flat, QueenAnt.SHAFT_STEP * QueenAnt.SHAFT_STEPS, 0.01)


func test_the_nest_goes_down_along_any_up() -> void:
	var up: Vector3 = Vector3(1.0, 1.0, 0.0).normalized()
	var plan: Array[Dictionary] = QueenAnt.nest_plan(ENTRANCE, up, Vector3.FORWARD)
	var chamber: Vector3 = plan.back()["position"]
	assert_almost_eq((chamber - ENTRANCE).dot(up), -QueenAnt.CHAMBER_DEPTH, 0.001)
	assert_almost_eq(
		(chamber - ENTRANCE).dot(Vector3.FORWARD),
		QueenAnt.SHAFT_STEP * QueenAnt.SHAFT_STEPS,
		0.001,
		"ground direction is kept"
	)
