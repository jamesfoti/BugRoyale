class_name BiomePatches
extends RefCounted
## Patches of a map that each draw one kind from a weighted list: the land biomes on top and
## the cave biomes below both pick this way. The map is cut into cells of a jittered grid,
## patch_size metres across, and the position looked up is first pushed about by a slow
## noise so the borders curve instead of running straight. Each cell draws its kind from the
## list by weight with its own hash, so a weight of 3 against 1 gives three patches in four
## on average whatever the patch size, a weight of 0 drops a kind, and a list with one
## weight is that kind everywhere.

## How far the warp pushes the lookup, as a share of the patch size.
const WARP: float = 0.35


## The warp noise for a list, one swell per patch.
static func make_warp(seed_value: int, patch_size: float) -> FastNoiseLite:
	var warp := FastNoiseLite.new()
	warp.seed = seed_value
	warp.noise_type = FastNoiseLite.TYPE_SIMPLEX
	warp.frequency = 1.0 / maxf(patch_size, 1.0)
	warp.fractal_type = FastNoiseLite.FRACTAL_NONE
	return warp


## The index into weights of the patch at a column, or -1 when every weight is 0.
static func pick(
	world_x: float,
	world_z: float,
	seed_value: int,
	patch_size: float,
	warp: FastNoiseLite,
	weights: PackedFloat32Array
) -> int:
	var total: float = 0.0
	for weight: float in weights:
		total += maxf(weight, 0.0)
	if total <= 0.0:
		return -1
	var size: float = maxf(patch_size, 1.0)
	var x: float = world_x
	var z: float = world_z
	if warp != null:
		var reach: float = size * WARP
		x += warp.get_noise_2d(world_x, world_z) * reach
		z += warp.get_noise_2d(world_x + 1000.0, world_z - 1000.0) * reach
	var cell_x: int = floori(x / size)
	var cell_z: int = floori(z / size)
	var nearest: float = INF
	var nearest_bits: int = 0
	for dz: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var cx: int = cell_x + dx
			var cz: int = cell_z + dz
			var bits: int = hash(Vector3i(cx, cz, seed_value)) & 0x7FFFFFFF
			var centre := Vector2(
				(float(cx) + 0.2 + 0.6 * float(bits & 0xFF) / 255.0) * size,
				(float(cz) + 0.2 + 0.6 * float((bits >> 8) & 0xFF) / 255.0) * size
			)
			var distance: float = centre.distance_squared_to(Vector2(x, z))
			if distance < nearest:
				nearest = distance
				nearest_bits = bits
	var draw: float = total * float((nearest_bits >> 16) & 0x7FFF) / 32768.0
	for index: int in weights.size():
		draw -= maxf(weights[index], 0.0)
		if draw < 0.0:
			return index
	return weights.size() - 1


## "meadow 60%, dryland 20%" and so on, from the names and weights.
static func shares(names: PackedStringArray, weights: PackedFloat32Array) -> String:
	var total: float = 0.0
	for weight: float in weights:
		total += maxf(weight, 0.0)
	if total <= 0.0:
		return "none"
	var parts: PackedStringArray = PackedStringArray()
	for index: int in mini(names.size(), weights.size()):
		if weights[index] > 0.0:
			parts.append("%s %d%%" % [names[index], roundi(100.0 * weights[index] / total)])
	return ", ".join(parts)
