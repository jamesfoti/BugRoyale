shader_type spatial;
render_mode cull_back;

// Cel-shaded stand-in for StandardMaterial3D. ToonStyle (autoload) builds one of these for
// every opaque standard material in the running game, copying its color, texture, vertex-color
// use and emission. See toon_surface_two_sided.gdshader for cull-disabled materials.
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform bool use_albedo_texture = false;
uniform bool use_vertex_color = false;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 base = albedo;
	if (use_albedo_texture) {
		base *= texture(albedo_texture, UV * uv_scale + uv_offset);
	}
	if (use_vertex_color) {
		base *= COLOR;
	}
	ALBEDO = base.rgb;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	EMISSION = emission.rgb * emission_energy;
}

#include "res://shaders/toon_lighting.gdshaderinc"
