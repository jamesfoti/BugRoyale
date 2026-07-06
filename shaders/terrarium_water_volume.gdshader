shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_front, unshaded;

uniform vec4 volume_color : source_color = vec4(0.08, 0.35, 0.52, 0.22);

void fragment() {
	ALBEDO = volume_color.rgb;
	ALPHA = volume_color.a;
}
