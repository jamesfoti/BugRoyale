"""
Blender script: builds the stylized "centaur" soldier ant, rigs it, animates it, and exports GLB.

The ant stands on its four back legs (rear thorax + abdomen stay low) while the front thorax rises
upright and the front pair of legs act as arms. Every body segment is rigidly bound to one bone,
which suits an exoskeleton and avoids skin stretching.

Animations (named to match the player state machine): idle, walk, run, jump, fall.
The weapon hand bone is named "DEF-hand.R" like the Godot plush rig.

Run from a terminal:
  blender --background --python tools/blender/create_ant.py
  blender --background --python tools/blender/create_ant.py -- --preview <output_dir>

Blender axes: Z up, the ant faces -Y (glTF export turns this into +Z, matching the plush skin).
"""

import bpy
import bmesh
import math
import os
import sys
from mathutils import Matrix, Quaternion, Vector

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GLB_PATH = os.path.join(PROJECT_ROOT, "character", "ant", "ant.glb")
BLEND_PATH = os.path.join(PROJECT_ROOT, "character", "ant", "source", "ant.blend")

FPS = 30

# Colors (linear RGB) loosely evoking a warm, glossy cartoon ant.
CHITIN_COLOR = (0.32, 0.11, 0.045, 1.0)
LIMB_COLOR = (0.16, 0.055, 0.025, 1.0)
EYE_WHITE_COLOR = (0.92, 0.9, 0.85, 1.0)
PUPIL_COLOR = (0.01, 0.01, 0.012, 1.0)


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
		bmesh.ops.create_uvsphere(part, u_segments=segments, v_segments=rings, radius=1.0)
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
			segments=16,
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
# mirrored for the left side. Mesh and rig both read these so they cannot drift apart.

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


def _leg_points(hip: tuple, forward: float) -> tuple:
	"""Hip, knee (raised), ankle and toe for a walking leg; forward < 0 for the mid pair."""
	knee = (0.26, hip[1] + forward * 0.1, 0.5)
	ankle = (0.38, hip[1] + forward * 0.2, 0.04)
	toe = (0.42, hip[1] + forward * 0.27, 0.0)
	return hip, knee, ankle, toe


def _gaster_point(axial: float) -> Vector:
	"""Point on the abdomen's long axis, `axial` meters from its center (positive = toward the tip)."""
	axis = _euler_quat((GASTER_TILT, 0.0, 0.0)) @ Vector((0.0, 1.0, 0.0))
	return Vector(GASTER_CENTER) + axis * axial


def _build_mesh(builder: AntBuilder, mats: dict) -> None:
	chitin = mats["chitin"]
	limb = mats["limb"]

	# Rear thorax (carries the four walking legs), petiole and abdomen.
	builder.ellipsoid(BODY_CENTER, (0.12, 0.16, 0.11), "body", chitin)
	builder.ellipsoid(PETIOLE, (0.05, 0.055, 0.05), "body", chitin)
	builder.ellipsoid(GASTER_CENTER, GASTER_RADII, "gaster", chitin, rotation=(GASTER_TILT, 0.0, 0.0))
	# Darker bands hugging the abdomen's curve give a segmented look.
	for axial in (-0.06, 0.06):
		cross = math.sqrt(max(0.0, 1.0 - (axial / GASTER_RADII[1]) ** 2))
		builder.ellipsoid(
			tuple(_gaster_point(axial)),
			(GASTER_RADII[0] * cross * 1.025, 0.022, GASTER_RADII[2] * cross * 1.025),
			"gaster",
			limb,
			rotation=(GASTER_TILT, 0.0, 0.0),
		)

	# Upright front thorax ("torso") with a rounded chest.
	builder.segment(TORSO_BASE, TORSO_TOP, 0.1, 0.095, "torso", chitin)
	builder.ellipsoid((0.0, -0.1, 0.62), (0.12, 0.11, 0.16), "torso", chitin, rotation=(8.0, 0.0, 0.0))

	# Neck and head.
	builder.ellipsoid(NECK, (0.05, 0.05, 0.05), "head", limb)
	builder.ellipsoid(HEAD_CENTER, (0.15, 0.14, 0.13), "head", chitin)
	for side in (1.0, -1.0):
		suffix = "R" if side > 0 else "L"
		builder.ellipsoid(
			(0.068 * side, -0.285, 1.01), (0.048, 0.03, 0.058), "head", mats["eye_white"], rotation=(0.0, 0.0, -12.0 * side)
		)
		builder.ellipsoid((0.062 * side, -0.31, 1.005), (0.022, 0.012, 0.026), "head", mats["pupil"])
		# Brow ridge gives the cartoon face some attitude.
		builder.segment((0.03 * side, -0.29, 1.075), (0.11 * side, -0.27, 1.06), 0.016, 0.012, "head", limb)

		# Pincer mandibles.
		mandible = "mandible." + suffix
		builder.segment(_mirror(MANDIBLE_BASE, side), _mirror(MANDIBLE_BEND, side), 0.028, 0.018, mandible, limb)
		builder.segment(_mirror(MANDIBLE_BEND, side), _mirror(MANDIBLE_TIP, side), 0.018, 0.007, mandible, limb)

		# Elbowed antennae with ball tips.
		builder.segment(_mirror(ANTENNA_BASE, side), _mirror(ANTENNA_ELBOW, side), 0.015, 0.012, "antenna1." + suffix, limb)
		builder.segment(_mirror(ANTENNA_ELBOW, side), _mirror(ANTENNA_TIP, side), 0.012, 0.01, "antenna2." + suffix, limb)
		builder.ellipsoid(_mirror(ANTENNA_TIP, side), (0.024, 0.024, 0.024), "antenna2." + suffix, limb)

		# Arms (front legs), bent forward in front of the chest to hold weapons.
		shoulder = _mirror(SHOULDER, side)
		elbow = _mirror(ELBOW, side)
		wrist = _mirror(WRIST, side)
		builder.ellipsoid(shoulder, (0.055, 0.055, 0.055), "DEF-upper_arm." + suffix, chitin)
		builder.segment(shoulder, elbow, 0.046, 0.038, "DEF-upper_arm." + suffix, limb)
		builder.segment(elbow, wrist, 0.038, 0.032, "DEF-forearm." + suffix, limb)
		# Two-claw hand.
		hand = "DEF-hand." + suffix
		builder.ellipsoid(wrist, (0.04, 0.04, 0.034), hand, limb)
		builder.segment(wrist, (0.19 * side, -0.375, 0.62), 0.02, 0.009, hand, limb)
		builder.segment(wrist, (0.155 * side, -0.37, 0.575), 0.018, 0.008, hand, limb)

		# Four walking legs.
		for name, hip, forward in (("mid", HIP_MID, -1.0), ("hind", HIP_HIND, 1.0)):
			hip_p, knee, ankle, toe = (_mirror(p, side) for p in _leg_points(hip, forward))
			builder.segment(hip_p, knee, 0.042, 0.033, "thigh_%s.%s" % (name, suffix), limb)
			builder.segment(knee, ankle, 0.033, 0.019, "shin_%s.%s" % (name, suffix), limb)
			builder.segment(ankle, toe, 0.019, 0.012, "foot_%s.%s" % (name, suffix), limb)


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
	add("gaster", PETIOLE, tuple(_gaster_point(GASTER_RADII[1])), "body")
	add("torso", TORSO_BASE, TORSO_TOP, "body")
	add("head", NECK, HEAD_TOP, "torso")
	for side in (1.0, -1.0):
		s = "R" if side > 0 else "L"
		add("mandible." + s, _mirror(MANDIBLE_BASE, side), _mirror(MANDIBLE_TIP, side), "head")
		add("antenna1." + s, _mirror(ANTENNA_BASE, side), _mirror(ANTENNA_ELBOW, side), "head")
		add("antenna2." + s, _mirror(ANTENNA_ELBOW, side), _mirror(ANTENNA_TIP, side), "antenna1." + s, True)
		add("DEF-upper_arm." + s, _mirror(SHOULDER, side), _mirror(ELBOW, side), "torso")
		add("DEF-forearm." + s, _mirror(ELBOW, side), _mirror(WRIST, side), "DEF-upper_arm." + s, True)
		add("DEF-hand." + s, _mirror(WRIST, side), _mirror(HAND_TIP, side), "DEF-forearm." + s, True)
		for name, hip, forward in (("mid", HIP_MID, -1.0), ("hind", HIP_HIND, 1.0)):
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

	def rotate(self, bone: str, rotation: Quaternion) -> None:
		self.rig.pose.bones[bone].rotation_quaternion = _armature_rotation_to_local(self.rig, bone, rotation)

	def move(self, bone: str, offset: tuple) -> None:
		self.rig.pose.bones[bone].location = _armature_offset_to_local(self.rig, bone, Vector(offset))

	def key_all(self, frame: int) -> None:
		for pose_bone in self.rig.pose.bones:
			pose_bone.keyframe_insert("rotation_quaternion", frame=frame)
			pose_bone.keyframe_insert("location", frame=frame)


LEGS = [
	# (bone suffix, side, gait phase offset): diagonal pairs move together.
	("mid.R", 1.0, 0.0),
	("hind.L", -1.0, 0.0),
	("mid.L", -1.0, 0.5),
	("hind.R", 1.0, 0.5),
]


def _pose_legs(keyer: PoseKeyer, phase: float, swing_degrees: float, lift_degrees: float, knee_degrees: float) -> None:
	"""Trot gait: stance sweeps the foot back along the ground, swing lifts it forward."""
	for suffix, side, offset in LEGS:
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
		_pose_legs(keyer, 0.0, 0.0, 0.0, 0.0)

	def walk(keyer: PoseKeyer, t: float) -> None:
		bob = math.sin(t * math.tau * 2.0)
		keyer.move("body", (0.0, 0.0, 0.012 * bob))
		keyer.rotate("body", _axis_rotation("Y", 2.5 * math.sin(t * math.tau)))
		keyer.rotate("gaster", _axis_rotation("Z", 5.0 * math.sin(t * math.tau)))
		keyer.rotate("torso", _axis_rotation("X", 5.0) @ _axis_rotation("Z", -3.0 * math.sin(t * math.tau)))
		_pose_antennae(keyer, 4.0 * math.sin(t * math.tau), 6.0 * bob)
		_pose_arms(keyer, 14.0 * math.sin(t * math.tau))
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
		for suffix, side, _offset in LEGS:
			lift = -12.0 * crouch + 30.0 * air
			keyer.rotate("thigh_" + suffix, _axis_rotation("Y", -lift * side))
			keyer.rotate("shin_" + suffix, _axis_rotation("Y", 25.0 * air * side))

	def fall(keyer: PoseKeyer, t: float) -> None:
		flail = math.sin(t * math.tau)
		keyer.rotate("torso", _axis_rotation("X", -10.0))
		keyer.rotate("gaster", _axis_rotation("X", -14.0 + 3.0 * flail))
		_pose_antennae(keyer, 10.0 * flail, -25.0)
		_pose_arms(keyer, -30.0 + 12.0 * flail, 55.0)
		for suffix, side, offset in LEGS:
			wiggle = math.sin((t + offset) * math.tau)
			keyer.rotate(
				"thigh_" + suffix,
				_axis_rotation("Z", 10.0 * wiggle * side) @ _axis_rotation("Y", -28.0 * side),
			)
			keyer.rotate("shin_" + suffix, _axis_rotation("Y", 20.0 * side))

	_make_action(rig, "idle", 60, idle)
	_make_action(rig, "walk", 24, walk)
	_make_action(rig, "run", 14, run)
	_make_action(rig, "jump", 12, jump)
	_make_action(rig, "fall", 20, fall)


# --- Output ------------------------------------------------------------------------------------

def _export(rig: bpy.types.Object, mesh_obj: bpy.types.Object) -> None:
	os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)
	os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
	# Keep Godot from importing the editable source file.
	gdignore = os.path.join(os.path.dirname(BLEND_PATH), ".gdignore")
	if not os.path.exists(gdignore):
		open(gdignore, "w").close()

	bpy.ops.object.select_all(action="DESELECT")
	rig.select_set(True)
	mesh_obj.select_set(True)
	bpy.context.view_layer.objects.active = rig
	bpy.ops.export_scene.gltf(
		filepath=GLB_PATH,
		use_selection=True,
		export_yup=True,
		export_animations=True,
		export_animation_mode="NLA_TRACKS",
		export_force_sampling=True,
		export_frame_step=1,
	)
	bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
	print("Exported ant to:", GLB_PATH)
	print("Saved editable source to:", BLEND_PATH)


def _render_previews(rig: bpy.types.Object, output_dir: str) -> None:
	scene = bpy.context.scene
	os.makedirs(output_dir, exist_ok=True)
	scene.render.resolution_x = 900
	scene.render.resolution_y = 900
	scene.render.film_transparent = False
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
	ground = bpy.context.active_object
	ground.data.materials.append(_make_material("Ground", (0.35, 0.3, 0.22, 1.0), 0.9))

	camera_data = bpy.data.cameras.new("PreviewCamera")
	camera_data.lens = 50
	camera = bpy.data.objects.new("PreviewCamera", camera_data)
	scene.collection.objects.link(camera)
	scene.camera = camera
	target = Vector((0.0, 0.05, 0.6))

	views = {
		"front_three_quarter": Vector((1.6, -2.4, 1.3)),
		"side": Vector((3.0, 0.05, 0.75)),
		"front": Vector((0.0, -3.0, 0.9)),
		"back_three_quarter": Vector((-1.8, 2.3, 1.4)),
	}
	poses = [("idle", 0), ("walk", 6), ("run", 3), ("fall", 5)]

	def aim(position: Vector) -> None:
		camera.location = position
		camera.rotation_euler = (target - position).to_track_quat("-Z", "Y").to_euler()

	def set_action(name: str, frame: int) -> None:
		for track in rig.animation_data.nla_tracks:
			track.mute = track.name != name
		scene.frame_set(frame)

	set_action("idle", 0)
	for view_name, position in views.items():
		aim(position)
		scene.render.filepath = os.path.join(output_dir, "ant_%s.png" % view_name)
		bpy.ops.render.render(write_still=True)
	aim(views["front_three_quarter"])
	for action_name, frame in poses[1:]:
		set_action(action_name, frame)
		scene.render.filepath = os.path.join(output_dir, "ant_pose_%s.png" % action_name)
		bpy.ops.render.render(write_still=True)
	print("Rendered previews to:", output_dir)


def main() -> None:
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	preview_dir = argv[argv.index("--preview") + 1] if "--preview" in argv else ""

	_clear_scene()
	bpy.context.scene.render.fps = FPS
	materials = {
		"chitin": _make_material("Chitin", CHITIN_COLOR, 0.32, 0.6),
		"limb": _make_material("Limb", LIMB_COLOR, 0.4, 0.5),
		"eye_white": _make_material("EyeWhite", EYE_WHITE_COLOR, 0.25),
		"pupil": _make_material("Pupil", PUPIL_COLOR, 0.1, 0.8),
	}
	builder = AntBuilder()
	_build_mesh(builder, materials)
	mesh_obj = builder.build_object("Ant")
	rig = _build_armature()
	mesh_obj.parent = rig
	modifier = mesh_obj.modifiers.new("Armature", "ARMATURE")
	modifier.object = rig
	_build_animations(rig)
	_export(rig, mesh_obj)
	if preview_dir:
		_render_previews(rig, preview_dir)


if __name__ == "__main__":
	main()
