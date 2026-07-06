shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_front, unshaded;

uniform vec3 base_color : source_color = vec3(0.04, 0.32, 0.58);
uniform vec3 deep_color : source_color = vec3(0.02, 0.16, 0.36);
uniform float volume_height = 8.0;
uniform float surface_alpha = 0.32;

varying float v_height;

void vertex() {
	v_height = VERTEX.y;
}

void fragment() {
	float depth_t = clamp(v_height / max(volume_height, 0.001), 0.0, 1.0);
	vec3 color = mix(deep_color, base_color, depth_t);
	ALBEDO = color;
	ALPHA = surface_alpha * mix(0.75, 1.0, depth_t);
}
