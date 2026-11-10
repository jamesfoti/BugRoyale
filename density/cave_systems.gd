class_name CaveSystems
extends RefCounted
## Carved cave systems: a seed's handful of passages that start at a mouth on the surface
## and worm their way down, the way Minecraft's old carver did beside its noise caves. Noise
## can give the underworld its texture but not an entrance on a hillside that leads
## somewhere, a passage with a direction, a dead end or a junction; these are that. Each
## system is a random walk of capsules: from the mouth it heads down at a pitch, turns a
## little each step with a persistent lean so it curves rather than jitters, swells and
## pinches along its length, branches now and then, and ends in a chamber. The mouths are
## picked on the steepest ground among a few candidates, so they open on cliff faces and
## hillsides where you expect a cave.
##
## Rolled from the seed, the world's bounds and a surface height function, so every chunk
## builds the same systems; a chunk prepares the segments in its reach once, and a sample
## far from all of them costs a few comparisons.

## Metres per step of the walk, how many spots a mouth's chooser tries for steep ground,
## and how near another mouth a spot may be before it is passed over.
const STEP: float = 5.0
const MOUTH_CANDIDATES: int = 6
const MOUTH_SPACING: float = 80.0
## A segment is skipped outside its box grown by its radius and this, the carver's blend.
const REACH: float = 2.5
## Metres of ground kept above bedrock, as the carver's own clearance.
const FLOOR_CLEARANCE: float = 6.0
## Systems per square kilometre of map, least and most, and each one's budget of steps.
const PER_KM2: Vector2 = Vector2(10.0, 24.0)
const STEPS: Vector2i = Vector2i(24, 60)
## Passage radius drawn per system, in metres, and the chamber at the end as a multiple.
const RADIUS: Vector2 = Vector2(2.0, 3.4)
const CHAMBER: float = 2.2

var count: int = 0
## Segment endpoints and their radii; a passage is the union of its capsules, each radius
## running from one end's to the other's.
var starts: PackedVector3Array = PackedVector3Array()
var ends: PackedVector3Array = PackedVector3Array()
var start_radii: PackedFloat32Array = PackedFloat32Array()
var end_radii: PackedFloat32Array = PackedFloat32Array()
## The mouths, one per system, on the surface.
var mouths: PackedVector3Array = PackedVector3Array()
## Per segment: the box a sample must be in to be within REACH of it.
var _box_min: PackedVector3Array = PackedVector3Array()
var _box_max: PackedVector3Array = PackedVector3Array()
## The segments a prepared region can reach (all of them until prepare_region is called).
var _region: PackedInt32Array = PackedInt32Array()


## Rolls a seed's systems inside bounds (world space); height is (x, z) -> surface height,
## and nothing is carved below floor_y plus the clearance.
static func roll(seed_value: int, bounds: AABB, height: Callable, floor_y: float) -> CaveSystems:
	var systems: CaveSystems = CaveSystems.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(seed_value, 1301))
	var km2: float = bounds.size.x * bounds.size.z / 1000000.0
	systems.count = maxi(roundi(rng.randf_range(PER_KM2.x, PER_KM2.y) * km2), 1)
	var inset: float = 30.0
	var low := Vector2(bounds.position.x + inset, bounds.position.z + inset)
	var high := Vector2(bounds.end.x - inset, bounds.end.z - inset)
	if high.x <= low.x or high.y <= low.y:
		low = Vector2(bounds.position.x, bounds.position.z)
		high = Vector2(bounds.end.x, bounds.end.z)
	for _system: int in systems.count:
		var mouth: Vector2 = _steepest_spot(rng, low, high, height, systems.mouths)
		var top: float = height.call(mouth.x, mouth.y)
		systems.mouths.append(Vector3(mouth.x, top, mouth.y))
		var radius: float = rng.randf_range(RADIUS.x, RADIUS.y)
		systems._walk(
			rng,
			Vector3(mouth.x, top + 0.5, mouth.y),
			rng.randf_range(0.0, TAU),
			radius,
			rng.randi_range(STEPS.x, STEPS.y),
			bounds,
			floor_y + FLOOR_CLEARANCE,
			true
		)
	systems._region.resize(systems.starts.size())
	for index: int in systems.starts.size():
		systems._region[index] = index
	return systems


## Of a few random spots, the one on the steepest ground: a cave mouth on a hillside. A
## spot within MOUTH_SPACING of a mouth already placed counts as flat, so one cliff does
## not take every mouth (unless every spot is near one).
static func _steepest_spot(
	rng: RandomNumberGenerator,
	low: Vector2,
	high: Vector2,
	height: Callable,
	taken: PackedVector3Array
) -> Vector2:
	var best := Vector2.ZERO
	var best_slope: float = -1.0
	for _candidate: int in MOUTH_CANDIDATES:
		var spot := Vector2(rng.randf_range(low.x, high.x), rng.randf_range(low.y, high.y))
		var here: float = height.call(spot.x, spot.y)
		var along_x: float = height.call(spot.x + 2.0, spot.y) - here
		var along_z: float = height.call(spot.x, spot.y + 2.0) - here
		var slope: float = along_x * along_x + along_z * along_z
		for mouth: Vector3 in taken:
			if Vector2(mouth.x, mouth.z).distance_to(spot) < MOUTH_SPACING:
				slope = 0.0
				break
		if slope > best_slope:
			best_slope = slope
			best = spot
	return best


## Walks one passage from a point: each step turns by the lean plus a wobble, pitches toward
## going down early and levelling later, and lays a capsule whose radius swells and pinches.
## Branches split off at an angle with a smaller radius and the rest of the budget halved.
func _walk(
	rng: RandomNumberGenerator,
	from: Vector3,
	yaw: float,
	radius: float,
	steps: int,
	bounds: AABB,
	lowest_y: float,
	trunk: bool
) -> void:
	var at: Vector3 = from
	var pitch: float = -rng.randf_range(0.6, 0.9)
	var lean: float = rng.randf_range(-0.07, 0.07)
	var phase: float = rng.randf_range(0.0, TAU)
	var last_radius: float = radius
	for step: int in steps:
		yaw += lean + rng.randf_range(-0.3, 0.3)
		# Steeply in at the mouth, down for the first third, then wandering about level
		# with dips and rises.
		var target_pitch: float = -0.4 if step < steps / 3 else rng.randf_range(-0.3, 0.15)
		if step < 3:
			target_pitch = -0.75
		pitch = lerpf(pitch, target_pitch, 0.3) + rng.randf_range(-0.1, 0.1)
		pitch = clampf(pitch, -1.0, 0.3)
		var direction := Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch))
		var next: Vector3 = at + direction * STEP
		if (
			next.y < lowest_y
			or not bounds.has_point(Vector3(next.x, bounds.position.y + 1.0, next.z))
		):
			break
		var swell: float = 0.8 + 0.35 * sin(float(step) * 0.45 + phase)
		var next_radius: float = radius * swell
		_add_segment(at, next, last_radius, next_radius)
		at = next
		last_radius = next_radius
		if trunk and step > 6 and step < steps - 6 and rng.randf() < 0.05:
			var side: float = rng.randf_range(0.7, 1.4) * (1.0 if rng.randf() < 0.5 else -1.0)
			_walk(rng, at, yaw + side, radius * 0.75, (steps - step) / 2, bounds, lowest_y, false)
	# A chamber where the passage ends, if it got well underground.
	if at.y < from.y - 15.0:
		var chamber: float = radius * CHAMBER
		_add_segment(at, at + Vector3(0.0, 0.01, 0.0), chamber, chamber)


func _add_segment(a: Vector3, b: Vector3, radius_a: float, radius_b: float) -> void:
	starts.append(a)
	ends.append(b)
	start_radii.append(radius_a)
	end_radii.append(radius_b)
	var grow: Vector3 = Vector3.ONE * (maxf(radius_a, radius_b) + REACH)
	_box_min.append(a.min(b) - grow)
	_box_max.append(a.max(b) + grow)


## Keeps only the segments that can reach a region (a chunk's samples plus the halo its
## normals and the loose rock pass read), so every sample there asks those alone.
func prepare_region(region: AABB) -> void:
	_region.clear()
	for index: int in starts.size():
		var box := AABB(_box_min[index], _box_max[index] - _box_min[index])
		if region.intersects(box):
			_region.append(index)


## Metres of air the systems put at a point: positive inside a passage, negative metres to
## the nearest one within REACH of it, and -INF further away than that.
func air(world_pos: Vector3) -> float:
	var best: float = -INF
	for index: int in _region:
		var low: Vector3 = _box_min[index]
		if world_pos.x < low.x or world_pos.y < low.y or world_pos.z < low.z:
			continue
		var high: Vector3 = _box_max[index]
		if world_pos.x > high.x or world_pos.y > high.y or world_pos.z > high.z:
			continue
		var a: Vector3 = starts[index]
		var along: Vector3 = ends[index] - a
		var length_squared: float = along.length_squared()
		var t: float = 0.0
		if length_squared > 0.000001:
			t = clampf((world_pos - a).dot(along) / length_squared, 0.0, 1.0)
		var distance: float = world_pos.distance_to(a + along * t)
		best = maxf(best, lerpf(start_radii[index], end_radii[index], t) - distance)
	return best


func summary() -> String:
	return "%d cave systems of %d passages" % [count, starts.size()]
