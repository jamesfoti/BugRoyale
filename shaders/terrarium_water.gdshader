shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, world_vertex_coords;

// Port of Thomas Lacasse's Shadertoy voronoi water (ltfGD7), adapted for Godot terrarium surface.
uniform vec3 base_color : source_color = vec3(0.04, 0.38, 0.68);
uniform vec4 shine_color : source_color = vec4(0.75, 0.95, 1.0, 1.0);
uniform float surface_alpha = 0.62;
uniform float shine_strength = 0.42;
uniform float pattern_scale = 0.035;
uniform float animation_speed = 1.0;
uniform float scroll_speed = 0.25;
uniform vec2 cell_separation = vec2(10.0, 10.0);
uniform vec2 noise_separation = vec2(10.0, 10.0);
uniform float distortion_amount = 0.25;
uniform float vertex_displacement = 0.08;

const int PRIME_1 = 182489;
const int PRIME_2 = 307609;
const int PRIME_3 = 566851;

varying vec2 v_pattern_uv;
varying vec3 v_world_pos;

float water_time() {
	return TIME * animation_speed;
}

float random_int(int seed) {
	int n = seed;
	for (int i = 0; i < 2; i++) {
		n *= PRIME_1;
		n = n ^ PRIME_2;
		n = n % PRIME_3;
	}
	return float(n) / float(PRIME_3);
}

vec2 voronoi_pos(int a, int b) {
	float x_phase = random_int(a + PRIME_3 * (b + 1));
	float y_phase = random_int(a + 2 * PRIME_3 * (b + 1));
	float x_rate = random_int(a + 3 * PRIME_3 * (b + 1));
	float y_rate = random_int(a + 4 * PRIME_3 * (b + 1));
	return vec2(
		(0.5 + 0.25 * cos(x_rate * water_time() + x_phase * 2.0 * PI) + float(a)) / cell_separation.x,
		(0.5 + 0.25 * sin(y_rate * water_time() + y_phase * 2.0 * PI) + float(b)) / cell_separation.y
	);
}

ivec2 get_closest_cell(vec2 point) {
	ivec2 close_cell = ivec2(0);
	float min_dist = cell_separation.x + cell_separation.y;
	ivec2 square = ivec2(point * cell_separation);

	for (int i = -2; i < 3; i++) {
		for (int j = -2; j < 3; j++) {
			ivec2 cell = ivec2(square.x + i, square.y + j);
			float dist = length(point - voronoi_pos(cell.x, cell.y));
			if (dist < min_dist) {
				min_dist = dist;
				close_cell = cell;
			}
		}
	}
	return close_cell;
}

float smooth_step_01(float x) {
	return x * x * (3.0 - 2.0 * x);
}

float get_close_to_border(vec2 point) {
	ivec2 cell = get_closest_cell(point);
	ivec2 square = ivec2(point * cell_separation);
	ivec2 forbidden = cell - square;
	vec2 point_1 = voronoi_pos(cell.x, cell.y);
	float min_dist = 2.0 * (cell_separation.x + cell_separation.y);

	for (int i = -2; i < 3; i++) {
		for (int j = -2; j < 3; j++) {
			vec2 point_2 = voronoi_pos(square.x + i, square.y + j);
			vec2 rel_line_pos = (point_2 - point_1) * 0.5;
			vec2 rel_point = (point - point_1) / max(length(rel_line_pos), 0.0001);
			float dist = length(rel_line_pos) - dot(rel_point, rel_line_pos);

			if (dist < min_dist && (i != forbidden.x || j != forbidden.y)) {
				min_dist = dist;
			}
		}
	}

	return smooth_step_01(max(1.0 - 2.0 * length(cell_separation) * min_dist, 0.0));
}

vec2 get_arrow(ivec2 pos) {
	int seed = (pos.x * PRIME_2 + pos.y * PRIME_3) % PRIME_1;
	float grad = random_int(seed);
	float random_rate = random_int(seed + 10);
	return vec2(
		cos(2.0 * PI * grad + random_rate * water_time()),
		sin(2.0 * PI * grad + random_rate * water_time())
	);
}

vec2 get_offset(vec2 uv, ivec2 square) {
	vec2 center_point = vec2(float(square.x) / noise_separation.x, float(square.y) / noise_separation.y);
	return (uv - center_point) * noise_separation;
}

float compute_perlin_value(vec2 uv, ivec2 square) {
	vec2 arrow = get_arrow(square);
	vec2 offset = normalize(get_offset(uv, square));
	return dot(offset, arrow);
}

float interpolate_noise(vec2 uv) {
	int up = int(ceil(uv.x * noise_separation.x));
	int down = up - 1;
	int right = int(ceil(uv.y * noise_separation.y));
	int left = right - 1;

	ivec2 square_1 = ivec2(up, right);
	ivec2 square_2 = ivec2(up, left);
	ivec2 square_3 = ivec2(down, right);
	ivec2 square_4 = ivec2(down, left);

	float value_1 = compute_perlin_value(uv, square_1);
	float value_2 = compute_perlin_value(uv, square_2);
	float value_3 = compute_perlin_value(uv, square_3);
	float value_4 = compute_perlin_value(uv, square_4);

	float dist_1 = min(length(get_offset(uv, square_1)), 1.0);
	float dist_2 = min(length(get_offset(uv, square_2)), 1.0);
	float dist_3 = min(length(get_offset(uv, square_3)), 1.0);
	float dist_4 = min(length(get_offset(uv, square_4)), 1.0);

	float den = 4.0 - dist_1 - dist_2 - dist_3 - dist_4;
	float num = (
		value_1 * (1.0 - dist_1)
		+ value_2 * (1.0 - dist_2)
		+ value_3 * (1.0 - dist_3)
		+ value_4 * (1.0 - dist_4)
	);
	float min_dist = min(min(min(dist_1, dist_2), dist_3), dist_4);
	float vertex_influence = min(min_dist * 3.0, 1.0);
	return vertex_influence * num / max(den, 0.0001);
}

float compute_fractal_noise(vec2 uv) {
	float noise = 0.0;
	for (float i = 1.0; i < 5.0; i += 1.0) {
		float octave = pow(2.0, i);
		noise += pow(0.5, i) * interpolate_noise(octave * uv + vec2(octave, octave));
	}
	return noise;
}

vec3 sample_water_color(vec2 uv) {
	float x_distortion = distortion_amount * compute_fractal_noise(0.5 * uv + vec2(100.0, 0.0));
	float y_distortion = distortion_amount * compute_fractal_noise(0.5 * uv + vec2(0.0, 100.0));
	vec2 distorted_pos = vec2(uv.x + x_distortion, uv.y + y_distortion);

	float white = 0.25 + 0.75 * get_close_to_border(distorted_pos);
	float highlight = white * shine_strength;
	vec3 water = mix(base_color, shine_color.rgb, highlight);
	return water;
}

void vertex() {
	vec2 xz = VERTEX.xz;
	v_pattern_uv = xz * pattern_scale + scroll_speed * water_time() * vec2(0.125, 0.125);

	float x_distortion = distortion_amount * compute_fractal_noise(0.5 * v_pattern_uv + vec2(100.0, 0.0));
	float y_distortion = distortion_amount * compute_fractal_noise(0.5 * v_pattern_uv + vec2(0.0, 100.0));
	VERTEX.y += (x_distortion + y_distortion) * vertex_displacement;

	v_world_pos = VERTEX;
}

void fragment() {
	vec3 water = sample_water_color(v_pattern_uv);
	ALBEDO = water;
	ALPHA = surface_alpha;
}
