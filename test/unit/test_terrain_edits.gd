extends GutTest
## The edit layer on its own: stamps into a flat world whose density is just the height, so
## everything below y = 0 is solid and everything above is air.

var _edits: TerrainEdits


func flat_ground(world_position: Vector3) -> float:
	return world_position.y


func _density() -> Callable:
	return Callable(self, "flat_ground")


func _solid_at(position: Vector3) -> bool:
	return _edits.apply_to_density(flat_ground(position), position) < 0.0


func before_each() -> void:
	_edits = TerrainEdits.new()
	_edits.set_voxel_size(1.0)
	_edits.set_grid_origin(Vector3.ZERO)


func test_sphere_in_the_air_turns_its_samples_solid() -> void:
	var changed: bool = _edits.add_brush(Vector3(0, 3, 0), 2.0, true, _density())
	assert_true(changed, "the stamp changed voxels")
	assert_true(_solid_at(Vector3(0, 3, 0)), "the centre is solid")
	assert_true(_solid_at(Vector3(1, 3, 0)), "a sample inside the radius is solid")
	assert_false(_solid_at(Vector3(0, 6, 0)), "a sample beyond the shell is untouched air")


func test_shell_sample_is_written_but_stays_air() -> void:
	_edits.add_brush(Vector3(0, 3, 0), 2.0, true, _density())
	# (0, 5, 0) sits exactly on the sphere: its distance is written (zero) but it is not solid.
	assert_false(_solid_at(Vector3(0, 5, 0)))
	assert_almost_eq(
		_edits.apply_to_density(flat_ground(Vector3(0, 5, 0)), Vector3(0, 5, 0)), 0.0, 0.0001
	)


func test_placed_material_tags_only_voxels_inside_the_stamp() -> void:
	# Half buried in natural ground: (0, 0, 0) is inside the sphere, (0, -1, 0) is in its shell.
	_edits.add_brush(Vector3(0, 1, 0), 1.5, true, _density(), TerrainMaterials.Kind.STONE)
	assert_eq(
		_edits.material_at(Vector3(0, 1, 0)),
		TerrainMaterials.Kind.STONE,
		"the centre takes the material"
	)
	assert_eq(
		_edits.material_at(Vector3(0, 0, 0)),
		TerrainMaterials.Kind.STONE,
		"ground inside the sphere is re-skinned"
	)
	assert_eq(
		_edits.material_at(Vector3(0, -1, 0)),
		TerrainMaterials.Kind.NATURAL,
		"ground in the shell keeps its own material"
	)
	assert_true(_edits.has_materials())


func test_carving_removes_ground_and_forgets_its_material() -> void:
	_edits.add_brush(Vector3(0, -3, 0), 1.5, true, _density(), TerrainMaterials.Kind.STONE)
	assert_eq(_edits.material_at(Vector3(0, -3, 0)), TerrainMaterials.Kind.STONE)
	var changed: bool = _edits.add_brush(Vector3(0, -3, 0), 1.5, false, _density())
	assert_true(changed)
	assert_false(_solid_at(Vector3(0, -3, 0)), "the carved centre is air")
	assert_eq(
		_edits.material_at(Vector3(0, -3, 0)), TerrainMaterials.Kind.NATURAL, "air has no material"
	)


func test_repeating_an_edit_that_changes_nothing_reports_no_change() -> void:
	assert_true(
		_edits.add_brush(Vector3(0, -3, 0), 1.5, false, _density()), "first carve changes voxels"
	)
	assert_false(
		_edits.add_brush(Vector3(0, -3, 0), 1.5, false, _density()),
		"the same carve again changes nothing"
	)


func test_box_with_faces_on_sample_planes_is_two_voxels_wide() -> void:
	# A block two voxels on a side, pushed out by a hair so its face samples are just solid.
	var half: Vector3 = Vector3.ONE * 1.02
	assert_true(_edits.add_box(Vector3(0, 3, 0), half, true, _density()))
	for offset: Vector3 in [
		Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)
	]:
		assert_true(_solid_at(Vector3(0, 3, 0) + offset), "face sample %s is solid" % offset)
	for offset: Vector3 in [
		Vector3(2, 0, 0), Vector3(-2, 0, 0), Vector3(0, 2, 0), Vector3(0, 0, -2)
	]:
		assert_false(
			_solid_at(Vector3(0, 3, 0) + offset), "sample %s beyond the face is air" % offset
		)


func test_voxel_keys_follow_the_grid_origin() -> void:
	_edits.set_grid_origin(Vector3(10.0, 0.0, 0.0))
	_edits.add_brush(Vector3(10, 3, 0), 1.5, true, _density())
	assert_true(_solid_at(Vector3(10, 3, 0)), "the stamp lands at the world position")
	assert_false(_solid_at(Vector3(0, 3, 0)), "nothing lands at the un-offset position")


func test_export_and_import_keep_every_voxel_and_material() -> void:
	_edits.add_brush(Vector3(0, 3, 0), 2.0, true, _density(), TerrainMaterials.Kind.STONE)
	_edits.add_brush(Vector3(6, -2, 0), 1.5, false, _density())
	var state: Dictionary = _edits.export_state()

	var copy: TerrainEdits = TerrainEdits.new()
	copy.set_voxel_size(1.0)
	copy.set_grid_origin(Vector3.ZERO)
	copy.import_state(state)

	assert_eq(copy.get_override_count(), _edits.get_override_count())
	for position: Vector3 in [
		Vector3(0, 3, 0), Vector3(0, 5, 0), Vector3(6, -2, 0), Vector3(6, -4, 0)
	]:
		assert_almost_eq(
			copy.apply_to_density(flat_ground(position), position),
			_edits.apply_to_density(flat_ground(position), position),
			0.0001,
			"density at %s survives the round trip" % position
		)
	assert_eq(copy.material_at(Vector3(0, 3, 0)), TerrainMaterials.Kind.STONE)


func test_all_bounds_enclose_every_stamp() -> void:
	assert_eq(_edits.get_all_bounds().size, Vector3.ZERO, "no edits, no bounds")
	_edits.add_brush(Vector3(0, 3, 0), 2.0, true, _density())
	_edits.add_brush(Vector3(20, -2, 5), 1.5, false, _density())
	var bounds: AABB = _edits.get_all_bounds()
	assert_true(bounds.has_point(Vector3(0, 3, 0)))
	assert_true(bounds.has_point(Vector3(20, -2, 5)))
	assert_true(bounds.has_point(Vector3(0, 5, 0)), "the shell is inside the bounds")
