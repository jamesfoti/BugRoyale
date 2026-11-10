class_name LooseRock
extends RefCounted
## Clears the floating rock out of a chunk's sampled field before it is meshed: a lump of
## solid samples with air on every side, up to a set number of voxels, is turned to air, so
## the sliver of cave wall the grid cut off its cavern, or the crumb a dig left hanging,
## does not float. At 4 m voxels most of what floats is the grid's own: a wall 4 to 8 m
## thick sampled every 4 m comes out as lone solid samples that no carver can smooth away.
##
## The chunks are built one by one, each from its own samples, and the samples on a chunk's
## faces are shared with its neighbours, so a lump on a face must be judged the same from
## both sides or the two meshes part along the seam. A lump is therefore cleared only when
## every chunk that holds a sample of it can see all of it: the pass may read up to HALO
## samples beyond the chunk's faces (evaluated from the density, and only where a small lump
## reaches them), so a lump that touches a face may extend one sample past it on either
## side and no further; lumps across a seam thicker than that are kept. Anything built with
## the brush (solid by an edit over what was air, or carrying a placed material) is never
## cleared: a block placed in the sky is a floating lump on purpose. Rock a dig thinned and
## cut loose is not built, and goes. Sealed air pockets are left alone: they are out of
## sight, and whether to fill one could turn on a lump the neighbouring chunk cannot see.

## Samples beyond the chunk's faces the pass may read.
const HALO: int = 2

## States of a padded sample: not yet evaluated (a halo sample), air, rock not yet reached,
## and from FIRST_LUMP up the number of the lump a rock sample was reached from.
const UNKNOWN: int = 0
const AIR: int = 1
const ROCK: int = 2
const FIRST_LUMP: int = 3

var _field: SignedDensityField
var _density: DensitySampler.WorldDensity
var _grid_world_origin: Vector3
var _grid_offset: Vector3i
var _step: float
var _cells: int
var _iso: float
var _max_voxels: int
var _values: PackedFloat32Array
var _padded: Vector3i
var _stride_y: int
var _stride_z: int
var _state: PackedInt32Array = PackedInt32Array()
var _queue: PackedInt32Array = PackedInt32Array()
var _pending: PackedInt32Array = PackedInt32Array()


## Clears the loose lumps of up to max_voxels samples from a chunk's field, in place, and
## returns how many samples it turned to air. The grid arguments are build_chunk_field's;
## cells_per_axis is the chunk's, so the pass knows where the neighbouring chunks' faces lie.
static func clear(
	field: SignedDensityField,
	density: DensitySampler.WorldDensity,
	grid_world_origin: Vector3,
	grid_offset: Vector3i,
	step: float,
	cells_per_axis: int,
	iso_level: float,
	max_voxels: int
) -> int:
	if max_voxels <= 0 or not field.is_valid():
		return 0
	var pass_state: LooseRock = LooseRock.new()
	pass_state._field = field
	pass_state._density = density
	pass_state._grid_world_origin = grid_world_origin
	pass_state._grid_offset = grid_offset
	pass_state._step = step
	pass_state._cells = cells_per_axis
	pass_state._iso = iso_level
	pass_state._max_voxels = max_voxels
	return pass_state._run()


func _run() -> int:
	var size: Vector3i = _field.size
	_values = _field.values
	_padded = size + Vector3i.ONE * (HALO * 2)
	_stride_y = _padded.x
	_stride_z = _padded.x * _padded.y
	_state.resize(_padded.x * _padded.y * _padded.z)
	_state.fill(UNKNOWN)
	var index: int = 0
	for z: int in size.z:
		for y: int in size.y:
			var row: int = HALO + (y + HALO) * _stride_y + (z + HALO) * _stride_z
			for x: int in size.x:
				_state[row + x] = ROCK if _values[index] < _iso else AIR
				index += 1
	var cleared: int = 0
	var lump: int = FIRST_LUMP
	for z: int in size.z:
		for y: int in size.y:
			var row: int = HALO + (y + HALO) * _stride_y + (z + HALO) * _stride_z
			for x: int in size.x:
				var cell: int = row + x
				if _state[cell] != ROCK:
					continue
				# Rock beside rock already kept (scanned before it, one sample back along x, y
				# or z) is part of that lump, so the mass of the ground costs a read per sample.
				var kept: int = _state[cell - 1]
				if kept < FIRST_LUMP:
					kept = _state[cell - _stride_y]
					if kept < FIRST_LUMP:
						kept = _state[cell - _stride_z]
				if kept >= FIRST_LUMP:
					_state[cell] = kept
					continue
				if _trace(cell, lump):
					cleared += _clear_lump()
				lump += 1
	if cleared > 0:
		_field.values = _values
		var min_value: float = INF
		var max_value: float = -INF
		for value: float in _values:
			min_value = minf(min_value, value)
			max_value = maxf(max_value, value)
		_field.min_value = min_value
		_field.max_value = max_value
	return cleared


## Follows the rock from a start sample through its neighbours, in the chunk first and out
## into the halo only while the chunk's part is small enough. True when the whole lump is
## small enough to clear, within sight of every chunk it touches, and none of it was built;
## the lump's samples are then the contents of _queue.
func _trace(start: int, lump: int) -> bool:
	_queue.clear()
	_pending.clear()
	_queue.append(start)
	_state[start] = lump
	var head: int = 0
	while true:
		while head < _queue.size():
			if not _spread(_queue[head], lump):
				return false
			head += 1
		if not _within_sight():
			return false
		if not _reach_into_halo(lump):
			return not _built()
		if _queue.size() > _max_voxels:
			return false
	return false


## Reaches a sample's six neighbours (unrolled: this is the pass's hot loop). False as soon
## as the lump is too big to clear or joins rock already kept (an earlier lump that was too
## big is still marked as itself).
func _spread(cell: int, lump: int) -> bool:
	var x: int = cell % _stride_y
	@warning_ignore("integer_division")
	var y: int = (cell % _stride_z) / _stride_y
	@warning_ignore("integer_division")
	var z: int = cell / _stride_z
	var state: int
	if x > 0:
		state = _state[cell - 1]
		if state == UNKNOWN:
			_pending.append(cell - 1)
		elif state == ROCK:
			_state[cell - 1] = lump
			_queue.append(cell - 1)
		elif state != AIR and state != lump:
			return false
	if x < _padded.x - 1:
		state = _state[cell + 1]
		if state == UNKNOWN:
			_pending.append(cell + 1)
		elif state == ROCK:
			_state[cell + 1] = lump
			_queue.append(cell + 1)
		elif state != AIR and state != lump:
			return false
	if y > 0:
		state = _state[cell - _stride_y]
		if state == UNKNOWN:
			_pending.append(cell - _stride_y)
		elif state == ROCK:
			_state[cell - _stride_y] = lump
			_queue.append(cell - _stride_y)
		elif state != AIR and state != lump:
			return false
	if y < _padded.y - 1:
		state = _state[cell + _stride_y]
		if state == UNKNOWN:
			_pending.append(cell + _stride_y)
		elif state == ROCK:
			_state[cell + _stride_y] = lump
			_queue.append(cell + _stride_y)
		elif state != AIR and state != lump:
			return false
	if z > 0:
		state = _state[cell - _stride_z]
		if state == UNKNOWN:
			_pending.append(cell - _stride_z)
		elif state == ROCK:
			_state[cell - _stride_z] = lump
			_queue.append(cell - _stride_z)
		elif state != AIR and state != lump:
			return false
	if z < _padded.z - 1:
		state = _state[cell + _stride_z]
		if state == UNKNOWN:
			_pending.append(cell + _stride_z)
		elif state == ROCK:
			_state[cell + _stride_z] = lump
			_queue.append(cell + _stride_z)
		elif state != AIR and state != lump:
			return false
	return _queue.size() <= _max_voxels


## Evaluates the halo samples the lump reached, one at a time, until one is rock: that one
## joins the lump (true). False when none of them is.
func _reach_into_halo(lump: int) -> bool:
	while not _pending.is_empty():
		var halo_cell: int = _pending[_pending.size() - 1]
		_pending.resize(_pending.size() - 1)
		if _state[halo_cell] != UNKNOWN:
			continue
		if _density.evaluate(_world_position(halo_cell)) >= _iso:
			_state[halo_cell] = AIR
			continue
		_state[halo_cell] = lump
		_queue.append(halo_cell)
		return true
	return false


## Whether every chunk holding a sample of the lump can see all of it: along each axis, the
## lump reaches no more than one sample past the faces of the chunks it touches (a
## neighbour's view ends HALO samples past its own face, and the air round the lump must be
## in view too).
func _within_sight() -> bool:
	var lowest: Vector3i = _coordinates(_queue[0])
	var highest: Vector3i = lowest
	for cell: int in _queue:
		var at: Vector3i = _coordinates(cell)
		lowest = lowest.min(at)
		highest = highest.max(at)
	for axis: int in 3:
		var low: int = lowest[axis] - HALO + _grid_offset[axis]
		var high: int = highest[axis] - HALO + _grid_offset[axis]
		var first_chunk: int = -_floor_divide(-low, _cells) - 1
		var last_chunk: int = _floor_divide(high, _cells)
		if high > (first_chunk + 1) * _cells + 1 or low < last_chunk * _cells - 1:
			return false
	return true


## Whether any sample of the traced lump was built: solid by an edit where the map's own
## ground was air, or carrying a placed material.
func _built() -> bool:
	var edits: TerrainEdits = _density.terrain_edits
	if edits == null or (edits.get_override_count() == 0 and not edits.has_materials()):
		return false
	for cell: int in _queue:
		var world_position: Vector3 = _world_position(cell)
		if edits.material_at(world_position) != TerrainMaterials.Kind.NATURAL:
			return true
		if (
			edits.is_overridden_at(world_position)
			and _density.evaluate(world_position, false) >= _iso
		):
			return true
	return false


## Turns the traced lump to air, mirroring each of the chunk's own samples about the iso
## level (a sample a little inside the rock becomes one a little outside it). Returns how
## many of the chunk's samples changed; the halo's belong to the neighbour's own pass.
func _clear_lump() -> int:
	var cleared: int = 0
	var size: Vector3i = _field.size
	for cell: int in _queue:
		_state[cell] = AIR
		var at: Vector3i = _coordinates(cell) - Vector3i.ONE * HALO
		if at.x < 0 or at.y < 0 or at.z < 0 or at.x >= size.x or at.y >= size.y or at.z >= size.z:
			continue
		var index: int = at.x + at.y * size.x + at.z * size.x * size.y
		_values[index] = _iso + (_iso - _values[index])
		cleared += 1
	return cleared


func _coordinates(cell: int) -> Vector3i:
	@warning_ignore("integer_division")
	return Vector3i(cell % _stride_y, (cell % _stride_z) / _stride_y, cell / _stride_z)


func _world_position(cell: int) -> Vector3:
	return DensitySampler.grid_sample_position(
		_grid_world_origin, _grid_offset + _coordinates(cell) - Vector3i.ONE * HALO, _step
	)


static func _floor_divide(value: int, divisor: int) -> int:
	@warning_ignore("integer_division")
	var quotient: int = value / divisor
	if (value % divisor != 0) and ((value < 0) != (divisor < 0)):
		quotient -= 1
	return quotient
