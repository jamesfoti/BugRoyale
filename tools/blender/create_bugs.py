"""
Blender script: builds the stylized "centaur" bug species (ants and termites), rigs them, animates
them, and exports GLBs.

Each bug stands on its four back legs (rear thorax + abdomen stay low) while the front thorax rises
upright and the front pair of legs act as arms. Every body segment is rigidly bound to one bone,
which suits an exoskeleton and avoids skin stretching. All species share the same bone names, so the
game uses one skin script (character/bug_skin.gd) for every bug.

Families set the body plan: ants have a pinched waist, elbowed antennae and big cartoon eyes;
termites (drawn as their soldier caste) have a broad waist, a long striped abdomen, beaded straight
antennae, a long armored head and small eyes.

Animations (named to match the player state machine): idle, walk, run, jump, fall.
The weapon hand bone is named "DEF-hand.R".

Run from a terminal (builds every species, or only the ones listed after --species):
  blender --background --python tools/blender/create_bugs.py
  blender --background --python tools/blender/create_bugs.py -- --species fire_ant formosan_termite
  blender --background --python tools/blender/create_bugs.py -- --preview <output_dir>
  blender --background --python tools/blender/create_bugs.py -- --species yellowjacket_wasp --drone
  blender --background --python tools/blender/create_bugs.py -- --species soldier_ant --lod

Outputs per species: character/<family>/models/<id>.glb and character/<family>/source/<id>.blend.
With --drone: a low-detail, rig-free copy frozen in its flying pose, models/<id>_drone.glb, for
flocks and other crowds drawn with a MultiMesh.
Blender axes: Z up, the bug faces -Y (glTF export turns this into +Z, the player's forward).
"""

import bpy
import bmesh
import math
import os
import sys
from mathutils import Matrix, Quaternion, Vector

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

FPS = 30

EYE_WHITE_COLOR = (0.92, 0.9, 0.85, 1.0)
PUPIL_COLOR = (0.01, 0.01, 0.012, 1.0)

# Per-species look. Colors are linear RGB. Scales are relative to the soldier ant:
#   head_scale / mandible_scale / antenna_scale / gaster_scale size those parts,
#   limb_thickness thickens or slims legs, arms and antennae.
# Optional: family ("ant" default, or "termite"), torso_color, gaster_color, band_color (abdomen
# stripes; else limb), head_proportions (x, y, z multipliers on the head shape), stinger,
# head_grooves, nasus (cone "nose" instead of jaws), defense_droplet, jaw_color. Families "wasp" and
# "spider" add wings, or eight eyes, fangs and a third pair of walking legs.
# In-game overall size is set per skin scene (character/<family>/skins/<id>.tscn).
SPECIES = {
	"soldier_ant": {
		"chitin": (0.32, 0.11, 0.045), "limb": (0.16, 0.055, 0.025), "roughness": 0.32,
	},
	"carpenter_ant": {
		# Large black ant, often with a reddish thorax; big head and jaws.
		"chitin": (0.03, 0.022, 0.02), "limb": (0.018, 0.013, 0.011), "torso_color": (0.2, 0.05, 0.025),
		"roughness": 0.3, "head_scale": 1.2, "mandible_scale": 1.25, "gaster_scale": 1.05,
	},
	"odorous_house_ant": {
		# Small brownish-black ant.
		"chitin": (0.14, 0.065, 0.03), "limb": (0.07, 0.035, 0.018), "roughness": 0.38,
		"head_scale": 0.95, "gaster_scale": 0.9, "antenna_scale": 1.12, "limb_thickness": 0.9,
	},
	"pavement_ant": {
		# Dark brown-black with lighter legs and grooved head.
		"chitin": (0.055, 0.032, 0.02), "limb": (0.13, 0.075, 0.04), "roughness": 0.42,
		"head_scale": 1.05, "mandible_scale": 1.1, "head_grooves": True,
	},
	"argentine_ant": {
		# Light brown, slender supercolony ant.
		"chitin": (0.22, 0.12, 0.06), "limb": (0.17, 0.095, 0.05), "roughness": 0.36,
		"head_scale": 0.92, "gaster_scale": 0.85, "antenna_scale": 1.15, "limb_thickness": 0.8,
	},
	"little_black_ant": {
		# Tiny glossy jet-black ant.
		"chitin": (0.012, 0.012, 0.014), "limb": (0.022, 0.022, 0.024), "roughness": 0.16,
		"head_scale": 0.95, "gaster_scale": 0.95, "limb_thickness": 0.9,
	},
	"pharaoh_ant": {
		# Small yellowish-red ant with a darker abdomen.
		"chitin": (0.55, 0.23, 0.06), "limb": (0.48, 0.21, 0.07), "gaster_color": (0.2, 0.075, 0.03),
		"roughness": 0.34, "head_scale": 0.9, "gaster_scale": 0.92, "limb_thickness": 0.8,
	},
	"fire_ant": {
		# Aggressive reddish-brown ant with a dark abdomen and a stinger.
		"chitin": (0.6, 0.06, 0.015), "limb": (0.32, 0.04, 0.012), "gaster_color": (0.08, 0.03, 0.018),
		"roughness": 0.3, "head_scale": 1.05, "mandible_scale": 1.15, "stinger": True,
	},
	# Termites are drawn as soldiers: "chitin" is the armored head, the rest of the body is pale.
	"eastern_subterranean_termite": {
		# Long yellow-brown head with saber jaws on a cream body.
		"family": "termite", "chitin": (0.42, 0.22, 0.06), "torso_color": (0.72, 0.62, 0.42),
		"gaster_color": (0.75, 0.64, 0.44), "limb": (0.66, 0.56, 0.38), "band_color": (0.5, 0.4, 0.26),
		"roughness": 0.55,
	},
	"formosan_termite": {
		# Oval orange head that oozes white defensive fluid; yellowish body.
		"family": "termite", "chitin": (0.55, 0.24, 0.04), "torso_color": (0.78, 0.66, 0.38),
		"gaster_color": (0.8, 0.68, 0.4), "limb": (0.72, 0.6, 0.34), "band_color": (0.56, 0.44, 0.22),
		"roughness": 0.5, "head_scale": 1.05, "head_proportions": (1.15, 0.92, 1.12), "mandible_scale": 0.85,
		"defense_droplet": True,
	},
	"drywood_termite": {
		# Dark reddish-brown head with thick dark jaws; tan body.
		"family": "termite", "chitin": (0.18, 0.05, 0.02), "torso_color": (0.48, 0.33, 0.18),
		"gaster_color": (0.5, 0.35, 0.2), "limb": (0.42, 0.28, 0.15), "band_color": (0.3, 0.19, 0.09),
		"roughness": 0.5, "head_scale": 1.05, "mandible_scale": 1.1, "limb_thickness": 1.1,
	},
	"dampwood_termite": {
		# The big one: large reddish-brown head with heavy jaws; brownish body.
		"family": "termite", "chitin": (0.3, 0.09, 0.03), "torso_color": (0.36, 0.22, 0.1),
		"gaster_color": (0.4, 0.25, 0.12), "limb": (0.32, 0.2, 0.09), "band_color": (0.22, 0.13, 0.06),
		"roughness": 0.5, "head_scale": 1.15, "mandible_scale": 1.2, "gaster_scale": 1.05,
	},
	"conehead_termite": {
		# Nasute soldier: dark cone-shaped nozzle head instead of jaws; light brown body.
		"family": "termite", "chitin": (0.06, 0.035, 0.02), "torso_color": (0.42, 0.3, 0.17),
		"gaster_color": (0.48, 0.34, 0.2), "limb": (0.4, 0.28, 0.16), "band_color": (0.28, 0.19, 0.1),
		"roughness": 0.5, "mandible_scale": 0.35, "nasus": True,
	},
	"yellowjacket_wasp": {
		# Airborne skirmisher: bright yellow with black thorax and abdomen stripes, stinger, wings.
		"family": "wasp", "chitin": (0.85, 0.52, 0.015), "torso_color": (0.02, 0.017, 0.014),
		"limb": (0.72, 0.42, 0.02), "band_color": (0.02, 0.017, 0.014), "jaw_color": (0.04, 0.03, 0.015),
		"roughness": 0.3, "limb_thickness": 0.8, "stinger": True,
	},
	"trapdoor_spider": {
		# Stealth sniper: glossy dark-brown carapace, matte abdomen, thick legs and black fangs.
		"family": "spider", "chitin": (0.06, 0.035, 0.022), "gaster_color": (0.035, 0.025, 0.018),
		"limb": (0.05, 0.032, 0.02), "jaw_color": (0.008, 0.006, 0.005),
		"roughness": 0.28, "limb_thickness": 1.3,
	},
}

# Mesh resolution multiplier (1.0 for player models; lower for crowd "drone" meshes).
_detail: float = 1.0
# Drones are flock/NPC copies: frozen in a pose, no rig, far fewer triangles.
DRONE_DETAIL = 0.22
# Bots (AI fighters) use rigged, animated copies at reduced detail: models/<id>_lod.glb.
LOD_DETAIL = 0.35


def _detail_count(count: int, minimum: int) -> int:
	return max(minimum, int(round(count * _detail)))


# Species currently being built; set by _build_species() before any geometry is made.
_species: dict = SPECIES["soldier_ant"]


def _param(name: str, default=1.0):
	return _species.get(name, default)


# --- Scene helpers -----------------------------------------------------------------------------

def _clear_scene() -> None:
	bpy.ops.wm.read_factory_settings(use_empty=True)


def _make_material(name: str, color: tuple, roughness: float, specular: float = 0.5) -> bpy.types.Material:
	material = bpy.data.materials.new(name=name)
	material.use_nodes = True
	principled = material.node_tree.nodes.get("Principled BSDF")
	principled.inputs["Base Color"].default_value = color
	principled.inputs["Roughness"].default_value = roughness
	if "Specular IOR Level" in principled.inputs:
		principled.inputs["Specular IOR Level"].default_value = specular
	if "Coat Weight" in principled.inputs and roughness < 0.4:
		principled.inputs["Coat Weight"].default_value = 0.35
		principled.inputs["Coat Roughness"].default_value = 0.15
	return material


class AntBuilder:
	"""Accumulates rigid mesh parts, each tagged with the bone that moves it."""

	def __init__(self) -> None:
		self.bm = bmesh.new()
		self.parts: list[tuple[bmesh.types.BMesh, str, int]] = []
		self.material_slots: list[bpy.types.Material] = []

	def material_index(self, material: bpy.types.Material) -> int:
		if material not in self.material_slots:
			self.material_slots.append(material)
		return self.material_slots.index(material)

	def ellipsoid(
		self,
		center: tuple,
		radii: tuple,
		bone: str,
		material: bpy.types.Material,
		rotation: tuple = (0.0, 0.0, 0.0),
		segments: int = 28,
		rings: int = 16,
	) -> None:
		part = bmesh.new()
		bmesh.ops.create_uvsphere(
			part, u_segments=_detail_count(segments, 6), v_segments=_detail_count(rings, 4), radius=1.0
		)
		transform = (
			Matrix.Translation(Vector(center))
			@ Matrix.LocRotScale(None, _euler_quat(rotation), None)
			@ Matrix.Diagonal((radii[0], radii[1], radii[2], 1.0))
		)
		bmesh.ops.transform(part, matrix=transform, verts=part.verts)
		self.parts.append((part, bone, self.material_index(material)))

	def segment(
		self,
		start: tuple,
		end: tuple,
		radius_start: float,
		radius_end: float,
		bone: str,
		material: bpy.types.Material,
		round_ends: bool = True,
	) -> None:
		"""Tapered capsule from start to end."""
		start_v = Vector(start)
		end_v = Vector(end)
		direction = end_v - start_v
		length = direction.length
		part = bmesh.new()
		bmesh.ops.create_cone(
			part,
			# Open tube: the rounded end spheres cover it (smooth-shaded caps catch odd highlights).
			cap_ends=False,
			segments=_detail_count(16, 6),
			radius1=radius_start,
			radius2=radius_end,
			depth=length,
		)
		align = Vector((0.0, 0.0, 1.0)).rotation_difference(direction.normalized())
		transform = Matrix.Translation((start_v + end_v) * 0.5) @ align.to_matrix().to_4x4()
		bmesh.ops.transform(part, matrix=transform, verts=part.verts)
		self.parts.append((part, bone, self.material_index(material)))
		if round_ends:
			self.ellipsoid(start, (radius_start,) * 3, bone, material, segments=16, rings=8)
			self.ellipsoid(end, (radius_end,) * 3, bone, material, segments=16, rings=8)

	def build_object(self, name: str) -> bpy.types.Object:
		mesh = bpy.data.meshes.new(name)
		obj = bpy.data.objects.new(name, mesh)
		bpy.context.collection.objects.link(obj)
		for material in self.material_slots:
			mesh.materials.append(material)

		combined = bmesh.new()
		deform_layer = combined.verts.layers.deform.verify()
		bone_names: list[str] = []
		for part, bone, material_index in self.parts:
			if bone not in bone_names:
				bone_names.append(bone)
			group_index = bone_names.index(bone)
			vert_map = {}
			for vert in part.verts:
				new_vert = combined.verts.new(vert.co)
				new_vert[deform_layer][group_index] = 1.0
				vert_map[vert] = new_vert
			for face in part.faces:
				new_face = combined.faces.new([vert_map[v] for v in face.verts])
				new_face.material_index = material_index
				new_face.smooth = True
			part.free()
		combined.normal_update()
		combined.to_mesh(mesh)
		combined.free()
		for bone in bone_names:
			obj.vertex_groups.new(name=bone)
		return obj


def _euler_quat(rotation_degrees: tuple) -> Quaternion:
	from mathutils import Euler
	return Euler(tuple(math.radians(a) for a in rotation_degrees), "XYZ").to_quaternion()


def _mirror(point: tuple, side: float) -> tuple:
	return (point[0] * side, point[1], point[2])


# --- Anatomy -----------------------------------------------------------------------------------
# All positions in meters; ground at Z = 0, ant faces -Y. Right-side (.R) points use +X and are
# mirrored for the left side. Mesh and rig both read these (through the species helpers below) so
# they cannot drift apart. Values are the soldier ant's; species scale parts around these anchors.

BODY_CENTER = (0.0, 0.04, 0.4)
PETIOLE = (0.0, 0.2, 0.41)
GASTER_CENTER = (0.0, 0.41, 0.47)
GASTER_RADII = (0.19, 0.24, 0.18)
GASTER_TILT = -18.0
TORSO_BASE = (0.0, -0.06, 0.42)
TORSO_TOP = (0.0, -0.13, 0.8)
NECK = (0.0, -0.14, 0.84)
HEAD_CENTER = (0.0, -0.18, 0.97)
HEAD_TOP = (0.0, -0.18, 1.1)

ANTENNA_BASE = (0.05, -0.25, 1.07)
ANTENNA_ELBOW = (0.12, -0.3, 1.24)
ANTENNA_TIP = (0.2, -0.42, 1.29)
MANDIBLE_BASE = (0.06, -0.27, 0.905)
MANDIBLE_BEND = (0.04, -0.355, 0.895)
MANDIBLE_TIP = (0.008, -0.385, 0.89)

SHOULDER = (0.12, -0.13, 0.75)
ELBOW = (0.21, -0.1, 0.57)
WRIST = (0.17, -0.3, 0.6)
HAND_TIP = (0.17, -0.38, 0.6)

HIP_MID = (0.09, -0.02, 0.37)
HIP_HIND = (0.09, 0.11, 0.37)

# Face and waist details (right side; mirrored).
HEAD_RADII = (0.15, 0.14, 0.13)
HEAD_TILT = 0.0
EYE_CENTER = (0.068, -0.285, 1.01)
EYE_RADII = (0.048, 0.03, 0.058)
PUPIL_CENTER = (0.062, -0.31, 1.005)
PUPIL_RADII = (0.022, 0.012, 0.026)
BROW_START = (0.03, -0.29, 1.075)
BROW_END = (0.11, -0.27, 1.06)
PETIOLE_RADII = (0.05, 0.055, 0.05)
# Abdomen stripe positions, as fractions of the abdomen's half-length, and stripe thickness.
GASTER_BAND_FRACTIONS = (-0.25, 0.25)
GASTER_BAND_THICKNESS = 0.022
# Spacing of beads along the antennae (0 = smooth elbowed antennae).
ANTENNA_BEAD_SPACING = 0.0
HAS_ANTENNAE = True
HAS_WINGS = False
EXTRA_EYES = False
PEDIPALPS = False

# Walking legs: (bone name part, hip, forward reach). Negative reach plants the foot ahead of the
# hip, positive behind it. LEG_REACH widens the stance; LEG_KNEE_HEIGHT raises the knees.
LEG_PAIRS = (("mid", HIP_MID, -1.0), ("hind", HIP_HIND, 1.0))
LEG_REACH = 1.0
LEG_KNEE_HEIGHT = 0.5

# Wasp wings (right side; mirrored): forewing and hindwing hinge on the thorax's back.
WING_BASE = (0.06, -0.08, 0.76)
WING_TIP = (0.3, 0.42, 0.84)

# Termite body plan: long forward-jutting armored head, small eyes, straight beaded antennae,
# long saber jaws, broad waist and a long striped abdomen. Applied over the ant anchors above.
TERMITE_ANCHORS = {
	"HEAD_CENTER": (0.0, -0.25, 0.98),
	"HEAD_TOP": (0.0, -0.27, 1.09),
	"HEAD_RADII": (0.14, 0.22, 0.125),
	"HEAD_TILT": 10.0,
	"EYE_CENTER": (0.07, -0.38, 1.035),
	"EYE_RADII": (0.03, 0.02, 0.036),
	"PUPIL_CENTER": (0.066, -0.396, 1.032),
	"PUPIL_RADII": (0.014, 0.008, 0.017),
	"BROW_START": (0.035, -0.39, 1.08),
	"BROW_END": (0.105, -0.37, 1.07),
	"ANTENNA_BASE": (0.07, -0.37, 1.05),
	"ANTENNA_ELBOW": (0.13, -0.45, 1.15),
	"ANTENNA_TIP": (0.19, -0.53, 1.26),
	"MANDIBLE_BASE": (0.07, -0.43, 0.95),
	"MANDIBLE_BEND": (0.11, -0.54, 0.95),
	"MANDIBLE_TIP": (0.035, -0.64, 0.94),
	"PETIOLE_RADII": (0.1, 0.085, 0.09),
	"GASTER_CENTER": (0.0, 0.45, 0.45),
	"GASTER_RADII": (0.17, 0.29, 0.15),
	"GASTER_TILT": -8.0,
	"GASTER_BAND_FRACTIONS": (-0.6, -0.3, 0.0, 0.3, 0.6),
	"ANTENNA_BEAD_SPACING": 0.032,
}

# Wasp body plan: thread waist, pointed abdomen with wide stripes, two pairs of wings.
WASP_ANCHORS = {
	"PETIOLE_RADII": (0.03, 0.075, 0.03),
	"GASTER_CENTER": (0.0, 0.47, 0.47),
	"GASTER_RADII": (0.15, 0.25, 0.14),
	"GASTER_TILT": -22.0,
	"GASTER_BAND_FRACTIONS": (-0.5, -0.15, 0.2, 0.55),
	"GASTER_BAND_THICKNESS": 0.045,
	"EYE_RADII": (0.056, 0.034, 0.068),
	"HAS_WINGS": True,
}

# Trapdoor spider body plan: no antennae, eight eyes, downward fangs and feeler pedipalps,
# big round abdomen, and three pairs of walking legs (the fourth pair are the arms).
SPIDER_ANCHORS = {
	"HEAD_CENTER": (0.0, -0.17, 0.95),
	"HEAD_TOP": (0.0, -0.17, 1.06),
	"HEAD_RADII": (0.16, 0.15, 0.115),
	"MANDIBLE_BASE": (0.05, -0.28, 0.92),
	"MANDIBLE_BEND": (0.06, -0.33, 0.85),
	"MANDIBLE_TIP": (0.035, -0.3, 0.79),
	"PETIOLE_RADII": (0.06, 0.06, 0.055),
	"GASTER_CENTER": (0.0, 0.43, 0.45),
	"GASTER_RADII": (0.22, 0.27, 0.21),
	"GASTER_TILT": -12.0,
	"GASTER_BAND_FRACTIONS": (),
	"HAS_ANTENNAE": False,
	"EXTRA_EYES": True,
	"PEDIPALPS": True,
	"LEG_PAIRS": (
		("fore", (0.09, -0.07, 0.37), -1.9),
		("mid", (0.1, 0.01, 0.37), -0.5),
		("hind", (0.09, 0.1, 0.37), 1.3),
	),
	"LEG_REACH": 1.2,
	"LEG_KNEE_HEIGHT": 0.6,
}

PLAN_ANCHORS = {"termite": TERMITE_ANCHORS, "wasp": WASP_ANCHORS, "spider": SPIDER_ANCHORS}
# Ant values of every anchor any plan overrides, so each build starts from the ant plan.
ANT_ANCHORS = {name: globals()[name] for plan in PLAN_ANCHORS.values() for name in plan}


def _apply_body_plan() -> None:
	globals().update(ANT_ANCHORS)
	globals().update(PLAN_ANCHORS.get(_param("family", "ant"), {}))


def _scaled(point: tuple, anchor: tuple, scale: float) -> tuple:
	return tuple(a + (p - a) * scale for p, a in zip(point, anchor))


def _head(point: tuple) -> tuple:
	"""Head-mounted point, scaled about the neck by the species' head size."""
	return _scaled(point, NECK, _param("head_scale"))


def _mandible(point: tuple) -> tuple:
	return _head(_scaled(point, MANDIBLE_BASE, _param("mandible_scale")))


def _antenna(point: tuple) -> tuple:
	return _head(_scaled(point, ANTENNA_BASE, _param("antenna_scale")))


def _gaster_center() -> tuple:
	return _scaled(GASTER_CENTER, PETIOLE, _param("gaster_scale"))


def _gaster_radii() -> tuple:
	return tuple(r * _param("gaster_scale") for r in GASTER_RADII)


def _leg_points(hip: tuple, forward: float) -> tuple:
	"""Hip, knee (raised), ankle and toe for a walking leg; forward < 0 for the mid pair."""
	knee = (0.26 * LEG_REACH, hip[1] + forward * 0.1, LEG_KNEE_HEIGHT)
	ankle = (0.38 * LEG_REACH, hip[1] + forward * 0.2, 0.04)
	toe = (0.42 * LEG_REACH, hip[1] + forward * 0.27, 0.0)
	return hip, knee, ankle, toe


def _gaster_point(axial: float) -> Vector:
	"""Point on the abdomen's long axis, `axial` meters from its center (positive = toward the tip)."""
	axis = _euler_quat((GASTER_TILT, 0.0, 0.0)) @ Vector((0.0, 1.0, 0.0))
	return Vector(_gaster_center()) + axis * axial


def _build_mesh(builder: AntBuilder, mats: dict) -> None:
	chitin = mats["chitin"]
	limb = mats["limb"]
	gaster_mat = mats["gaster"]
	torso_mat = mats["torso"]
	head_size = _param("head_scale")
	jaw_size = head_size * _param("mandible_scale")
	thickness = _param("limb_thickness")
	antenna_thickness = head_size * thickness
	gaster_radii = _gaster_radii()

	band_mat = mats["band"]
	jaw_mat = mats["jaw"]

	# Rear thorax (carries the four walking legs), waist and abdomen.
	builder.ellipsoid(BODY_CENTER, (0.12, 0.16, 0.11), "body", torso_mat)
	builder.ellipsoid(PETIOLE, PETIOLE_RADII, "body", torso_mat)
	builder.ellipsoid(_gaster_center(), gaster_radii, "gaster", gaster_mat, rotation=(GASTER_TILT, 0.0, 0.0))
	# Darker bands hugging the abdomen's curve give a segmented look.
	for axial_fraction in GASTER_BAND_FRACTIONS:
		axial = axial_fraction * gaster_radii[1]
		cross = math.sqrt(max(0.0, 1.0 - axial_fraction ** 2))
		builder.ellipsoid(
			tuple(_gaster_point(axial)),
			(gaster_radii[0] * cross * 1.025, GASTER_BAND_THICKNESS, gaster_radii[2] * cross * 1.025),
			"gaster",
			band_mat,
			rotation=(GASTER_TILT, 0.0, 0.0),
		)
	if _param("stinger", False):
		builder.segment(
			tuple(_gaster_point(gaster_radii[1] * 0.9)), tuple(_gaster_point(gaster_radii[1] * 1.45)),
			0.05, 0.005, "gaster", band_mat,
		)

	# Upright front thorax ("torso") with a rounded chest.
	builder.segment(TORSO_BASE, TORSO_TOP, 0.1, 0.095, "torso", torso_mat)
	builder.ellipsoid((0.0, -0.1, 0.62), (0.12, 0.11, 0.16), "torso", torso_mat, rotation=(8.0, 0.0, 0.0))

	# Neck and head.
	builder.ellipsoid(NECK, (0.05, 0.05, 0.05), "head", limb)
	builder.ellipsoid(
		_head(HEAD_CENTER),
		tuple(r * head_size * p for r, p in zip(HEAD_RADII, _param("head_proportions", (1.0, 1.0, 1.0)))),
		"head",
		chitin,
		rotation=(HEAD_TILT, 0.0, 0.0),
	)
	if _param("head_grooves", False):
		# Pavement-ant style ridges running front to back over the head.
		for x in (-0.06, -0.02, 0.02, 0.06):
			builder.segment(
				_head((x, -0.27, 1.06)), _head((x, -0.12, 1.07)), 0.009 * head_size, 0.009 * head_size, "head", limb
			)
	if _param("nasus", False):
		# Nasute termite soldier: a cone-shaped nozzle that sprays sticky glue.
		nozzle_base = _head((0.0, -0.41, 1.0))
		nozzle_tip = _head((0.0, -0.6, 0.985))
		builder.segment(nozzle_base, nozzle_tip, 0.06 * head_size, 0.014 * head_size, "head", chitin)
	if _param("defense_droplet", False):
		# Formosan soldiers ooze white defensive fluid from a gland on top of the head.
		builder.ellipsoid(_head((0.0, -0.33, 1.105)), (0.032 * head_size,) * 3, "head", mats["eye_white"])
	for side in (1.0, -1.0):
		suffix = "R" if side > 0 else "L"
		builder.ellipsoid(
			_head(_mirror(EYE_CENTER, side)),
			tuple(r * head_size for r in EYE_RADII),
			"head",
			mats["eye_white"],
			rotation=(0.0, 0.0, -12.0 * side),
		)
		builder.ellipsoid(
			_head(_mirror(PUPIL_CENTER, side)), tuple(r * head_size for r in PUPIL_RADII), "head", mats["pupil"]
		)
		# Brow ridge gives the cartoon face some attitude.
		builder.segment(
			_head(_mirror(BROW_START, side)), _head(_mirror(BROW_END, side)),
			0.016 * head_size, 0.012 * head_size, "head", limb,
		)

		# Pincer mandibles.
		mandible = "mandible." + suffix
		base, bend, tip = (_mandible(_mirror(p, side)) for p in (MANDIBLE_BASE, MANDIBLE_BEND, MANDIBLE_TIP))
		builder.segment(base, bend, 0.028 * jaw_size, 0.018 * jaw_size, mandible, jaw_mat)
		builder.segment(bend, tip, 0.018 * jaw_size, 0.007 * jaw_size, mandible, jaw_mat)

		if EXTRA_EYES:
			# Spiders have eight eyes: six small beady ones above the two big cartoon eyes.
			for eye in ((0.025, -0.29, 1.065), (0.075, -0.275, 1.075), (0.115, -0.235, 1.05)):
				builder.ellipsoid(_head(_mirror(eye, side)), (0.017 * head_size,) * 3, "head", mats["pupil"])
		if PEDIPALPS:
			# Short feelers beside the fangs.
			palp = (_head(_mirror(p, side)) for p in ((0.075, -0.26, 0.93), (0.115, -0.34, 0.87), (0.1, -0.37, 0.8)))
			palp_base, palp_bend, palp_tip = palp
			builder.segment(palp_base, palp_bend, 0.024 * thickness, 0.019 * thickness, "head", limb)
			builder.segment(palp_bend, palp_tip, 0.019 * thickness, 0.014 * thickness, "head", limb)
		if HAS_WINGS:
			# Forewing and hindwing hinge on the thorax's back and lie swept back over the abdomen.
			wing = "wing." + suffix
			builder.ellipsoid(
				(0.2 * side, 0.24, 0.83), (0.1, 0.36, 0.008), wing, mats["wing"], rotation=(6.0, -18.0 * side, -25.0 * side)
			)
			builder.ellipsoid(
				(0.15 * side, 0.19, 0.795), (0.065, 0.24, 0.006), wing, mats["wing"], rotation=(4.0, -14.0 * side, -35.0 * side)
			)

		# Antennae with ball tips: elbowed for ants and wasps, straight and beaded for termites.
		if HAS_ANTENNAE:
			a_base, a_elbow, a_tip = (_antenna(_mirror(p, side)) for p in (ANTENNA_BASE, ANTENNA_ELBOW, ANTENNA_TIP))
			builder.segment(a_base, a_elbow, 0.015 * antenna_thickness, 0.012 * antenna_thickness, "antenna1." + suffix, limb)
			builder.segment(a_elbow, a_tip, 0.012 * antenna_thickness, 0.01 * antenna_thickness, "antenna2." + suffix, limb)
			builder.ellipsoid(a_tip, (0.024 * antenna_thickness,) * 3, "antenna2." + suffix, limb)
			if ANTENNA_BEAD_SPACING > 0.0:
				for start, end, bone in ((a_base, a_elbow, "antenna1." + suffix), (a_elbow, a_tip, "antenna2." + suffix)):
					start_v, end_v = Vector(start), Vector(end)
					beads = max(1, int((end_v - start_v).length / (ANTENNA_BEAD_SPACING * head_size)))
					for bead in range(1, beads):
						point = start_v.lerp(end_v, bead / beads)
						builder.ellipsoid(tuple(point), (0.018 * antenna_thickness,) * 3, bone, limb, segments=12, rings=6)

		# Arms (front legs), bent forward in front of the chest to hold weapons.
		shoulder = _mirror(SHOULDER, side)
		elbow = _mirror(ELBOW, side)
		wrist = _mirror(WRIST, side)
		builder.ellipsoid(shoulder, (0.055 * thickness,) * 3, "DEF-upper_arm." + suffix, torso_mat)
		builder.segment(shoulder, elbow, 0.046 * thickness, 0.038 * thickness, "DEF-upper_arm." + suffix, limb)
		builder.segment(elbow, wrist, 0.038 * thickness, 0.032 * thickness, "DEF-forearm." + suffix, limb)
		# Two-claw hand.
		hand = "DEF-hand." + suffix
		builder.ellipsoid(wrist, (0.04 * thickness, 0.04 * thickness, 0.034 * thickness), hand, limb)
		builder.segment(wrist, (0.19 * side, -0.375, 0.62), 0.02 * thickness, 0.009 * thickness, hand, limb)
		builder.segment(wrist, (0.155 * side, -0.37, 0.575), 0.018 * thickness, 0.008 * thickness, hand, limb)

		# Four walking legs.
		for name, hip, forward in LEG_PAIRS:
			hip_p, knee, ankle, toe = (_mirror(p, side) for p in _leg_points(hip, forward))
			builder.segment(hip_p, knee, 0.042 * thickness, 0.033 * thickness, "thigh_%s.%s" % (name, suffix), limb)
			builder.segment(knee, ankle, 0.033 * thickness, 0.019 * thickness, "shin_%s.%s" % (name, suffix), limb)
			builder.segment(ankle, toe, 0.019 * thickness, 0.012 * thickness, "foot_%s.%s" % (name, suffix), limb)


# --- Rig ---------------------------------------------------------------------------------------

def _build_armature() -> bpy.types.Object:
	armature_data = bpy.data.armatures.new("AntRig")
	rig = bpy.data.objects.new("AntRig", armature_data)
	bpy.context.collection.objects.link(rig)
	bpy.context.view_layer.objects.active = rig
	bpy.ops.object.mode_set(mode="EDIT")
	bones = armature_data.edit_bones

	def add(name: str, head: tuple, tail: tuple, parent: str = "", connect: bool = False) -> None:
		bone = bones.new(name)
		bone.head = head
		bone.tail = tail
		if parent:
			bone.parent = bones[parent]
			bone.use_connect = connect

	add("root", (0.0, 0.0, 0.0), (0.0, 0.25, 0.0))
	add("body", (0.0, -0.1, BODY_CENTER[2]), (0.0, 0.15, BODY_CENTER[2]), "root")
	add("gaster", PETIOLE, tuple(_gaster_point(_gaster_radii()[1])), "body")
	add("torso", TORSO_BASE, TORSO_TOP, "body")
	add("head", NECK, _head(HEAD_TOP), "torso")
	for side in (1.0, -1.0):
		s = "R" if side > 0 else "L"
		add("mandible." + s, _mandible(_mirror(MANDIBLE_BASE, side)), _mandible(_mirror(MANDIBLE_TIP, side)), "head")
		if HAS_ANTENNAE:
			add("antenna1." + s, _antenna(_mirror(ANTENNA_BASE, side)), _antenna(_mirror(ANTENNA_ELBOW, side)), "head")
			add(
				"antenna2." + s, _antenna(_mirror(ANTENNA_ELBOW, side)), _antenna(_mirror(ANTENNA_TIP, side)),
				"antenna1." + s, True,
			)
		if HAS_WINGS:
			add("wing." + s, _mirror(WING_BASE, side), _mirror(WING_TIP, side), "torso")
		add("DEF-upper_arm." + s, _mirror(SHOULDER, side), _mirror(ELBOW, side), "torso")
		add("DEF-forearm." + s, _mirror(ELBOW, side), _mirror(WRIST, side), "DEF-upper_arm." + s, True)
		add("DEF-hand." + s, _mirror(WRIST, side), _mirror(HAND_TIP, side), "DEF-forearm." + s, True)
		for name, hip, forward in LEG_PAIRS:
			hip_p, knee, ankle, toe = (_mirror(p, side) for p in _leg_points(hip, forward))
			add("thigh_%s.%s" % (name, s), hip_p, knee, "body")
			add("shin_%s.%s" % (name, s), knee, ankle, "thigh_%s.%s" % (name, s), True)
			add("foot_%s.%s" % (name, s), ankle, toe, "shin_%s.%s" % (name, s), True)

	bpy.ops.object.mode_set(mode="OBJECT")
	for pose_bone in rig.pose.bones:
		pose_bone.rotation_mode = "QUATERNION"
	return rig


# --- Animation ---------------------------------------------------------------------------------

def _armature_rotation_to_local(rig: bpy.types.Object, bone_name: str, rotation: Quaternion) -> Quaternion:
	"""Rotation given about armature-space axes (pivoting at the bone head) -> bone-local pose rotation."""
	rest = rig.data.bones[bone_name].matrix_local.to_quaternion()
	return rest.inverted() @ rotation @ rest


def _armature_offset_to_local(rig: bpy.types.Object, bone_name: str, offset: Vector) -> Vector:
	rest = rig.data.bones[bone_name].matrix_local.to_3x3()
	return rest.inverted() @ offset


def _axis_rotation(axis: str, degrees: float) -> Quaternion:
	vectors = {"X": Vector((1, 0, 0)), "Y": Vector((0, 1, 0)), "Z": Vector((0, 0, 1))}
	return Quaternion(vectors[axis], math.radians(degrees))


class PoseKeyer:
	def __init__(self, rig: bpy.types.Object) -> None:
		self.rig = rig

	def reset(self) -> None:
		for pose_bone in self.rig.pose.bones:
			pose_bone.rotation_quaternion = Quaternion()
			pose_bone.location = Vector()

	# Bones a body plan lacks (e.g. a spider's antennae) are skipped, so one set of poses fits all.
	def rotate(self, bone: str, rotation: Quaternion) -> None:
		if bone in self.rig.pose.bones:
			self.rig.pose.bones[bone].rotation_quaternion = _armature_rotation_to_local(self.rig, bone, rotation)

	def move(self, bone: str, offset: tuple) -> None:
		if bone in self.rig.pose.bones:
			self.rig.pose.bones[bone].location = _armature_offset_to_local(self.rig, bone, Vector(offset))

	def key_all(self, frame: int) -> None:
		for pose_bone in self.rig.pose.bones:
			pose_bone.keyframe_insert("rotation_quaternion", frame=frame)
			pose_bone.keyframe_insert("location", frame=frame)


def _legs() -> list:
	"""(bone suffix, side, gait phase offset) per walking leg. Alternating legs share a phase, giving
	a diagonal trot with two leg pairs and the classic insect tripod with three."""
	legs = []
	for pair_index, (name, _hip, _reach) in enumerate(LEG_PAIRS):
		for side, suffix in ((1.0, "R"), (-1.0, "L")):
			offset = 0.0 if (pair_index + (0 if side > 0 else 1)) % 2 == 0 else 0.5
			legs.append(("%s.%s" % (name, suffix), side, offset))
	return legs


def _pose_legs(keyer: PoseKeyer, phase: float, swing_degrees: float, lift_degrees: float, knee_degrees: float) -> None:
	"""Stance sweeps the foot back along the ground, swing lifts it forward."""
	for suffix, side, offset in _legs():
		s = (phase + offset) % 1.0
		if s < 0.5:
			t = s / 0.5
			sweep = -swing_degrees + 2.0 * swing_degrees * t
			lift = 0.0
		else:
			t = (s - 0.5) / 0.5
			sweep = swing_degrees - 2.0 * swing_degrees * t
			lift = lift_degrees * math.sin(math.pi * t)
		# Positive sweep moves the foot backward (+Y); lift raises it outward-up.
		rotation = _axis_rotation("Z", sweep * side) @ _axis_rotation("Y", -lift * side)
		keyer.rotate("thigh_" + suffix, rotation)
		keyer.rotate("shin_" + suffix, _axis_rotation("Y", knee_degrees * side * (lift / max(lift_degrees, 0.001))))


def _pose_antennae(keyer: PoseKeyer, sway: float, droop: float) -> None:
	for side, s in ((1.0, "R"), (-1.0, "L")):
		keyer.rotate("antenna1." + s, _axis_rotation("X", droop) @ _axis_rotation("Z", sway * side))
		keyer.rotate("antenna2." + s, _axis_rotation("X", droop * 1.5))


def _pose_arms(keyer: PoseKeyer, swing: float, raise_degrees: float = 0.0) -> None:
	for side, s in ((1.0, "R"), (-1.0, "L")):
		keyer.rotate(
			"DEF-upper_arm." + s,
			_axis_rotation("X", swing * side) @ _axis_rotation("Y", -raise_degrees * side),
		)


def _pose_wings(keyer: PoseKeyer, raise_degrees: float) -> None:
	"""Wing beat: raises both wings about the body's long axis (no-op for wingless bugs)."""
	for side, s in ((1.0, "R"), (-1.0, "L")):
		keyer.rotate("wing." + s, _axis_rotation("Y", -raise_degrees * side))


def _make_action(rig: bpy.types.Object, name: str, frame_count: int, pose_at) -> None:
	"""pose_at(keyer, t) sets the pose for normalized time t in [0, 1]; keys frame 0..frame_count."""
	action = bpy.data.actions.new(name)
	action.use_fake_user = True
	rig.animation_data_create()
	rig.animation_data.action = action
	keyer = PoseKeyer(rig)
	for frame in range(frame_count + 1):
		keyer.reset()
		pose_at(keyer, frame / frame_count)
		keyer.key_all(frame)
	track = rig.animation_data.nla_tracks.new()
	track.name = name
	strip = track.strips.new(name, 0, action)
	strip.name = name
	rig.animation_data.action = None


def _build_animations(rig: bpy.types.Object) -> None:
	def idle(keyer: PoseKeyer, t: float) -> None:
		breath = math.sin(t * math.tau)
		keyer.move("body", (0.0, 0.0, 0.006 * breath))
		keyer.rotate("gaster", _axis_rotation("X", 3.0 * breath))
		keyer.rotate("torso", _axis_rotation("X", 1.5 * breath))
		keyer.rotate("head", _axis_rotation("Z", 6.0 * math.sin(t * math.tau * 0.5 + 0.6)))
		_pose_antennae(keyer, 6.0 * math.sin(t * math.tau * 2.0), 4.0 * breath)
		_pose_arms(keyer, 3.0 * breath)
		_pose_wings(keyer, 8.0 * math.sin(t * math.tau * 8.0))
		_pose_legs(keyer, 0.0, 0.0, 0.0, 0.0)

	def walk(keyer: PoseKeyer, t: float) -> None:
		bob = math.sin(t * math.tau * 2.0)
		keyer.move("body", (0.0, 0.0, 0.012 * bob))
		keyer.rotate("body", _axis_rotation("Y", 2.5 * math.sin(t * math.tau)))
		keyer.rotate("gaster", _axis_rotation("Z", 5.0 * math.sin(t * math.tau)))
		keyer.rotate("torso", _axis_rotation("X", 5.0) @ _axis_rotation("Z", -3.0 * math.sin(t * math.tau)))
		_pose_antennae(keyer, 4.0 * math.sin(t * math.tau), 6.0 * bob)
		_pose_arms(keyer, 14.0 * math.sin(t * math.tau))
		_pose_wings(keyer, 4.0 * math.sin(t * math.tau * 4.0))
		_pose_legs(keyer, t, 22.0, 26.0, 18.0)

	def run(keyer: PoseKeyer, t: float) -> None:
		bob = math.sin(t * math.tau * 2.0)
		keyer.move("body", (0.0, 0.0, 0.025 * bob))
		keyer.rotate("body", _axis_rotation("Y", 4.0 * math.sin(t * math.tau)))
		keyer.rotate("gaster", _axis_rotation("X", -6.0 + 4.0 * bob) @ _axis_rotation("Z", 7.0 * math.sin(t * math.tau)))
		keyer.rotate("torso", _axis_rotation("X", 16.0))
		keyer.rotate("head", _axis_rotation("X", -10.0))
		_pose_antennae(keyer, 3.0 * math.sin(t * math.tau), -12.0 + 8.0 * bob)
		_pose_arms(keyer, 28.0 * math.sin(t * math.tau), 10.0)
		_pose_wings(keyer, 5.0 + 12.0 * math.sin(t * math.tau * 3.0))
		_pose_legs(keyer, t, 32.0, 38.0, 26.0)

	def jump(keyer: PoseKeyer, t: float) -> None:
		# Crouch, then spring with legs tucked and arms flung up.
		crouch = max(0.0, 1.0 - t * 3.0)
		air = min(1.0, max(0.0, (t - 0.2) / 0.5))
		keyer.move("body", (0.0, 0.0, -0.08 * crouch + 0.03 * air))
		keyer.rotate("torso", _axis_rotation("X", 10.0 * crouch - 8.0 * air))
		keyer.rotate("gaster", _axis_rotation("X", -10.0 * air))
		_pose_antennae(keyer, 0.0, -20.0 * air)
		_pose_arms(keyer, -35.0 * air, 40.0 * air)
		_pose_wings(keyer, 15.0 + 30.0 * math.sin(t * math.tau * 3.0))
		for suffix, side, _offset in _legs():
			lift = -12.0 * crouch + 30.0 * air
			keyer.rotate("thigh_" + suffix, _axis_rotation("Y", -lift * side))
			keyer.rotate("shin_" + suffix, _axis_rotation("Y", 25.0 * air * side))

	def fall(keyer: PoseKeyer, t: float) -> None:
		flail = math.sin(t * math.tau)
		keyer.rotate("torso", _axis_rotation("X", -10.0))
		keyer.rotate("gaster", _axis_rotation("X", -14.0 + 3.0 * flail))
		_pose_antennae(keyer, 10.0 * flail, -25.0)
		_pose_arms(keyer, -30.0 + 12.0 * flail, 55.0)
		_pose_wings(keyer, 15.0 + 35.0 * math.sin(t * math.tau * 4.0))
		for suffix, side, offset in _legs():
			wiggle = math.sin((t + offset) * math.tau)
			keyer.rotate(
				"thigh_" + suffix,
				_axis_rotation("Z", 10.0 * wiggle * side) @ _axis_rotation("Y", -28.0 * side),
			)
			keyer.rotate("shin_" + suffix, _axis_rotation("Y", 20.0 * side))

	def fly(keyer: PoseKeyer, t: float) -> None:
		# Hovering flight: leaning forward, legs tucked up, wings beating fast.
		hover = math.sin(t * math.tau * 2.0)
		keyer.move("body", (0.0, 0.0, 0.02 * hover))
		keyer.rotate("torso", _axis_rotation("X", 16.0))
		keyer.rotate("gaster", _axis_rotation("X", -16.0 + 4.0 * hover))
		_pose_antennae(keyer, 5.0 * math.sin(t * math.tau), -14.0)
		_pose_arms(keyer, -12.0, 18.0)
		for suffix, side, offset in _legs():
			dangle = 6.0 * math.sin((t + offset) * math.tau * 2.0)
			keyer.rotate("thigh_" + suffix, _axis_rotation("Y", -(34.0 + dangle) * side))
			keyer.rotate("shin_" + suffix, _axis_rotation("Y", 38.0 * side))
		_pose_wings(keyer, 20.0 + 40.0 * math.sin(t * math.tau * 8.0))

	if HAS_WINGS:
		_make_action(rig, "fly", 24, fly)
	_make_action(rig, "idle", 60, idle)
	_make_action(rig, "walk", 24, walk)
	_make_action(rig, "run", 14, run)
	_make_action(rig, "jump", 12, jump)
	_make_action(rig, "fall", 20, fall)




# --- Output ------------------------------------------------------------------------------------

def _export(species_id: str, rig: bpy.types.Object, mesh_obj: bpy.types.Object, lod: bool = False) -> None:
	family_dir = os.path.join(PROJECT_ROOT, "character", _param("family", "ant"))
	model_dir = os.path.join(family_dir, "models")
	source_dir = os.path.join(family_dir, "source")
	glb_path = os.path.join(model_dir, species_id + ("_lod.glb" if lod else ".glb"))
	blend_path = os.path.join(source_dir, species_id + ".blend")
	os.makedirs(model_dir, exist_ok=True)
	os.makedirs(source_dir, exist_ok=True)
	# Keep Godot from importing the editable source files.
	gdignore = os.path.join(source_dir, ".gdignore")
	if not os.path.exists(gdignore):
		open(gdignore, "w").close()

	bpy.ops.object.select_all(action="DESELECT")
	rig.select_set(True)
	mesh_obj.select_set(True)
	bpy.context.view_layer.objects.active = rig
	bpy.ops.export_scene.gltf(
		filepath=glb_path,
		use_selection=True,
		export_yup=True,
		export_animations=True,
		export_animation_mode="NLA_TRACKS",
		export_force_sampling=True,
		export_frame_step=1,
	)
	if not lod:
		bpy.ops.wm.save_as_mainfile(filepath=blend_path)
	print("Exported %s to: %s" % (species_id, glb_path))


def _render_preview(species_id: str, output_dir: str) -> None:
	scene = bpy.context.scene
	os.makedirs(output_dir, exist_ok=True)
	scene.render.resolution_x = 700
	scene.render.resolution_y = 700
	try:
		scene.render.engine = "BLENDER_EEVEE"
	except TypeError:
		scene.render.engine = "BLENDER_EEVEE_NEXT"

	world = bpy.data.worlds.new("PreviewWorld")
	world.use_nodes = True
	world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.62, 0.7, 1.0)
	world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
	scene.world = world

	sun_data = bpy.data.lights.new("Sun", "SUN")
	sun_data.energy = 3.5
	sun = bpy.data.objects.new("Sun", sun_data)
	sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
	scene.collection.objects.link(sun)

	bpy.ops.mesh.primitive_plane_add(size=6.0, location=(0.0, 0.0, 0.0))
	bpy.context.active_object.data.materials.append(_make_material("Ground", (0.35, 0.3, 0.22, 1.0), 0.9))

	camera_data = bpy.data.cameras.new("PreviewCamera")
	camera_data.lens = 50
	camera = bpy.data.objects.new("PreviewCamera", camera_data)
	scene.collection.objects.link(camera)
	scene.camera = camera
	target = Vector((0.0, 0.05, 0.62))
	position = Vector((1.6, -2.4, 1.3))
	camera.location = position
	camera.rotation_euler = (target - position).to_track_quat("-Z", "Y").to_euler()
	scene.frame_set(0)
	scene.render.filepath = os.path.join(output_dir, species_id + ".png")
	bpy.ops.render.render(write_still=True)
	# Straight-on front view shows the face and jaws clearly.
	position = Vector((0.0, -2.6, 1.0))
	camera.location = position
	camera.rotation_euler = (target - position).to_track_quat("-Z", "Y").to_euler()
	scene.render.filepath = os.path.join(output_dir, species_id + "_front.png")
	bpy.ops.render.render(write_still=True)


def _export_drone(species_id: str, rig: bpy.types.Object, mesh_obj: bpy.types.Object) -> None:
	"""Freezes the mesh in its flying pose (or idle if wingless) and exports it without a rig, for
	cheap crowds drawn with a MultiMesh: character/<family>/models/<id>_drone.glb."""
	pose_track = "fly" if any(t.name == "fly" for t in rig.animation_data.nla_tracks) else "idle"
	for track in rig.animation_data.nla_tracks:
		track.mute = track.name != pose_track
	bpy.context.scene.frame_set(6)
	bpy.ops.object.select_all(action="DESELECT")
	mesh_obj.select_set(True)
	bpy.context.view_layer.objects.active = mesh_obj
	bpy.ops.object.modifier_apply(modifier="Armature")
	mesh_obj.parent = None
	mesh_obj.vertex_groups.clear()
	bpy.data.objects.remove(rig)

	model_dir = os.path.join(PROJECT_ROOT, "character", _param("family", "ant"), "models")
	os.makedirs(model_dir, exist_ok=True)
	glb_path = os.path.join(model_dir, species_id + "_drone.glb")
	bpy.ops.export_scene.gltf(
		filepath=glb_path,
		use_selection=True,
		export_yup=True,
		export_animations=False,
		export_skins=False,
	)
	triangles = sum(len(polygon.vertices) - 2 for polygon in mesh_obj.data.polygons)
	print("Exported %s drone (%d triangles) to: %s" % (species_id, triangles, glb_path))


def _build_species(species_id: str, preview_dir: str, drone: bool = False, lod: bool = False) -> None:
	global _species, _detail
	_detail = DRONE_DETAIL if drone else (LOD_DETAIL if lod else 1.0)
	_species = SPECIES[species_id]
	_apply_body_plan()
	_clear_scene()
	bpy.context.scene.render.fps = FPS
	roughness: float = _param("roughness", 0.32)
	chitin_color = _param("chitin") + (1.0,)
	limb_color = _param("limb") + (1.0,)
	materials = {
		"chitin": _make_material("Chitin", chitin_color, roughness, 0.6),
		"limb": _make_material("Limb", limb_color, roughness + 0.08, 0.5),
		"eye_white": _make_material("EyeWhite", EYE_WHITE_COLOR, 0.25),
		"pupil": _make_material("Pupil", PUPIL_COLOR, 0.1, 0.8),
	}
	materials["torso"] = materials["chitin"]
	if "torso_color" in _species:
		materials["torso"] = _make_material("Torso", _param("torso_color") + (1.0,), roughness, 0.6)
	materials["band"] = materials["limb"]
	if "band_color" in _species:
		materials["band"] = _make_material("Band", _param("band_color") + (1.0,), roughness, 0.5)
	# Termite soldier jaws are dark and hard; ant jaws match the legs.
	materials["jaw"] = materials["limb"]
	if _param("family", "ant") == "termite":
		materials["jaw"] = _make_material("Jaw", (0.05, 0.025, 0.012, 1.0), 0.3, 0.6)
	if "jaw_color" in _species:
		materials["jaw"] = _make_material("Jaw", _param("jaw_color") + (1.0,), 0.25, 0.6)
	# See-through wings (only used by bugs that have them).
	materials["wing"] = _make_material("Wing", (0.42, 0.48, 0.58, 0.65), 0.15, 0.6)
	materials["wing"].surface_render_method = "BLENDED"
	principled = materials["wing"].node_tree.nodes.get("Principled BSDF")
	principled.inputs["Alpha"].default_value = 0.65
	materials["gaster"] = materials["chitin"]
	if "gaster_color" in _species:
		materials["gaster"] = _make_material("Gaster", _param("gaster_color") + (1.0,), roughness, 0.6)

	builder = AntBuilder()
	_build_mesh(builder, materials)
	mesh_obj = builder.build_object("Ant")
	rig = _build_armature()
	mesh_obj.parent = rig
	modifier = mesh_obj.modifiers.new("Armature", "ARMATURE")
	modifier.object = rig
	_build_animations(rig)
	if drone:
		_export_drone(species_id, rig, mesh_obj)
		return
	_export(species_id, rig, mesh_obj, lod)
	if preview_dir:
		_render_preview(species_id, preview_dir)


def main() -> None:
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	preview_dir = argv[argv.index("--preview") + 1] if "--preview" in argv else ""
	species_ids = list(SPECIES.keys())
	if "--species" in argv:
		start = argv.index("--species") + 1
		species_ids = []
		for arg in argv[start:]:
			if arg.startswith("--"):
				break
			species_ids.append(arg)
	for species_id in species_ids:
		if species_id not in SPECIES:
			raise SystemExit("Unknown species '%s'. Known: %s" % (species_id, ", ".join(SPECIES)))
		_build_species(species_id, preview_dir, "--drone" in argv, "--lod" in argv)


if __name__ == "__main__":
	main()
