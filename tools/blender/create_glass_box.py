"""
Blender script: creates a 1 m glass box with bottom-center origin and exports GLB.

Run inside Blender:
  Scripting workspace -> Open this file -> Run Script

Or from a terminal:
  blender --background --python tools/blender/create_glass_box.py
"""

import bpy
import math
import os

OUTPUT_PATH = os.path.abspath(
	os.path.join(os.path.dirname(__file__), "..", "..", "props", "glass_box", "glass_box.glb")
)

REFERENCE_SIZE = (1.0, 1.0, 1.0)
WALL_THICKNESS = 0.025


def _clear_scene() -> None:
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.object.delete(use_global=False)
	for block in bpy.data.meshes:
		if block.users == 0:
			bpy.data.meshes.remove(block)
	for material in bpy.data.materials:
		if material.users == 0:
			bpy.data.materials.remove(material)


def _create_glass_material() -> bpy.types.Material:
	material = bpy.data.materials.new(name="Glass")
	material.use_nodes = True
	nodes = material.node_tree.nodes
	links = material.node_tree.links
	nodes.clear()

	output = nodes.new(type="ShaderNodeOutputMaterial")
	principled = nodes.new(type="ShaderNodeBsdfPrincipled")
	principled.inputs["Base Color"].default_value = (0.85, 0.95, 1.0, 1.0)
	principled.inputs["Roughness"].default_value = 0.04
	principled.inputs["IOR"].default_value = 1.45
	if "Transmission Weight" in principled.inputs:
		principled.inputs["Transmission Weight"].default_value = 1.0
	elif "Transmission" in principled.inputs:
		principled.inputs["Transmission"].default_value = 1.0
	principled.inputs["Alpha"].default_value = 0.22

	material.blend_method = "BLEND"
	material.shadow_method = "NONE"

	links.new(principled.outputs["BSDF"], output.inputs["Surface"])
	return material


def _add_panel(
	parent: bpy.types.Object,
	name: str,
	size: tuple[float, float, float],
	center: tuple[float, float, float],
	material: bpy.types.Material,
) -> None:
	bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
	panel = bpy.context.active_object
	panel.name = name
	panel.scale = (size[0] * 0.5, size[1] * 0.5, size[2] * 0.5)
	bpy.ops.object.transform_apply(scale=True)
	panel.data.materials.append(material)
	panel.parent = parent


def _build_glass_box() -> bpy.types.Object:
	glass_material = _create_glass_material()
	root = bpy.data.objects.new("GlassBox", None)
	bpy.context.collection.objects.link(root)

	sx, sy, sz = REFERENCE_SIZE
	t = WALL_THICKNESS

	_add_panel(root, "Bottom", (sx, t, sz), (0.0, t * 0.5, 0.0), glass_material)
	_add_panel(root, "Top", (sx, t, sz), (0.0, sy - t * 0.5, 0.0), glass_material)
	_add_panel(root, "Front", (sx, sy, t), (0.0, sy * 0.5, sz * 0.5 - t * 0.5), glass_material)
	_add_panel(root, "Back", (sx, sy, t), (0.0, sy * 0.5, -sz * 0.5 + t * 0.5), glass_material)
	_add_panel(root, "Left", (t, sy, sz), (-sx * 0.5 + t * 0.5, sy * 0.5, 0.0), glass_material)
	_add_panel(root, "Right", (t, sy, sz), (sx * 0.5 - t * 0.5, sy * 0.5, 0.0), glass_material)

	return root


def _export_glb(root: bpy.types.Object) -> None:
	os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
	bpy.ops.object.select_all(action="DESELECT")
	root.select_set(True)
	bpy.context.view_layer.objects.active = root
	bpy.ops.export_scene.gltf(
		filepath=OUTPUT_PATH,
		use_selection=True,
		export_apply=True,
		export_yup=True,
	)
	print("Exported glass box to:", OUTPUT_PATH)


def main() -> None:
	_clear_scene()
	root = _build_glass_box()
	_export_glb(root)


if __name__ == "__main__":
	main()
