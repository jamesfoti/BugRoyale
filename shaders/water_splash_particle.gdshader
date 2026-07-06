shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_opaque, fog_disabled;

uniform vec3 color_shallow : source_color = vec3(0.75, 0.95, 1.0);
uniform vec3 color_deep : source_color = vec3(0.2, 0.65, 0.9);

void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p) * 2.0;
	float alpha = pow(clamp(1.0 - r, 0.0, 1.0), 1.6);
	vec3 color = mix(color_deep, color_shallow, 1.0 - r);
	ALBEDO = color * COLOR.rgb;
	ALPHA = alpha * COLOR.a;
}
