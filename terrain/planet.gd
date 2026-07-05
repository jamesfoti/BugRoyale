@tool
class_name Planet
extends ChunkedTerrainWorld
## Spherical chunked terrain with optional ravines and caves.

const RECOMMENDED_RAVINE_DEPTH := 12.0
const RECOMMENDED_RAVINE_WIDTH := 0.08


@export_group("Planet Grid")
## Planet radius in chunk units. World radius = this × chunk_size (e.g. 1.5 × 12 = 18).
@export_range(0.5, 32.0, 0.1, "or_greater") var planet_radius_chunks: float = 1.5:
	set(value):
		planet_radius_chunks = maxf(value, 0.5)
		_request_rebuild()

@export_group("Sphere")
@export var sphere_enabled: bool = true:
	set(value):
		sphere_enabled = value
		_request_rebuild()
@export var sphere_center: Vector3 = Vector3.ZERO:
	set(value):
		sphere_center = value
		_request_rebuild()

@export_group("Planet Features")
## Use planet density (auto surface noise, ravines, caves). Enable this before tuning ravine sliders.
@export var planet_features_enabled: bool = false:
	set(value):
		planet_features_enabled = value
		_request_rebuild()
## Radial grooves carved into the sphere. Requires Planet Features.
@export var planet_ravines_enabled: bool = true:
	set(value):
		planet_ravines_enabled = value
		_request_rebuild()
## Near-surface cave pockets via smooth SDF subtract. Requires Planet Features.
@export var planet_caves_enabled: bool = true:
	set(value):
		planet_caves_enabled = value
		_request_rebuild()
## Ravine carve depth (world units). Recommended: ~1× chunk_size for radius ~1.5 chunks, ~100 at radius 1600. -1 = auto from radius.
@export_range(-1, 100.0, 0.5, "or_greater") var planet_ravine_depth: float = RECOMMENDED_RAVINE_DEPTH:
	get:
		return _planet_ravine_depth
	set(value):
		_planet_ravine_depth = (
			RECOMMENDED_RAVINE_DEPTH if value == null else float(value)
		)
		_request_rebuild()
## Ravine groove width (noise valley threshold). Higher = wider. Recommended: 0.08 for small planets, ~0.002 at radius 1600. -1 = auto from radius.
@export_range(-1, 0.5, 0.005, "or_greater") var planet_ravine_width: float = RECOMMENDED_RAVINE_WIDTH:
	get:
		return _planet_ravine_width
	set(value):
		_planet_ravine_width = (
			RECOMMENDED_RAVINE_WIDTH if value == null else float(value)
		)
		_request_rebuild()

@export_group("Runtime")
## When false (e.g. decorative sun mesh), this world is excluded from spawn and editing queries.
@export var is_playable_planet: bool = true:
	set(value):
		is_playable_planet = value
		is_playable_world = value

var _planet_ravine_depth: float = RECOMMENDED_RAVINE_DEPTH
var _planet_ravine_width: float = RECOMMENDED_RAVINE_WIDTH


func _ensure_world_defaults() -> void:
	if get("planet_ravine_depth") == null:
		_planet_ravine_depth = RECOMMENDED_RAVINE_DEPTH
	if get("planet_ravine_width") == null:
		_planet_ravine_width = RECOMMENDED_RAVINE_WIDTH
	is_playable_world = is_playable_planet


func _register_playable_groups() -> void:
	add_to_group("planet")


func _get_grid_dimensions() -> Vector3i:
	var grid_chunks: int = maxi(3, int(ceil(planet_radius_chunks * 2.0 + 2.0)))
	return Vector3i.ONE * grid_chunks


func _get_world_log_name() -> String:
	return "Planet"


func get_grid_chunks_per_axis() -> int:
	return _get_grid_dimensions().x


func get_sphere_radius() -> float:
	return planet_radius_chunks * chunk_size


func get_planet_center_world() -> Vector3:
	return global_position + sphere_center


func _apply_world_specific_settings(settings: ChunkedTerrainWorld.SettingsSnapshot) -> void:
	settings.planet_radius_chunks = planet_radius_chunks
	settings.sphere_enabled = sphere_enabled
	settings.sphere_center = sphere_center
	settings.sphere_radius = get_sphere_radius()
	settings.planet_features_enabled = planet_features_enabled
	settings.planet_ravines_enabled = planet_ravines_enabled
	settings.planet_caves_enabled = planet_caves_enabled
	settings.planet_ravine_depth = _planet_ravine_depth
	settings.planet_ravine_width = _planet_ravine_width
	settings.boxed_in_terrain_enabled = false
	settings.open_terrain_enabled = false


func _build_world_density(settings: ChunkedTerrainWorld.SettingsSnapshot) -> DensitySampler.WorldDensity:
	var sphere_world: Vector3 = settings.bounds_center + settings.sphere_center
	if settings.planet_features_enabled and settings.sphere_enabled:
		return DensitySampler.create_planet_world_density(
			sphere_world,
			settings.sphere_radius,
			settings.noise_seed,
			-1.0,
			-1.0,
			settings.planet_ravines_enabled,
			settings.planet_caves_enabled,
			settings.bounds_center,
			settings.bounds_half,
			settings.bounds_falloff_enabled,
			settings.bounds_falloff_distance,
			settings.bounds_falloff_strength,
			settings.bounds_clip_inset,
			settings.planet_ravine_depth,
			settings.planet_ravine_width
		)
	return DensitySampler.WorldDensity.create(
		settings.sphere_enabled,
		sphere_world,
		settings.sphere_radius,
		settings.noise_enabled,
		settings.noise_seed,
		settings.noise_frequency,
		settings.noise_amplitude,
		settings.noise_octaves,
		settings.noise_lacunarity,
		settings.noise_gain,
		settings.bounds_center,
		settings.bounds_half,
		settings.bounds_falloff_enabled,
		settings.bounds_falloff_distance,
		settings.bounds_falloff_strength,
		settings.bounds_clip_inset
	)


func _sync_terrain_shader_uniforms(material: Material) -> void:
	var shader_material: ShaderMaterial = material as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		return
	if shader_material.shader.resource_path != "res://shaders/terrain_spherical.gdshader":
		return
	shader_material.set_shader_parameter("planet_center", get_planet_center_world())
	shader_material.set_shader_parameter("planet_radius", get_sphere_radius())
