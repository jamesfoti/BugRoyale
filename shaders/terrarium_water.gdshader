shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, world_vertex_coords;

uniform vec4 shallow_color : source_color = vec4(0.22, 0.68, 0.82, 0.5);
uniform vec4 deep_color : source_color = vec4(0.04, 0.28, 0.48, 0.72);
uniform float wave_speed = 0.45;
uniform float wave_strength = 0.035;
uniform float wave_scale = 2.2;
uniform float fresnel_power = 2.8;

void vertex() {
	float wave_a = sin(TIME * wave_speed + VERTEX.x * wave_scale);
	float wave_b = cos(TIME * wave_speed * 0.82 + VERTEX.z * wave_scale * 1.15);
	VERTEX.y += (wave_a + wave_b) * wave_strength;
}

void fragment() {
	vec3 view_dir = normalize(VIEW);
	vec3 normal = normalize(NORMAL);
	float fresnel = pow(1.0 - clamp(dot(normal, view_dir), 0.0, 1.0), fresnel_power);
	vec3 color = mix(shallow_color.rgb, deep_color.rgb, fresnel * 0.65);
	ALBEDO = color;
	ALPHA = mix(shallow_color.a, deep_color.a, fresnel);
}
