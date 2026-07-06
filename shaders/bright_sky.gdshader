shader_type sky;

uniform vec3 sky_top_color : source_color = vec3(0.18, 0.48, 0.92);
uniform vec3 sky_horizon_color : source_color = vec3(0.76, 0.9, 1.0);
uniform vec3 ground_glow_color : source_color = vec3(0.55, 0.72, 0.45);
uniform vec3 sun_direction = vec3(0.35, 0.82, 0.25);
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.82);
uniform float sun_disc_size = 0.035;
uniform float sun_glow_strength = 0.42;
uniform float cloud_strength = 0.22;
uniform float cloud_scale = 3.2;
uniform float cloud_speed = 0.015;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float clouds(vec3 eye_dir) {
	vec2 uv = eye_dir.xz / max(eye_dir.y + 0.55, 0.15);
	uv *= cloud_scale;
	uv += vec2(TIME * cloud_speed, TIME * cloud_speed * 0.7);
	float n = noise2d(uv);
	n += noise2d(uv * 2.1 + vec2(4.2, 1.8)) * 0.5;
	n += noise2d(uv * 4.3 - vec2(2.1, 3.4)) * 0.25;
	return smoothstep(0.45, 0.82, n);
}

void sky() {
	float elevation = EYEDIR.y;
	float horizon_blend = pow(1.0 - abs(elevation), 2.4);
	vec3 color = mix(sky_top_color, sky_horizon_color, horizon_blend);

	if (elevation < 0.0) {
		color = mix(color, ground_glow_color, smoothstep(0.0, -0.35, elevation));
	} else {
		float cloud_mask = clouds(normalize(EYEDIR)) * cloud_strength;
		cloud_mask *= smoothstep(0.02, 0.25, elevation);
		color = mix(color, vec3(1.0), cloud_mask);
	}

	vec3 sun_dir = normalize(sun_direction);
	float sun_alignment = dot(EYEDIR, sun_dir);
	float sun_disc = smoothstep(1.0 - sun_disc_size, 1.0, sun_alignment);
	float sun_glow = pow(max(sun_alignment, 0.0), 12.0) * sun_glow_strength;
	color += sun_color * (sun_disc + sun_glow);

	COLOR = color;
}
