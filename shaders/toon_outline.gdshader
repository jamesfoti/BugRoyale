shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_mix, fog_disabled, shadows_disabled;

// Ink outlines for the cel-shaded look: a full-screen quad (ToonStyle keeps one in the current
// 3D scene) that darkens pixels where the depth buffer jumps, i.e. object silhouettes and
// terrain ledges. Depth-only so it works on every renderer, including the web export.
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec4 line_color : source_color = vec4(0.07, 0.05, 0.08, 0.85);
uniform float line_width : hint_range(0.5, 4.0) = 1.3;
// Depth step (in meters, at the camera) that counts as an edge; grows with distance.
uniform float edge_depth : hint_range(0.05, 2.0) = 0.45;
// Outlines fade out between these view distances so far terrain doesn't turn to noise.
uniform float fade_start = 70.0;
uniform float fade_end = 140.0;

void vertex() {
	// Pin the quad to the screen regardless of the camera.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float view_depth(vec2 uv, mat4 inverse_projection) {
	float raw = texture(depth_texture, uv).r;
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ndc.z = raw * 2.0 - 1.0;
#endif
	vec4 view = inverse_projection * vec4(ndc, 1.0);
	return -view.z / view.w;
}

void fragment() {
	vec2 step_size = line_width / VIEWPORT_SIZE;
	float center = view_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float threshold = edge_depth * (1.0 + center * 0.08);
	float edge = 0.0;
	// Ink the near side only: a neighbor that is farther away marks this pixel as a silhouette.
	edge = max(edge, step(threshold, view_depth(SCREEN_UV + vec2(step_size.x, 0.0), INV_PROJECTION_MATRIX) - center));
	edge = max(edge, step(threshold, view_depth(SCREEN_UV - vec2(step_size.x, 0.0), INV_PROJECTION_MATRIX) - center));
	edge = max(edge, step(threshold, view_depth(SCREEN_UV + vec2(0.0, step_size.y), INV_PROJECTION_MATRIX) - center));
	edge = max(edge, step(threshold, view_depth(SCREEN_UV - vec2(0.0, step_size.y), INV_PROJECTION_MATRIX) - center));
	float fade = 1.0 - smoothstep(fade_start, fade_end, center);
	ALBEDO = line_color.rgb;
	ALPHA = edge * line_color.a * fade;
}
