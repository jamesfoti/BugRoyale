extends Node
## Autoload: Low / High graphics toggle, saved to user:// and applied to every loaded scene.
## Both render 3D at a capped height (720 lines on Low, 1080 on High) with plain bilinear
## upscaling (FSR costs more than it saves on integrated GPUs), so a high-resolution screen
## never draws the world at its native pixel count. Low also disables glow and SSAO-style post
## effects, drops omni/spot
## shadows, shortens directional shadows, and sets the graphics_low_quality global shader
## uniform (cheaper water / sky paths). High restores scene values.

signal low_quality_changed(enabled: bool)

const SETTINGS_PATH: String = "user://graphics_settings.cfg"
## The 3D view renders at no more than this many lines high (the UI stays at native size); a
## Surface or 4K screen would otherwise draw several times the pixels of a 1080p laptop.
const LOW_RENDER_HEIGHT: float = 720.0
const HIGH_RENDER_HEIGHT: float = 1080.0
const LOW_DIRECTIONAL_SHADOW_DISTANCE: float = 60.0
const LOW_DIRECTIONAL_ATLAS_SIZE: int = 2048
const LOW_POSITIONAL_ATLAS_SIZE: int = 1024

## Meta key holding a node's / resource's original values while Low is active.
const _ORIGINAL_META: StringName = &"_graphics_original"

var low_quality: bool = false

var _default_directional_atlas_size: int = 4096
var _default_positional_atlas_size: int = 4096


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_default_directional_atlas_size = ProjectSettings.get_setting(
		"rendering/lights_and_shadows/directional_shadow/size", 4096
	)
	_default_positional_atlas_size = ProjectSettings.get_setting(
		"rendering/lights_and_shadows/positional_shadow/atlas_size", 4096
	)
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK and config.has_section_key("graphics", "low_quality"):
		low_quality = bool(config.get_value("graphics", "low_quality", false))
	else:
		# No choice saved yet: an integrated GPU (most laptops) starts on Low.
		low_quality = (
			RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU
		)
	get_tree().node_added.connect(_on_node_added)
	get_tree().root.size_changed.connect(_apply_viewport)
	_apply_viewport()
	_apply_to_tree()


func set_low_quality(enabled: bool) -> void:
	if enabled == low_quality:
		return
	low_quality = enabled
	var config := ConfigFile.new()
	config.set_value("graphics", "low_quality", low_quality)
	config.save(SETTINGS_PATH)
	_apply_viewport()
	_apply_to_tree()
	low_quality_changed.emit(low_quality)


func _apply_viewport() -> void:
	RenderingServer.global_shader_parameter_set(&"graphics_low_quality", low_quality)
	var root: Window = get_tree().root
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = _render_scale_for(
		root.size, LOW_RENDER_HEIGHT if low_quality else HIGH_RENDER_HEIGHT
	)
	if low_quality:
		root.positional_shadow_atlas_size = LOW_POSITIONAL_ATLAS_SIZE
		RenderingServer.directional_shadow_atlas_set_size(LOW_DIRECTIONAL_ATLAS_SIZE, true)
	else:
		root.positional_shadow_atlas_size = _default_positional_atlas_size
		RenderingServer.directional_shadow_atlas_set_size(_default_directional_atlas_size, true)


## The 3D scale that renders a window at no more than a target height (never upscaled).
static func _render_scale_for(window_size: Vector2i, target_height: float) -> float:
	if window_size.y <= 0:
		return 1.0
	return clampf(target_height / float(window_size.y), 0.25, 1.0)


func _apply_to_tree() -> void:
	for node in get_tree().root.find_children("*", "", true, false):
		_apply_to_node(node)


func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment or node is Camera3D or node is Light3D:
		# Deferred so the node's own _ready setup (e.g. torch shadows) runs first.
		_apply_to_node.call_deferred(node)


func _apply_to_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node is WorldEnvironment:
		_apply_environment((node as WorldEnvironment).environment)
	elif node is Camera3D:
		_apply_environment((node as Camera3D).environment)
	elif node is DirectionalLight3D:
		_apply_directional_light(node as DirectionalLight3D)
	elif node is OmniLight3D or node is SpotLight3D:
		_apply_positional_light(node as Light3D)


func _apply_environment(environment: Environment) -> void:
	if environment == null:
		return
	if low_quality:
		if not environment.has_meta(_ORIGINAL_META):
			var original: Dictionary = {
				"ssao": environment.ssao_enabled,
				"ssil": environment.ssil_enabled,
				"ssr": environment.ssr_enabled,
				"sdfgi": environment.sdfgi_enabled,
				"volumetric_fog": environment.volumetric_fog_enabled,
				"glow": environment.glow_enabled,
			}
			environment.set_meta(_ORIGINAL_META, original)
		environment.ssao_enabled = false
		environment.ssil_enabled = false
		environment.ssr_enabled = false
		environment.sdfgi_enabled = false
		environment.volumetric_fog_enabled = false
		environment.glow_enabled = false
	elif environment.has_meta(_ORIGINAL_META):
		var original: Dictionary = environment.get_meta(_ORIGINAL_META)
		environment.ssao_enabled = original["ssao"]
		environment.ssil_enabled = original["ssil"]
		environment.ssr_enabled = original["ssr"]
		environment.sdfgi_enabled = original["sdfgi"]
		environment.volumetric_fog_enabled = original["volumetric_fog"]
		environment.glow_enabled = original["glow"]
		environment.remove_meta(_ORIGINAL_META)


func _apply_directional_light(light: DirectionalLight3D) -> void:
	if low_quality:
		if not light.has_meta(_ORIGINAL_META):
			(
				light
				. set_meta(
					_ORIGINAL_META,
					{
						"max_distance": light.directional_shadow_max_distance,
						"mode": light.directional_shadow_mode,
					}
				)
			)
		light.directional_shadow_max_distance = minf(
			light.directional_shadow_max_distance, LOW_DIRECTIONAL_SHADOW_DISTANCE
		)
		if light.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS:
			light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	elif light.has_meta(_ORIGINAL_META):
		var original: Dictionary = light.get_meta(_ORIGINAL_META)
		light.directional_shadow_max_distance = original["max_distance"]
		light.directional_shadow_mode = original["mode"]
		light.remove_meta(_ORIGINAL_META)


func _apply_positional_light(light: Light3D) -> void:
	if low_quality:
		if not light.has_meta(_ORIGINAL_META):
			light.set_meta(_ORIGINAL_META, light.shadow_enabled)
		light.shadow_enabled = false
	elif light.has_meta(_ORIGINAL_META):
		light.shadow_enabled = light.get_meta(_ORIGINAL_META)
		light.remove_meta(_ORIGINAL_META)
