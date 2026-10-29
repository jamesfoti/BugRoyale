extends GutTest
## Where the block tool puts a block for a given hit: the grid maths in
## TerrainBrush.snap_block_center, on a unit lattice unless a test says otherwise.

const UNIT: float = 1.0
const ORIGIN: Vector3 = Vector3.ZERO


func _snap(hit: Vector3, normal: Vector3, size: int, add: bool, voxel: float = UNIT, origin: Vector3 = ORIGIN) -> Vector3:
	return TerrainBrush.snap_block_center(hit, normal, voxel, origin, size, add)


func test_placing_on_natural_ground_buries_the_block_up_to_a_voxel() -> void:
	# The surface at y = 3.4 is between sample planes 3 and 4: the block sits on plane 3.
	var center: Vector3 = _snap(Vector3(0.3, 3.4, 0.2), Vector3.UP, 2, true)
	assert_eq(center, Vector3(0, 4, 0))


func test_removing_from_natural_ground_takes_the_block_below_the_face() -> void:
	var center: Vector3 = _snap(Vector3(0.3, 3.4, 0.2), Vector3.UP, 2, false)
	assert_eq(center, Vector3(0, 2, 0))


func test_placing_on_a_block_top_stacks_flush() -> void:
	# A drawn block's face sits a hair past its sample plane (the face bias); the slack snaps it back.
	var center: Vector3 = _snap(Vector3(0.1, 5.02, 0.1), Vector3.UP, 2, true)
	assert_eq(center, Vector3(0, 6, 0))


func test_removing_a_block_by_its_top_takes_that_block() -> void:
	var center: Vector3 = _snap(Vector3(0.1, 5.02, 0.1), Vector3.UP, 2, false)
	assert_eq(center, Vector3(0, 4, 0))


func test_placing_against_a_side_face_goes_outward() -> void:
	var center: Vector3 = _snap(Vector3(5.02, 3.9, 0.2), Vector3.RIGHT, 2, true)
	assert_eq(center, Vector3(6, 4, 0))


func test_placing_against_a_negative_side_face_goes_the_other_way() -> void:
	var center: Vector3 = _snap(Vector3(-1.02, 3.9, 0.2), Vector3.LEFT, 2, true)
	assert_eq(center, Vector3(-2, 4, 0))


func test_odd_sized_block_centres_between_samples() -> void:
	# Three voxels wide: the corner snaps to a sample, so the centre lands on a half.
	var center: Vector3 = _snap(Vector3(0.3, 3.4, 0.2), Vector3.UP, 3, true)
	assert_eq(center, Vector3(0.5, 4.5, 0.5))


func test_one_voxel_block_sits_on_the_face_plane() -> void:
	var center: Vector3 = _snap(Vector3(0.3, 3.4, 0.2), Vector3.UP, 1, true)
	assert_eq(center, Vector3(0.5, 3.5, 0.5))


func test_lattice_with_a_bigger_voxel_and_an_offset_origin() -> void:
	# Two-metre voxels with the lattice starting at x = 10: the hit is (0.3, 3.4, 0) in lattice units.
	var center: Vector3 = _snap(Vector3(10.6, 6.8, 0.0), Vector3.UP, 2, true, 2.0, Vector3(10, 0, 0))
	assert_eq(center, Vector3(10, 8, 0))


func test_dominant_axis_of_a_slanted_normal_wins() -> void:
	# Mostly up with a little lean still counts as a top-face hit.
	var center: Vector3 = _snap(Vector3(0.3, 3.4, 0.2), Vector3(0.2, 0.9, 0.1).normalized(), 2, true)
	assert_eq(center, Vector3(0, 4, 0))
