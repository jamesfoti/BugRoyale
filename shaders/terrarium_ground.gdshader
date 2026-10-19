shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled, fog_disabled;

// Terrarium ground: dark potting soil with moss creeping over the flatter, higher spots and
// bare slate on steep faces, like a planted glass garden.
uniform vec4 soil_color : source_color = vec4(0.4, 0.28, 0.18, 1.0);
uniform vec4 soil_dark_color : source_color = vec4(0.24, 0.16, 0.1, 1.0);
uniform vec4 moss_color : source_color = vec4(0.3, 0.52, 0.2, 1.0);
uniform vec4 moss_bright_color : source_color = vec4(0.5, 0.7, 0.24, 1.0);
uniform vec4 rock_color : source_color = vec4(0.44, 0.46, 0.48, 1.0);
// Meters per noise cell for the moss patches and the finer soil grain.
uniform float moss_patch_size : hint_range(1.0, 40.0) = 9.0;
uniform float soil_grain_size : hint_range(0.1, 10.0) = 1.3;
// How much of the ground the moss covers (0 = bare soil, 1 = all moss).
uniform float moss_coverage : hint_range(0.0, 1.0) = 0.55;
// Surface normal Y below which the ground turns to rock (steep faces), with a soft edge.
uniform float rock_slope_start : hint_range(0.0, 1.0) = 0.45;
uniform float rock_slope_end : hint_range(0.0, 1.0) = 0.7;

varying vec3 world_vertex;
varying vec3 world_normal;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	return value_noise(p) * 0.55 + value_noise(p * 2.17 + vec2(13.7, 9.2)) * 0.3
		+ value_noise(p * 4.83 + vec2(4.1, 21.5)) * 0.15;
}

void vertex() {
	world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 ground = world_vertex.xz;
	float grain = fbm(ground / soil_grain_size);
	vec3 soil = mix(soil_dark_color.rgb, soil_color.rgb, grain);

	// Moss likes flat ground: patches from large-scale noise, thinned out on slopes.
	float up = clamp(world_normal.y, 0.0, 1.0);
	float patch = fbm(ground / moss_patch_size);
	float moss_threshold = 1.0 - moss_coverage;
	float moss = smoothstep(moss_threshold - 0.12, moss_threshold + 0.12, patch) * smoothstep(0.55, 0.85, up);
	vec3 moss_shade = mix(moss_color.rgb, moss_bright_color.rgb, fbm(ground / (soil_grain_size * 2.0)));
	vec3 base = mix(soil, moss_shade, moss);

	// Steep faces show slate.
	float rock = 1.0 - smoothstep(rock_slope_start, rock_slope_end, up);
	base = mix(base, rock_color.rgb * (0.85 + 0.3 * grain), rock);

	ALBEDO = base;
	ROUGHNESS = 1.0;
}
