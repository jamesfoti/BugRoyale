extends Node3D
class_name CharacterSkin
## Interface shared by every playable character skin (ant, and future bugs).
## Players, the shooter and the HUD talk to whichever skin is the first child of VisualRoot.
## Methods here are safe defaults; skins override what they support.

signal torch_equipped_changed(equipped: bool)
signal pickaxe_equipped_changed(equipped: bool)

const ANT_SKIN_SCENE_PATH: String = "res://character/ant/ant_skin.tscn"
## Skin scene and display name per selectable character; add an entry for each new bug.
const CHARACTER_SCENES: Dictionary = {
	LoadingScreen.PlayerCharacter.ANT: ANT_SKIN_SCENE_PATH,
}
const CHARACTER_NAMES: Dictionary = {
	LoadingScreen.PlayerCharacter.ANT: "Soldier Ant",
}


static func scene_path_for(character: LoadingScreen.PlayerCharacter) -> String:
	return CHARACTER_SCENES.get(character, ANT_SKIN_SCENE_PATH)


static func display_name_for(character: LoadingScreen.PlayerCharacter) -> String:
	return CHARACTER_NAMES.get(character, "Unknown Bug")


## Makes the selected character the skin under visual_root (replacing the scene's default skin
## when another character is chosen) and returns it.
static func install_selected(visual_root: Node3D) -> CharacterSkin:
	var current: CharacterSkin = null
	if visual_root.get_child_count() > 0:
		current = visual_root.get_child(0) as CharacterSkin
	var wanted_path: String = scene_path_for(LoadingScreen.selected_player_character)
	if current != null and current.scene_file_path == wanted_path:
		return current
	var skin_scene: PackedScene = load(wanted_path) as PackedScene
	if skin_scene == null:
		push_error("[CharacterSkin] Missing skin scene: %s" % wanted_path)
		return current
	var skin: CharacterSkin = skin_scene.instantiate() as CharacterSkin
	if current != null:
		skin.transform = current.transform
		visual_root.remove_child(current)
		current.queue_free()
	visual_root.add_child(skin)
	visual_root.move_child(skin, 0)
	return skin


func set_state(_state_name: String) -> void:
	pass


func is_waving() -> bool:
	return false


func toggle_torch() -> void:
	if is_torch_equipped():
		stow_torch()
	else:
		equip_torch()


func equip_torch() -> void:
	pass


func stow_torch() -> void:
	pass


func is_torch_equipped() -> bool:
	return false


func is_torch_busy() -> bool:
	return false


func set_terrain_edit_equipped(_active: bool) -> void:
	pass


func is_pickaxe_equipped() -> bool:
	return false


func is_pickaxe_busy() -> bool:
	return false


func set_equipped_weapon_from_item(_item: PlayerItems.Item) -> void:
	pass


func has_weapon_equipped() -> bool:
	return false


func get_equipped_weapon_item() -> PlayerItems.Item:
	return PlayerItems.Item.NONE
