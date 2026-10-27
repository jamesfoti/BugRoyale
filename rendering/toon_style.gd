extends Node
## Autoload: the game's cel-shaded art style. As nodes enter the tree, every opaque
## StandardMaterial3D on a mesh (characters, weapons, items, props, furniture, plants) is swapped
## for the toon surface shader, which keeps its color, texture, vertex colors and emission but
## lights in flat bands. Custom shaders (terrain, water, sky) keep their own look; the terrain
## ones include toon_lighting.gdshaderinc themselves. A full-screen depth-edge quad in the
## current 3D scene draws ink outlines. Transparent, unshaded and billboard materials (glass,
## particles, projectiles, HUD) are left alone.

const TOON_SHADER: Shader = preload("res://shaders/toon_surface.gdshader")
const TOON_TWO_SIDED_SHADER: Shader = preload("res://shaders/toon_surface_two_sided.gdshader")
const OUTLINE_SHADER: Shader = preload("res://shaders/toon_outline.gdshader")
## Render layer (bit 20) the outline quad lives on, so secondary cameras (the minimap) can
## leave it out of their cull mask.
const OUTLINE_RENDER_LAYER: int = 1 << 19

var enabled: bool = true
var outlines_enabled: bool = true

## Source StandardMaterial3D instance id -> its toon ShaderMaterial, so shared materials convert
## once and instance colors / MultiMesh tints keep working through the shared copy.
var _converted: Dictionary = {}
var _outline_quad: MeshInstance3D
var _outline_scene: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not enabled:
		return
	get_tree().node_added.connect(_on_node_added)
	# Nodes that exist already (the main scene is added before autoload _ready runs on some
	# paths) get the same treatment.
	_restyle_tree.call_deferred(get_tree().root)


func _process(_delta: float) -> void:
	if not enabled:
		return
	var scene: Node = get_tree().current_scene
	if scene != _outline_scene:
		_attach_outline(scene)


func _on_node_added(node: Node) -> void:
	if node is GeometryInstance3D:
		# Deferred so a script that assigns materials in its own _ready has already run.
		_restyle.call_deferred(node)


func _restyle_tree(root: Node) -> void:
	for node: Node in root.find_children("*", "GeometryInstance3D", true, false):
		_restyle(node)


func _restyle(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		mesh_instance.material_override = _toon_version(mesh_instance.material_override)
		for surface: int in mesh_instance.get_surface_override_material_count():
			var override: Material = mesh_instance.get_surface_override_material(surface)
			if override != null:
				mesh_instance.set_surface_override_material(surface, _toon_version(override))
		_restyle_mesh(mesh_instance.mesh)
	elif node is MultiMeshInstance3D:
		var multimesh_instance: MultiMeshInstance3D = node as MultiMeshInstance3D
		multimesh_instance.material_override = _toon_version(multimesh_instance.material_override)
		if multimesh_instance.multimesh != null:
			_restyle_mesh(multimesh_instance.multimesh.mesh)


func _restyle_mesh(mesh: Mesh) -> void:
	if mesh == null:
		return
	for surface: int in mesh.get_surface_count():
		var material: Material = mesh.surface_get_material(surface)
		var toon: Material = _toon_version(material)
		if toon != material:
			mesh.surface_set_material(surface, toon)


## The toon ShaderMaterial standing in for a standard material, or the material itself when it
## is not a plain opaque StandardMaterial3D.
func _toon_version(material: Material) -> Material:
	if not (material is StandardMaterial3D):
		return material
	var source: StandardMaterial3D = material as StandardMaterial3D
	if not _is_convertible(source):
		return material
	var key: int = source.get_instance_id()
	if _converted.has(key):
		return _converted[key]
	var toon := ShaderMaterial.new()
	toon.shader = TOON_TWO_SIDED_SHADER if source.cull_mode == BaseMaterial3D.CULL_DISABLED else TOON_SHADER
	toon.resource_name = source.resource_name
	toon.render_priority = source.render_priority
	toon.set_shader_parameter("albedo", source.albedo_color)
	if source.albedo_texture != null:
		toon.set_shader_parameter("albedo_texture", source.albedo_texture)
		toon.set_shader_parameter("use_albedo_texture", true)
	toon.set_shader_parameter("use_vertex_color", source.vertex_color_use_as_albedo)
	toon.set_shader_parameter("uv_scale", Vector2(source.uv1_scale.x, source.uv1_scale.y))
	toon.set_shader_parameter("uv_offset", Vector2(source.uv1_offset.x, source.uv1_offset.y))
	toon.set_shader_parameter("roughness", source.roughness)
	if source.emission_enabled:
		toon.set_shader_parameter("emission", source.emission)
		toon.set_shader_parameter("emission_energy", source.emission_energy_multiplier)
	# Procedural surface detail (wood grain, concrete, masonry), tagged on the source material
	# by the builders: see toon_detail.gdshaderinc.
	if source.has_meta(&"toon_detail"):
		toon.set_shader_parameter("detail", int(source.get_meta(&"toon_detail")))
		toon.set_shader_parameter("detail_scale", float(source.get_meta(&"toon_detail_scale", 1.0)))
		toon.set_shader_parameter("grain_axis", int(source.get_meta(&"toon_grain_axis", 0)))
	_converted[key] = toon
	return toon


func _is_convertible(material: StandardMaterial3D) -> bool:
	if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return false
	if material.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL:
		return false
	if material.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
		return false
	return true


## Keeps one outline quad in the current 3D scene (menus render their 3D in SubViewports and
## get none).
func _attach_outline(scene: Node) -> void:
	_outline_scene = scene
	if _outline_quad != null and is_instance_valid(_outline_quad):
		_outline_quad.queue_free()
	_outline_quad = null
	if scene == null or not outlines_enabled or not (scene is Node3D):
		return
	var quad := MeshInstance3D.new()
	quad.name = "ToonOutline"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	quad.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = OUTLINE_SHADER
	material.render_priority = 127
	quad.material_override = material
	# The vertex shader pins the quad to the screen, so it must never be culled.
	quad.custom_aabb = AABB(Vector3.ONE * -1.0e6, Vector3.ONE * 2.0e6)
	quad.ignore_occlusion_culling = true
	quad.layers = OUTLINE_RENDER_LAYER
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(quad)
	_outline_quad = quad
