class_name BoidsRules
extends RefCounted
## Classic boids steering: separation, alignment, and cohesion.
## This is the flock's O(n²) inner loop, so it compares squared distances and never takes a
## square root per pair.


static func compute_steering(
	index: int,
	positions: PackedVector3Array,
	velocities: PackedVector3Array,
	separation_radius: float,
	alignment_radius: float,
	cohesion_radius: float,
	separation_weight: float,
	alignment_weight: float,
	cohesion_weight: float
) -> Vector3:
	var position: Vector3 = positions[index]
	var velocity: Vector3 = velocities[index]
	var separation: Vector3 = Vector3.ZERO
	var alignment: Vector3 = Vector3.ZERO
	var cohesion: Vector3 = Vector3.ZERO
	var alignment_count: int = 0
	var cohesion_count: int = 0
	var separation_radius_sq: float = separation_radius * separation_radius
	var alignment_radius_sq: float = alignment_radius * alignment_radius
	var cohesion_radius_sq: float = cohesion_radius * cohesion_radius
	var widest_radius_sq: float = maxf(
		separation_radius_sq, maxf(alignment_radius_sq, cohesion_radius_sq)
	)

	for other_index in positions.size():
		if other_index == index:
			continue
		var offset: Vector3 = position - positions[other_index]
		var distance_sq: float = offset.length_squared()
		if distance_sq < 0.0001 or distance_sq >= widest_radius_sq:
			continue

		if distance_sq < separation_radius_sq:
			separation += offset / distance_sq

		if distance_sq < alignment_radius_sq:
			alignment += velocities[other_index]
			alignment_count += 1

		if distance_sq < cohesion_radius_sq:
			cohesion += positions[other_index]
			cohesion_count += 1

	var steering: Vector3 = Vector3.ZERO
	if separation != Vector3.ZERO:
		steering += separation.normalized() * separation_weight

	if alignment_count > 0:
		alignment /= float(alignment_count)
		alignment = (alignment - velocity).normalized() * alignment_weight
		steering += alignment

	if cohesion_count > 0:
		cohesion = cohesion / float(cohesion_count) - position
		if cohesion != Vector3.ZERO:
			steering += cohesion.normalized() * cohesion_weight

	return steering
