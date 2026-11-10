extends SceneTree
## Dev tool: paints a seed's underworld as a vertical slice, one pixel per step metres,
## white where the cave carver puts air and dark where it leaves rock, under a flat surface
## at the top edge. The fast way to see what a seed's caves are made of (regions, bands,
## floors, halls, shafts, carved systems) without building a single chunk. Headless, from
## the project folder:
##   godot --headless --path . --script res://tools/cave_slice.gd -- seed=7 out=C:/tmp/slice.png
## Arguments: seed= (the lab's default), out=<png path>, step=<metres per pixel, 1>,
## width= and depth= (metres, 512 by 480), z=<the slice's z, 0>.
## Prints the carver's summary and the share of the slice that is air.

const DEFAULT_SEED: int = 368670


func _init() -> void:
	var options: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		var split: int = arg.find("=")
		if split > 0:
			options[arg.substr(0, split)] = arg.substr(split + 1)
	var seed_value: int = int(options.get("seed", DEFAULT_SEED))
	var out: String = str(options.get("out", "user://cave_slice.png"))
	var step: float = float(options.get("step", 1.0))
	var width: int = int(options.get("width", 512))
	var depth: int = int(options.get("depth", 480))
	var slice_z: float = float(options.get("z", 0.0))
	var carver: CaveCarver = CaveCarver.from_seed(
		seed_value, -float(depth) - CaveCarver.FLOOR_MARGIN
	)
	# The carved systems too, under the flat surface, so their mouths and passages show.
	carver.systems = CaveSystems.roll(
		seed_value,
		AABB(Vector3(-float(width) / 2.0, carver.floor_y, -256.0), Vector3(width, depth, 512.0)),
		func(_x: float, _z: float) -> float: return 0.0,
		carver.floor_y
	)
	var image: Image = Image.create(width, depth, false, Image.FORMAT_RGB8)
	var air: int = 0
	for px: int in width:
		for py: int in depth:
			var x: float = snappedf(float(px) - float(width) / 2.0, step)
			var y: float = snappedf(-float(py), step)
			var inside: bool = carver.is_cave(Vector3(x, y, slice_z), 0.0)
			if inside:
				air += 1
			image.set_pixel(px, py, Color.WHITE if inside else Color(0.1, 0.1, 0.1))
	var error: Error = image.save_png(out)
	if error != OK:
		print("CAVE SLICE FAIL: could not save %s (%s)." % [out, error_string(error)])
		quit(1)
		return
	print(
		(
			"seed %d: %s; air %.1f%% of the slice, saved %s"
			% [seed_value, carver.summary(), 100.0 * air / (width * depth), out]
		)
	)
	quit()
