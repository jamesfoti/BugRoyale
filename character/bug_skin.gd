extends CharacterSkin
## Skin for every six-legged bug (ants, termites): plays the model's animations and holds the torch,
## pickaxe or a weapon in its right claw. Models are built by tools/blender/create_bugs.py.

const TORCH_SCENE: PackedScene = preload("res://props/torch.tscn")
const PICKAXE_SCENE: PackedScene = preload("res://props/pickaxe.tscn")
const SHOOTER_KIT_DIR: String = "res://character/shooter_kit/Characters/glTF"
const WEAPON_SOURCE_SCENE_PATH: String = SHOOTER_KIT_DIR + "/Character_Soldier.gltf"
const HAND_BONE: String = "DEF-hand.R"
const LOOPING_ANIMATIONS: PackedStringArray = ["idle", "walk", "run", "fall", "fly"]
## States a model may lack, and what to play instead (only winged bugs have "fly").
const ANIMATION_FALLBACKS: Dictionary = {"fly": "fall"}
const ANIMATION_BLEND_SECONDS: float = 0.15
## Longest dimension each weapon is scaled to, in meters (the ant is about 1.1 m tall).
const WEAPON_LENGTHS: Dictionary = {
	"Pistol": 0.26,
	"Revolver": 0.28,
	"Revolver_Small": 0.24,
	"Knife_1": 0.3,
	"Knife_2": 0.3,
	"Shovel": 0.6,
	"Sniper": 0.85,
	"Sniper_2": 0.85,
	"RocketLauncher": 0.75,
}
const DEFAULT_WEAPON_LENGTH: float = 0.6
## Weapons modelled standing up (blade or handle along their Y) instead of along X.
const UPRIGHT_WEAPONS: PackedStringArray = ["Knife_1", "Knife_2", "Shovel"]

var _current_state: String = ""
var _hand_attachment: BoneAttachment3D
var _torch: GameTorch
var _torch_equipped: bool = false
var _pickaxe: GamePickaxe
var _pickaxe_equipped: bool = false
var _terrain_edit_active: bool = false
var _weapon_mesh_instance: MeshInstance3D
var _weapon_meshes: Dictionary = {}
var _equipped_weapon_item: PlayerItems.Item = PlayerItems.Item.NONE

@onready var _anim_player: AnimationPlayer = $AntModel/AnimationPlayer
@onready var _skeleton: Skeleton3D = $AntModel/AntRig/Skeleton3D


func _ready() -> void:
	for animation_name: String in LOOPING_ANIMATIONS:
		if _anim_player.has_animation(animation_name):
			_anim_player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
	_setup_hand_items()
	set_state("idle")


func set_state(state_name: String) -> void:
	if not _anim_player.has_animation(state_name):
		state_name = ANIMATION_FALLBACKS.get(state_name, "")
	if state_name == _current_state or not _anim_player.has_animation(state_name):
		return
	_current_state = state_name
	_anim_player.play(state_name, ANIMATION_BLEND_SECONDS)


func equip_torch() -> void:
	if _torch_equipped or _terrain_edit_active:
		return
	_torch_equipped = true
	_set_weapon_mesh("")
	_torch.visible = true
	_torch.set_lit(true)
	torch_equipped_changed.emit(true)


func stow_torch() -> void:
	if not _torch_equipped:
		return
	_torch_equipped = false
	_torch.set_lit(false)
	_torch.visible = false
	_show_equipped_weapon()
	torch_equipped_changed.emit(false)


func is_torch_equipped() -> bool:
	return _torch_equipped


func set_terrain_edit_equipped(active: bool) -> void:
	if active == _terrain_edit_active:
		return
	_terrain_edit_active = active
	_pickaxe_equipped = active
	_pickaxe.visible = active
	if active:
		_set_weapon_mesh("")
		if _torch_equipped:
			_torch.visible = false
	elif _torch_equipped:
		_torch.visible = true
	else:
		_show_equipped_weapon()
	pickaxe_equipped_changed.emit(active)


func is_pickaxe_equipped() -> bool:
	return _pickaxe_equipped


func set_equipped_weapon_from_item(item: PlayerItems.Item) -> void:
	_equipped_weapon_item = item
	if PlayerItems.is_weapon(item) and _torch_equipped:
		stow_torch()
	_show_equipped_weapon()


func has_weapon_equipped() -> bool:
	return _equipped_weapon_item != PlayerItems.Item.NONE


func get_equipped_weapon_item() -> PlayerItems.Item:
	return _equipped_weapon_item


func _show_equipped_weapon() -> void:
	if _terrain_edit_active or _torch_equipped or not PlayerItems.is_weapon(_equipped_weapon_item):
		_set_weapon_mesh("")
		return
	_set_weapon_mesh(PlayerItems.weapon_mesh_name(_equipped_weapon_item))


func _setup_hand_items() -> void:
	_hand_attachment = BoneAttachment3D.new()
	_hand_attachment.name = "HandAttachment"
	_hand_attachment.bone_name = HAND_BONE
	_skeleton.add_child(_hand_attachment)

	# Hand-held items are placed in skeleton space (forward = +Z, up = +Y) and converted into the
	# hand bone's frame, so they stay correct if the rig's bone rolls change.
	_torch = TORCH_SCENE.instantiate() as GameTorch
	_hand_attachment.add_child(_torch)
	# Held out to the right and tilted forward/outward so the flame clears the face.
	_torch.transform = _hand_local(
		Basis.from_euler(Vector3(deg_to_rad(25.0), 0.0, deg_to_rad(-20.0))),
		Vector3(0.08, 0.06, 0.04)
	)
	_torch.scale = Vector3.ONE * 0.85
	_torch.visible = false

	_pickaxe = PICKAXE_SCENE.instantiate() as GamePickaxe
	_hand_attachment.add_child(_pickaxe)
	_pickaxe.transform = _hand_local(
		Basis.from_euler(Vector3(deg_to_rad(25.0), 0.0, deg_to_rad(-25.0))),
		Vector3(0.08, 0.02, 0.04)
	)
	_pickaxe.scale = Vector3.ONE * 0.75
	_pickaxe.visible = false

	_weapon_mesh_instance = MeshInstance3D.new()
	_weapon_mesh_instance.name = "WeaponMesh"
	_weapon_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_weapon_mesh_instance.visible = false
	_hand_attachment.add_child(_weapon_mesh_instance)
	_cache_weapon_meshes()


## Transform in the hand bone's local frame for an item with the given skeleton-space
## orientation, offset from the hand bone's rest position (skeleton-space meters).
func _hand_local(skeleton_basis: Basis, skeleton_offset: Vector3) -> Transform3D:
	var hand_rest: Transform3D = _skeleton.get_bone_global_rest(_skeleton.find_bone(HAND_BONE))
	var desired := Transform3D(skeleton_basis, hand_rest.origin + skeleton_offset)
	return hand_rest.affine_inverse() * desired


func _cache_weapon_meshes() -> void:
	_weapon_meshes.clear()
	if not ResourceLoader.exists(WEAPON_SOURCE_SCENE_PATH):
		return
	var weapon_source_scene: PackedScene = load(WEAPON_SOURCE_SCENE_PATH) as PackedScene
	if weapon_source_scene == null:
		return
	var temporary_root: Node = weapon_source_scene.instantiate()
	for item: PlayerItems.Item in PlayerItems.Item.values():
		if not PlayerItems.is_weapon(item):
			continue
		var weapon_mesh_name: String = PlayerItems.weapon_mesh_name(item)
		var weapon_node: MeshInstance3D = (
			temporary_root.find_child(weapon_mesh_name, true, false) as MeshInstance3D
		)
		if weapon_node != null and weapon_node.mesh != null:
			_weapon_meshes[weapon_mesh_name] = weapon_node.mesh
	temporary_root.free()


func _set_weapon_mesh(weapon_mesh_name: String) -> void:
	if weapon_mesh_name.is_empty() or not _weapon_meshes.has(weapon_mesh_name):
		_weapon_mesh_instance.mesh = null
		_weapon_mesh_instance.visible = false
		return
	var mesh: Mesh = _weapon_meshes[weapon_mesh_name] as Mesh
	_weapon_mesh_instance.mesh = mesh
	_weapon_mesh_instance.transform = _weapon_transform(weapon_mesh_name, mesh.get_aabb())
	_weapon_mesh_instance.visible = true


func _weapon_transform(weapon_mesh_name: String, aabb: AABB) -> Transform3D:
	var length: float = WEAPON_LENGTHS.get(weapon_mesh_name, DEFAULT_WEAPON_LENGTH)
	var weapon_scale: float = length / maxf(aabb.get_longest_axis_size(), 0.001)
	var skeleton_basis: Basis
	if weapon_mesh_name in UPRIGHT_WEAPONS:
		# Blade / handle (+Y) points forward and slightly up, flat side facing sideways.
		skeleton_basis = Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)).rotated(
			Vector3.RIGHT, deg_to_rad(-30.0)
		)
	else:
		# Barrel (+X) points forward (+Z), weapon up (+Y) stays up.
		skeleton_basis = Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))
	return _hand_local(
		skeleton_basis.scaled_local(Vector3.ONE * weapon_scale), Vector3(0.0, 0.0, 0.02)
	)
