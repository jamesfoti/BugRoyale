extends Node3D
class_name CharacterSkin
## Interface shared by every playable character skin (ant, and future bugs).
## Players, the shooter and the HUD talk to whichever skin is the first child of VisualRoot.
## Methods here are safe defaults; skins override what they support.

signal torch_equipped_changed(equipped: bool)
signal pickaxe_equipped_changed(equipped: bool)

const DEFAULT_SKIN_SCENE_PATH: String = "res://character/ant/skins/soldier_ant.tscn"
## Bot skin for the Black colony in Ants vs Ants (the player's Red colony uses the soldier ant).
const BLACK_ANT_BOT_SCENE_PATH: String = "res://character/ant/skins/little_black_ant_bot.tscn"
## Per class: skin scene, display name, role, description, and stats. max_health replaces the
## player's Damageable health; speed and jump multiply the controller's speed, run_speed and
## jump_velocity; can_fly lets the class take off by jumping in mid-air. Models are built by
## tools/blender/create_bugs.py. Add an entry per new class.
const CHARACTERS: Dictionary = {
	LoadingScreen.PlayerCharacter.ANT_WARRIOR: {
		"scene": "res://character/ant/skins/soldier_ant.tscn",
		"bot_scene": "res://character/ant/skins/soldier_ant_bot.tscn",
		"weapon": PlayerItems.Item.WEAPON_AK,
		"bot_weapon": {"damage": 7.0, "cooldown": 0.28, "range": 45.0, "spread_degrees": 3.5, "pellets": 1},
		"name": "Ant Warrior",
		"role": "Assault / All-Rounder",
		"description": "High stamina, balanced armor and rapid ground speed. Formidable mandibles for close quarters and acid-artillery for range.",
		"max_health": 110.0,
		"speed": 1.15,
		"jump": 1.0,
	},
	LoadingScreen.PlayerCharacter.TERMITE_SOLDIER: {
		"scene": "res://character/termite/skins/dampwood_termite.tscn",
		"bot_scene": "res://character/termite/skins/dampwood_termite_bot.tscn",
		"weapon": PlayerItems.Item.WEAPON_SHOTGUN,
		"bot_weapon": {"damage": 4.0, "cooldown": 0.9, "range": 18.0, "spread_degrees": 7.0, "pellets": 5},
		"name": "Termite Soldier",
		"role": "Heavy Juggernaut",
		"description": "Tank class. Slow but heavily armored. Close-range chemical sprays and a defensive pheromone shield to protect the squad.",
		"max_health": 170.0,
		"speed": 0.75,
		"jump": 0.8,
	},
	LoadingScreen.PlayerCharacter.WASP: {
		"scene": "res://character/wasp/skins/yellowjacket_wasp.tscn",
		"bot_scene": "res://character/wasp/skins/yellowjacket_wasp_bot.tscn",
		"weapon": PlayerItems.Item.WEAPON_SMG,
		"bot_weapon": {"damage": 4.0, "cooldown": 0.13, "range": 30.0, "spread_degrees": 5.0, "pellets": 1},
		"name": "Wasp",
		"role": "Airborne Skirmisher",
		"description": "High mobility and rapid-fire stingers for hit-and-run attacks. Fragile armor, but incredibly hard to hit in mid-air.",
		"max_health": 70.0,
		"speed": 1.25,
		"jump": 1.1,
		"can_fly": true,
	},
	LoadingScreen.PlayerCharacter.TRAPDOOR_SPIDER: {
		"scene": "res://character/spider/skins/trapdoor_spider.tscn",
		"bot_scene": "res://character/spider/skins/trapdoor_spider_bot.tscn",
		"weapon": PlayerItems.Item.WEAPON_SNIPER,
		"bot_weapon": {"damage": 18.0, "cooldown": 1.5, "range": 90.0, "spread_degrees": 1.2, "pellets": 1},
		"name": "Trapdoor Spider",
		"role": "Stealth Sniper",
		"description": "Camouflages into terrain and foliage, sets web traps to anchor enemies, then strikes with high-damage venom shots.",
		"max_health": 90.0,
		"speed": 1.0,
		"jump": 1.25,
	},
}


static func _entry(character: LoadingScreen.PlayerCharacter) -> Dictionary:
	return CHARACTERS.get(character, {})


static func scene_path_for(character: LoadingScreen.PlayerCharacter) -> String:
	return _entry(character).get("scene", DEFAULT_SKIN_SCENE_PATH)


static func display_name_for(character: LoadingScreen.PlayerCharacter) -> String:
	return _entry(character).get("name", "Unknown Bug")


static func role_for(character: LoadingScreen.PlayerCharacter) -> String:
	return _entry(character).get("role", "")


## Lightweight skin used when this class is played by a bot.
static func bot_scene_path_for(character: LoadingScreen.PlayerCharacter) -> String:
	return _entry(character).get("bot_scene", scene_path_for(character))


## Gun this class carries, and the bot version of it (damage, cooldown, range, spread, pellets).
static func weapon_for(character: LoadingScreen.PlayerCharacter) -> PlayerItems.Item:
	return _entry(character).get("weapon", PlayerItems.Item.WEAPON_AK)


static func bot_weapon_for(character: LoadingScreen.PlayerCharacter) -> Dictionary:
	return _entry(character).get("bot_weapon", {})


static func stats_for(character: LoadingScreen.PlayerCharacter) -> Dictionary:
	return _entry(character)


static func description_for(character: LoadingScreen.PlayerCharacter) -> String:
	return _entry(character).get("description", "")


## Applies the selected class's health, speed and jump to a freshly spawned player.
static func apply_class_stats(player: Node, damageable: Damageable) -> void:
	var entry: Dictionary = _entry(LoadingScreen.selected_player_character)
	if damageable != null and entry.has("max_health"):
		damageable.max_health = entry["max_health"]
		damageable.health = damageable.max_health
	var speed_multiplier: float = entry.get("speed", 1.0)
	var jump_multiplier: float = entry.get("jump", 1.0)
	for property: String in ["speed", "run_speed"]:
		if property in player:
			player.set(property, float(player.get(property)) * speed_multiplier)
	if "jump_velocity" in player:
		player.set("jump_velocity", float(player.get("jump_velocity")) * jump_multiplier)
	if "can_fly" in player:
		player.set("can_fly", entry.get("can_fly", false))


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
